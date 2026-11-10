import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @ObservedObject var model: TrafficModel
    @State private var range = UsageRange.thirty
    private var now: Date { model.now() }
    private var accent: Color { model.accentColor }
    private func t(_ key: String, _ arguments: String...) -> String { model.translate(key,arguments:arguments) }
    private var days: [UsageDay] {
        let all = model.usageDays(now:now)
        switch range {
        case .seven: return Array(all.suffix(7))
        case .thirty: return Array(all.suffix(30))
        case .all: return all
        }
    }
    private var isEmpty: Bool { days.allSatisfy(\.isMissing) }
    var body: some View {
        let summary = model.usageSummary(now:now)
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Text(t("用量历史")).font(.headline)
                Spacer()
                Button(t("导出 CSV")) { exportCSV() }.font(.caption).esaiGlassButton()
                    .disabled(isEmpty)
            }.padding(.horizontal,18).padding(.top,14).padding(.bottom,10)
            EsaiHairline()
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    EsaiGlassSegments(selection:Binding(get:{range.rawValue},set:{ range = UsageRange(rawValue:$0) ?? .thirty }),
                        options:[.init(id:"7",title:t("近 7 日")),.init(id:"30",title:t("近 30 日")),.init(id:"all",title:t("全部"))],
                        accent:accent,label:t("范围"))
                        .frame(minWidth:260,idealWidth:280)
                    Spacer(minLength:8)
                    Text(t("日界线：新加坡时间每天 10:00")).font(.caption).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.85)
                }
                HStack(alignment:.top,spacing:14) {
                    VStack(alignment:.leading,spacing:12) {
                        VStack(alignment:.leading,spacing:8) {
                            HStack(alignment:.firstTextBaseline) {
                                Text(t("每日用量")).font(.callout.weight(.semibold))
                                Spacer(minLength:8)
                                Text(t("完整日均 %@ · 米色为不完整",summary.average30.map { formatTraffic(gb:TrafficStats.gb($0)) } ?? t("暂无")))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.trailing)
                            }
                            if isEmpty {
                                emptyChart
                            } else {
                                UsageBarChart(days:days,accent:accent,language:model.resolvedLanguage)
                                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                            }
                        }.padding(14).frame(minHeight:220,maxHeight:.infinity).esaiCard(.sunken)
                        HStack(spacing:8) {
                            UsageMetricCard(title:t("今日已用"),
                                value:summary.todayUsedBytes.map { formatTraffic(gb:TrafficStats.gb($0)) } ?? t("暂无"),
                                subtitle:t("还剩 %@",UsageMath.formatDuration(summary.secondsLeftInDay,language:model.resolvedLanguage)))
                            UsageMetricCard(title:t("7 日日均"),
                                value:summary.average7.map { formatTraffic(gb:TrafficStats.gb($0)) } ?? t("暂无"),
                                subtitle:t("不含今日与不完整日"))
                            let predicted = predictedText(summary)
                            UsageMetricCard(title:t("预计用尽"),value:predicted.value,subtitle:predicted.sub,warn:summary.predictedWholeDays.map { $0 <= model.runoutWarnDays } ?? false)
                        }
                    }
                    dayList.frame(width:260)
                }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                Text(t("若一天的开始和结束都有记录，当天用量按累计已用的差值计算，中间休眠不影响。若关闭应用或电脑休眠跨越了新加坡时间 10:00 的日界线，中间用量会计入醒来后的那一天，并标成「数据不完整」，不算进日均。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(16)
        }
        .frame(minWidth:800,minHeight:560,alignment:.topLeading)
        .background(EsaiSurface.panel)
        .tint(accent)
        .preferredColorScheme(model.colorScheme)
        .environment(\.locale,model.resolvedLanguage.locale)
    }
    private var emptyChart: some View {
        VStack(spacing:8) {
            Spacer(minLength:0)
            Text(t("还没有用量记录")).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            Text(t("刷新一次后，会从今天开始按新加坡时间 10:00 记每天的用量。"))
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                .fixedSize(horizontal:false,vertical:true)
            Spacer(minLength:0)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }

    private var dayList: some View {
        VStack(alignment:.leading,spacing:6) {
            Text(t("每日明细")).font(.callout.weight(.semibold))
            listRow(t("日期"),t("用量"),nil,header:true)
            if isEmpty {
                Text(t("还没有用量记录")).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).padding(.top,12)
            } else if EsaiRenderMode.offscreen {
                VStack(spacing:0) {
                    ForEach(days.reversed(),id:\.id) { day in
                        listRow(UsageMath.formatDayID(day.id,language:model.resolvedLanguage),
                                day.usedBytes.map { formatTraffic(gb:TrafficStats.gb($0)) } ?? "—",
                                tag(day))
                    }
                }
            } else {
                ScrollView(.vertical) {
                    VStack(spacing:0) {
                        ForEach(days.reversed(),id:\.id) { day in
                            listRow(UsageMath.formatDayID(day.id,language:model.resolvedLanguage),
                                    day.usedBytes.map { formatTraffic(gb:TrafficStats.gb($0)) } ?? "—",
                                    tag(day))
                        }
                    }
                }
            }
        }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).esaiCard(.sunken)
    }
    private func listRow(_ date: String, _ usage: String, _ tag: String?, header: Bool = false) -> some View {
        HStack(spacing:6) {
            Text(date).frame(maxWidth:.infinity,alignment:.leading).lineLimit(1).minimumScaleFactor(0.8)
            if let tag = tag { Text(tag).font(.system(size:10,weight:.semibold))
                .foregroundStyle(tagColor(tag))
                .padding(.horizontal,6).padding(.vertical,1)
                .background(tagColor(tag).opacity(0.14),in:Capsule())
                .lineLimit(1).layoutPriority(1) }
            Text(usage).fontWeight(header ? .semibold : .regular).monospacedDigit().lineLimit(1)
        }
        .font(header ? .system(size:11,weight:.semibold) : .system(size:12.5))
        .foregroundStyle(header ? Color.secondary : Color.primary)
        .padding(.vertical,7)
        .overlay(alignment:.bottom) { Rectangle().fill(EsaiSurface.hairlineFaint).frame(height:0.5) }
    }
    private func tag(_ day: UsageDay) -> String? {
        if day.isToday { return t("今日") }
        if day.isMissing { return t("无数据") }
        if day.isIncomplete { return t("不完整") }
        return nil
    }
    private func tagColor(_ tag: String) -> Color {
        if tag == t("今日") { return accent }
        if tag == t("不完整") { return Color(red:0.56,green:0.48,blue:0.29) }
        return .secondary
    }
    private func predictedText(_ summary: UsageSummary) -> (value: String, sub: String) {
        guard let whole = summary.predictedWholeDays, let date = summary.predictedRunoutDate else {
            return (t("暂无"), t("完整日不足，暂无法预测"))
        }
        let text = UsageMath.formatSGTDate(date,language:model.resolvedLanguage)
        return (t("约 %@ 天",String(whole)), t("约 %@（新加坡日期）",text))
    }
    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "esai-impulse-usage.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        NSApp.activate(ignoringOtherApps:true)
        if panel.runModal() == .OK, let url = panel.url {
            try? model.usageCSV(now:now).write(to:url,atomically:true,encoding:.utf8)
        }
    }
}

