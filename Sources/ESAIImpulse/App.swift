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
        statusItem.button?.target = self; statusItem.button?.action = #selector(togglePanel)
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

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName:"antenna.radiowaves.left.and.right",accessibilityDescription:"ESAI Impulse")
        image?.isTemplate = true
        button.image = image?.withSymbolConfiguration(.init(pointSize:13,weight:.medium))
        let text: String; var color: NSColor? = nil
        if let left = model.leftGB {
            text = " " + statusText(leftGB:left)
            switch model.level { case .depleted: color = .systemRed; case .low: color = .systemOrange; case .normal: color = nil }
        } else { text = model.hasCredentials ? " — GB" : "" }
        var attrs: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedDigitSystemFont(ofSize:NSFont.systemFontSize,weight:.medium),.baselineOffset:0]
        if let color = color { attrs[.foregroundColor] = color }
        button.attributedTitle = NSAttributedString(string:text,attributes:attrs)
        button.toolTip = model.translate("ESAI Impulse · DataImpulse 剩余流量")
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

enum SelfTest {
    static func run() {
        let json = #"{"total_traffic":4522600562688,"traffic_used":4522636562688,"traffic_left":-36000000,"used_threads":0,"status":"ok"}"#
        let s = try! JSONDecoder().decode(TrafficStats.self,from:Data(json.utf8))
        precondition(abs(s.leftGB - -0.036) < 1e-9)
        precondition(statusText(leftGB:s.leftGB) == "0 GB")
        precondition(formatGB(TrafficStats.gb(s.total)) == "4,522.6 GB")
        precondition(statusText(leftGB:128.44) == "128.4 GB")
        precondition(AlertLevel.of(leftGB:s.leftGB,threshold:200) == .depleted)
        precondition(AlertLevel.of(leftGB:150,threshold:200) == .low)
        precondition(alertTransition(previous:.normal,current:.low) == .low)
        precondition(alertTransition(previous:.low,current:.low) == nil)
        precondition(alertTransition(previous:.low,current:.depleted) == .depleted)
        precondition(alertTransition(previous:.depleted,current:.depleted) == nil)
        let edit = EditMenu.make().items[1].submenu!
        for (key,sel) in [("v","paste:"),("c","copy:"),("x","cut:"),("a","selectAll:"),("z","undo:")] {
            precondition(edit.items.contains { $0.keyEquivalent == key && $0.action == Selector((sel)) && $0.keyEquivalentModifierMask == .command })
        }
        print("SELF_TEST_OK")
    }
}
