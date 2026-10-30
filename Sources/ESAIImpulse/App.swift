import AppKit
import SwiftUI
import Combine
import UserNotifications

final class PanelHostController: NSViewController {
    private let hosting: NSHostingView<TrafficPanel>
    init(model: TrafficModel) {
        hosting = NSHostingView(rootView:TrafficPanel(model:model))
        hosting.sizingOptions = []
        super.init(nibName:nil,bundle:nil)
        preferredContentSize = model.panelSize
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = NSView(frame:NSRect(origin:.zero,size:preferredContentSize))
        hosting.frame = view.bounds; hosting.autoresizingMask = [.width,.height]
        view.addSubview(hosting)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var model: TrafficModel!
    private var subscriptions = Set<AnyCancellable>()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // LSUIElement apps get no main menu; without one Cmd+V/C/X/A/Z never reach text fields.
        NSApp.mainMenu = EditMenu.make()
        UNUserNotificationCenter.current().delegate = self
        model = TrafficModel()
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        popover = NSPopover(); popover.behavior = .applicationDefined; popover.delegate = self; popover.animates = false
        popover.contentViewController = PanelHostController(model:model)
        model.objectWillChange.receive(on:RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }.store(in:&subscriptions)
        model.$appearance.removeDuplicates().sink { [weak self] in self?.applyAppearance($0) }.store(in:&subscriptions)
        updateStatusItem()
        if !model.hasCredentials {
            model.navigation.showingSettings = true; model.navigation.settingsTab = "account"
            DispatchQueue.main.asyncAfter(deadline:.now()+0.6) { self.togglePanel() }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner,.sound])
    }

    private var spinTimer: Timer?
    private var spinPhase: Double = 0
    private lazy var contextMenu: NSMenu = NSMenu()

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        if model.refreshing && spinTimer == nil {
            spinPhase = 0
            spinTimer = Timer(timeInterval:1.0/30, repeats:true) { [weak self] _ in
                guard let self = self else { return }
                self.spinPhase = (self.spinPhase + 12).truncatingRemainder(dividingBy:360); self.drawStatus()
            }
            RunLoop.main.add(spinTimer!, forMode:.common)
        } else if !model.refreshing, let timer = spinTimer { timer.invalidate(); spinTimer = nil }
        drawStatus()
        button.toolTip = model.tooltip
    }
    private func drawStatus() {
        guard let button = statusItem.button else { return }
        let snapshot = model.statusSnapshot(spinPhase:spinTimer == nil ? nil : spinPhase)
        let image = StatusRenderer.image(snapshot, style:model.statusStyle, typography:model.typography)
        button.title = ""; button.imagePosition = .imageOnly
        button.image = image
        statusItem.length = image.size.width + 8
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu() } else { togglePanel() }
    }
    private func showContextMenu() {
        if popover.isShown { popover.performClose(nil) }
        let menu = NSMenu()
        let refresh = NSMenuItem(title:model.translate("立即刷新"), action:#selector(menuRefresh), keyEquivalent:"r"); refresh.target = self
        let settings = NSMenuItem(title:model.translate("设置…"), action:#selector(menuSettings), keyEquivalent:","); settings.target = self
        let quit = NSMenuItem(title:model.translate("退出 ESAI Impulse"), action:#selector(NSApplication.terminate(_:)), keyEquivalent:"q")
        menu.items = [refresh, settings, .separator(), quit]
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    @objc private func menuRefresh() { model.refresh() }
    @objc private func menuSettings() {
        model.navigation.settingsTab = "account"; model.navigation.showingSettings = true
        if !popover.isShown { togglePanel() }
    }

    private func applyAppearance(_ preference: String) {
        let appearance: NSAppearance? = preference == "dark" ? NSAppearance(named:.darkAqua) : preference == "light" ? NSAppearance(named:.aqua) : nil
        NSApp.appearance = appearance; popover.appearance = appearance
        if let host = popover.contentViewController, host.isViewLoaded { host.view.appearance = appearance; host.view.window?.appearance = appearance }
    }

    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        fitPopoverToScreen(); applyAppearance(model.appearance)
        NSApp.activate(ignoringOtherApps:true)
        popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
        focusPanel()
        DispatchQueue.main.async { [weak self] in self?.keepPopoverOnScreen(); self?.focusPanel() }
        if let last = model.lastRefresh, Date().timeIntervalSince(last) > 60 { model.refresh() }
    }
    private func focusPanel() {
        guard popover.isShown, let window = popover.contentViewController?.view.window else { return }
        window.makeKey(); window.orderFront(nil)
    }
    func popoverDidShow(_ notification: Notification) {
        focusPanel(); stopMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown]) { [weak self] event in
            guard let self = self, self.popover.isShown else { return event }
            if event.type == .keyDown { if event.keyCode == 53 { self.popover.performClose(nil); return nil }; return event }
            guard let window = self.popover.contentViewController?.view.window else { return event }
            if event.window === window || event.window === self.statusItem.button?.window || event.window?.sheetParent === window { return event }
            if let other = event.window, other is NSPanel || other.level > .normal { return event }
            self.popover.performClose(nil); return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] _ in self?.popover.performClose(nil) }
        resignObserver = NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:NSApp,queue:.main) { [weak self] _ in self?.popover.performClose(nil) }
    }
    func popoverDidClose(_ notification: Notification) { stopMonitors() }
    private func stopMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
    }
    private func fitPopoverToScreen() {
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return }
        var available = screen.visibleFrame.size
        if let button = statusItem.button, let window = button.window {
            let anchor = window.convertToScreen(button.convert(button.bounds,to:nil))
            available.height = min(available.height,anchor.minY-screen.visibleFrame.minY)
        }
        let size = PopoverLayout.size(available:available)
        model.panelSize = size
        popover.contentViewController?.preferredContentSize = size
        popover.contentSize = size
    }
    private func keepPopoverOnScreen() {
        guard let window = popover.contentViewController?.view.window, let button = statusItem.button,
              let statusWindow = button.window, let screen = statusWindow.screen ?? NSScreen.main else { return }
        let anchor = statusWindow.convertToScreen(button.convert(button.bounds,to:nil))
        let origin = PopoverLayout.anchoredOrigin(for:window.frame,inside:screen.visibleFrame,anchor:anchor)
        if origin != window.frame.origin { window.setFrameOrigin(origin) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePanel() }; return false
    }
}

