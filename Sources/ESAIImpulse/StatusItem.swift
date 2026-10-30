import AppKit

// MARK: - Pure logic (self-tested)

/// Auto units: >=1 TB "1.2 TB"; >=100 GB "128 GB"; >=1 GB "86.2 GB"; <1 GB "850 MB"; negatives keep the sign.
func formatTraffic(gb: Double) -> String {
    let sign = gb < 0 ? "-" : ""
    let v = abs(gb)
    if v >= 1000 { return sign + String(format:"%.1f TB", v/1000) }
    if v >= 99.95 { return sign + String(format:"%.0f GB", v) }
    if v >= 0.9995 { return sign + String(format:"%.1f GB", v) }
    let mb = (v*1000).rounded()
    return mb == 0 ? "0 MB" : sign + String(format:"%.0f MB", mb)
}

/// Ring length: remaining ÷ alert threshold, clamped to 0…1.
func ringFraction(leftGB: Double, thresholdGB: Double) -> Double {
    guard thresholdGB > 0 else { return leftGB > 0 ? 1 : 0 }
    return min(1, max(0, leftGB/thresholdGB))
}

/// Stale when the last refresh failed, or no success for more than two refresh intervals.
func isStale(lastSuccess: Date?, lastFailed: Bool, intervalMinutes: Int, now: Date = Date()) -> Bool {
    if lastFailed { return true }
    guard let last = lastSuccess else { return false }
    return now.timeIntervalSince(last) > Double(intervalMinutes)*60*2
}

enum StatusStyle: String, CaseIterable, Codable { case iconText, icon, compact }

struct StatusSnapshot {
    var text: String?            // nil = no data yet
    var fraction: Double = 1
    var level: AlertLevel = .normal
    var stale = false
    var spinPhase: Double? = nil // degrees; non-nil while refreshing
    var usedPercent: Double = 0
    var leftLabel = "剩余 %@"
    var usedLabel = "已用 %@"
}

// MARK: - Typography (user adjustable; v1.1.2 defaults chosen by Fitz)

enum StatusWeight: String, CaseIterable, Codable { case regular, medium, semibold
    var nsWeight: NSFont.Weight { switch self { case .regular: return .regular; case .medium: return .medium; case .semibold: return .semibold } }
}

struct StatusTypography: Equatable, Codable {
    /// v1.1.2 defaults (chosen by Fitz): 10.5 pt regular text with tabular digits.
    var fontSize: Double = 10.5
    var weight: StatusWeight = .regular
    /// 19 pt ring icon followed by a 9 pt gap.
    var iconSize: Double = 19
    var spacing: Double = 9
    /// Stacked rows 8.5 pt at row centres 6 and 16 of a 22 pt canvas.
    var compactFontSize: Double = 8.5
    /// Manual vertical nudge of the text (pt, positive = up), relative to the computed optical centre.
    var textOffset: Double = 0

