import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @ObservedObject var model: TrafficModel
    @State private var range = UsageRange.thirty
    var now: Date = Date()
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
    var body: some View {
        let summary = model.usageSummary(now:now)
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Text(t("用量历史")).font(.headline)
                Spacer()
                Button(t("导出 CSV")) { exportCSV() }.font(.caption).esaiGlassButton()
                    .disabled(model.usageDays(now:now).allSatisfy(\.isMissing) && model.usageDays(now:now).filter{!$0.isToday}.isEmpty)
            }.padding(.horizontal,18).padding(.top,14).padding(.bottom,10)
            EsaiHairline()
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    EsaiGlassSegments(selection:Binding(get:{range.rawValue},set:{ range = UsageRange(rawValue:$0) ?? .thirty }),
                        options:[.init(id:"7",title:t("近 7 日")),.init(id:"30",title:t("近 30 日")),.init(id:"all",title:t("全部"))],
                        accent:accent,label:t("范围"))
                        .frame(width:260)
                    Spacer()
                    Text(t("日界线：新加坡时间每天 10:00")).font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment:.top,spacing:14) {
                    VStack(alignment:.leading,spacing:12) {
                        VStack(alignment:.leading,spacing:8) {
                            HStack {
                                Text(t("每日用量")).font(.callout.weight(.semibold))
                                Spacer()
                                Text(t("完整日均 %@ · 米色为不完整",summary.average30.map { formatTraffic(gb:TrafficStats.gb($0)) } ?? t("暂无")))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            UsageBarChart(days:days,accent:accent).frame(minHeight:220,maxHeight:280)
                        }.padding(14).esaiCard(.sunken)
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
                    dayList.frame(width:250)
                }
                Text(t("若一天的开始和结束都有记录，当天用量按累计已用的差值计算，中间休眠不影响。若关闭应用或电脑休眠跨越了新加坡时间 10:00 的日界线，中间用量会计入醒来后的那一天，并标成「数据不完整」，不算进日均。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(16)
        }
        .frame(minWidth:780,minHeight:520)
        .background(EsaiSurface.panel)
        .tint(accent)
        .preferredColorScheme(model.colorScheme)
        .environment(\.locale,model.resolvedLanguage.locale)
    }

    private var dayList: some View {
        VStack(alignment:.leading,spacing:6) {
            Text(t("每日明细")).font(.callout.weight(.semibold))
            VStack(spacing:0) {
                listRow(t("日期"),t("用量"),nil,header:true)
                ForEach(days.reversed(),id:\.id) { day in
                    listRow(listDate(day.id),
                            day.usedBytes.map { formatTraffic(gb:TrafficStats.gb($0)) } ?? "—",
                            tag(day))
                }
            }
        }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).esaiCard(.sunken)
    }
    private func listRow(_ date: String, _ usage: String, _ tag: String?, header: Bool = false) -> some View {
        HStack(spacing:8) {
            Text(date).frame(maxWidth:.infinity,alignment:.leading)
            if let tag = tag { Text(tag).font(.system(size:10,weight:.semibold))
                .foregroundStyle(tagColor(tag))
                .padding(.horizontal,6).padding(.vertical,1)
                .background(tagColor(tag).opacity(0.14),in:Capsule()) }
            Text(usage).fontWeight(header ? .semibold : .semibold).monospacedDigit()
        }
        .font(header ? .system(size:11,weight:.semibold) : .system(size:12.5))
        .foregroundStyle(header ? Color.secondary : Color.primary)
        .padding(.vertical,7)
        .overlay(alignment:.bottom) { Rectangle().fill(EsaiSurface.hairlineFaint).frame(height:0.5) }
    }
    private func listDate(_ id: String) -> String {
        let parts = id.split(separator:"-").compactMap { Int($0) }
        guard parts.count == 3 else { return id }
        return model.resolvedLanguage == .english ? String(format:"%d/%d",parts[1],parts[2]) : String(format:"%d月%d日",parts[1],parts[2])
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
        guard let whole = summary.predictedWholeDays, let frac = summary.predictedDays else {
            return (t("暂无"), t("完整日不足，暂无法预测"))
        }
        let date = UsageMath.formatSGTDate(UsageMath.predictedRunoutDate(predictedDays:frac,now:now),language:model.resolvedLanguage)
        return (t("约 %@ 天",String(whole)), t("约 %@（新加坡日期）",date))
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
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:820,height:580),
                              styleMask:[.titled,.closable,.miniaturizable,.resizable],
                              backing:.buffered,defer:false)
        window.title = model.translate("用量历史")
        window.contentViewController = host
        window.setContentSize(NSSize(width:820,height:580))
        window.minSize = NSSize(width:700,height:480)
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

        let history = HistoryView(model:model, now:UsageSample.sampleNow)
            .frame(width:820,height:580)
        write(dark ? "history-dark.png" : "history.png", history)

        let summary = model.usageSummary(now:UsageSample.sampleNow)
        let info = RunoutAlertInfo(days:summary.predictedWholeDays ?? 8,
            remainingBytes:UsageSample.sampleStats.left,
            averageBytes:summary.average7, todayUsedBytes:summary.todayUsedBytes)
        let alert = RunoutAlertView(model:model, info:info, onConfirm:{}).padding(4)
        write(dark ? "alert-dark.png" : "alert.png", alert)
        d.removePersistentDomain(forName:suite)
        print("RENDERED usage shots to \(folder)")
    }
}
