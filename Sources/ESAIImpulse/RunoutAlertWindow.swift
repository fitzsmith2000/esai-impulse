import AppKit
import SwiftUI

struct RunoutAlertInfo: Equatable {
    var days: Int
    var remainingBytes: Double
    var averageBytes: Double?
    var todayUsedBytes: Double?
    var runoutDate: Date? = nil
}

struct RunoutAlertView: View {
    @ObservedObject var model: TrafficModel
    let info: RunoutAlertInfo
    var onConfirm: () -> Void
    private var accentWarn: Color { Color(red:0.78,green:0.42,blue:0.03) }
    private func t(_ key: String, _ arguments: String...) -> String { model.translate(key,arguments:arguments) }
    var body: some View {
        VStack(spacing:0) {
            VStack(spacing:12) {
                ring
                Text(t("流量将在约 %@ 天后用尽",String(info.days)))
                    .font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                Text(bodyText)
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal:false,vertical:true)
                HStack(spacing:8) {
                    card(t("剩余"),formatTraffic(gb:TrafficStats.gb(info.remainingBytes)))
                    card(t("今日已用"),info.todayUsedBytes.map { formatTraffic(gb:TrafficStats.gb($0)) } ?? t("暂无"))
                }
                Button(action:onConfirm) { Text(t("确认，我知道了")).frame(maxWidth:.infinity) }
                    .modifier(RunoutConfirmStyle(warn:accentWarn))
                Text(t("这是独立桌面窗口，点确认前会一直留着"))
                    .font(.system(size:11)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }.padding(22)
        }
        .frame(width:390)
        .background(EsaiSurface.panel)
        .preferredColorScheme(model.colorScheme)
        .environment(\.locale,model.resolvedLanguage.locale)
    }
    private var ring: some View {
        let fraction = min(1, max(0.08, Double(info.days)/Double(max(1,model.runoutWarnDays))))
        return ZStack {
            Circle().stroke(Color.primary.opacity(0.08),lineWidth:12)
            Circle().trim(from:0,to:fraction)
                .stroke(accentWarn,style:StrokeStyle(lineWidth:12,lineCap:.round))
                .rotationEffect(.degrees(-90))
            VStack(spacing:0) {
                Text("\(info.days)").font(.system(size:32,weight:.semibold,design:.rounded)).monospacedDigit()
                Text(t("天后")).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(width:108,height:108).padding(.top,4)
    }
    private func card(_ title: String, _ value: String) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).esaiCard()
    }
    private var bodyText: String {
        let left = formatTraffic(gb:TrafficStats.gb(info.remainingBytes))
        let avg = info.averageBytes.map { formatTraffic(gb:TrafficStats.gb($0)) } ?? "—"
        var date = ""
        let instant = info.runoutDate ?? UsageMath.forecast(remainingBytes:info.remainingBytes, averageBytes:info.averageBytes ?? 0, now:model.now())?.date
        if let instant = instant {
            date = UsageMath.formatSGTDate(instant,language:model.resolvedLanguage)
        }
        if date.isEmpty { return t("剩余 %@，近 7 日日均 %@。请确认你已看到这条提醒。",left,avg) }
        return t("剩余 %@，近 7 日日均 %@。预计用尽日为 %@（新加坡日期）。请确认你已看到这条提醒。",left,avg,date)
    }
}

final class RunoutWindowController: NSWindowController, NSWindowDelegate {
    private var model: TrafficModel
    private var onConfirm: () -> Void
    private var host: NSHostingView<RunoutAlertView>?
    init(model: TrafficModel, onConfirm: @escaping () -> Void) {
        self.model = model
        self.onConfirm = onConfirm
        let dummy = RunoutAlertInfo(days:0,remainingBytes:0)
        let view = RunoutAlertView(model:model,info:dummy,onConfirm:onConfirm)
        let hosting = NSHostingView(rootView:view)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:390,height:420),
                              styleMask:[.titled],
                              backing:.buffered,defer:false)
        window.title = "ESAI Impulse"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        window.center()
        self.host = hosting
        super.init(window:window)
        window.delegate = self
        hosting.setFrameSize(hosting.fittingSize)
        window.setContentSize(hosting.fittingSize)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowShouldClose(_ sender: NSWindow) -> Bool { false }
    func update(_ info: RunoutAlertInfo) {
        let view = RunoutAlertView(model:model,info:info,onConfirm:onConfirm)
        if host == nil {
            let hosting = NSHostingView(rootView:view)
            window?.contentView = hosting
            host = hosting
        } else {
            host?.rootView = view
        }
        if let host = host {
            host.setFrameSize(host.fittingSize)
            window?.setContentSize(host.fittingSize)
        }
    }
    func show(_ info: RunoutAlertInfo) {
        update(info)
        guard let window = window else { return }
        if !window.isVisible { window.center() }
        // Don't steal focus if the window is already up and the user is elsewhere;
        // first appearance does order front so the confirm target is visible.
        if window.isVisible { window.orderFront(nil) }
        else { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    }
    func dismiss() { window?.orderOut(nil) }
}

private struct RunoutConfirmStyle: ViewModifier {
    var warn: Color
    func body(content: Content) -> some View {
        if EsaiRenderMode.offscreen {
            content.font(.callout.weight(.semibold)).foregroundStyle(.white)
                .padding(.vertical,8)
                .background(warn,in:Capsule())
                .buttonStyle(.plain)
        } else {
            content.esaiGlassButton(prominent:true).tint(warn)
        }
    }
}