    static let defaults = StatusTypography()
    init(fontSize: Double = 10.5, weight: StatusWeight = .regular, iconSize: Double = 19, spacing: Double = 9, compactFontSize: Double = 8.5, textOffset: Double = 0) {
        self.fontSize = fontSize; self.weight = weight; self.iconSize = iconSize; self.spacing = spacing
        self.compactFontSize = compactFontSize; self.textOffset = textOffset
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self), d = StatusTypography()
        self.init(fontSize:try c.decodeIfPresent(Double.self, forKey:.fontSize) ?? d.fontSize,
                  weight:try c.decodeIfPresent(StatusWeight.self, forKey:.weight) ?? d.weight,
                  iconSize:try c.decodeIfPresent(Double.self, forKey:.iconSize) ?? d.iconSize,
                  spacing:try c.decodeIfPresent(Double.self, forKey:.spacing) ?? d.spacing,
                  compactFontSize:try c.decodeIfPresent(Double.self, forKey:.compactFontSize) ?? d.compactFontSize,
                  textOffset:try c.decodeIfPresent(Double.self, forKey:.textOffset) ?? 0)
    }
    static let fontRange = 9.0...14.0, iconRange = 12.0...20.0, spacingRange = 0.0...10.0, compactRange = 7.0...11.0, offsetRange = -3.0...3.0

    static func clamp(_ v: Double, _ r: ClosedRange<Double>, step: Double) -> Double {
        let snapped = (v/step).rounded()*step
        return min(r.upperBound, max(r.lowerBound, snapped))
    }
    func clamped() -> StatusTypography {
        var t = self
        t.fontSize = Self.clamp(fontSize, Self.fontRange, step:0.5)
        t.iconSize = Self.clamp(iconSize, Self.iconRange, step:0.5)
        t.spacing = Self.clamp(spacing, Self.spacingRange, step:0.5)
        t.compactFontSize = Self.clamp(compactFontSize, Self.compactRange, step:0.5)
        t.textOffset = Self.clamp(textOffset, Self.offsetRange, step:0.25)
        return t
    }
    func save(_ d: UserDefaults) {
        d.set(fontSize, forKey:"sb.fontSize"); d.set(weight.rawValue, forKey:"sb.weight")
        d.set(iconSize, forKey:"sb.iconSize"); d.set(spacing, forKey:"sb.spacing"); d.set(compactFontSize, forKey:"sb.compactFontSize")
        d.set(textOffset, forKey:"sb.textOffset")
    }
    static func load(_ d: UserDefaults) -> StatusTypography {
        var t = StatusTypography()
        if let v = d.object(forKey:"sb.fontSize") as? Double { t.fontSize = v }
        if let v = d.string(forKey:"sb.weight").flatMap(StatusWeight.init(rawValue:)) { t.weight = v }
        if let v = d.object(forKey:"sb.iconSize") as? Double { t.iconSize = v }
        if let v = d.object(forKey:"sb.spacing") as? Double { t.spacing = v }
        if let v = d.object(forKey:"sb.compactFontSize") as? Double { t.compactFontSize = v }
        if let v = d.object(forKey:"sb.textOffset") as? Double { t.textOffset = v }
        return t.clamped()
    }
    var font: NSFont { NSFont.monospacedDigitSystemFont(ofSize:fontSize, weight:weight.nsWeight) }
    var compactValueFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize:compactFontSize, weight:weight.nsWeight) }
    /// Quosparr row labels: 0.5 pt smaller, weight 500, 62 % ink.
    var compactLabelFont: NSFont { NSFont.systemFont(ofSize:max(6, compactFontSize-0.5), weight:.medium) }
}

// MARK: - Drawing (22 pt canvas; text centred on cap height, icon on the same midline y=11)

enum StatusRenderer {
    static let flowerPath = "M 8.68000 6.95000 L 8.06000 1.69000 C 8.06000 1.17085 8.48085 0.75000 9.00000 0.75000 C 9.51915 0.75000 9.94000 1.17085 9.94000 1.69000 L 9.32000 6.95000 Q 9.43500 7.37500 9.74787 7.06465 L 11.84094 2.19935 C 12.10051 1.74976 12.67540 1.59572 13.12500 1.85529 C 13.57460 2.11486 13.72864 2.68976 13.46906 3.13935 L 10.30213 7.38465 Q 10.18922 7.81021 10.61535 7.69787 L 14.86065 4.53094 C 15.31024 4.27136 15.88514 4.42540 16.14471 4.87500 C 16.40428 5.32460 16.25024 5.89949 15.80065 6.15906 L 10.93535 8.25213 Q 10.62479 8.56422 11.05000 8.68000 L 16.31000 8.06000 C 16.82915 8.06000 17.25000 8.48085 17.25000 9.00000 C 17.25000 9.51915 16.82915 9.94000 16.31000 9.94000 L 11.05000 9.32000 Q 10.62500 9.43500 10.93535 9.74787 L 15.80065 11.84094 C 16.25024 12.10051 16.40428 12.67540 16.14471 13.12500 C 15.88514 13.57460 15.31024 13.72864 14.86065 13.46906 L 10.61535 10.30213 Q 10.18979 10.18922 10.30213 10.61535 L 13.46906 14.86065 C 13.72864 15.31024 13.57460 15.88514 13.12500 16.14471 C 12.67540 16.40428 12.10051 16.25024 11.84094 15.80065 L 9.74787 10.93535 Q 9.43578 10.62479 9.32000 11.05000 L 9.94000 16.31000 C 9.94000 16.82915 9.51915 17.25000 9.00000 17.25000 C 8.48085 17.25000 8.06000 16.82915 8.06000 16.31000 L 8.68000 11.05000 Q 8.56500 10.62500 8.25213 10.93535 L 6.15906 15.80065 C 5.89949 16.25024 5.32460 16.40428 4.87500 16.14471 C 4.42540 15.88514 4.27136 15.31024 4.53094 14.86065 L 7.69787 10.61535 Q 7.81078 10.18979 7.38465 10.30213 L 3.13935 13.46906 C 2.68976 13.72864 2.11486 13.57460 1.85529 13.12500 C 1.59572 12.67540 1.74976 12.10051 2.19935 11.84094 L 7.06465 9.74787 Q 7.37521 9.43578 6.95000 9.32000 L 1.69000 9.94000 C 1.17085 9.94000 0.75000 9.51915 0.75000 9.00000 C 0.75000 8.48085 1.17085 8.06000 1.69000 8.06000 L 6.95000 8.68000 Q 7.37500 8.56500 7.06465 8.25213 L 2.19935 6.15906 C 1.74976 5.89949 1.59572 5.32460 1.85529 4.87500 C 2.11486 4.42540 2.68976 4.27136 3.13935 4.53094 L 7.38465 7.69787 Q 7.81021 7.81078 7.69787 7.38465 L 4.53094 3.13935 C 4.27136 2.68976 4.42540 2.11486 4.87500 1.85529 C 5.32460 1.59572 5.89949 1.74976 6.15906 2.19935 L 8.25213 7.06465 Q 8.56422 7.37521 8.68000 6.95000 Z"
    static let height: CGFloat = 22
    static let compactBar = NSSize(width:22, height:4)