final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    convenience init(model: TrafficModel) {
        let host = NSHostingController(rootView:HistoryView(model:model))
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:860,height:640),
                              styleMask:[.titled,.closable,.miniaturizable,.resizable],
                              backing:.buffered,defer:false)
        window.title = model.translate("用量历史")
        window.contentViewController = host
        window.setContentSize(NSSize(width:860,height:640))
        window.minSize = NSSize(width:800,height:560)
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window:window)
        window.delegate = self
    }
    func show() {
        guard let window = window else { return }
        window.title = (window.contentViewController as? NSHostingController<HistoryView>)?.rootView.model.translate("用量历史") ?? window.title
        NSApp.activate(ignoringOtherApps:true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Offscreen renders of the panel summary, history window, and run-out alert. No Keychain or network.
@MainActor enum UsageRender {
    static func run(to folder: String, dark: Bool) {
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        let suite = "com.fitzsmith2000.esai-impulse.usage-render"
        let d = UserDefaults(suiteName:suite)!
        d.removePersistentDomain(forName:suite)
        d.set("zh-Hans", forKey:"language")
        d.set(200.0, forKey:"thresholdGB")
        d.set(10, forKey:"runoutWarnDays")
        if let data = try? JSONEncoder().encode(UsageSample.sampleStats) { d.set(data, forKey:"lastStats") }
        d.set(UsageSample.sampleNow, forKey:"lastRefresh")
        let store = UsageSample.store(now:UsageSample.sampleNow)
        let model = TrafficModel(defaults:d, preview:true, usage:store)
        model.nowOverride = UsageSample.sampleNow
        model.prepareForUsageRender()
        model.panelSize = PopoverLayout.preferredSize
        try? FileManager.default.createDirectory(atPath:folder,withIntermediateDirectories:true)
        EsaiRenderMode.offscreen = true
        let scheme: ColorScheme = dark ? .dark : .light
        let bg = dark ? Color(white:0.13) : Color(white:0.97)

        func write(_ name: String, _ view: some View, width: CGFloat? = nil) {
            let r = ImageRenderer(content:view.background(bg).environment(\.colorScheme,scheme))
            r.scale = 2
            guard let img = r.nsImage, let tiff = img.tiffRepresentation,
                  let png = NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) else { fatalError("render failed \(name)") }
            try! png.write(to:URL(fileURLWithPath:"\(folder)/\(name)"))
            print("RENDERED \(name)")
        }

        let panel = TrafficPanel(model:model)
            .frame(width:model.panelSize.width,height:model.panelSize.height)
        write(dark ? "panel-dark.png" : "panel.png", panel)

        let history = HistoryView(model:model)
            .frame(width:860,height:640,alignment:.topLeading)
        write(dark ? "history-dark.png" : "history.png", history)

        let summary = model.usageSummary(now:UsageSample.sampleNow)
        let info = RunoutAlertInfo(days:summary.predictedWholeDays ?? 8,
            remainingBytes:UsageSample.sampleStats.left,
            averageBytes:summary.average7, todayUsedBytes:summary.todayUsedBytes,
            runoutDate:summary.predictedRunoutDate)
        let alert = RunoutAlertView(model:model, info:info, onConfirm:{}).padding(4)
        write(dark ? "alert-dark.png" : "alert.png", alert)
        d.removePersistentDomain(forName:suite)
        print("RENDERED usage shots to \(folder)")
    }
}


/// Broader offscreen QA pack: empty / 1-day / English / dark / settings tabs. No Keychain or network.
@MainActor enum QARender {
    static func run(to folder: String) {
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(atPath:folder,withIntermediateDirectories:true)
        UsageRender.run(to:folder, dark:false)
        UsageRender.run(to:folder, dark:true)
        writeUsage(folder, name:"panel-en.png", dark:false, english:true, store:UsageSample.store())
        writeUsage(folder, name:"panel-en-dark.png", dark:true, english:true, store:UsageSample.store())
        writeUsage(folder, name:"history-en.png", dark:false, english:true, store:UsageSample.store(), kind:.history)
        writeUsage(folder, name:"history-en-dark.png", dark:true, english:true, store:UsageSample.store(), kind:.history)
        writeUsage(folder, name:"history-empty.png", dark:false, english:false, store:UsageStore.memory(), kind:.history)
        writeUsage(folder, name:"history-1day.png", dark:false, english:false, store:oneDayStore(), kind:.history)
        writeUsage(folder, name:"alert-en.png", dark:false, english:true, store:UsageSample.store(), kind:.alert)
        writeSettings(folder, tab:"account", name:"settings-account.png", dark:false)
        writeSettings(folder, tab:"alerts", name:"settings-alerts.png", dark:false)
        writeSettings(folder, tab:"alerts", name:"settings-alerts-dark.png", dark:true)
        writeSettings(folder, tab:"appearance", name:"settings-appearance.png", dark:false)
        writeSettings(folder, tab:"appearance", name:"settings-appearance-dark.png", dark:true)
        writeSettings(folder, tab:"general", name:"settings-general.png", dark:false)
        print("RENDERED QA pack to \(folder)")
    }

    private enum Kind { case panel, history, alert }

    private static func oneDayStore() -> UsageStore {
        let s = UsageStore.memory()
        let start = UsageCalendar.interval(forDay:"2026-11-09").start
        _ = s.record(used:4_200e9,total:5_661.8e9,left:1_461.8e9,at:start)
        _ = s.record(used:4_242.6e9,total:5_661.8e9,left:1_419.2e9,at:UsageSample.sampleNow)
        return s
    }

    private static func writeUsage(_ folder: String, name: String, dark: Bool, english: Bool, store: UsageStore, kind: Kind = .panel) {
        let suite = "com.fitzsmith2000.esai-impulse.qa-\(name)"
        let d = UserDefaults(suiteName:suite)!
        d.removePersistentDomain(forName:suite)
        d.set(english ? "en" : "zh-Hans", forKey:"language")
        d.set(200.0, forKey:"thresholdGB")
        d.set(10, forKey:"runoutWarnDays")
        d.set(dark ? "dark" : "light", forKey:"appearance")
        if let data = try? JSONEncoder().encode(UsageSample.sampleStats) { d.set(data, forKey:"lastStats") }
        d.set(UsageSample.sampleNow, forKey:"lastRefresh")
        let model = TrafficModel(defaults:d, preview:true, usage:store)
        model.nowOverride = UsageSample.sampleNow
        model.prepareForUsageRender()
        model.panelSize = PopoverLayout.preferredSize
        EsaiRenderMode.offscreen = true
        let scheme: ColorScheme = dark ? .dark : .light
        let bg = dark ? Color(white:0.13) : Color(white:0.97)
        let view: AnyView
        switch kind {
        case .panel:
            view = AnyView(TrafficPanel(model:model).frame(width:model.panelSize.width,height:model.panelSize.height))
        case .history:
            view = AnyView(HistoryView(model:model).frame(width:860,height:640,alignment:.topLeading))
        case .alert:
            let summary = model.usageSummary(now:UsageSample.sampleNow)
            let info = RunoutAlertInfo(days:summary.predictedWholeDays ?? 8,
                remainingBytes:UsageSample.sampleStats.left,
                averageBytes:summary.average7, todayUsedBytes:summary.todayUsedBytes,
                runoutDate:summary.predictedRunoutDate)
            view = AnyView(RunoutAlertView(model:model, info:info, onConfirm:{}).padding(4))
        }
        let r = ImageRenderer(content:view.background(bg).environment(\.colorScheme,scheme))
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) else { fatalError("qa render failed \(name)") }
        try! png.write(to:URL(fileURLWithPath:"\(folder)/\(name)"))
        d.removePersistentDomain(forName:suite)
        print("RENDERED \(name)")
    }

    private static func writeSettings(_ folder: String, tab: String, name: String, dark: Bool) {
        let suite = "com.fitzsmith2000.esai-impulse.qa-settings-\(name)"
        let d = UserDefaults(suiteName:suite)!
        d.removePersistentDomain(forName:suite)
        d.set("zh-Hans", forKey:"language")
        d.set(dark ? "dark" : "light", forKey:"appearance")
        d.set(200.0, forKey:"thresholdGB")
        d.set(10, forKey:"runoutWarnDays")
        d.set(0.0, forKey:"dailyThresholdGB")
        let typo = StatusTypography.defaults
        typo.save(d)
        d.set("iconText", forKey:"statusStyle")
        let model = TrafficModel(defaults:d, preview:true)
        model.navigation.showingSettings = true
        model.navigation.settingsTab = tab
        model.panelSize = NSSize(width:PopoverLayout.preferredSize.width, height:1600)
        EsaiRenderMode.offscreen = true
        let scheme: ColorScheme = dark ? .dark : .light
        let bg = dark ? Color(white:0.13) : Color(white:0.97)
        let host = NSHostingView(rootView:TrafficPanel(model:model).settingsTabForRender(tab))
        host.setFrameSize(host.fittingSize)
        let r = ImageRenderer(content:TrafficPanel(model:model).settingsTabForRender(tab)
            .background(bg).environment(\.colorScheme,scheme))
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) else { fatalError("qa settings failed \(name)") }
        try! png.write(to:URL(fileURLWithPath:"\(folder)/\(name)"))
        d.removePersistentDomain(forName:suite)
        print("RENDERED \(name)")
    }
}
