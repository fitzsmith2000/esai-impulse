import AppKit
import SwiftUI
import QuartzCore

// Anchor the menu to the outer control, rather than SwiftUI Menu's inset label.
struct EsaiMenuChoice {
    let id: String
    let title: String
}

struct EsaiAlignedMenu: NSViewRepresentable {
    let selection: String
    let choices: [EsaiMenuChoice]
    let label: String
    let accent: Color
    var centered = false
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> EsaiMenuButton { EsaiMenuButton() }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:EsaiMenuButton,context:Context) -> CGSize? {
        CGSize(width:proposal.width ?? 64,height:proposal.height ?? 30)
    }
    func updateNSView(_ button: EsaiMenuButton, context: Context) {
        button.choices = choices; button.selection = selection; button.onSelect = onSelect
        button.title = choices.first(where: { $0.id == selection })?.title ?? selection
        button.ink = NSColor(accent); button.centered = centered
        button.setAccessibilityTitle(label); button.setAccessibilityLabel(label)
        button.setAccessibilityValue(button.title)
        button.needsDisplay = true
    }
}

final class EsaiMenuButton: NSButton {
    var choices: [EsaiMenuChoice] = []
    var selection = ""
    var onSelect: (String) -> Void = { _ in }
    var ink = NSColor.controlAccentColor
    var centered = false
    override var intrinsicContentSize: NSSize { NSSize(width:NSView.noIntrinsicMetric,height:30) }
    override init(frame: NSRect) {
        super.init(frame:frame)
        isBordered = false; focusRingType = .none
        target = self; action = #selector(openMenu)
        setAccessibilityRole(.menuButton)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect:NSRect) {
        let font = centered ? NSFont.monospacedDigitSystemFont(ofSize:13,weight:.medium) : NSFont.systemFont(ofSize:13,weight:.medium)
        let text = title as NSString
        let attributes: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:ink]
        let size = text.size(withAttributes:attributes)
        // Reserve the same 30 pt checkmark column as the native menu.
        let x:CGFloat = 30
        let available = max(0,bounds.width-x-18)
        text.draw(in:NSRect(x:x,y:(bounds.height-size.height)/2,width:available,height:size.height),withAttributes:attributes)
        let path = NSBezierPath(); path.lineWidth = 1.5; path.lineCapStyle = .round; path.lineJoinStyle = .round
        let right = bounds.maxX-12, y = bounds.midY
        path.move(to:NSPoint(x:right-5,y:y-1.5)); path.line(to:NSPoint(x:right-2.5,y:y+1)); path.line(to:NSPoint(x:right,y:y-1.5))
        ink.setStroke(); path.stroke()
    }
    @objc private func openMenu() {
        DispatchQueue.main.asyncAfter(deadline:.now()+0.03) { [weak self] in self?.presentMenu() }
    }
    override func accessibilityPerformPress() -> Bool { openMenu(); return true }
    private func presentMenu() {
        guard let window = window else { return }
        let menu = NSMenu(); menu.autoenablesItems = false
        menu.font = NSFont.systemFont(ofSize:13)
        menu.minimumWidth = bounds.width
        for choice in choices {
            let item = NSMenuItem(title:choice.title,action:#selector(choose(_:)),keyEquivalent:"")
            item.target = self; item.representedObject = choice.id
            item.state = choice.id == selection ? .on : .off
            menu.addItem(item)
        }
        // NSMenu snaps to whole screen points; match the glass outline's rounding.
        let screenRect = window.convertToScreen(convert(bounds,to:nil))
        let correction = centered ? ceil(screenRect.minX)-screenRect.minX : 0
        menu.popUp(positioning:nil,at:NSPoint(x:bounds.minX+correction,y:isFlipped ? bounds.maxY+9 : bounds.minY-9),in:self)
    }
    @objc private func choose(_ item:NSMenuItem) {
        if let id = item.representedObject as? String { onSelect(id) }
    }
}

struct EsaiGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing:8) { content }
        } else { content }
    }
}