    /// Widest text the single-line slot must hold, measured in the chosen font.
    static func reservedTextWidth(_ t: StatusTypography) -> CGFloat {
        let a = [NSAttributedString.Key.font:t.font]
        return ceil(["888.8 GB","-888 MB","8.8 TB"].map { ($0 as NSString).size(withAttributes:a).width }.max()!)
    }

    static let flower: NSBezierPath = {
        let p = NSBezierPath()
        let tokens = flowerPath.replacingOccurrences(of:",", with:" ").split(separator:" ").map(String.init)
        var i = 0, cur = NSPoint.zero
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        func pt() -> NSPoint { let x = num(); return NSPoint(x:x, y:num()) }
        while i < tokens.count {
            let cmd = tokens[i]; i += 1
            switch cmd {
            case "M": cur = pt(); p.move(to:cur)
            case "L": cur = pt(); p.line(to:cur)
            case "C": let c1 = pt(), c2 = pt(); cur = pt(); p.curve(to:cur, controlPoint1:c1, controlPoint2:c2)
            case "Q":
                let q = pt(), end = pt()
                p.curve(to:end, controlPoint1:NSPoint(x:cur.x+2/3*(q.x-cur.x), y:cur.y+2/3*(q.y-cur.y)),
                        controlPoint2:NSPoint(x:end.x+2/3*(q.x-end.x), y:end.y+2/3*(q.y-end.y))); cur = end
            case "Z": p.close()
            default: break
            }
        }
        return p
    }()

    static func ringColor(_ level: AlertLevel) -> NSColor? {
        switch level { case .normal: return nil; case .low: return .systemOrange; case .depleted: return .systemRed }
    }

