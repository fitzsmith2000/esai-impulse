import AppKit
import SwiftUI

/// Vertical usage bars for the history chart or the panel sparkline.
struct UsageBarChart: View {
    let days: [UsageDay]
    var accent: Color
    var compact = false
    var language: AppLanguage = .chinese
    @State private var hoveredID: String? = nil
    @State private var chipWidth: CGFloat = 120
    var body: some View {
        let finite = days.compactMap(\.usedBytes)
        let yMax = UsageChartLayout.yMaxBytes(finite.max() ?? 0)
        GeometryReader { proxy in
            let gap = CGFloat(UsageChartLayout.gap(compact:compact))
            let n = max(1, days.count)
            let axisW: CGFloat = compact ? 0 : 36
            let labelH: CGFloat = compact ? 16 : 20
            let plotW = max(1, proxy.size.width - axisW)
            let plotH = max(1, proxy.size.height - labelH)
            let width = CGFloat(UsageChartLayout.barWidth(dayCount:n, available:Double(plotW), compact:compact))
            let plotOriginX: CGFloat = compact ? 0 : axisW
            ZStack(alignment:.topLeading) {
                HStack(alignment:.bottom,spacing:0) {
                    if !compact {
                        VStack(alignment:.trailing,spacing:0) {
                            Text(formatTraffic(gb:TrafficStats.gb(yMax)))
                                .font(.system(size:9)).foregroundStyle(.tertiary).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength:0)
                        }.frame(width:axisW,height:plotH,alignment:.topTrailing)
                        .padding(.trailing,4)
                    }
                    HStack(alignment:.bottom,spacing:gap) {
                        ForEach(Array(days.enumerated()),id:\.offset) { _, day in
                            VStack(spacing:compact ? 3 : 5) {
                                Spacer(minLength:0)
                                cap(day,maxBytes:yMax,width:width,height:plotH,highlighted:hoveredID == day.id)
                                Text(shortLabel(day.id)).font(.system(size:compact ? 8 : 9.5))
                                    .foregroundStyle(hoveredID == day.id ? .secondary : .tertiary).monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(width:width)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(_): hoveredID = day.id
                                case .ended: if hoveredID == day.id { hoveredID = nil }
                                }
                            }
                        }
                    }
                    Spacer(minLength:0)
                }
                if let hoveredID, let idx = days.firstIndex(where:{ $0.id == hoveredID }) {
                    let rawX = plotOriginX + CGFloat(idx)*(width+gap) + width/2
                    let x = CGFloat(UsageChartLayout.clampCenter(Double(rawX), half:Double(chipWidth/2), total:Double(proxy.size.width)))
                    Color.clear.frame(width:0,height:0)
                        .overlay(hoverChip(days[idx]).background(GeometryReader { g in
                            Color.clear.preference(key:ChipWidthKey.self,value:g.size.width)
                        }))
                        .offset(x:x, y: compact ? 1 : 2)
                        .allowsHitTesting(false)
                        .zIndex(1)
                }
            }
            .onPreferenceChange(ChipWidthKey.self) { if $0 > 0 { chipWidth = $0 } }
        }
    }
    @ViewBuilder private func cap(_ day: UsageDay, maxBytes: Double, width: CGFloat, height: CGFloat, highlighted: Bool) -> some View {
        let fraction = max(0, (day.usedBytes ?? 0)/maxBytes)
        let h = max(day.usedBytes == nil ? 0 : 4, height*fraction)
        let shape = RoundedRectangle(cornerRadius:compact ? 2 : 3, style:.continuous)
        let dimmed = hoveredID != nil && !highlighted
        Group {
            if day.isToday {
                shape.fill(stripes).frame(width:width,height:h)
            } else if day.isIncomplete {
                shape.fill(Color(red:0.77,green:0.71,blue:0.54)).frame(width:width,height:h)
            } else if day.isMissing {
                shape.fill(Color.clear).frame(width:width,height:max(4,h))
                    .overlay(shape.strokeBorder(Color.secondary.opacity(0.25),style:StrokeStyle(lineWidth:1,dash:[3,2])))
            } else {
                shape.fill(accent).frame(width:width,height:h)
            }
        }
        .opacity(dimmed ? 0.55 : 1)
        .overlay {
            if highlighted { shape.stroke(Color.primary.opacity(0.28),lineWidth:1).frame(width:width,height:h) }
        }
        .shadow(color:highlighted ? accent.opacity(0.35) : .clear, radius:highlighted ? 3 : 0, y:highlighted ? 1 : 0)
    }
    private func hoverChip(_ day: UsageDay) -> some View {
        Text(UsageMath.barHoverLabel(day:day,language:language))
            .font(.system(size:compact ? 10 : 11, weight:.semibold))
            .monospacedDigit()
            .padding(.horizontal,8).padding(.vertical,3)
            .background(.ultraThinMaterial, in:Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
            .shadow(color:.black.opacity(0.14), radius:4, y:1)
            .fixedSize()
            .allowsHitTesting(false)
    }
    private var stripes: AnyShapeStyle {
        AnyShapeStyle(LinearGradient(colors:[accent,accent.opacity(0.45)],startPoint:.top,endPoint:.bottom))
    }
    private func shortLabel(_ id: String) -> String {
        let parts = id.split(separator:"-")
        return parts.count == 3 ? String(parts[2]) : id
        // For "today" the caller still passes the date id; panel overlay can replace the last label.
    }
}