struct EsaiGlassControl: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(),in:.capsule)
        } else {
            content.background(EsaiSurface.raised,in:Capsule())
                .overlay(Capsule().strokeBorder(EsaiSurface.hairline.opacity(0.5),lineWidth:0.5))
        }
    }
}

struct EsaiGlassButton: ViewModifier {
    var prominent = false
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        }
    }
}

extension View {
    func esaiGlassControl() -> some View { modifier(EsaiGlassControl()) }
    func esaiGlassButton(prominent: Bool = false) -> some View { modifier(EsaiGlassButton(prominent:prominent)) }
}

struct EsaiSegmentOption: Identifiable {
    let id: String
    let title: String
}

// Native, fixed-size host keeps the moving glass independent of label and page layout.
struct EsaiGlassSegments: View {
    @Binding var selection: String
    let options: [EsaiSegmentOption]
    let accent: Color
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        EsaiNativeSegments(selection:selection,options:options,accent:NSColor(accent),label:label,
            reduceMotion:reduceMotion,reduceTransparency:reduceTransparency,dark:colorScheme == .dark) { value in
            withTransaction(Transaction(animation:nil)) { selection = value }
        }
        .frame(height:34)
        .background(.thinMaterial,in:Capsule())
        .overlay(Capsule().strokeBorder(EsaiSurface.hairline.opacity(0.35),lineWidth:0.5))
    }
}

private struct EsaiNativeSegments: NSViewRepresentable {
    let selection:String
    let options:[EsaiSegmentOption]
    let accent:NSColor
    let label:String
    let reduceMotion:Bool
    let reduceTransparency:Bool
    let dark:Bool
    let onSelect:(String)->Void
    func makeNSView(context:Context) -> EsaiSegmentedView { EsaiSegmentedView(frame:.zero) }
    func updateNSView(_ view:EsaiSegmentedView,context:Context) {
        view.configure(selection:selection,options:options,accent:accent,label:label,
            reduceMotion:reduceMotion,reduceTransparency:reduceTransparency,dark:dark,onSelect:onSelect)
    }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:EsaiSegmentedView,context:Context) -> CGSize? {
        CGSize(width:proposal.width ?? 200,height:34)
    }
}

