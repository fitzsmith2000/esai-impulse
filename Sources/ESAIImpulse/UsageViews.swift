import AppKit
import SwiftUI

/// Vertical usage bars for the history chart or the panel sparkline.
struct UsageBarChart: View {
    let days: [UsageDay]
    var accent: Color
    var compact = false
    var body: some View {
        let finite = days.compactMap(\.usedBytes)
        let maxBytes = max(finite.max() ?? 1, 1)
        GeometryReader { proxy in
            let gap: CGFloat = compact ? 4 : 6
            let n = max(1, days.count)
            let width = max(2, (proxy.size.width - gap*CGFloat(n-1))/CGFloat(n))
            HStack(alignment:.bottom,spacing:gap) {
                ForEach(Array(days.enumerated()),id:\.offset) { _, day in
                    VStack(spacing:compact ? 3 : 5) {
                        Spacer(minLength:0)
                        cap(day,maxBytes:maxBytes,width:min(width, compact ? 16 : 22),height:proxy.size.height - (compact ? 16 : 20))
                        Text(shortLabel(day.id)).font(.system(size:compact ? 8 : 9.5)).foregroundStyle(.tertiary).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }.frame(maxWidth:.infinity)
                }
            }
        }
    }
    @ViewBuilder private func cap(_ day: UsageDay, maxBytes: Double, width: CGFloat, height: CGFloat) -> some View {
        let fraction = max(0, (day.usedBytes ?? 0)/maxBytes)
        let h = max(day.usedBytes == nil ? 0 : 4, height*fraction)
        let shape = RoundedRectangle(cornerRadius:compact ? 2 : 3, style:.continuous)
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
        .background {
            if warn { RoundedRectangle(cornerRadius:EsaiSurface.radiusCard,style:.continuous).fill(Color(red:0.96,green:0.90,blue:0.83).opacity(0.65)) }
        }
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
                UsageBarChart(days:spark,accent:accent,compact:true).frame(height:52)
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
                if let whole = summary.predictedWholeDays, let frac = summary.predictedDays {
                    Text(t("预计约 %@ 天后用尽",String(whole)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red:0.78,green:0.42,blue:0.03))
                        .help(runoutHelp(frac:frac))
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
    private func runoutHelp(frac: Double) -> String {
        let date = UsageMath.formatSGTDate(UsageMath.predictedRunoutDate(predictedDays:frac,now:now),language:model.resolvedLanguage)
        return model.translate("约 %@（新加坡日期）",arguments:[date])
    }
}