struct UsageMetricCard: View {
    var title: String
    var value: String
    var subtitle: String
    var emphasis = false
    var warn = false
    var body: some View {
        VStack(alignment:.leading,spacing:3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size:20,weight:.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(warn ? Color(red:0.78,green:0.42,blue:0.03) : Color.primary)
            Text(subtitle).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal:false,vertical:true)
        }
        .padding(12).frame(maxWidth:.infinity,alignment:.leading)
        .esaiCard(warn || emphasis ? .sunken : .raised)
        .background { WarnCardFill(warn:warn) }
    }
}

/// Design B menu-panel summary: 7-day sparkline, today / time left / prediction, 7d & 30d averages.
struct UsagePanelSummary: View {
    @ObservedObject var model: TrafficModel
    var now: Date
    var onOpenHistory: () -> Void
    private var accent: Color { model.accentColor }
    private func t(_ key: String, _ arguments: String...) -> String { model.translate(key,arguments:arguments) }
    var body: some View {
        let summary = model.usageSummary(now:now)
        let spark = Array(model.usageDays(now:now).suffix(7))
        VStack(alignment:.leading,spacing:8) {
            EsaiHairline().padding(.bottom,2)
            HStack {
                Text(t("近 7 日用量")).font(.callout.weight(.semibold))
                Spacer()
                Button(t("打开用量历史"),action:onOpenHistory)
                    .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(accent).pointingHandCursor()
            }
            if spark.contains(where:{ $0.usedBytes != nil }) {
                UsageBarChart(days:spark,accent:accent,compact:true,language:model.resolvedLanguage).frame(height:52)
            }
            HStack(alignment:.firstTextBaseline) {
                if let used = summary.todayUsedBytes {
                    Text(t("今日 %@ · 还剩 %@",formatTraffic(gb:TrafficStats.gb(used)),UsageMath.formatDuration(summary.secondsLeftInDay,language:model.resolvedLanguage)))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(t("还剩 %@ · 从本次更新开始记录",UsageMath.formatDuration(summary.secondsLeftInDay,language:model.resolvedLanguage)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:8)
                if let whole = summary.predictedWholeDays, let date = summary.predictedRunoutDate {
                    Text(t("预计约 %@ 天后用尽",String(whole)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red:0.78,green:0.42,blue:0.03))
                        .help(runoutHelp(date:date))
                }
            }
            HStack(spacing:8) {
                metric(t("7 日日均"), summary.average7.map { formatTraffic(gb:TrafficStats.gb($0)) } ?? t("暂无"),
                       summary.completeDays7 == 0 ? t("仅计完整日，不含今日") : t("%@ 个完整日",String(summary.completeDays7)))
                metric(t("30 日日均"), summary.average30.map { formatTraffic(gb:TrafficStats.gb($0)) } ?? t("暂无"),
                       summary.completeDays30 == 0 ? t("仅计完整日，不含今日") : t("%@ / %@ 个完整日",String(summary.completeDays30),String(summary.considered30)))
            }
        }
    }
    private func metric(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).esaiCard()
        .help(sub)
    }
    private func runoutHelp(date: Date) -> String {
        let text = UsageMath.formatSGTDate(date,language:model.resolvedLanguage)
        return model.translate("约 %@（新加坡日期）",arguments:[text])
    }
}

private struct ChipWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value,nextValue()) }
}

private struct WarnCardFill: View {
    var warn: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if warn {
            RoundedRectangle(cornerRadius:EsaiSurface.radiusCard,style:.continuous)
                .fill(scheme == .dark ? Color(red:0.42,green:0.26,blue:0.08).opacity(0.72)
                                      : Color(red:0.96,green:0.90,blue:0.83).opacity(0.65))
        }
    }
}