    /// Ring icon designed on an 18-unit grid, drawn at `size` pt with bottom-left at origin.
    static func drawIcon(_ s: StatusSnapshot, at origin: NSPoint, size: CGFloat, fg: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x:origin.x, y:origin.y)
        ctx.scaleBy(x:size/18, y:size/18)
        ctx.beginTransparencyLayer(auxiliaryInfo:nil)
        if s.stale { ctx.setAlpha(0.45) }
        let c = NSPoint(x:9, y:9), r: CGFloat = 7.4, w: CGFloat = 1.8
        let track = NSBezierPath(ovalIn:NSRect(x:c.x-r, y:c.y-r, width:2*r, height:2*r))
        track.lineWidth = w; fg.withAlphaComponent(0.25).setStroke(); track.stroke()
        let arc = NSBezierPath(); arc.lineWidth = w; arc.lineCapStyle = .round
        if let phase = s.spinPhase {
            arc.appendArc(withCenter:c, radius:r, startAngle:90-phase, endAngle:90-phase-80, clockwise:true)
            fg.setStroke(); arc.stroke()
        } else if s.fraction > 0 {
            if s.fraction >= 0.999 { arc.appendOval(in:NSRect(x:c.x-r, y:c.y-r, width:2*r, height:2*r)) }
            else { arc.appendArc(withCenter:c, radius:r, startAngle:90, endAngle:90-360*s.fraction, clockwise:true) }
            (ringColor(s.level) ?? fg).setStroke(); arc.stroke()
        }
        let f = flower.copy() as! NSBezierPath
        f.transform(using:AffineTransform(m11:0.64, m12:0, m21:0, m22:-0.64, tX:9-0.64*9, tY:9+0.64*9))
        fg.setFill(); f.fill()
        ctx.setAlpha(1)
        if s.stale {
            let slash = NSBezierPath(); slash.move(to:NSPoint(x:3.2, y:3.2)); slash.line(to:NSPoint(x:14.8, y:14.8))
            slash.lineCapStyle = .round; slash.lineWidth = 3.2
            NSGraphicsContext.current?.compositingOperation = .clear; slash.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            slash.lineWidth = 1.5; fg.withAlphaComponent(0.8).setStroke(); slash.stroke()
        }
        if s.level == .depleted && !s.stale {
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn:NSRect(x:15.2-3.6, y:14.8-3.6, width:7.2, height:7.2)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemRed.setFill(); NSBezierPath(ovalIn:NSRect(x:15.2-2.5, y:14.8-2.5, width:5, height:5)).fill()
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Snaps to the device pixel grid (half points on Retina).
    static func snap(_ v: CGFloat, scale: CGFloat = 2) -> CGFloat { (v*scale).rounded()/scale }

    /// Baseline that puts the optical centre of digits / capitals ("-36 MB", "128 GB") on `cy`.
    /// Uses the font's cap height (SF digits are cap-height tall) instead of the
    /// ascender+descender line box, whose centre sits above the glyphs the eye reads.
    static func baseline(centeredOn cy: CGFloat, font: NSFont, offset: CGFloat = 0) -> CGFloat {
        ((cy - font.capHeight/2)*2).rounded(.down)/2 + offset
    }

    /// Draws `text` with its cap-height band centred on `cy` (bottom-up), baseline pixel-aligned.
    @discardableResult
    static func drawText(_ text: String, x: CGFloat, cy: CGFloat, font: NSFont, color: NSColor, offset: CGFloat = 0) -> CGFloat {
        let attrs: [NSAttributedString.Key:Any] = [.font:font, .foregroundColor:color]
        let str = NSAttributedString(string:text, attributes:attrs)
        let line = CTLineCreateWithAttributedString(str)
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(x:snap(x), y:baseline(centeredOn:cy, font:font, offset:offset))
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        return ceil(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    static func size(for s: StatusSnapshot, style: StatusStyle, typography t: StatusTypography) -> NSSize {
        let icon = CGFloat(t.iconSize), gap = CGFloat(t.spacing)
        switch style {
        case .icon: return NSSize(width:icon, height:height)
        case .iconText: return NSSize(width:icon+gap+reservedTextWidth(t), height:height)
        case .compact:
            let v = [NSAttributedString.Key.font:t.compactValueFont], l = [NSAttributedString.Key.font:t.compactLabelFont]
            let labelW = max(labelWidth(s.leftLabel, l), labelWidth(s.usedLabel, l))
            let row1 = ("888.8 GB" as NSString).size(withAttributes:v).width
            let row2 = compactBar.width + 3 + ("100%" as NSString).size(withAttributes:v).width
            return NSSize(width:ceil(icon+gap+labelW+3+max(row1,row2)), height:height)
        }
    }
    private static func labelWidth(_ format: String, _ a: [NSAttributedString.Key:Any]) -> CGFloat {
        (label(format) as NSString).size(withAttributes:a).width
    }
    /// "剩余 %@" -> "剩余"
    static func label(_ format: String) -> String { format.replacingOccurrences(of:"%@", with:"").trimmingCharacters(in:.whitespaces) }

    static func image(_ s: StatusSnapshot, style: StatusStyle, typography t: StatusTypography) -> NSImage {
        let template = s.level == .normal
        let size = size(for:s, style:style, typography:t)
        let image = NSImage(size:size, flipped:false) { rect in
            let dark = NSAppearance.currentDrawing().bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
            draw(s, style:style, typography:t, in:rect, fg:template ? .black : (dark ? .white : .black))
            return true
        }
        image.isTemplate = template
        image.cacheMode = .never
        image.accessibilityDescription = s.text.map { "ESAI Impulse \($0)" } ?? "ESAI Impulse"
        return image
    }

    static func draw(_ s: StatusSnapshot, style: StatusStyle, typography t: StatusTypography, in rect: NSRect, fg: NSColor) {
        let icon = CGFloat(t.iconSize), gap = CGFloat(t.spacing)
        drawIcon(s, at:NSPoint(x:rect.minX, y:rect.minY+snap((height-icon)/2)), size:icon, fg:fg)
        let ink = s.stale ? fg.withAlphaComponent(0.5) : fg
        let x = snap(rect.minX + icon + gap)
        let dy = CGFloat(t.textOffset)
        switch style {
        case .icon: break
        case .iconText:
            // Left-aligned next to the icon; the slot keeps a fixed trailing width.
            drawText(s.text ?? "—", x:x, cy:rect.minY+11, font:t.font, color:ink, offset:dy)
        case .compact:
            let l = [NSAttributedString.Key.font:t.compactLabelFont]
            let labelW = ceil(max(labelWidth(s.leftLabel, l), labelWidth(s.usedLabel, l)))
            let top = rect.minY+16, bottom = rect.minY+6   // Quosparr row centres 6 / 16 from the top
            drawText(label(s.leftLabel), x:x, cy:top, font:t.compactLabelFont, color:ink.withAlphaComponent(0.62*ink.alphaComponent), offset:dy)
            drawText(label(s.usedLabel), x:x, cy:bottom, font:t.compactLabelFont, color:ink.withAlphaComponent(0.62*ink.alphaComponent), offset:dy)
            let vx = x + labelW + 3
            drawText(s.text ?? "—", x:vx, cy:top, font:t.compactValueFont, color:ink, offset:dy)
            let bar = NSRect(x:vx, y:bottom+dy-compactBar.height/2, width:compactBar.width, height:compactBar.height)
            ink.withAlphaComponent(0.22*ink.alphaComponent).setFill(); NSBezierPath(roundedRect:bar, xRadius:2, yRadius:2).fill()
            var fill = bar; fill.size.width = max(4, bar.width*min(1, s.usedPercent/100))
            (ringColor(s.level) ?? ink).setFill(); NSBezierPath(roundedRect:fill, xRadius:2, yRadius:2).fill()
            drawText(String(format:"%.0f%%", s.usedPercent), x:bar.maxX+3, cy:bottom, font:t.compactValueFont, color:ink, offset:dy)
        }
    }

    /// Bitmap of the item on a light/dark menu-bar background, using the same drawing as the status button.
    static func preview(_ s: StatusSnapshot, style: StatusStyle, typography t: StatusTypography, dark: Bool, scale: CGFloat = 2, pad: CGFloat = 8) -> NSBitmapImageRep? {
        let size = size(for:s, style:style, typography:t)
        let w = size.width+2*pad, h: CGFloat = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:Int(ceil(w*scale)), pixelsHigh:Int(h*scale), bitsPerSample:8, samplesPerPixel:4, hasAlpha:true, isPlanar:false, colorSpaceName:.deviceRGB, bytesPerRow:0, bitsPerPixel:0) else { return nil }
        rep.size = NSSize(width:w, height:h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
        NSAppearance(named:dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            (dark ? NSColor(srgbRed:0.36, green:0.29, blue:0.24, alpha:1) : NSColor(srgbRed:0.92, green:0.91, blue:0.89, alpha:1)).setFill()
            NSRect(x:0, y:0, width:w, height:h).fill()
            draw(s, style:style, typography:t, in:NSRect(x:pad, y:1, width:size.width, height:size.height), fg:dark ? .white : .black)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func previewImage(_ s: StatusSnapshot, style: StatusStyle, typography t: StatusTypography, dark: Bool) -> NSImage {
        let image = NSImage(size:NSSize(width:size(for:s, style:style, typography:t).width+16, height:24))
        if let rep = preview(s, style:style, typography:t, dark:dark) { image.addRepresentation(rep) }
        return image
    }

    static func sampleStates() -> [(String,StatusSnapshot)] {
        [("normal", StatusSnapshot(text:formatTraffic(gb:4522.6), fraction:1, level:.normal, usedPercent:2)),
         ("normal-128", StatusSnapshot(text:formatTraffic(gb:128.4), fraction:ringFraction(leftGB:128.4, thresholdGB:200), level:.normal, usedPercent:97)),
         ("low", StatusSnapshot(text:formatTraffic(gb:86.24), fraction:ringFraction(leftGB:86.24, thresholdGB:200), level:.low, usedPercent:98)),
         ("exhausted", StatusSnapshot(text:formatTraffic(gb:-0.036), fraction:0, level:.depleted, usedPercent:100)),
         ("stale", StatusSnapshot(text:formatTraffic(gb:128.4), fraction:0.64, level:.normal, stale:true, usedPercent:97)),
         ("refreshing", StatusSnapshot(text:formatTraffic(gb:128.4), fraction:0.64, level:.normal, spinPhase:40, usedPercent:97))]
    }

    static func renderPreviews(to folder: String, typography t: StatusTypography = .defaults) {
        try? FileManager.default.createDirectory(atPath:folder, withIntermediateDirectories:true)
        let states = sampleStates()
        for (name, s) in states {
            for style in StatusStyle.allCases {
                for dark in [false, true] {
                    let file = "\(folder)/\(name)-\(style.rawValue)-\(dark ? "dark" : "light").png"
                    try? preview(s, style:style, typography:t, dark:dark)?.representation(using:.png, properties:[:])?.write(to:URL(fileURLWithPath:file))
                }
            }
        }
        print("RENDERED \(states.count*StatusStyle.allCases.count*2) previews to \(folder)")
    }
}
