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
        "默认值：文字 10.5 pt 常规、图标 19 pt、间距 9 pt、两行 8.5 pt、偏移 0。修改即时生效。":"Defaults: 10.5 pt regular text, 19 pt icon, 9 pt spacing, 8.5 pt two-line text, offset 0. Changes apply instantly.",
        "文字上下偏移":"Text offset", "双击滑块归零；正值上移，负值下移":"Double-click to reset; positive moves up, negative down", "归零":"Reset to 0",
        "已保存的配置":"Saved configurations", "导出配置…":"Export Configurations…", "导入配置…":"Import Configurations…", "导入 / 导出 JSON":"Import / export JSON",
        "保存为配置…":"Save as Configuration…", "覆盖保存":"Overwrite", "保存为配置":"Save as Configuration", "保存":"Save", "取消":"Cancel",
        "配置包含样式、字号、字重、图标大小、间距、两行字号和文字偏移。点击即可切换；「默认」为内置配置，不可删除。":"A configuration stores style, font size, weight, icon size, spacing, two-line size and text offset. Click one to switch; the built-in Default can't be deleted.",
        "图标 %@":"Icon %@", "间距 %@":"Gap %@", "偏移 %@":"Offset %@", "已修改":"Modified", "重命名…":"Rename…", "删除…":"Delete…", "重命名配置":"Rename Configuration", "重命名":"Rename",
        "删除配置「%@」？":"Delete configuration “%@”?", "此操作无法撤销。":"This can't be undone.", "删除":"Delete", "无法导入：文件不是有效的配置 JSON。":"Couldn't import: the file isn't a valid configuration JSON.", "配置":"Config", "默认":"Default", "图标+数字":"Icon + number", "仅图标":"Icon only", "两行紧凑":"Two lines",
        "环的长度 = 剩余 ÷ 提醒阈值；偏低变橙，用尽变红并带角标。":"Ring length = remaining ÷ alert threshold. Orange when low, red with a badge when used up.",
        "剩余 %@":"Left %@", "立即刷新":"Refresh Now", "设置…":"Settings…",
        "剩余 %@ / 总量 %@":"Remaining %@ / Total %@", "上次刷新 %@ · %@":"Last refresh %@ · %@",
        "数据可能已过期":"Data may be out of date", "上次刷新失败，数据可能已过期":"Last refresh failed; data may be out of date",
        "连接方式":"Connection", "自动（推荐）":"Automatic (recommended)", "走系统网络":"System network", "直连（绕过代理 / VPN）":"Direct (bypass proxy / VPN)",
        "自动：先走系统网络，失败时经物理网卡直连 DataImpulse，绕过代理 / VPN 的 TUN。":"Automatic tries the system network first, then connects directly over the physical interface, bypassing proxy/VPN TUN.",
        "直连":"Direct", "系统网络":"System", "已绕过代理 / VPN，经物理网卡直连":"Bypassed proxy/VPN via the physical interface", "经系统网络连接":"Connected via the system network",
        "直连失败：%@":"Direct connection failed: %@", "系统网络与直连均失败：%@":"Both system and direct connections failed: %@",
        "连接可能被代理或 VPN 阻断（%@）。可在设置中将连接方式改为「直连」。":"The connection may be blocked by a proxy or VPN (%@). Try Connection → Direct in Settings.",
        "近 7 日用量":"Last 7 days", "打开用量历史":"Open usage history", "用量历史":"Usage history",
        "今日 %@ · 还剩 %@":"Today %@ · %@ left", "还剩 %@ · 从本次更新开始记录":"%@ left in the day · Recording starts with this update",
        "预计约 %@ 天后用尽":"About %@ days until it runs out", "约 %@（新加坡日期）":"Around %@ (Singapore date)",
        "7 日日均":"7-day average", "30 日日均":"30-day average", "暂无":"No data",
        "仅计完整日，不含今日":"Completed days only, not today",
        "%@ 个完整日":"%@ completed days", "%@ / %@ 个完整日":"%@ / %@ completed",
        "导出 CSV":"Export CSV", "近 7 日":"7 days", "近 30 日":"30 days", "全部":"All", "范围":"Range",
        "日界线：新加坡时间每天 10:00":"A day starts at 10:00 Singapore time",
        "每日用量":"Daily usage", "完整日均 %@ · 米色为不完整":"Completed-day average %@ · Tan = incomplete",
        "今日已用":"Today so far", "还剩 %@":"%@ left in the day", "不含今日与不完整日":"Excludes today and incomplete days",
        "预计用尽":"Estimated run-out", "约 %@ 天":"About %@ days", "完整日不足，暂无法预测":"Not enough completed days to estimate",
        "每日明细":"Daily list", "日期":"Date", "用量":"Usage", "今日":"Today", "不完整":"Incomplete", "无数据":"No data",
        "若一天的开始和结束都有记录，当天用量按累计已用的差值计算，中间休眠不影响。若关闭应用或电脑休眠跨越了新加坡时间 10:00 的日界线，中间用量会计入醒来后的那一天，并标成「数据不完整」，不算进日均。":"If a day is recorded at both ends, usage is the change in cumulative used, even if the computer slept in between. If the app is closed or the computer sleeps across the 10:00 Singapore boundary, that usage is counted on the wake day, marked incomplete, and left out of averages.",
        "流量将在约 %@ 天后用尽":"Traffic will run out in about %@ days", "天后":"days left", "天":"days",
        "确认，我知道了":"Confirm, I understand",
        "这是独立桌面窗口，点确认前会一直留着":"This desktop window stays until you confirm.",
        "剩余 %@，近 7 日日均 %@。请确认你已看到这条提醒。":"%@ left, 7-day average %@. Please confirm you have seen this warning.",
        "剩余 %@，近 7 日日均 %@。预计用尽日为 %@（新加坡日期）。请确认你已看到这条提醒。":"%@ left, 7-day average %@. Estimated run-out: %@ (Singapore date). Please confirm you have seen this warning.",
        "用尽预测预警":"Run-out forecast warning", "提前几天提醒":"Warn this many days ahead",
        "按近 7 日日均预测还能用多少天。剩余天数首次降到该值或以下时弹出桌面窗口，需点确认才会关闭；之后在 7、3、1 天再提醒。流量回升到该值以上后重新待命。":"Uses the 7-day average to estimate how many days remain. A desktop window appears the first time that estimate falls to this value or below, and stays until you confirm. It warns again at 7, 3 and 1 days, and re-arms if remaining days climb back above the threshold.",
        "每日用量提醒":"Daily usage alert", "每日阈值":"Daily threshold", "关闭":"Off",
        "今日用量达到该值时发送一次系统通知。设为 0 表示关闭，默认关闭。":"Sends one notification on a Singapore day when today's usage reaches this amount. Set to 0 to turn it off (the default).",
        "DataImpulse 今日用量已达阈值":"DataImpulse daily usage reached your threshold",
        "今日已用 %@，超过 %@ GB 的每日提醒。":"%@ used today, above your %@ GB daily alert.",
        "用量历史…":"Usage History…",
        "剩余":"Remaining",
        "还没有用量记录":"No usage recorded yet",
        "刷新一次后，会从今天开始按新加坡时间 10:00 记每天的用量。":"After a refresh, daily usage is recorded from today, with days starting at 10:00 Singapore time.",
        "配置名称":"Configuration name"
    ]
}
