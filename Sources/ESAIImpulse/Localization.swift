import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, chinese = "zh-Hans", english = "en"
    var id: String { rawValue }
    var nativeName: String {
        switch self { case .system: return "跟随系统"; case .chinese: return "简体中文"; case .english: return "English" }
    }
    func resolved(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        return preferred.first?.lowercased().hasPrefix("zh") == true ? .chinese : .english
    }
    var locale: Locale { Locale(identifier:self == .chinese ? "zh_CN" : "en_US") }
}

enum L10n {
    static func text(_ key: String, language: AppLanguage) -> String {
        language == .chinese ? key : english[key] ?? key
    }
    static let english: [String:String] = [
        "剩余流量":"Remaining", "总流量":"Total", "已用":"Used", "已用 %@":"%@ used",
        "已超额":"Overdrawn", "已超额 %@":"Overdrawn by %@", "流量充足":"Healthy", "流量偏低":"Low",
        "流量用尽":"Depleted", "未配置账号":"No account", "上次刷新：%@":"Last refresh: %@", "尚未刷新":"Not refreshed yet",
        "刷新":"Refresh", "正在刷新…":"Refreshing…", "刷新失败":"Refresh failed",
        "请在设置中填写 DataImpulse 账号和密码。":"Enter your DataImpulse login and password in Settings.",
        "去设置":"Open settings", "每 %@ 分钟自动刷新":"Auto refresh every %@ min", "下次：%@":"Next: %@",
        "低于 %@ GB 时提醒":"Alert below %@ GB", "流量详情":"Traffic details", "提醒":"Alerts",
        "账号":"Account", "外观":"Appearance", "通用":"General", "设置":"Settings", "返回":"Back",
        "DataImpulse 账号":"DataImpulse account", "登录名":"Login", "密码":"Password",
        "保存并刷新":"Save & refresh", "清除":"Clear", "已保存到钥匙串":"Saved to Keychain",
        "账号和密码仅保存在 macOS 钥匙串中，不会写入文件或日志。":"Stored only in the macOS Keychain, never in files or logs.",
        "填写代理套餐（Plan）的登录名和密码，与 gw.dataimpulse.com 使用的凭据相同。":"Use your proxy plan login and password (the gw.dataimpulse.com credentials).",
        "刷新间隔":"Refresh interval", "%@ 分钟":"%@ min", "低流量提醒":"Low traffic alert", "提醒阈值":"Threshold",
        "剩余低于阈值时，状态栏数字变为橙色并发送一次系统通知；用尽时变为红色并再通知一次。":"Below the threshold the status number turns orange and one notification is sent; at zero it turns red and notifies once more.",
        "系统通知":"System notifications", "打开通知设置":"Open Notification Settings",
        "外观模式":"Appearance", "跟随系统":"Follow system", "浅色":"Light", "深色":"Dark", "强调色":"Accent color",
        "透明玻璃背景":"Transparent glass background", "面板会透出桌面背景；关闭后使用实色面板。":"The panel reveals the desktop behind it; turn off for a solid surface.",
        "选择经典颜色，或调出属于你的 esai。":"Choose a classic color or make it your own.",
        "esai 绿":"esai", "经典蓝":"Blue", "鸢尾紫":"Violet", "琥珀橙":"Amber", "玫瑰红":"Rose", "湖水青":"Teal",
        "自定义颜色":"Custom color", "自定义强调色取色器":"Custom accent color picker", "强调色 HEX 色值":"Accent HEX color",
        "应用":"Apply", "请输入六位 HEX 色值，例如 #2878ED。":"Enter a six-digit HEX color, such as #2878ED.",
        "强调色预览":"Accent preview", "实时应用并保存；浅色和深色模式自动调整可读性。":"Applies and saves instantly. Adjusts for readability in light and dark modes.",
        "语言":"Language", "界面语言":"Interface language",
        "跟随系统会自动使用电脑的首选语言，切换立即生效。":"Follows your computer’s preferred language. Changes apply instantly.",
        "当前语言：%@":"Current language: %@", "登录时启动":"Launch at login",
        "打开登录项设置":"Open Login Items", "请在系统设置的登录项中允许启动":"Allow ESAI Impulse in System Settings → Login Items",
        "登录启动设置失败：%@":"Could not change login setting: %@",
        "版本 %@":"Version %@", "开源许可":"Licenses", "退出":"Quit", "打开设置":"Open settings", "退出 ESAI Impulse":"Quit ESAI Impulse",
        "ESAI Impulse · DataImpulse 剩余流量":"ESAI Impulse · DataImpulse traffic left",
        "DataImpulse 流量偏低":"DataImpulse traffic is low", "DataImpulse 流量已用尽":"DataImpulse traffic is used up",
        "剩余 %@，低于 %@ GB 提醒阈值。":"%@ left, below your %@ GB threshold.",
        "当前剩余 %@，已超额 %@。":"%@ left, overdrawn by %@.",
        "账号或密码错误（401）":"Wrong login or password (401)", "账号或密码错误":"Wrong login or password", "网络错误：%@":"Network error: %@",
        "服务器返回 HTTP %@":"Server returned HTTP %@", "无法解析返回数据":"Could not parse the response",
        "仅显示信息，不会执行任何操作。":"Informational only.", "在 GitHub 上查看项目":"View project on GitHub",
        "状态栏样式":"Status bar style", "状态栏":"Status bar", "恢复默认":"Restore Defaults", "状态栏预览":"Status bar preview",
        "字号":"Font size", "字重":"Weight", "常规":"Regular", "中等":"Medium", "半粗":"Semibold", "图标大小":"Icon size",
        "图标与文字间距":"Icon spacing", "两行字号":"Two-line size",
        "默认值：文字 10.5 pt 常规、图标 19 pt、间距 9 pt、两行 8.5 pt。修改即时生效。":"Defaults: 10.5 pt regular text, 19 pt icon, 9 pt spacing, 8.5 pt two-line text. Changes apply instantly.", "图标+数字":"Icon + number", "仅图标":"Icon only", "两行紧凑":"Two lines",
        "环的长度 = 剩余 ÷ 提醒阈值；偏低变橙，用尽变红并带角标。":"Ring length = remaining ÷ alert threshold. Orange when low, red with a badge when used up.",
        "剩余 %@":"Left %@", "立即刷新":"Refresh Now", "设置…":"Settings…",
        "剩余 %@ / 总量 %@":"Remaining %@ / Total %@", "上次刷新 %@ · %@":"Last refresh %@ · %@",
        "数据可能已过期":"Data may be out of date", "上次刷新失败，数据可能已过期":"Last refresh failed; data may be out of date",
        "连接方式":"Connection", "自动（推荐）":"Automatic (recommended)", "走系统网络":"System network", "直连（绕过代理 / VPN）":"Direct (bypass proxy / VPN)",
        "自动：先走系统网络，失败时经物理网卡直连 DataImpulse，绕过代理 / VPN 的 TUN。":"Automatic tries the system network first, then connects directly over the physical interface, bypassing proxy/VPN TUN.",
        "直连":"Direct", "系统网络":"System", "已绕过代理 / VPN，经物理网卡直连":"Bypassed proxy/VPN via the physical interface", "经系统网络连接":"Connected via the system network",
        "直连失败：%@":"Direct connection failed: %@", "系统网络与直连均失败：%@":"Both system and direct connections failed: %@",
        "连接可能被代理或 VPN 阻断（%@）。可在设置中将连接方式改为「直连」。":"The connection may be blocked by a proxy or VPN (%@). Try Connection → Direct in Settings."
    ]
}
