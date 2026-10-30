import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications
import Network

final class PanelNavigation: ObservableObject {
    @Published var showingSettings = false
    @Published var settingsTab = "account"
}

final class TrafficModel: ObservableObject {
    @Published private(set) var stats: TrafficStats?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var errorKey: String?
    @Published private(set) var errorArgument = ""
    @Published private(set) var refreshing = false
    @Published private(set) var lastFailed = false
    @Published private(set) var statusStyle = StatusStyle.iconText
    @Published private(set) var hasCredentials = false
    @Published private(set) var savedLogin = ""
    @Published private(set) var lastRoute: Route?
    @Published private(set) var connectionMode = ConnectionMode.auto
    private var pathMonitor: NWPathMonitor?
    private var lastPathKey = ""
    @Published var intervalMinutes = 15
    @Published var thresholdGB = 200.0
    @Published var appearance = "system"
    @Published var glassBackground = true
    @Published private(set) var language = AppLanguage.system
    @Published private(set) var resolvedLanguage = AppLanguage.system.resolved()
    @Published private(set) var accentHex = AccentPreset.choices[0].hex
    @Published var panelSize = PopoverLayout.preferredSize
    @Published var loginEnabled = false
    @Published private var loginError: String?
    @Published private var loginNeedsApproval = false
    let navigation = PanelNavigation()
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        intervalMinutes = defaults.object(forKey:"intervalMinutes") as? Int ?? 15
        thresholdGB = defaults.object(forKey:"thresholdGB") as? Double ?? 200
        appearance = defaults.string(forKey:"appearance") ?? "system"
        glassBackground = defaults.object(forKey:"glassBackground") as? Bool ?? true
        language = AppLanguage(rawValue:defaults.string(forKey:"language") ?? "system") ?? .system
        resolvedLanguage = language.resolved()
        accentHex = defaults.string(forKey:"accentHex").flatMap { AccentRGB(hex:$0)?.hex } ?? AccentPreset.choices[0].hex
        if let data = defaults.data(forKey:"lastStats") { stats = try? JSONDecoder().decode(TrafficStats.self,from:data) }
        lastRefresh = defaults.object(forKey:"lastRefresh") as? Date
        statusStyle = StatusStyle(rawValue:defaults.string(forKey:"statusStyle") ?? "") ?? .iconText
        let creds = CredentialStore.credentials
        hasCredentials = creds != nil; savedLogin = creds?.0 ?? ""
        loginEnabled = SMAppService.mainApp.status == .enabled
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound]) { _,_ in }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName:NSLocale.currentLocaleDidChangeNotification,object:nil,queue:.main) { [weak self] _ in
            guard let self = self else { return }; self.resolvedLanguage = self.language.resolved()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline:.now()+5) { self?.refresh() }
        })
        connectionMode = ConnectionMode(rawValue:defaults.string(forKey:"connectionMode") ?? "auto") ?? .auto
        lastRoute = defaults.string(forKey:"lastRoute").flatMap(Route.init(rawValue:))
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let key = "\(path.status)|" + path.availableInterfaces.map(\.name).joined(separator:",")
            DispatchQueue.main.async {
                guard let self = self, key != self.lastPathKey else { return }
                let first = self.lastPathKey.isEmpty
                self.lastPathKey = key
                guard !first else { return }
                // Network changed (Wi-Fi switch, VPN/TUN on/off): forget the cached route and retry.
                TrafficClient.resetCache()
                if path.status == .satisfied { DispatchQueue.main.asyncAfter(deadline:.now()+3) { self.refresh() } }
            }
        }
        monitor.start(queue:DispatchQueue(label:"esai-impulse.path"))
        pathMonitor = monitor
        scheduleTimer()
        refresh()
    }

    // MARK: Data
    var leftGB: Double? { stats?.leftGB }
    var level: AlertLevel { leftGB.map { AlertLevel.of(leftGB:$0,threshold:thresholdGB) } ?? .normal }
    var nextRefresh: Date? { lastRefresh.map { $0.addingTimeInterval(Double(intervalMinutes)*60) } }

    func refresh() {
        guard let (login,password) = CredentialStore.credentials else {
            hasCredentials = false; errorKey = nil; return
        }
        hasCredentials = true
        guard !refreshing else { return }
        refreshing = true
        TrafficClient.fetch(login:login,password:password,mode:connectionMode) { [weak self] result in
            guard let self = self else { return }
            self.refreshing = false
            switch result {
            case .success(let (s,route)):
                self.lastRoute = route; self.defaults.set(route.rawValue,forKey:"lastRoute")
                self.stats = s; self.lastRefresh = Date(); self.errorKey = nil; self.lastFailed = false
                self.defaults.set(try? JSONEncoder().encode(s),forKey:"lastStats")
                self.defaults.set(self.lastRefresh,forKey:"lastRefresh")
                self.evaluateAlerts()
            case .failure(let e):
                self.lastFailed = true
                switch e {
                case .unauthorized: self.errorKey = "账号或密码错误（401）"; self.errorArgument = ""
                case .http(let code): self.errorKey = "服务器返回 HTTP %@"; self.errorArgument = String(code)
                case .decoding: self.errorKey = "无法解析返回数据"; self.errorArgument = ""
                case .network(let m):
                    self.errorKey = self.connectionMode == .direct ? "直连失败：%@" : "网络错误：%@"; self.errorArgument = m
                case .blocked(let sys, let dir):
                    if let dir = dir { self.errorKey = "系统网络与直连均失败：%@"; self.errorArgument = "\(sys) / \(dir)" }
                    else { self.errorKey = "连接可能被代理或 VPN 阻断（%@）。可在设置中将连接方式改为「直连」。"; self.errorArgument = sys }
                case .missingCredentials: self.errorKey = nil
                }
            }
            self.scheduleTimer()
        }
    }
    var errorText: String? { errorKey.map { translate($0,arguments:errorArgument.isEmpty ? [] : [errorArgument]) } }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer(timeInterval:Double(intervalMinutes)*60,repeats:true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!,forMode:.common)
    }

    private func evaluateAlerts() {
        guard let left = leftGB else { return }
        let previous = AlertLevel(rawValue:defaults.integer(forKey:"notifiedLevel")) ?? .normal
        let current = AlertLevel.of(leftGB:left,threshold:thresholdGB)
        if let fire = alertTransition(previous:previous,current:current) { notify(fire,left:left) }
        defaults.set(current.rawValue,forKey:"notifiedLevel")
    }

    private func notify(_ level: AlertLevel, left: Double) {
        let content = UNMutableNotificationContent()
        content.title = "ESAI Impulse"
        if level == .depleted {
            content.subtitle = translate("DataImpulse 流量已用尽")
            content.body = translate("当前剩余 %@，已超额 %@。",arguments:[formatTraffic(gb:left),formatTraffic(gb:max(0,-left))])
        } else {
            content.subtitle = translate("DataImpulse 流量偏低")
            content.body = translate("剩余 %@，低于 %@ GB 提醒阈值。",arguments:[formatTraffic(gb:left),thresholdText])
        }
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:"traffic-\(level.rawValue)-\(Date().timeIntervalSince1970)",content:content,trigger:nil))
    }
    var thresholdText: String { thresholdGB.truncatingRemainder(dividingBy:1) == 0 ? String(Int(thresholdGB)) : String(format:"%.1f",thresholdGB) }

    // MARK: Settings
    func saveCredentials(login: String, password: String) {
        let l = login.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !l.isEmpty, !password.isEmpty else { return }
        CredentialStore.write("login",l); CredentialStore.write("password",password)
        savedLogin = l; hasCredentials = true
        defaults.set(0,forKey:"notifiedLevel")
        refresh()
    }
    func clearCredentials() {
        CredentialStore.delete("login"); CredentialStore.delete("password")
        savedLogin = ""; hasCredentials = false; stats = nil; errorKey = nil
        defaults.removeObject(forKey:"lastStats"); defaults.removeObject(forKey:"lastRefresh"); lastRefresh = nil
    }
    func setConnectionMode(_ mode: ConnectionMode) {
        connectionMode = mode; defaults.set(mode.rawValue,forKey:"connectionMode")
        TrafficClient.resetCache(); refresh()
    }
    var routeText: String? {
        guard let route = lastRoute else { return nil }
        return translate(route == .direct ? "直连" : "系统网络")
    }
    func setStatusStyle(_ style: StatusStyle) { statusStyle = style; defaults.set(style.rawValue,forKey:"statusStyle") }
    var stale: Bool { isStale(lastSuccess:lastRefresh, lastFailed:lastFailed, intervalMinutes:intervalMinutes) }
    func statusSnapshot(spinPhase: Double?) -> StatusSnapshot {
        var s = StatusSnapshot()
        s.leftLabel = translate("剩余 %@"); s.usedLabel = translate("已用 %@")
        s.spinPhase = spinPhase
        guard let stats = stats else { s.fraction = 0; s.text = hasCredentials ? nil : nil; return s }
        s.text = formatTraffic(gb:stats.leftGB)
        s.fraction = ringFraction(leftGB:stats.leftGB, thresholdGB:thresholdGB)
        s.level = level
        s.stale = stale && spinPhase == nil
        s.usedPercent = stats.usedFraction*100
        return s
    }
    var tooltip: String {
        guard let s = stats else { return translate("ESAI Impulse · DataImpulse 剩余流量") }
        var lines = ["ESAI Impulse",
            translate("剩余 %@ / 总量 %@",arguments:[formatTraffic(gb:s.leftGB),formatTraffic(gb:TrafficStats.gb(s.total))]),
            translate("已用 %@",arguments:[String(format:"%.1f%%",s.usedFraction*100)])]
        if s.leftGB < 0 { lines.append(translate("已超额 %@",arguments:[formatTraffic(gb:-s.leftGB)])) }
        if let last = lastRefresh { lines.append(translate("上次刷新 %@ · %@",arguments:[timeText(last),routeText ?? "—"])) }
        if stale { lines.append(translate(lastFailed ? "上次刷新失败，数据可能已过期" : "数据可能已过期")) }
        return lines.joined(separator:"\n")
    }
    func setInterval(_ minutes: Int) { intervalMinutes = minutes; defaults.set(minutes,forKey:"intervalMinutes"); scheduleTimer() }
    func setThreshold(_ gb: Double) {
        thresholdGB = max(1,gb); defaults.set(thresholdGB,forKey:"thresholdGB")
        // Re-arm so a raised threshold can alert again; never alert just for lowering it.
        if let left = leftGB { defaults.set(min(defaults.integer(forKey:"notifiedLevel"),AlertLevel.of(leftGB:left,threshold:thresholdGB).rawValue),forKey:"notifiedLevel") }
        evaluateAlerts()
    }
    func openNotificationSettings() {
        if let url = URL(string:"x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    func setAccent(_ value: String) { guard let rgb = AccentRGB(hex:value) else { return }; accentHex = rgb.hex; defaults.set(accentHex,forKey:"accentHex") }
    var accentColor: Color {
        let rgb = AccentRGB(hex:accentHex)!
        return Color(nsColor:NSColor(name:nil) { appearance in
            let a = rgb.readable(onDark:appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua)
            return NSColor(srgbRed:a.red,green:a.green,blue:a.blue,alpha:1)
        })
    }
    var selectedAccent: Color { let rgb = AccentRGB(hex:accentHex)!; return Color(red:rgb.red,green:rgb.green,blue:rgb.blue) }
    func setAccentColor(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        setAccent(AccentRGB(red:rgb.redComponent,green:rgb.greenComponent,blue:rgb.blueComponent).hex)
    }
    var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    func setAppearance(_ value: String) { appearance = value; defaults.set(value,forKey:"appearance") }
    func setGlassBackground(_ value: Bool) { glassBackground = value; defaults.set(value,forKey:"glassBackground") }
    func setLanguage(_ value: AppLanguage) { language = value; resolvedLanguage = value.resolved(); defaults.set(value.rawValue,forKey:"language") }
    func translate(_ key: String, arguments: [String] = []) -> String {
        let format = L10n.text(key,language:resolvedLanguage)
        return arguments.isEmpty ? format : String(format:format,locale:resolvedLanguage.locale,arguments:arguments)
    }
    func timeText(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = resolvedLanguage.locale
        f.dateFormat = resolvedLanguage == .english ? "MMM d HH:mm" : "M月d日 HH:mm"
        return f.string(from:date)
    }
    var loginMessage: String? {
        if let error = loginError { return translate("登录启动设置失败：%@",arguments:[error]) }
        return loginNeedsApproval ? translate("请在系统设置的登录项中允许启动") : nil
    }
    func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            loginError = nil
            loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        } catch { loginError = error.localizedDescription }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