private final class EsaiSegmentedView: NSView {
    private var glass:NSView!
    private var buttons:[NSButton] = []
    private var ids:[String] = []
    private var selection = ""
    private var onSelect:(String)->Void = { _ in }
    private var lastSize = CGSize.zero
    override var intrinsicContentSize:NSSize { NSSize(width:NSView.noIntrinsicMetric,height:34) }
    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer = true
        if #available(macOS 26.0,*) {
            let native = NSGlassEffectView(); native.style = .regular; native.cornerRadius = 14
            native.contentView = NSView()
            glass = native
        } else { glass = NSView(); glass.wantsLayer = true; glass.layer?.cornerRadius = 14 }
        addSubview(glass)
        setAccessibilityElement(true); setAccessibilityRole(.group)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(selection:String,options:[EsaiSegmentOption],accent:NSColor,label:String,
        reduceMotion:Bool,reduceTransparency:Bool,dark:Bool,onSelect:@escaping(String)->Void) {
        let changed = self.selection != selection && !self.selection.isEmpty
        self.selection = selection; self.onSelect = onSelect
        setAccessibilityLabel(label)
        if #available(macOS 26.0, *) {
            let native = glass is NSGlassEffectView
            if native == reduceTransparency {
                let oldFrame = glass.frame
                glass.removeFromSuperview()
                if reduceTransparency {
                    glass = NSView(); glass.wantsLayer = true; glass.layer?.cornerRadius = 14
                } else {
                    let effect = NSGlassEffectView(); effect.style = .regular; effect.cornerRadius = 14
                    effect.contentView = NSView(); glass = effect
                }
                glass.frame = oldFrame
                addSubview(glass,positioned:.below,relativeTo:buttons.first)
            }
        }
        if ids != options.map(\.id) {
            buttons.forEach { $0.removeFromSuperview() }; buttons = []; ids = options.map(\.id)
            for index in options.indices {
                let button = NSButton(title:"",target:self,action:#selector(select(_:)))
                button.tag = index; button.isBordered = false; button.focusRingType = .none
                addSubview(button,positioned:.above,relativeTo:glass); buttons.append(button)
            }
            lastSize = .zero; needsLayout = true
        }
        for (index,button) in buttons.enumerated() {
            let selected = ids[index] == selection
            let color = selected ? (dark ? NSColor.white : accent) : NSColor.labelColor
            button.attributedTitle = NSAttributedString(string:options[index].title,attributes:[
                .font:NSFont.systemFont(ofSize:13,weight:selected ? .semibold : .medium),.foregroundColor:color])
            button.setAccessibilityLabel(options[index].title)
            button.setAccessibilityValue(selected ? 1 : 0)
        }
        if #available(macOS 26.0,*), let native = glass as? NSGlassEffectView {
            native.tintColor = accent.withAlphaComponent(dark ? 0.32 : 0.18)
        } else { glass.layer?.backgroundColor = accent.withAlphaComponent(0.16).cgColor }
        if bounds.width > 0 && changed && window != nil && !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(controlPoints:0.35,0,0.25,1)
                glass.animator().frame = selectionFrame
            }
        } else if changed && lastSize == bounds.size { glass.frame = selectionFrame }
    }
    private var selectionFrame:NSRect {
        let width = max(0,bounds.width-6)/CGFloat(max(1,ids.count))
        let index = ids.firstIndex(of:selection) ?? 0
        return NSRect(x:3+CGFloat(index)*width,y:3,width:width,height:28)
    }
    override func layout() {
        super.layout()
        let width = max(0,bounds.width-6)/CGFloat(max(1,ids.count))
        for (index,button) in buttons.enumerated() {
            button.frame = NSRect(x:3+CGFloat(index)*width,y:3,width:width,height:28)
        }
        if lastSize != bounds.size { glass.frame = selectionFrame; lastSize = bounds.size }
    }
    @objc private func select(_ button:NSButton) { if ids.indices.contains(button.tag) { onSelect(ids[button.tag]) } }
}

// Thin knob adapted from Licoy/Quosparr (formerly CodexRunway),
// PolishedScrollView.swift at 411240f4bd758e8d5f788b94e4187ba161374ebb; AGPL-3.0.
// Keep SwiftUI's scroll host and sizing; customize only its native scroller.
struct EsaiScrollChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> EsaiScrollChromeProbe { EsaiScrollChromeProbe() }
    func updateNSView(_ view: EsaiScrollChromeProbe, context: Context) { view.scheduleConfiguration() }
}

final class EsaiScrollChromeProbe: NSView {
    private var pending = false
    private var styleObserver: NSObjectProtocol?
    override init(frame: NSRect) {
        super.init(frame: frame)
        styleObserver = NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.scheduleConfiguration() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observer = styleObserver { NotificationCenter.default.removeObserver(observer) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleConfiguration() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); scheduleConfiguration() }
    func scheduleConfiguration() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pending = false
            guard let scroll = self.enclosingScrollView else { return }
            if scroll.scrollerStyle != .overlay { scroll.scrollerStyle = .overlay }
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            scroll.contentView.drawsBackground = false
            scroll.hasHorizontalScroller = false
            if !(scroll.verticalScroller is EsaiThinOverlayScroller) {
                let scroller = EsaiThinOverlayScroller()
                scroller.scrollerStyle = .overlay
                scroller.controlSize = .small
                scroll.verticalScroller = scroller
            }
        }
    }
}

final class EsaiThinOverlayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize,
                                      scrollerStyle: NSScroller.Style) -> CGFloat { 7 }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) { drawKnob() }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        let nativeKnob = rect(for: .knob)
        guard nativeKnob.height > 2 else { return }
        let knob = NSRect(x: bounds.midX - 1.5, y: nativeKnob.minY + 1,
                          width: 3, height: max(3, nativeKnob.height - 2))
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor.white.withAlphaComponent(0.36)
              : NSColor.black.withAlphaComponent(0.22)).setFill()
        NSBezierPath(roundedRect: knob, xRadius: 1.5, yRadius: 1.5).fill()
    }
}
