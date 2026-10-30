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

enum StatusStyle: String, CaseIterable { case iconText, icon, compact }

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

// MARK: - Drawing

enum StatusRenderer {
    static let flowerPath = "M 8.68000 6.95000 L 8.06000 1.69000 C 8.06000 1.17085 8.48085 0.75000 9.00000 0.75000 C 9.51915 0.75000 9.94000 1.17085 9.94000 1.69000 L 9.32000 6.95000 Q 9.43500 7.37500 9.74787 7.06465 L 11.84094 2.19935 C 12.10051 1.74976 12.67540 1.59572 13.12500 1.85529 C 13.57460 2.11486 13.72864 2.68976 13.46906 3.13935 L 10.30213 7.38465 Q 10.18922 7.81021 10.61535 7.69787 L 14.86065 4.53094 C 15.31024 4.27136 15.88514 4.42540 16.14471 4.87500 C 16.40428 5.32460 16.25024 5.89949 15.80065 6.15906 L 10.93535 8.25213 Q 10.62479 8.56422 11.05000 8.68000 L 16.31000 8.06000 C 16.82915 8.06000 17.25000 8.48085 17.25000 9.00000 C 17.25000 9.51915 16.82915 9.94000 16.31000 9.94000 L 11.05000 9.32000 Q 10.62500 9.43500 10.93535 9.74787 L 15.80065 11.84094 C 16.25024 12.10051 16.40428 12.67540 16.14471 13.12500 C 15.88514 13.57460 15.31024 13.72864 14.86065 13.46906 L 10.61535 10.30213 Q 10.18979 10.18922 10.30213 10.61535 L 13.46906 14.86065 C 13.72864 15.31024 13.57460 15.88514 13.12500 16.14471 C 12.67540 16.40428 12.10051 16.25024 11.84094 15.80065 L 9.74787 10.93535 Q 9.43578 10.62479 9.32000 11.05000 L 9.94000 16.31000 C 9.94000 16.82915 9.51915 17.25000 9.00000 17.25000 C 8.48085 17.25000 8.06000 16.82915 8.06000 16.31000 L 8.68000 11.05000 Q 8.56500 10.62500 8.25213 10.93535 L 6.15906 15.80065 C 5.89949 16.25024 5.32460 16.40428 4.87500 16.14471 C 4.42540 15.88514 4.27136 15.31024 4.53094 14.86065 L 7.69787 10.61535 Q 7.81078 10.18979 7.38465 10.30213 L 3.13935 13.46906 C 2.68976 13.72864 2.11486 13.57460 1.85529 13.12500 C 1.59572 12.67540 1.74976 12.10051 2.19935 11.84094 L 7.06465 9.74787 Q 7.37521 9.43578 6.95000 9.32000 L 1.69000 9.94000 C 1.17085 9.94000 0.75000 9.51915 0.75000 9.00000 C 0.75000 8.48085 1.17085 8.06000 1.69000 8.06000 L 6.95000 8.68000 Q 7.37500 8.56500 7.06465 8.25213 L 2.19935 6.15906 C 1.74976 5.89949 1.59572 5.32460 1.85529 4.87500 C 2.11486 4.42540 2.68976 4.27136 3.13935 4.53094 L 7.38465 7.69787 Q 7.81021 7.81078 7.69787 7.38465 L 4.53094 3.13935 C 4.27136 2.68976 4.42540 2.11486 4.87500 1.85529 C 5.32460 1.59572 5.89949 1.74976 6.15906 2.19935 L 8.25213 7.06465 Q 8.56422 7.37521 8.68000 6.95000 Z"
    static let height: CGFloat = 22
    static let iconSize: CGFloat = 18
    static var textFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize:NSFont.systemFontSize, weight:.regular) }
    static var smallFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize:9.5, weight:.regular) }
    /// Width reserved for "888.8 GB" so neighbours never jump.
    static var reservedTextWidth: CGFloat { ceil(("888.8 GB" as NSString).size(withAttributes:[.font:textFont]).width) + 1 }

    /// esai 12-petal flower in an 18x18 SVG coordinate space (y down), parsed once.
    static let flower: NSBezierPath = {
        let p = NSBezierPath()
        let scanner = flowerPath.replacingOccurrences(of:",", with:" ").split(separator:" ").map(String.init)
        var i = 0, cur = NSPoint.zero
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(scanner[i]) ?? 0) }
        func pt() -> NSPoint { let x = num(); return NSPoint(x:x, y:num()) }
        while i < scanner.count {
            let cmd = scanner[i]; i += 1
            switch cmd {
            case "M": cur = pt(); p.move(to:cur)
            case "L": cur = pt(); p.line(to:cur)
            case "C": let c1 = pt(), c2 = pt(); cur = pt(); p.curve(to:cur, controlPoint1:c1, controlPoint2:c2)
            case "Q":
                let q = pt(), end = pt()
                let c1 = NSPoint(x:cur.x+2/3*(q.x-cur.x), y:cur.y+2/3*(q.y-cur.y))
                let c2 = NSPoint(x:end.x+2/3*(q.x-end.x), y:end.y+2/3*(q.y-end.y))
                p.curve(to:end, controlPoint1:c1, controlPoint2:c2); cur = end
            case "Z": p.close()
            default: break
            }
        }
        return p
    }()

    static func ringColor(_ level: AlertLevel) -> NSColor? {
        switch level { case .normal: return nil; case .low: return .systemOrange; case .depleted: return .systemRed }
    }

    /// Draws the 18pt ring icon with its bottom-left at origin (non-flipped context).
    static func drawIcon(_ s: StatusSnapshot, at origin: NSPoint, fg: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x:origin.x, y:origin.y)
        ctx.beginTransparencyLayer(auxiliaryInfo:nil)
        if s.stale { ctx.setAlpha(0.45) }
        let c = NSPoint(x:9, y:9), r: CGFloat = 7.4, w: CGFloat = 1.7
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
        // Original esai flower, scaled 0.64 about the centre (scheme C), flipped from SVG space.
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
            let cut = NSBezierPath(ovalIn:NSRect(x:15-4.1, y:14.6-4.1, width:8.2, height:8.2))
            NSGraphicsContext.current?.compositingOperation = .clear; cut.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemRed.setFill(); NSBezierPath(ovalIn:NSRect(x:15-2.9, y:14.6-2.9, width:5.8, height:5.8)).fill()
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    static func size(for s: StatusSnapshot, style: StatusStyle) -> NSSize {
        switch style {
        case .icon: return NSSize(width:iconSize, height:height)
        case .iconText: return NSSize(width:iconSize+5+reservedTextWidth, height:height)
        case .compact:
            let a = [NSAttributedString.Key.font:smallFont]
            let l1 = (String(format:s.leftLabel, "888.8 GB") as NSString).size(withAttributes:a).width
            let l2 = (String(format:s.usedLabel, "100%") as NSString).size(withAttributes:a).width + 4 + 22
            return NSSize(width:ceil(iconSize+4+max(l1,l2)), height:height)
        }
    }

    /// Whole status item as one image. Template (system tint) unless the ring carries colour.
    static func image(_ s: StatusSnapshot, style: StatusStyle) -> NSImage {
        let template = s.level == .normal
        let size = size(for:s, style:style)
        let image = NSImage(size:size, flipped:false) { rect in
            let dark = NSAppearance.currentDrawing().bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
            let fg: NSColor = template ? .black : (dark ? .white : .black)
            draw(s, style:style, in:rect, fg:fg)
            return true
        }
        image.isTemplate = template
        image.cacheMode = .never
        image.accessibilityDescription = s.text.map { "ESAI Impulse \($0)" } ?? "ESAI Impulse"
        return image
    }

    static func draw(_ s: StatusSnapshot, style: StatusStyle, in rect: NSRect, fg: NSColor) {
        drawIcon(s, at:NSPoint(x:0, y:round((rect.height-iconSize)/2)), fg:fg)
        let textColor = s.stale ? fg.withAlphaComponent(0.5) : fg
        switch style {
        case .icon: break
        case .iconText:
            let text = s.text ?? "—"
            let attrs: [NSAttributedString.Key:Any] = [.font:textFont, .foregroundColor:textColor]
            let ts = (text as NSString).size(withAttributes:attrs)
            // Right-aligned inside the reserved width; baseline centred on the bar.
            (text as NSString).draw(at:NSPoint(x:rect.maxX-ts.width, y:round((rect.height-ts.height)/2)), withAttributes:attrs)
        case .compact:
            let attrs: [NSAttributedString.Key:Any] = [.font:smallFont, .foregroundColor:textColor]
            let x = iconSize+4
            (String(format:s.leftLabel, s.text ?? "—") as NSString).draw(at:NSPoint(x:x, y:10.6), withAttributes:attrs)
            let used = String(format:s.usedLabel, String(format:"%.0f%%", s.usedPercent)) as NSString
            used.draw(at:NSPoint(x:x, y:0.6), withAttributes:attrs)
            let bx = x + used.size(withAttributes:attrs).width + 4
            let barRect = NSRect(x:bx, y:4, width:22, height:3)
            textColor.withAlphaComponent(0.22).setFill(); NSBezierPath(roundedRect:barRect, xRadius:1.5, yRadius:1.5).fill()
            var fill = barRect; fill.size.width = max(3, 22*min(1, s.usedPercent/100))
            (ringColor(s.level) ?? textColor).setFill(); NSBezierPath(roundedRect:fill, xRadius:1.5, yRadius:1.5).fill()
        }
    }

    /// Writes PNG previews (@2x) of every state × style on light and dark bars.
    static func renderPreviews(to folder: String) {
        try? FileManager.default.createDirectory(atPath:folder, withIntermediateDirectories:true)
        let states: [(String,StatusSnapshot)] = [
            ("normal", StatusSnapshot(text:formatTraffic(gb:4522.6), fraction:1, level:.normal, usedPercent:2)),
            ("normal-128", StatusSnapshot(text:formatTraffic(gb:128.4), fraction:ringFraction(leftGB:128.4, thresholdGB:200), level:.normal, usedPercent:97)),
            ("low", StatusSnapshot(text:formatTraffic(gb:86.24), fraction:ringFraction(leftGB:86.24, thresholdGB:200), level:.low, usedPercent:98)),
            ("exhausted", StatusSnapshot(text:formatTraffic(gb:-0.036), fraction:0, level:.depleted, usedPercent:100)),
            ("stale", StatusSnapshot(text:formatTraffic(gb:128.4), fraction:0.64, level:.normal, stale:true, usedPercent:97)),
            ("refreshing", StatusSnapshot(text:formatTraffic(gb:128.4), fraction:0.64, level:.normal, spinPhase:40, usedPercent:97)),
        ]
        for (name, s) in states {
            for style in StatusStyle.allCases {
                for dark in [false, true] {
                    let size = StatusRenderer.size(for:s, style:style)
                    let pad: CGFloat = 10, scale: CGFloat = 2
                    let w = Int((size.width+2*pad)*scale), h = Int(24*scale)
                    guard let rep = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:w, pixelsHigh:h, bitsPerSample:8, samplesPerPixel:4, hasAlpha:true, isPlanar:false, colorSpaceName:.deviceRGB, bytesPerRow:0, bitsPerPixel:0) else { continue }
                    rep.size = NSSize(width:size.width+2*pad, height:24)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
                    let appearance = NSAppearance(named:dark ? .darkAqua : .aqua)!
                    appearance.performAsCurrentDrawingAppearance {
                        (dark ? NSColor(srgbRed:0.36, green:0.29, blue:0.24, alpha:1) : NSColor(srgbRed:0.92, green:0.91, blue:0.89, alpha:1)).setFill()
                        NSRect(x:0, y:0, width:size.width+2*pad, height:24).fill()
                        // Same drawing the status button gets; template images tint like the system menu bar does.
                        let fg: NSColor = dark ? .white : .black
                        draw(s, style:style, in:NSRect(x:pad, y:1, width:size.width, height:size.height), fg:fg)
                    }
                    NSGraphicsContext.restoreGraphicsState()
                    let file = "\(folder)/\(name)-\(style.rawValue)-\(dark ? "dark" : "light").png"
                    try? rep.representation(using:.png, properties:[:])?.write(to:URL(fileURLWithPath:file))
                }
            }
        }
        print("RENDERED \(states.count*StatusStyle.allCases.count*2) previews to \(folder)")
    }
}