@main struct ESAIImpulseApp {
    static func main() {
        if CommandLine.arguments.contains("--self-test") { SelfTest.run(); return }
        if let i = CommandLine.arguments.firstIndex(of:"--render-statusbar") {
            let folder = CommandLine.arguments.count > i+1 ? CommandLine.arguments[i+1] : "/tmp/esai-impulse-statusbar"
            _ = NSApplication.shared
            let a = CommandLine.arguments
            func num(_ k: String) -> Double? { a.firstIndex(of:k).flatMap { a.count > $0+1 ? Double(a[$0+1]) : nil } }
            var t = StatusTypography.defaults
            if let v = num("--font") { t.fontSize = v }
            if let v = num("--icon") { t.iconSize = v }
            if let v = num("--spacing") { t.spacing = v }
            if let v = num("--compact") { t.compactFontSize = v }
            if let v = num("--offset") { t.textOffset = v }
            if let w = a.firstIndex(of:"--weight").flatMap({ a.count > $0+1 ? StatusWeight(rawValue:a[$0+1]) : nil }) { t.weight = w }
            StatusRenderer.renderPreviews(to:folder, typography:t.clamped()); return
        }
        if let i = CommandLine.arguments.firstIndex(of:"--render-settings") {
            let file = CommandLine.arguments.count > i+1 ? CommandLine.arguments[i+1] : "/tmp/esai-impulse-settings.png"
            MainActor.assumeIsolated { SettingsRender.run(to:file, dark:CommandLine.arguments.contains("--dark")) }; return
        }
        if CommandLine.arguments.contains("--probe") { CLI.probe(); return }
        if CommandLine.arguments.contains("--refresh-once") { CLI.refreshOnce(); return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

enum EditMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(title:"ESAI Impulse")
        appMenu.addItem(withTitle:"Quit ESAI Impulse",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title:"Edit")
        edit.addItem(withTitle:"Undo",action:Selector(("undo:")),keyEquivalent:"z")
        let redo = edit.addItem(withTitle:"Redo",action:Selector(("redo:")),keyEquivalent:"z")
        redo.keyEquivalentModifierMask = [.command,.shift]
        edit.addItem(.separator())
        edit.addItem(withTitle:"Cut",action:#selector(NSText.cut(_:)),keyEquivalent:"x")
        edit.addItem(withTitle:"Copy",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        edit.addItem(withTitle:"Paste",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        edit.addItem(withTitle:"Select All",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        editItem.submenu = edit
        return main
    }
}

/// Offscreen render of Settings → 外观 using the real TrafficPanel in a preview model
/// (separate UserDefaults suite seeded from the user's status bar values; no Keychain or network).
@MainActor enum SettingsRender {
    static func run(to file: String, dark: Bool) {
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        let suiteName = "com.fitzsmith2000.esai-impulse.settings-render"
        let d = UserDefaults(suiteName:suiteName)!
        d.removePersistentDomain(forName:suiteName)
        let real = UserDefaults.standard
        for k in ["statusStyle","language","accentHex","appearance","sb.fontSize","sb.weight","sb.iconSize","sb.spacing","sb.compactFontSize","sb.textOffset","sb.configs","sb.activeConfig","lastStats","thresholdGB"] {
            if let v = real.object(forKey:k) { d.set(v, forKey:k) }
        }
        if d.data(forKey:"sb.configs") == nil {
            var t = StatusTypography.load(d); t.textOffset = 0.5
            let demo = [StatusConfig(id:"demo-1", name:"配置 1", style:.iconText, typography:t)]
            d.set(try! JSONEncoder().encode(demo), forKey:"sb.configs"); d.set("demo-1", forKey:"sb.activeConfig")
            t.textOffset = 0.5; t.save(d)
        }
        let model = TrafficModel(defaults:d, preview:true)
        model.navigation.showingSettings = true; model.navigation.settingsTab = "appearance"
        model.panelSize = NSSize(width:PopoverLayout.preferredSize.width, height:1500)
        let host = NSHostingView(rootView:TrafficPanel(model:model).appearanceForRender)
        host.setFrameSize(host.fittingSize); model.panelSize = host.fittingSize
        host.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect:NSRect(origin:.zero, size:model.panelSize), styleMask:[.borderless], backing:.buffered, defer:false)
        window.appearance = host.appearance; window.backgroundColor = dark ? NSColor(white:0.16, alpha:1) : NSColor(white:0.96, alpha:1)
        window.contentView = host; window.setFrameOrigin(NSPoint(x:-10000, y:-10000)); window.orderFrontRegardless()
        for _ in 0..<40 { RunLoop.main.run(until:Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() }
        EsaiRenderMode.offscreen = true
        let r = ImageRenderer(content:TrafficPanel(model:model).appearanceForRender
            .background(dark ? Color(white:0.13) : Color(white:0.97)).environment(\.colorScheme, dark ? .dark : .light))
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data:tiff)?.representation(using:.png, properties:[:]) else { fatalError("render failed") }
        try! png.write(to:URL(fileURLWithPath:file))
        window.orderOut(nil)
        d.removePersistentDomain(forName:suiteName)
        print("RENDERED settings to \(file)")
    }
}

enum SelfTest {
    static func run() {
        let json = #"{"total_traffic":4522600562688,"traffic_used":4522636562688,"traffic_left":-36000000,"used_threads":0,"status":"ok"}"#
        let s = try! JSONDecoder().decode(TrafficStats.self,from:Data(json.utf8))
        precondition(abs(s.leftGB - -0.036) < 1e-9)
        precondition(formatGB(TrafficStats.gb(s.total)) == "4,522.6 GB")
        let units: [(Double,String)] = [(4522.6,"4.5 TB"),(1234,"1.2 TB"),(1000,"1.0 TB"),(128.4,"128 GB"),(100,"100 GB"),(99.96,"100 GB"),
            (86.24,"86.2 GB"),(1,"1.0 GB"),(0.85,"850 MB"),(0,"0 MB"),(-0.036,"-36 MB"),(-1.5,"-1.5 GB")]
        for (v,e) in units { precondition(formatTraffic(gb:v) == e, "formatTraffic(\(v)) = \(formatTraffic(gb:v)), expected \(e)") }
        precondition(formatTraffic(gb:s.leftGB) == "-36 MB")
        precondition(ringFraction(leftGB:128, thresholdGB:200) == 0.64)
        precondition(ringFraction(leftGB:250, thresholdGB:200) == 1)
        precondition(ringFraction(leftGB:-0.036, thresholdGB:200) == 0)
        let now = Date()
        precondition(!isStale(lastSuccess:now.addingTimeInterval(-29*60), lastFailed:false, intervalMinutes:15, now:now))
        precondition(isStale(lastSuccess:now.addingTimeInterval(-31*60), lastFailed:false, intervalMinutes:15, now:now))
        precondition(isStale(lastSuccess:now, lastFailed:true, intervalMinutes:15, now:now))
        precondition(!isStale(lastSuccess:nil, lastFailed:false, intervalMinutes:15, now:now))
        let d = StatusTypography.defaults
        precondition(d.fontSize == 10.5 && d.weight == .regular && d.iconSize == 19 && d.spacing == 9 && d.compactFontSize == 8.5)
        let cl = StatusTypography(fontSize:20, weight:.regular, iconSize:30, spacing:-3, compactFontSize:5).clamped()
        precondition(cl.fontSize == 14 && cl.iconSize == 20 && cl.spacing == 0 && cl.compactFontSize == 7)
        let c2 = StatusTypography(fontSize:8.74, weight:.medium, iconSize:13.3, spacing:4.2, compactFontSize:9.26).clamped()
        precondition(c2.fontSize == 9 && c2.iconSize == 13.5 && c2.spacing == 4 && c2.compactFontSize == 9.5)
        precondition(d.clamped() == d)
        for t in [d, cl] {
            let a = StatusRenderer.size(for:StatusSnapshot(text:"-36 MB"), style:.iconText, typography:t)
            precondition(a == StatusRenderer.size(for:StatusSnapshot(text:"888.8 GB"), style:.iconText, typography:t))
            precondition(a.width == CGFloat(t.iconSize+t.spacing) + StatusRenderer.reservedTextWidth(t))
        }
        precondition(StatusRenderer.reservedTextWidth(d) < StatusRenderer.reservedTextWidth(cl))
        precondition(AlertLevel.of(leftGB:s.leftGB,threshold:200) == .depleted)
        precondition(AlertLevel.of(leftGB:150,threshold:200) == .low)
        precondition(alertTransition(previous:.normal,current:.low) == .low)
        precondition(alertTransition(previous:.low,current:.low) == nil)
        precondition(alertTransition(previous:.low,current:.depleted) == .depleted)
        precondition(alertTransition(previous:.depleted,current:.depleted) == nil)
        // Text offset: default 0, clamps to ±3 and snaps to 0.25.
        precondition(d.textOffset == 0)
        precondition(StatusTypography(textOffset:9).clamped().textOffset == 3 && StatusTypography(textOffset:-7).clamped().textOffset == -3)
        precondition(StatusTypography(textOffset:0.6).clamped().textOffset == 0.5 && StatusTypography(textOffset:-1.13).clamped().textOffset == -1.25)
        let f = NSFont.systemFont(ofSize:11)
        precondition(StatusRenderer.baseline(centeredOn:11, font:f, offset:1.25) - StatusRenderer.baseline(centeredOn:11, font:f) == 1.25)
        // Old JSON without textOffset still decodes.
        let legacy = try! JSONDecoder().decode(StatusTypography.self, from:Data(#"{"fontSize":12,"weight":"medium","iconSize":14,"spacing":3,"compactFontSize":9}"#.utf8))
        precondition(legacy.fontSize == 12 && legacy.weight == .medium && legacy.textOffset == 0)
        // Configurations: save / load / rename / overwrite / delete, built-in protected, export/import.
        let suite = "com.fitzsmith2000.esai-impulse.selftest"
        let ud = UserDefaults(suiteName:suite)!; ud.removePersistentDomain(forName:suite)
        var t1 = StatusTypography.defaults; t1.textOffset = -1.5; t1.fontSize = 12; t1.save(ud); ud.set("compact", forKey:"statusStyle")
        let m = TrafficModel(defaults:ud, preview:true)
        precondition(m.statusConfigs.count == 1 && m.statusConfigs[0].isBuiltIn && m.activeConfigID == nil)
        precondition(m.typography.textOffset == -1.5 && m.statusStyle == .compact)   // existing values preserved
        precondition(m.suggestedConfigName.hasSuffix(" 1"))
        let c1 = m.saveConfig(named:"  测试  ")
        precondition(c1.name == "测试" && m.activeConfigID == c1.id && !m.activeConfigModified)
        m.applyConfig(StatusConfig.builtInID)
        precondition(m.typography == .defaults && m.statusStyle == .iconText && m.activeConfigID == StatusConfig.builtInID)
        m.deleteConfig(StatusConfig.builtInID); precondition(m.statusConfigs.count == 2)
        m.overwriteActiveConfig(); precondition(StatusConfigStore.load(ud)[0] == .builtIn)
        m.applyConfig(c1.id); precondition(m.typography.textOffset == -1.5 && m.statusStyle == .compact)
        var t2 = m.typography; t2.textOffset = 2; m.setTypography(t2); precondition(m.activeConfigModified)
        m.overwriteActiveConfig(); precondition(!m.activeConfigModified)
        m.renameConfig(c1.id, to:"新名字")
        let m2 = TrafficModel(defaults:ud, preview:true)   // survives "restart"
        precondition(m2.statusConfigs.count == 2 && m2.statusConfigs[1].name == "新名字" && m2.statusConfigs[1].typography.textOffset == 2 && m2.activeConfigID == c1.id)
        let exported = m2.exportConfigs()
        precondition(m2.importConfigs(exported) && m2.statusConfigs.count == 3 && m2.statusConfigs[2].id != c1.id)
        precondition(!m2.importConfigs(Data("nope".utf8)))
        m2.deleteConfig(c1.id); precondition(m2.activeConfigID == nil && m2.statusConfigs.count == 2)
        precondition(TrafficModel(defaults:ud, preview:true).statusConfigs.count == 2)
        ud.removePersistentDomain(forName:suite)
        let edit = EditMenu.make().items[1].submenu!
        for (key,sel) in [("v","paste:"),("c","copy:"),("x","cut:"),("a","selectAll:"),("z","undo:")] {
            precondition(edit.items.contains { $0.keyEquivalent == key && $0.action == Selector((sel)) && $0.keyEquivalentModifierMask == .command })
        }
        let chunked = Data("HTTP/1.1 401 Unauthorized\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nabcd\r\n2\r\nef\r\n0\r\n\r\n".utf8)
        let c = DirectHTTP.parse(chunked)!
        precondition(c.complete && c.response.status == 401 && String(data:c.response.body,encoding:.utf8) == "abcdef")
        let fixed = DirectHTTP.parse(Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}".utf8))!
        precondition(fixed.complete && fixed.response.status == 200 && fixed.response.body.count == 2)
        precondition(DirectHTTP.parse(Data("HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\n{}".utf8))!.complete == false)
        let dns = Data(#"{"Answer":[{"type":5,"data":"x."},{"type":1,"data":"198.18.0.71"},{"type":1,"data":"162.43.189.215"}]}"#.utf8)
        precondition(RealDNS.addresses(from:dns) == ["162.43.189.215"])
        print("SELF_TEST_OK")
    }
}

/// Diagnostics. Never prints credentials or response bodies.
enum CLI {
    static func wait(_ body: (@escaping () -> Void) -> Void) {
        var done = false
        body { done = true }
        let limit = Date().addingTimeInterval(90)
        while !done && Date() < limit { RunLoop.main.run(until:Date().addingTimeInterval(0.05)) }
    }
    static func probe() {
        wait { done in DirectHTTP.physicalInterface { i in print("PROBE physical_interface=\(i.map { "\($0.name) (\($0.type))" } ?? "none")"); done() } }
        for route in [Route.system, .direct] {
            let start = Date()
            wait { done in
                TrafficClient.raw(route:route, authorization:nil) { result in
                    let ms = Int(Date().timeIntervalSince(start)*1000)
                    switch result {
                    case .success(let r): print("PROBE route=\(route.rawValue) http=\(r.status) reachable=\(r.status == 401 || r.status == 200) ms=\(ms)")
                    case .failure(let e): print("PROBE route=\(route.rawValue) error=\"\(e.message)\" ms=\(ms)")
                    }
                    done()
                }
            }
        }
        print("PROBE direct_ips=\(TrafficClient.cachedIPs.joined(separator:","))")
    }
    static func refreshOnce() {
        guard let (login,password) = CredentialStore.credentials else { print("REFRESH no credentials in keychain"); return }
        wait { done in
            TrafficClient.fetch(login:login, password:password, mode:.auto) { result in
                switch result {
                case .success(let (s,route)): print("REFRESH http=200 route=\(route.rawValue) left=\(formatTraffic(gb:s.leftGB)) left_gb=\(String(format:"%.3f",s.leftGB))")
                case .failure(.unauthorized): print("REFRESH http=401 (login/password rejected)")
                case .failure(.http(let code)): print("REFRESH http=\(code)")
                case .failure(.blocked(let sys, let dir)): print("REFRESH failed system=\"\(sys)\" direct=\"\(dir ?? "-")\"")
                case .failure(let e): print("REFRESH failed \(e.message)")
                }
                done()
            }
        }
    }
}
