import Foundation

// MARK: - Singapore usage day (10:00 SGT → next 10:00 SGT)

enum UsageCalendar {
    static let timeZone = TimeZone(identifier:"Asia/Singapore")!
    static let startHour = 10
    static func calendar() -> Calendar {
        var c = Calendar(identifier:.gregorian)
        c.timeZone = timeZone
        return c
    }
    /// Usage-day label: the Singapore calendar date on which the 10:00 window starts.
    static func dayID(for date: Date, calendar cal: Calendar = calendar()) -> String {
        var comps = cal.dateComponents([.year,.month,.day,.hour],from:date)
        if (comps.hour ?? 0) < startHour {
            let start = cal.date(from:DateComponents(year:comps.year,month:comps.month,day:comps.day))!
            let prev = cal.date(byAdding:.day,value:-1,to:start)!
            comps = cal.dateComponents([.year,.month,.day],from:prev)
        }
        return String(format:"%04d-%02d-%02d",comps.year!,comps.month!,comps.day!)
    }
    /// 10:00 SGT on `dayID`, and 10:00 SGT the following day.
    static func interval(forDay id: String, calendar cal: Calendar = calendar()) -> (start: Date, end: Date) {
        let parts = id.split(separator:"-").compactMap { Int($0) }
        precondition(parts.count == 3, "invalid day id")
        let start = cal.date(from:DateComponents(year:parts[0],month:parts[1],day:parts[2],hour:startHour))!
        return (start, cal.date(byAdding:.day,value:1,to:start)!)
    }
    static func addingDays(_ n: Int, to id: String, calendar cal: Calendar = calendar()) -> String {
        let start = interval(forDay:id,calendar:cal).start
        return dayID(for:cal.date(byAdding:.day,value:n,to:start)!,calendar:cal)
    }
    static func daysFrom(_ start: String, through end: String, calendar cal: Calendar = calendar()) -> [String] {
        if start > end { return [] }
        var ids = [start]
        while let last = ids.last, last < end { ids.append(addingDays(1,to:last,calendar:cal)) }
        return ids
    }
    static func secondsLeft(inDayOf date: Date, now: Date, calendar cal: Calendar = calendar()) -> TimeInterval {
        let end = interval(forDay:dayID(for:date,calendar:cal),calendar:cal).end
        return max(0, end.timeIntervalSince(now))
    }
}

/// Gap longer than this marks the wake day incomplete. Floor is 3 hours so brief sleep doesn't trip it.
func usageGapThreshold(intervalMinutes: Int) -> TimeInterval {
    max(Double(intervalMinutes*2 + 15)*60, 3*3600)
}

/// A used drop larger than this starts a new plan epoch (resets / new plan). Smaller dips are clamped to 0.
let usageResetEpsilon: Double = 1_000_000
/// Remaining at or below this is treated as quota exhausted (~10 MB).
let usageQuotaExhaustedEpsilon: Double = 10_000_000

// MARK: - Records

struct UsageSnapshot: Codable, Equatable {
    var ts: Date
    var used: Double
    var total: Double
    var left: Double
    var epoch: Int
}

struct UsageAlertState: Codable, Equatable {
    /// Window is on screen (or was when the app quit) and has not been confirmed.
    var unconfirmed = false
    /// Floor(days remaining) at the last confirm in this episode; nil if not yet confirmed.
    var acknowledgedDays: Int? = nil
    var acknowledgedAt: Date? = nil
    var lastShownDays: Int? = nil
    var lastShownRemainingBytes: Double? = nil
    var lastShownAverageBytes: Double? = nil
    /// SGT day id on which the optional daily-usage notification already fired.
    var dailyAckDayID: String? = nil
}

struct UsageFile: Codable, Equatable {
    var version = 1
    var snapshots: [UsageSnapshot] = []
    var alerts = UsageAlertState()
}

struct UsageDay: Equatable {
    var id: String
    var usedBytes: Double? = nil
    var isToday = false
    var isIncomplete = false
    var isQuotaExhausted = false
    var snapshotCount = 0
    var firstTs: Date? = nil
    var lastTs: Date? = nil
    var endingLeftBytes: Double? = nil
    var isMissing: Bool { usedBytes == nil }
    var isComplete: Bool { usedBytes != nil && !isToday && !isIncomplete }
    /// Complete and not quota-exhausted. Used for averages and the run-out forecast.
    var isUsable: Bool { isComplete && !isQuotaExhausted }
}

/// How ready the run-out forecast is, based on the number of usable complete days.
enum ForecastStage: Equatable {
    /// Fewer than 3 usable days; `needed` more complete days are required.
    case insufficient(needed: Int)
    /// 3–6 usable days: show a forecast marked as a preliminary estimate; do not pop the desktop alert.
    case preliminary
    /// 7 or more usable days: formal forecast; the ≤10-day desktop alert may appear.
    case official
}

struct UsageSummary: Equatable {
    var todayID: String
    var todayUsedBytes: Double? = nil
    var todayIncomplete = false
    var secondsLeftInDay: TimeInterval = 0
    var average7: Double? = nil
    var completeDays7 = 0
    var average30: Double? = nil
    var completeDays30 = 0
    var considered30 = 0
    /// Usable complete days in the whole series (excluding today).
    var usableDaysTotal = 0
    /// Usable days in the last-7 window used for the typical rate.
    var usableDaysWindow = 0
    /// Trimmed mean of the last 7 usable days; this is the typical daily rate for the forecast.
    var typicalRateBytes: Double? = nil
    /// 80th percentile of the same window, or the second-highest value if fewer than 5 usable days.
    var highRateBytes: Double? = nil
    var forecastStage: ForecastStage = .insufficient(needed: 3)
    /// remaining ÷ typical rate, in days; nil if the forecast is hidden.
    var predictedDays: Double? = nil
    var predictedWholeDays: Int? = nil
    /// `now + predictedDays` (fractional), for display as a Singapore calendar date.
    var predictedRunoutDate: Date? = nil
    var highPredictedDays: Double? = nil
    var highPredictedWholeDays: Int? = nil
    var highPredictedRunoutDate: Date? = nil
    var weekdayRateBytes: Double? = nil
    var weekendMedianBytes: Double? = nil
    var showWeekdayWeekendSplit = false
    var showWeekendLaterHint = false
    var isPreliminary: Bool { forecastStage == .preliminary }
    var isOfficial: Bool { forecastStage == .official }
    var insufficientNeeded: Int? {
        if case .insufficient(let n) = forecastStage { return n }
        return nil
    }
    var forecast: RunoutForecast? {
        guard let days = predictedDays, let whole = predictedWholeDays, let date = predictedRunoutDate else { return nil }
        return RunoutForecast(fractionalDays:days, wholeDays:whole, date:date)
    }
}

/// Shared run-out forecast: day count is floor(fractional days); date is now + fractional days.
struct RunoutForecast: Equatable {
    var fractionalDays: Double
    var wholeDays: Int
    var date: Date
}

enum UsageRange: String, CaseIterable { case seven = "7", thirty = "30", all = "all" }

// MARK: - Pure math

enum UsageMath {
    static func rollup(snapshots: [UsageSnapshot], now: Date, intervalMinutes: Int,
                       calendar cal: Calendar = UsageCalendar.calendar()) -> [UsageDay] {
        let gap = usageGapThreshold(intervalMinutes:intervalMinutes)
        let todayID = UsageCalendar.dayID(for:now,calendar:cal)
        let ordered = snapshots.sorted { $0.ts < $1.ts }
        guard let first = ordered.first else {
            return [UsageDay(id:todayID,isToday:true)]
        }
        let startID = UsageCalendar.dayID(for:first.ts,calendar:cal)
        var days: [UsageDay] = UsageCalendar.daysFrom(startID,through:todayID,calendar:cal).map {
            UsageDay(id:$0,isToday:$0 == todayID)
        }
        var index: [String:Int] = [:]
        for (i,d) in days.enumerated() { index[d.id] = i }

        func markIncomplete(_ id: String) {
            if let i = index[id] { days[i].isIncomplete = true }
        }
        func addUsage(_ id: String, _ bytes: Double) {
            guard let i = index[id] else { return }
            days[i].usedBytes = (days[i].usedBytes ?? 0) + bytes
        }

        for (offset, shot) in ordered.enumerated() {
            let id = UsageCalendar.dayID(for:shot.ts,calendar:cal)
            guard let i = index[id] else { continue }
            days[i].snapshotCount += 1
            if days[i].firstTs == nil { days[i].firstTs = shot.ts }
            days[i].lastTs = shot.ts
            days[i].endingLeftBytes = shot.left

            if offset == 0 { continue }
            let prev = ordered[offset-1]
            let prevID = UsageCalendar.dayID(for:prev.ts,calendar:cal)
            if shot.epoch != prev.epoch {
                markIncomplete(id)
                continue
            }
            let delta = shot.used - prev.used
            if delta < -usageResetEpsilon {
                markIncomplete(id)
                continue
            }
            let gained = max(0, delta)
            let span = shot.ts.timeIntervalSince(prev.ts)
            addUsage(id, gained)
            // A mid-day sleep still has a correct used-delta if both ends of the day are recorded.
            // Only a gap that crosses the 10:00 SGT boundary cannot be split, so the wake day is incomplete.
            if span > gap && prevID != id { markIncomplete(id) }
        }

        // A finished day whose last snapshot is far from the day end (app off) is incomplete.
        // The leftover usage is attributed to the wake day by the gap rule above.
        for i in days.indices {
            let day = days[i]
            if day.isToday || day.snapshotCount == 0 { continue }
            let end = UsageCalendar.interval(forDay:day.id,calendar:cal).end
            if let last = day.lastTs, end.timeIntervalSince(last) > gap, end <= now {
                days[i].isIncomplete = true
            }
            let start = UsageCalendar.interval(forDay:day.id,calendar:cal).start
            if let first = day.firstTs, first.timeIntervalSince(start) > gap {
                days[i].isIncomplete = true
            }
        }
        for i in days.indices {
            if days[i].isToday { continue }
            if let left = days[i].endingLeftBytes, left <= usageQuotaExhaustedEpsilon {
                days[i].isQuotaExhausted = true
            }
        }
        return days
    }

    static let formalForecastUsableDays = 7
    static let preliminaryForecastUsableDays = 3
    static let weekdayWeekendSplitUsableDays = 14
    static let weekdayRateWindow = 10
    static let weekendMedianWindow = 8
    static let weekendHintRatio = 0.5
    static let weekendHintMinGapBytes: Double = 1_000_000_000

    static func average(of days: [UsageDay], last n: Int, excludingToday: Bool = true) -> (average: Double?, complete: Int, considered: Int) {
        let pool = excludingToday ? days.filter { !$0.isToday } : days
        let window = Array(pool.suffix(n))
        let usable = window.filter(\.isUsable)
        let considered = window.count
        guard !usable.isEmpty else { return (nil,0,considered) }
        let total = usable.compactMap(\.usedBytes).reduce(0,+)
        return (total/Double(usable.count), usable.count, considered)
    }

    /// Trimmed mean of daily usage: 3 values drop the highest; 4 or more drop the highest and the lowest.
    static func trimmedMean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let xs = values.sorted()
        let kept: ArraySlice<Double>
        switch xs.count {
        case 1, 2: kept = xs[...]
        case 3: kept = xs.dropLast()
        default: kept = xs.dropFirst().dropLast()
        }
        return kept.reduce(0,+)/Double(kept.count)
    }

    /// 80th percentile of the window; if fewer than 5 values, the second-highest (or the only value).
    static func highScenarioRate(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let xs = values.sorted()
        if xs.count < 5 {
            return xs.count >= 2 ? xs[xs.count-2] : xs[0]
        }
        let pos = 0.80 * Double(xs.count - 1)
        let lo = Int(pos.rounded(.down))
        let hi = min(xs.count-1, Int(pos.rounded(.up)))
        if lo == hi { return xs[lo] }
        let w = pos - Double(lo)
        return xs[lo]*(1-w) + xs[hi]*w
    }

    /// Weekend of a usage-day id is the SGT calendar weekday at noon of that date (Sat/Sun).
    static func isWeekend(_ id: String, calendar cal: Calendar = UsageCalendar.calendar()) -> Bool {
        let parts = id.split(separator:"-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = cal.date(from:DateComponents(year:parts[0],month:parts[1],day:parts[2],hour:12))
        else { return false }
        let w = cal.component(.weekday, from:date)
        return w == 1 || w == 7
    }

    static func lastUsable(_ days: [UsageDay], limit: Int) -> [UsageDay] {
        Array(days.filter { $0.isUsable }.suffix(limit))
    }

    static func weekdayRate(days: [UsageDay]) -> Double? {
        trimmedMean(lastUsable(days.filter { !isWeekend($0.id) }, limit:weekdayRateWindow).compactMap(\.usedBytes))
    }

    static func weekendMedian(days: [UsageDay]) -> Double? {
        let vals = lastUsable(days.filter { isWeekend($0.id) }, limit:weekendMedianWindow).compactMap(\.usedBytes)
        guard !vals.isEmpty else { return nil }
        let xs = vals.sorted()
        let mid = xs.count / 2
        if xs.count % 2 == 1 { return xs[mid] }
        return (xs[mid-1] + xs[mid]) / 2
    }

    static func shouldShowWeekendLaterHint(weekdayRate: Double, weekendMedian: Double) -> Bool {
        weekdayRate > 0 && weekendMedian < weekdayRate * weekendHintRatio && (weekdayRate - weekendMedian) >= weekendHintMinGapBytes
    }

    static func forecastStage(usableCount: Int) -> ForecastStage {
        if usableCount >= formalForecastUsableDays { return .official }
        if usableCount >= preliminaryForecastUsableDays { return .preliminary }
        return .insufficient(needed: max(0, preliminaryForecastUsableDays - usableCount))
    }

    static func summarize(days: [UsageDay], remainingBytes: Double?, now: Date,
                          calendar cal: Calendar = UsageCalendar.calendar()) -> UsageSummary {
        let todayID = UsageCalendar.dayID(for:now,calendar:cal)
        let today = days.first { $0.id == todayID }
        let a7 = average(of:days,last:7)
        let a30 = average(of:days,last:30)
        var summary = UsageSummary(
            todayID:todayID, todayUsedBytes:today?.usedBytes, todayIncomplete:today?.isIncomplete ?? false,
            secondsLeftInDay:UsageCalendar.secondsLeft(inDayOf:now,now:now,calendar:cal),
            average7:a7.average, completeDays7:a7.complete,
            average30:a30.average, completeDays30:a30.complete, considered30:a30.considered)
        let usableAll = days.filter(\.isUsable)
        summary.usableDaysTotal = usableAll.count
        let window = Array(usableAll.suffix(formalForecastUsableDays))
        summary.usableDaysWindow = window.count
        let windowValues = window.compactMap(\.usedBytes)
        summary.typicalRateBytes = trimmedMean(windowValues)
        summary.highRateBytes = highScenarioRate(windowValues)
        summary.forecastStage = forecastStage(usableCount:usableAll.count)
        if summary.insufficientNeeded == nil, let left = remainingBytes, left > 0,
           let rate = summary.typicalRateBytes, rate > 0 {
            let f = forecast(predictedDays:left/rate, now:now)
            summary.predictedDays = f.fractionalDays
            summary.predictedWholeDays = f.wholeDays
            summary.predictedRunoutDate = f.date
        }
        if summary.insufficientNeeded == nil, let left = remainingBytes, left > 0,
           let rate = summary.highRateBytes, rate > 0 {
            let f = forecast(predictedDays:left/rate, now:now)
            summary.highPredictedDays = f.fractionalDays
            summary.highPredictedWholeDays = f.wholeDays
            summary.highPredictedRunoutDate = f.date
        }
        if usableAll.count >= weekdayWeekendSplitUsableDays {
            summary.weekdayRateBytes = weekdayRate(days:days)
            summary.weekendMedianBytes = weekendMedian(days:days)
            summary.showWeekdayWeekendSplit = summary.weekdayRateBytes != nil || summary.weekendMedianBytes != nil
            if let weekday = summary.weekdayRateBytes, let weekend = summary.weekendMedianBytes {
                summary.showWeekendLaterHint = shouldShowWeekendLaterHint(weekdayRate:weekday, weekendMedian:weekend)
            }
        }
        return summary
    }

    /// Day count = floor(fractional days); date = now + fractional days (display as SGT calendar date).
    static func forecast(predictedDays: Double, now: Date) -> RunoutForecast {
        RunoutForecast(fractionalDays:predictedDays,
                       wholeDays:Int(predictedDays.rounded(.down)),
                       date:now.addingTimeInterval(predictedDays*24*3600))
    }
    static func forecast(remainingBytes: Double, averageBytes: Double, now: Date) -> RunoutForecast? {
        guard remainingBytes > 0, averageBytes > 0 else { return nil }
        return forecast(predictedDays:remainingBytes/averageBytes, now:now)
    }
    static func predictedRunoutDate(predictedDays: Double, now: Date) -> Date {
        forecast(predictedDays:predictedDays, now:now).date
    }
    /// Singapore calendar date of a usage-day id (`yyyy-MM-dd`), e.g. 11月9日 / Nov 9.
    static func formatDayID(_ id: String, language: AppLanguage) -> String {
        let parts = id.split(separator:"-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = UsageCalendar.calendar().date(from:DateComponents(year:parts[0],month:parts[1],day:parts[2],hour:12)) else { return id }
        return formatSGTDate(date,language:language)
    }
    /// Hover label: "11月9日 · 42.6 GB", plus 今日 / 不完整 / 无数据 when applicable.
    static func barHoverLabel(day: UsageDay, language: AppLanguage) -> String {
        let date = formatDayID(day.id,language:language)
        let usage = day.usedBytes.map { formatTraffic(gb:TrafficStats.gb($0)) } ?? "—"
        var parts = [date, usage]
        if day.isToday { parts.append(L10n.text("今日",language:language)) }
        else if day.isQuotaExhausted { parts.append(L10n.text("流量耗尽",language:language)) }
        else if day.isIncomplete { parts.append(L10n.text("不完整",language:language)) }
        else if day.isMissing { parts.append(L10n.text("无数据",language:language)) }
        return parts.joined(separator:" · ")
    }
    /// Singapore calendar date `yyyy-MM-dd` of an instant (not the 10:00 usage-day id).
    static func formatSGTISODate(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = UsageCalendar.calendar()
        f.timeZone = UsageCalendar.timeZone
        f.locale = Locale(identifier:"en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from:date)
    }

    static func formatSGTDate(_ date: Date, language: AppLanguage) -> String {
        let f = DateFormatter()
        f.calendar = UsageCalendar.calendar()
        f.timeZone = UsageCalendar.timeZone
        f.locale = language.locale
        f.dateFormat = language == .english ? "MMM d" : "M月d日"
        return f.string(from:date)
    }

    static func formatDuration(_ interval: TimeInterval, language: AppLanguage) -> String {
        let total = max(0, Int(interval.rounded()))
        let h = total/3600, m = (total%3600)/60
        return language == .english ? "\(h) h \(m) min" : "\(h) 小时 \(m) 分"
    }
}

/// Bar-chart layout: cap width for 1–2 days and use a padded nice y-max so a single day is not a full-height needle.
enum UsageChartLayout {
    static let historyBarMax = 36.0
    static let compactBarMax = 16.0
    static let historyBarMin = 6.0
    static let compactBarMin = 4.0
    static func gap(compact: Bool) -> Double { compact ? 4 : 6 }
    static func barWidth(dayCount: Int, available: Double, compact: Bool) -> Double {
        let n = max(1, dayCount)
        let g = gap(compact:compact)
        let raw = (available - g*Double(n-1))/Double(n)
        let cap = compact ? compactBarMax : historyBarMax
        let floor = compact ? compactBarMin : historyBarMin
        return min(cap, max(floor, raw))
    }
    static func yMaxBytes(_ maxBytes: Double) -> Double {
        let gb = max(TrafficStats.gb(max(0,maxBytes)), 1)
        return niceGB(gb*1.15)*1e9
    }
    static func niceGB(_ gb: Double) -> Double {
        guard gb > 0 else { return 1 }
        let exp = floor(log10(gb))
        let pow10 = pow(10.0, exp)
        let mantissa = gb/pow10
        let steps = [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]
        let nice = steps.first(where:{ $0+1e-9 >= mantissa }) ?? 10
        return nice*pow10
    }
    /// Keep a hover chip's center inside [inset+half, total-inset-half].
    static func clampCenter(_ x: Double, half: Double, total: Double, inset: Double = 4) -> Double {
        let lo = inset+half
        let hi = total-inset-half
        if hi <= lo { return total/2 }
        return min(max(x,lo),hi)
    }
}

// MARK: - Runout policy

enum RunoutAction: Equatable {
    case stayHidden
    case show(days: Int)
    case keepShowing(days: Int)
    case dismiss
}

enum RunoutPolicy {
    static let milestones = [7,3,1]
    static func action(predictedWholeDays: Int?, remainingBytes: Double, threshold: Int,
                       unconfirmed: Bool, acknowledgedDays: Int?) -> RunoutAction {
        let limit = max(1, threshold)
        // Depleted, or remaining days climbed back above the threshold: end this episode and re-arm.
        if remainingBytes <= 0 { return .dismiss }
        if let days = predictedWholeDays, days > limit { return .dismiss }
        guard let days = predictedWholeDays else { return unconfirmed ? .dismiss : .stayHidden }
        if unconfirmed { return .keepShowing(days:days) }
        if acknowledgedDays == nil { return .show(days:days) }
        if let ack = acknowledgedDays, let barrier = (milestones + [limit]).filter({ $0 < ack }).max(), days <= barrier {
            return .show(days:days)
        }
        return .stayHidden
    }
}

// MARK: - Persistence

final class UsageStore {
    private let url: URL?
    private var file: UsageFile
    private(set) var intervalMinutes: Int
    var snapshots: [UsageSnapshot] { file.snapshots }
    var alerts: UsageAlertState { file.alerts }

    /// On-disk store in Application Support. Creates the folder if needed.
    static func applicationSupport() -> UsageStore {
        let root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("com.fitzsmith2000.esai-impulse",isDirectory:true)
        try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        return UsageStore(url:root.appendingPathComponent("usage.json"))
    }
    static func memory(_ file: UsageFile = UsageFile()) -> UsageStore { UsageStore(url:nil,file:file) }

    init(url: URL?, file: UsageFile = UsageFile(), intervalMinutes: Int = 15) {
        self.url = url
        self.intervalMinutes = intervalMinutes
        if let url = url, let data = try? Data(contentsOf:url),
           let decoded = try? Self.decoder.decode(UsageFile.self,from:data) {
            self.file = decoded
        } else {
            self.file = file
        }
    }

    func setInterval(_ minutes: Int) { intervalMinutes = minutes }

    /// Append a snapshot. Drops near-duplicates; starts a new epoch when used drops sharply.
    @discardableResult
    func record(used: Double, total: Double, left: Double, at date: Date) -> Bool {
        if let last = file.snapshots.last,
           date.timeIntervalSince(last.ts) < 60,
           last.used == used, last.total == total { return false }
        var epoch = file.snapshots.last?.epoch ?? 0
        if let last = file.snapshots.last, used + usageResetEpsilon < last.used { epoch += 1 }
        file.snapshots.append(UsageSnapshot(ts:date,used:used,total:total,left:left,epoch:epoch))
        save()
        return true
    }

    /// First launch of 1.2.0: seed one snapshot from the cached last refresh if it is recent and the store is empty.
    func seedIfEmpty(used: Double, total: Double, left: Double, at date: Date, now: Date = Date()) {
        guard file.snapshots.isEmpty else { return }
        guard now.timeIntervalSince(date) < 24*3600 else { return }
        _ = record(used:used,total:total,left:left,at:date)
    }

    func days(now: Date) -> [UsageDay] {
        UsageMath.rollup(snapshots:file.snapshots,now:now,intervalMinutes:intervalMinutes)
    }
    func summary(remainingBytes: Double?, now: Date) -> UsageSummary {
        UsageMath.summarize(days:days(now:now),remainingBytes:remainingBytes,now:now)
    }

    func updateAlerts(_ mutate: (inout UsageAlertState) -> Void) {
        mutate(&file.alerts)
        save()
    }

    func csv(days: [UsageDay], language: AppLanguage = .english, forecast: RunoutForecast? = nil, summary: UsageSummary? = nil) -> String {
        var lines = ["date,usage_gb,status,snapshot_count,first_ts,last_ts"]
        let iso = ISO8601DateFormatter()
        func stamp(_ d: Date?) -> String { d.map { iso.string(from:$0) } ?? "" }
        for day in days.reversed() {
            let status: String
            if day.isToday { status = "today" }
            else if day.isMissing { status = "missing" }
            else if day.isQuotaExhausted { status = "exhausted" }
            else if day.isIncomplete { status = "incomplete" }
            else { status = "complete" }
            let usage = day.usedBytes.map { String(format:"%.3f",TrafficStats.gb($0)) } ?? ""
            lines.append("\(day.id),\(usage),\(status),\(day.snapshotCount),\(stamp(day.firstTs)),\(stamp(day.lastTs))")
        }
        if let s = summary {
            switch s.forecastStage {
            case .official: lines.append("# predicted_stage,official")
            case .preliminary: lines.append("# predicted_stage,preliminary")
            case .insufficient(let n): lines.append("# predicted_stage,insufficient,needed,\(n)")
            }
        }
        if let f = forecast ?? summary?.forecast {
            lines.append("# predicted_whole_days,\(f.wholeDays)")
            lines.append("# predicted_runout_date_sgt,\(UsageMath.formatSGTISODate(f.date))")
        }
        if let high = summary?.highPredictedWholeDays, let date = summary?.highPredictedRunoutDate {
            lines.append("# high_predicted_whole_days,\(high)")
            lines.append("# high_predicted_runout_date_sgt,\(UsageMath.formatSGTISODate(date))")
        }
        return lines.joined(separator:"\n") + "\n"
    }

    private func save() {
        guard let url = url else { return }
        guard let data = try? Self.encoder.encode(file) else { return }
        let temp = url.appendingPathExtension("tmp")
        do {
            try data.write(to:temp,options:.atomic)
            _ = try FileManager.default.replaceItemAt(url,withItemAt:temp)
        } catch {
            try? data.write(to:url,options:.atomic)
            try? FileManager.default.removeItem(at:temp)
        }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted,.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

// MARK: - Sample data for offscreen renders

enum UsageSample {
    static func store(now: Date = sampleNow) -> UsageStore {
        let s = UsageStore.memory()
        // Build 14 usage-days of snapshots ending "today" 11/9 22:36 PT = 14:36 SGT 11/10? 
        // Sample now is 22:36 PST on 9 Nov 2026 = 14:36 SGT on 10 Nov, which would be the Nov 10 usage day
        // (starts 10:00 SGT Nov 10). To match the mockup "11月9日" as today, pin "now" to 03:36 SGT on Nov 10
        // (still in the Nov 9 usage day, which ends 10:00 SGT Nov 10). 03:36 SGT = 11:36 PST Nov 9.
        // The mockup used "距今日结束还有 11 小时 24 分" → 10:00 - 11h24m = 22:36 SGT Nov 9,
        // which is still Nov 9 usage day (starts 10:00 SGT Nov 9). 22:36 SGT = 06:36 PST Nov 9.
        // Extra early days so the sample has ≥14 usable days (weekday/weekend split + weekend tip).
        // Weekends are low; 10-26 is quota-exhausted (visible tag); 11-06 stays incomplete
        // via a late first snapshot, with a close-of-day bound so 11-07 remains complete.
        let values: [(id:String,gb:Double,incomplete:Bool,exhausted:Bool)] = [
            ("2026-10-23",128.4,false,false),("2026-10-24",2.1,false,false),("2026-10-25",0.4,false,false),
            ("2026-10-26",8.4,false,true),
            ("2026-10-27",133.8,false,false),("2026-10-28",116.5,false,false),("2026-10-29",121.0,false,false),
            ("2026-10-30",144.7,false,false),("2026-10-31",3.2,false,false),("2026-11-01",1.1,false,false),
            ("2026-11-02",125.6,false,false),("2026-11-03",109.8,false,false),("2026-11-04",152.1,false,false),
            ("2026-11-05",98.4,false,false),("2026-11-06",141.0,true,false),("2026-11-07",0.8,false,false),
            ("2026-11-08",2.4,false,false),("2026-11-09",42.6,false,false)
        ]
        var used: Double = 4_200_000_000_000
        let total: Double = 5_661_800_000_000
        for (id, gb, incomplete, exhausted) in values {
            let start = UsageCalendar.interval(forDay:id).start
            if incomplete {
                // First snapshot > 3h after start → incomplete, but close to the day end so the next day stays complete.
                _ = s.record(used:used,total:total,left:total-used,at:start.addingTimeInterval(5*3600))
                used += gb*1e9
                _ = s.record(used:used,total:total,left:total-used,at:start.addingTimeInterval(23*3600))
            } else if id == "2026-11-09" {
                _ = s.record(used:used,total:total,left:total-used,at:start)
                used += gb*1e9
                _ = s.record(used:used,total:total,left:total-used,at:sampleNow)
            } else {
                _ = s.record(used:used,total:total,left:total-used,at:start)
                used += gb*1e9
                let endish = start.addingTimeInterval(23*3600)
                let left = exhausted ? 0.0 : total-used
                _ = s.record(used:used,total:total,left:left,at:endish)
            }
        }
        return s
    }
    /// 22:36 SGT on 9 Nov 2026 — 11 h 24 min left in the Nov 9 usage day.
    static let sampleNow: Date = {
        var c = UsageCalendar.calendar()
        return c.date(from:DateComponents(year:2026,month:11,day:9,hour:22,minute:36))!
    }()
    static let sampleStats = TrafficStats(total:5_661_800_000_000,used:4_551_100_000_000,left:1_110_700_000_000)
}

// MARK: - Self-tests

enum UsageTests {
    static func sgt(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, _ s: Int = 0) -> Date {
        UsageCalendar.calendar().date(from:DateComponents(year:y,month:m,day:d,hour:h,minute:min,second:s))!
    }
    static func run() {
        // SGT boundary: 09:59 belongs to the previous usage day; 10:00 starts a new one.
        precondition(UsageCalendar.dayID(for:sgt(2026,11,10,9,59)) == "2026-11-09")
        precondition(UsageCalendar.dayID(for:sgt(2026,11,10,10,0)) == "2026-11-10")
        precondition(UsageCalendar.dayID(for:sgt(2026,11,10,0,0)) == "2026-11-09")
        let (start,end) = UsageCalendar.interval(forDay:"2026-11-09")
        precondition(start == sgt(2026,11,9,10))
        precondition(end == sgt(2026,11,10,10))
        let left = UsageCalendar.secondsLeft(inDayOf:sgt(2026,11,9,22,36),now:sgt(2026,11,9,22,36))
        precondition(abs(left - (11*3600 + 24*60)) < 1)

        // DST independence: US spring-forward (2026-03-08) and fall-back (2026-11-01)
        // must not change the Singapore day id around 10:00 SGT.
        let march = sgt(2026,3,15,10) // PDT is in effect in the US
        precondition(UsageCalendar.dayID(for:march) == "2026-03-15")
        precondition(UsageCalendar.dayID(for:march.addingTimeInterval(-60)) == "2026-03-14")
        let nov = sgt(2026,11,9,10) // PST is in effect in the US
        precondition(UsageCalendar.dayID(for:nov) == "2026-11-09")
        precondition(UsageCalendar.dayID(for:nov.addingTimeInterval(-60)) == "2026-11-08")
        // Same instant expressed from a PT calendar still yields the SGT day.
        var pt = Calendar(identifier:.gregorian); pt.timeZone = TimeZone(identifier:"America/Los_Angeles")!
        let ptMarch = pt.date(from:DateComponents(year:2026,month:3,day:14,hour:19))! // 19:00 PDT = 10:00 SGT Mar 15
        precondition(UsageCalendar.dayID(for:ptMarch) == "2026-03-15")
        let ptNov = pt.date(from:DateComponents(year:2026,month:11,day:8,hour:18))! // 18:00 PST = 10:00 SGT Nov 9
        precondition(UsageCalendar.dayID(for:ptNov) == "2026-11-09")

        // Top-up: total rises, used grows by 10 GB only — top-up itself is not usage.
        let store = UsageStore.memory()
        let t0 = sgt(2026,11,8,10)
        _ = store.record(used:100e9,total:200e9,left:100e9,at:t0)
        _ = store.record(used:110e9,total:500e9,left:390e9,at:t0.addingTimeInterval(2*3600)) // +10 GB used, +300 GB top-up
        _ = store.record(used:110e9,total:500e9,left:390e9,at:sgt(2026,11,9,9,0))
        let days = store.days(now:sgt(2026,11,9,12))
        let nov8 = days.first { $0.id == "2026-11-08" }!
        precondition(abs((nov8.usedBytes ?? -1) - 10e9) < 1, "top-up must not count as usage")
        precondition(nov8.isComplete)

        // Used reset / new plan: drop in used starts a new epoch and is not negative usage.
        let reset = UsageStore.memory()
        _ = reset.record(used:80e9,total:100e9,left:20e9,at:sgt(2026,11,8,10))
        _ = reset.record(used:90e9,total:100e9,left:10e9,at:sgt(2026,11,8,12))
        _ = reset.record(used:5e9,total:200e9,left:195e9,at:sgt(2026,11,8,13)) // reset
        _ = reset.record(used:8e9,total:200e9,left:192e9,at:sgt(2026,11,9,12))
        let rDays = reset.days(now:sgt(2026,11,9,12))
        let r8 = rDays.first { $0.id == "2026-11-08" }!
        precondition(r8.isIncomplete)
        precondition((r8.usedBytes ?? 0) >= 0)
        precondition(abs((r8.usedBytes ?? 0) - 10e9) < 1, "usage before reset kept; drop not subtracted")
        precondition(reset.snapshots.last?.epoch == 1)

        // Gaps: 4 hours off (> 3h floor) — delta lands on the wake day, which is incomplete;
        // a day with no snapshots in the middle is missing.
        let gapped = UsageStore.memory(); gapped.setInterval(15)
        _ = gapped.record(used:10e9,total:100e9,left:90e9,at:sgt(2026,11,7,12)) // Nov 7
        _ = gapped.record(used:20e9,total:100e9,left:80e9,at:sgt(2026,11,7,18)) // still Nov 7, regular
        _ = gapped.record(used:20e9,total:100e9,left:80e9,at:sgt(2026,11,8,9))  // close to day end
        // Sleep from Nov 8 09:00 until Nov 10 12:00 SGT (Nov 10 usage day starts 10:00 Nov 10).
        _ = gapped.record(used:50e9,total:100e9,left:50e9,at:sgt(2026,11,10,12))
        let gDays = gapped.days(now:sgt(2026,11,11,12))
        let g7 = gDays.first { $0.id == "2026-11-07" }!
        let g8 = gDays.first { $0.id == "2026-11-08" }!
        let g9 = gDays.first { $0.id == "2026-11-09" }!
        let g10 = gDays.first { $0.id == "2026-11-10" }!
        precondition(g7.isComplete)
        precondition(abs((g7.usedBytes ?? 0) - 10e9) < 1)
        // 09:00 SGT Nov 8 is still the Nov 7 usage day, so Nov 8 and Nov 9 have no snapshots.
        precondition(g8.isMissing)
        precondition(g9.isMissing)
        precondition(g9.usedBytes == nil)
        precondition(g10.isIncomplete)
        precondition(abs((g10.usedBytes ?? 0) - 30e9) < 1, "gap usage attributed to wake day")

        // Averages exclude today, incomplete, and missing days.
        let avgStore = UsageStore.memory()
        // Three complete days (Nov 5–7) at 10, 20, 30 GB, Nov 8 incomplete 40, Nov 9 today 5.
        func fill(_ id: String, gb: Double, startUsed: inout Double, incomplete: Bool = false) {
            let start = UsageCalendar.interval(forDay:id).start
            _ = avgStore.record(used:startUsed,total:1000e9,left:1000e9-startUsed,at:start)
            startUsed += gb*1e9
            if incomplete {
                // Stop early so this finished day has no closing bound and is incomplete.
                _ = avgStore.record(used:startUsed,total:1000e9,left:1000e9-startUsed,at:start.addingTimeInterval(4*3600))
            } else {
                _ = avgStore.record(used:startUsed,total:1000e9,left:1000e9-startUsed,at:start.addingTimeInterval(23*3600))
            }
        }
        var u = 0.0
        fill("2026-11-05",gb:10,startUsed:&u)
        fill("2026-11-06",gb:20,startUsed:&u)
        fill("2026-11-07",gb:30,startUsed:&u)
        fill("2026-11-08",gb:40,startUsed:&u,incomplete:true)
        _ = avgStore.record(used:u,total:1000e9,left:1000e9-u,at:sgt(2026,11,9,10))
        u += 5e9
        _ = avgStore.record(used:u,total:1000e9,left:1000e9-u,at:sgt(2026,11,9,12))
        let aDays = avgStore.days(now:sgt(2026,11,9,12,30))
        let a7 = UsageMath.average(of:aDays,last:7)
        // complete days in window: Nov 5,6,7 (Nov 8 incomplete, Nov 9 today excluded)
        precondition(a7.complete == 3)
        precondition(abs((a7.average ?? 0) - 20e9) < 1)

        // Prediction: 3 usable days → preliminary; typical rate is trimmed mean of 10/20/30 = 15 GB.
        // 50 / 15 ≈ 3.333 → floor 3. The desktop alert must not fire in the preliminary stage.
        let rem = 50e9
        var summary = UsageMath.summarize(days:aDays,remainingBytes:rem,now:sgt(2026,11,9,12,30))
        precondition(summary.forecastStage == .preliminary)
        precondition(abs((summary.typicalRateBytes ?? 0) - 15e9) < 1)
        precondition(abs((summary.predictedDays ?? 0) - (50e9/15e9)) < 0.01)
        precondition(summary.predictedWholeDays == 3)
        let prelimDays = summary.isOfficial ? summary.predictedWholeDays : nil
        precondition(RunoutPolicy.action(predictedWholeDays:prelimDays,remainingBytes:rem,threshold:10,unconfirmed:false,acknowledgedDays:nil) == .stayHidden)
        summary = UsageMath.summarize(days:aDays,remainingBytes:0,now:sgt(2026,11,9,12,30))
        precondition(summary.predictedDays == nil)
        let emptySummary = UsageMath.summarize(days:[UsageDay(id:"2026-11-09",isToday:true)],remainingBytes:100e9,now:sgt(2026,11,9,12))
        precondition(emptySummary.predictedDays == nil)
        precondition(emptySummary.forecastStage == .insufficient(needed:3))

        // Run-out re-alert rules.
        let T = 10
        precondition(RunoutPolicy.action(predictedWholeDays:11,remainingBytes:100,threshold:T,unconfirmed:false,acknowledgedDays:nil) == .dismiss ||
                     RunoutPolicy.action(predictedWholeDays:11,remainingBytes:100,threshold:T,unconfirmed:false,acknowledgedDays:nil) == .stayHidden)
        // days > threshold with no window: dismiss (re-arm / clear) — see below, stayHidden vs dismiss.
        precondition(RunoutPolicy.action(predictedWholeDays:11,remainingBytes:100,threshold:T,unconfirmed:false,acknowledgedDays:nil) == .dismiss)
        precondition(RunoutPolicy.action(predictedWholeDays:8,remainingBytes:100,threshold:T,unconfirmed:false,acknowledgedDays:nil) == .show(days:8))
        precondition(RunoutPolicy.action(predictedWholeDays:8,remainingBytes:100,threshold:T,unconfirmed:true,acknowledgedDays:nil) == .keepShowing(days:8))
        // After confirm at 8, do not re-show at 8.
        precondition(RunoutPolicy.action(predictedWholeDays:8,remainingBytes:100,threshold:T,unconfirmed:false,acknowledgedDays:8) == .stayHidden)
        // Milestone 7.
        precondition(RunoutPolicy.action(predictedWholeDays:7,remainingBytes:100,threshold:T,unconfirmed:false,acknowledgedDays:8) == .show(days:7))
        precondition(RunoutPolicy.action(predictedWholeDays:3,remainingBytes:100,threshold:T,unconfirmed:false,acknowledgedDays:7) == .show(days:3))
        precondition(RunoutPolicy.action(predictedWholeDays:1,remainingBytes:100,threshold:T,unconfirmed:false,acknowledgedDays:3) == .show(days:1))
        precondition(RunoutPolicy.action(predictedWholeDays:1,remainingBytes:100,threshold:T,unconfirmed:false,acknowledgedDays:1) == .stayHidden)
        // Re-arm when remaining days climb back above 10.
        precondition(RunoutPolicy.action(predictedWholeDays:12,remainingBytes:100,threshold:T,unconfirmed:false,acknowledgedDays:8) == .dismiss)
        precondition(RunoutPolicy.action(predictedWholeDays:12,remainingBytes:100,threshold:T,unconfirmed:true,acknowledgedDays:nil) == .dismiss)
        // Depleted: dismiss (existing depleted path takes over).
        precondition(RunoutPolicy.action(predictedWholeDays:5,remainingBytes:0,threshold:T,unconfirmed:true,acknowledgedDays:nil) == .dismiss)
        // No prediction: close an unconfirmed window, otherwise stay hidden.
        precondition(RunoutPolicy.action(predictedWholeDays:nil,remainingBytes:100,threshold:T,unconfirmed:true,acknowledgedDays:nil) == .dismiss)
        precondition(RunoutPolicy.action(predictedWholeDays:nil,remainingBytes:100,threshold:T,unconfirmed:false,acknowledgedDays:nil) == .stayHidden)
        // Unconfirmed on launch is keepShowing as long as still <= threshold.
        precondition(RunoutPolicy.action(predictedWholeDays:8,remainingBytes:100,threshold:T,unconfirmed:true,acknowledgedDays:nil) == .keepShowing(days:8))

        precondition(abs(usageGapThreshold(intervalMinutes:15) - 3*3600) < 1)
        precondition(UsageMath.formatDuration(11*3600+24*60,language:.chinese) == "11 小时 24 分")
        precondition(UsageMath.formatDuration(11*3600+24*60,language:.english) == "11 h 24 min")

        // Dedup: same used/total within 60s is ignored.
        let dup = UsageStore.memory()
        precondition(dup.record(used:1,total:2,left:1,at:sgt(2026,11,9,10)))
        precondition(dup.record(used:1,total:2,left:1,at:sgt(2026,11,9,10,0,30)) == false)
        precondition(dup.snapshots.count == 1)

        // CSV has a header and does not invent usage for missing days.
        let csv = gapped.csv(days:gDays)
        precondition(csv.hasPrefix("date,usage_gb,status,"))
        precondition(csv.contains("2026-11-09,,missing,"))
        precondition(csv.contains("2026-11-10,") && csv.contains(",incomplete,"))

        // Forecast display is shared: day count = floor, date = now + fractional days (SGT calendar date).
        let predNow = sgt(2026,11,9,22,36)
        let pred = UsageMath.forecast(predictedDays:8.815, now:predNow)
        precondition(pred.wholeDays == 8)
        precondition(abs(pred.date.timeIntervalSince(predNow) - 8.815*24*3600) < 0.01)
        precondition(UsageMath.formatSGTDate(pred.date,language:.chinese) == "11月18日")
        precondition(UsageMath.formatSGTISODate(pred.date) == "2026-11-18")
        // Using floor days for the date would land on a different SGT calendar day — must not do that.
        let floorDate = predNow.addingTimeInterval(8*24*3600)
        precondition(UsageMath.formatSGTDate(floorDate,language:.chinese) == "11月17日")
        precondition(UsageMath.formatSGTDate(pred.date,language:.chinese) != UsageMath.formatSGTDate(floorDate,language:.chinese))
        // summarize() and a remaining/avg rebuild match the same function (panel, history, alert, CSV).
        let predNow2 = sgt(2026,11,9,12,30)
        let fromParts = UsageMath.forecast(remainingBytes:rem, averageBytes:15e9, now:predNow2)!
        let consistent = UsageMath.summarize(days:aDays,remainingBytes:rem,now:predNow2)
        precondition(consistent.predictedWholeDays == fromParts.wholeDays)
        precondition(consistent.predictedRunoutDate == fromParts.date)
        precondition(consistent.forecast?.date == fromParts.date)
        precondition(consistent.predictedWholeDays == 3)
        precondition(consistent.forecastStage == .preliminary)
        precondition(UsageMath.formatSGTISODate(fromParts.date) == "2026-11-12")
        let csvForecast = gapped.csv(days:gDays, forecast:consistent.forecast, summary:consistent)
        precondition(csvForecast.contains("# predicted_whole_days,3"))
        precondition(csvForecast.contains("# predicted_runout_date_sgt,2026-11-12"))
        precondition(csvForecast.contains("# predicted_stage,preliminary"))
        // 1–2 day charts stay width-capped; y-max is padded above the tallest bar.
        precondition(UsageChartLayout.barWidth(dayCount:1,available:400,compact:false) == UsageChartLayout.historyBarMax)
        precondition(UsageChartLayout.barWidth(dayCount:2,available:400,compact:false) == UsageChartLayout.historyBarMax)
        precondition(UsageChartLayout.barWidth(dayCount:30,available:400,compact:false) < UsageChartLayout.historyBarMax)
        precondition(UsageChartLayout.yMaxBytes(42.6e9) > 42.6e9)
        precondition(UsageChartLayout.yMaxBytes(0) >= 1e9)

        // Hover labels share the same date + usage wording on the panel and the history chart.
        var todayBar = UsageDay(id:"2026-11-09", usedBytes:42.6e9, isToday:true)
        precondition(UsageMath.barHoverLabel(day:todayBar,language:.chinese) == "11月9日 · 42.6 GB · 今日")
        precondition(UsageMath.barHoverLabel(day:todayBar,language:.english) == "Nov 9 · 42.6 GB · Today")
        todayBar.isToday = false
        todayBar.isIncomplete = true
        precondition(UsageMath.barHoverLabel(day:todayBar,language:.chinese) == "11月9日 · 42.6 GB · 不完整")
        let missing = UsageDay(id:"2026-11-08", isToday:false)
        precondition(UsageMath.barHoverLabel(day:missing,language:.chinese) == "11月8日 · — · 无数据")
        let complete = UsageDay(id:"2026-11-07", usedBytes:98.4e9, isToday:false)
        precondition(UsageMath.barHoverLabel(day:complete,language:.chinese) == "11月7日 · 98.4 GB")
        let exhaustedBar = UsageDay(id:"2026-10-26", usedBytes:8.4e9, isToday:false, isQuotaExhausted:true)
        precondition(UsageMath.barHoverLabel(day:exhaustedBar,language:.chinese) == "10月26日 · 8.4 GB · 流量耗尽")
        precondition(UsageMath.barHoverLabel(day:exhaustedBar,language:.english) == "Oct 26 · 8.4 GB · Quota exhausted")
        precondition(UsageMath.formatDayID("2026-11-09",language:.chinese) == "11月9日")
        precondition(UsageMath.formatDayID("2026-11-09",language:.english) == "Nov 9")
        precondition(abs(UsageChartLayout.clampCenter(0,half:40,total:200) - 44) < 0.01)
        precondition(abs(UsageChartLayout.clampCenter(200,half:40,total:200) - 156) < 0.01)
        precondition(abs(UsageChartLayout.clampCenter(100,half:40,total:200) - 100) < 0.01)
        // English map covers keys shown on every usage surface, including short card titles.
        for key in ["剩余","今日已用","今日","不完整","无数据","流量耗尽","用量历史","导出 CSV","配置名称","还没有用量记录","初步估计","数据不足，还需 %@ 个完整日","按近期偏高用量，约 %@ 天","按近期偏高用量，约 %@ 天（%@）","工作日日均 %@ · 周末 %@","若周末接近近期中位数（多为接近 0），用完会更晚","初步估计 · 约 %@（新加坡日期）"] {
            precondition(L10n.english[key] != nil, "missing English for \(key)")
        }
        let sampleDays = UsageSample.store().days(now:UsageSample.sampleNow)
        let nov6 = sampleDays.first { $0.id == "2026-11-06" }
        precondition(nov6?.isIncomplete == true)
        let nov7 = sampleDays.first { $0.id == "2026-11-07" }
        precondition(nov7?.isComplete == true)
        let oct26 = sampleDays.first { $0.id == "2026-10-26" }
        precondition(oct26?.isQuotaExhausted == true)
        precondition(oct26?.isUsable == false)
        let sampleSummary = UsageMath.summarize(days:sampleDays,remainingBytes:UsageSample.sampleStats.left,now:UsageSample.sampleNow)
        precondition(sampleSummary.usableDaysTotal >= 14)
        precondition(sampleSummary.forecastStage == .official)
        precondition(sampleSummary.showWeekdayWeekendSplit)
        precondition(sampleSummary.showWeekendLaterHint)

        Self.runForecastV2Tests()
    }

    /// Build consecutive complete days ending on `lastID`; `now` is 12:30 SGT of the next usage day.
    static func seedUsableDays(daily: [Double], lastID: String, startUsed: Double = 1e12, total: Double = 10e12, exhaustedIndex: Int? = nil) -> (store: UsageStore, days: [UsageDay], now: Date) {
        let store = UsageStore.memory()
        let lastStart = UsageCalendar.interval(forDay:lastID).start
        var ids: [String] = []
        for i in 0..<daily.count {
            let start = lastStart.addingTimeInterval(Double(i-(daily.count-1))*24*3600)
            ids.append(UsageCalendar.dayID(for:start.addingTimeInterval(3600)))
        }
        var used = startUsed
        for (i, id) in ids.enumerated() {
            let start = UsageCalendar.interval(forDay:id).start
            _ = store.record(used:used,total:total,left:total-used,at:start)
            used += daily[i]
            let left = (i == exhaustedIndex) ? 0.0 : total-used
            _ = store.record(used:used,total:total,left:left,at:start.addingTimeInterval(23*3600))
        }
        let todayStart = lastStart.addingTimeInterval(24*3600)
        let now = todayStart.addingTimeInterval(2.5*3600)
        _ = store.record(used:used,total:total,left:total-used,at:todayStart)
        return (store, store.days(now:now), now)
    }

    static func runForecastV2Tests() {
        // Date formula stays: floor days, date = now + fractional days.
        let formula = UsageMath.forecast(remainingBytes:50e9, averageBytes:20e9, now:sgt(2026,11,9,12,30))!
        precondition(abs(formula.fractionalDays - 2.5) < 0.01)
        precondition(formula.wholeDays == 2)
        precondition(UsageMath.formatSGTISODate(formula.date) == "2026-11-12")

        // Trimmed mean: 3 values drop the highest; ≥4 drop highest and lowest.
        precondition(abs((UsageMath.trimmedMean([10,20,30]) ?? 0) - 15) < 0.001)
        precondition(abs((UsageMath.trimmedMean([10,20,30,40]) ?? 0) - 25) < 0.001)
        precondition(abs((UsageMath.trimmedMean([40,40,40,40,40,40,400]) ?? 0) - 40) < 0.001)

        // 80th percentile (linear, n≥5); n<5 uses the second-highest.
        precondition(abs((UsageMath.highScenarioRate([10]) ?? 0) - 10) < 0.001)
        precondition(abs((UsageMath.highScenarioRate([10,20,30,40]) ?? 0) - 30) < 0.001)
        // n=5, pos=0.8*4=3.2 → 0.8*xs[3]+0.2*xs[4] = 0.8*40+0.2*50 = 42
        precondition(abs((UsageMath.highScenarioRate([10,20,30,40,50]) ?? 0) - 42) < 0.001)

        // Thresholds: <3 hide; 3–6 preliminary; ≥7 official.
        let two = seedUsableDays(daily:[10e9,20e9], lastID:"2026-11-08")
        let twoS = UsageMath.summarize(days:two.days,remainingBytes:50e9,now:two.now)
        precondition(twoS.forecastStage == .insufficient(needed:1))
        precondition(twoS.predictedDays == nil)
        let three = seedUsableDays(daily:[10e9,20e9,30e9], lastID:"2026-11-08")
        let threeS = UsageMath.summarize(days:three.days,remainingBytes:50e9,now:three.now)
        precondition(threeS.forecastStage == .preliminary)
        precondition(threeS.predictedWholeDays != nil)
        let six = seedUsableDays(daily:Array(repeating:20e9,count:6), lastID:"2026-11-08")
        precondition(UsageMath.summarize(days:six.days,remainingBytes:50e9,now:six.now).forecastStage == .preliminary)
        let seven = seedUsableDays(daily:Array(repeating:20e9,count:7), lastID:"2026-11-08")
        let sevenS = UsageMath.summarize(days:seven.days,remainingBytes:160e9,now:seven.now)
        precondition(sevenS.forecastStage == .official)
        precondition(abs((sevenS.typicalRateBytes ?? 0) - 20e9) < 1)
        precondition(sevenS.predictedWholeDays == 8)
        precondition(RunoutPolicy.action(predictedWholeDays:sevenS.isOfficial ? sevenS.predictedWholeDays : nil,remainingBytes:160e9,threshold:10,unconfirmed:false,acknowledgedDays:nil) == .show(days:8))

        // Spike: six 40 GB days + one 400 GB day; trimmed typical is 40, not 91.
        let spike = seedUsableDays(daily:[40e9,40e9,40e9,40e9,40e9,40e9,400e9], lastID:"2026-11-08")
        let spikeS = UsageMath.summarize(days:spike.days,remainingBytes:200e9,now:spike.now)
        precondition(abs((spikeS.typicalRateBytes ?? 0) - 40e9) < 1)
        precondition(abs((spikeS.average7 ?? 0) - ((40e9*6+400e9)/7)) < 1)

        // Level shift: seven 20 GB then seven 80 GB; last-7 typical is 80.
        let step = seedUsableDays(daily:Array(repeating:20e9,count:7)+Array(repeating:80e9,count:7), lastID:"2026-11-08")
        let stepS = UsageMath.summarize(days:step.days,remainingBytes:400e9,now:step.now)
        precondition(abs((stepS.typicalRateBytes ?? 0) - 80e9) < 1)

        // Exhausted days are flagged and excluded from the rate window.
        let exh = seedUsableDays(daily:[20e9,0,20e9,20e9,20e9], lastID:"2026-11-08", exhaustedIndex:1)
        let exhDays = exh.days.filter { !$0.isToday }
        let exhMarked = exhDays.first { $0.usedBytes == 0 || abs(($0.usedBytes ?? -1)) < 1 }
        precondition(exhMarked?.isQuotaExhausted == true)
        precondition(exhMarked?.isUsable == false)
        let exhS = UsageMath.summarize(days:exh.days,remainingBytes:60e9,now:exh.now)
        // 4 usable days of 20 GB (0-usage exhausted day dropped); 4-day trim drops min+max → 20.
        precondition(exhS.usableDaysTotal == 4)
        precondition(abs((exhS.typicalRateBytes ?? 0) - 20e9) < 1)
        let csvExh = exh.store.csv(days:exh.days)
        precondition(csvExh.contains(",exhausted,"))

        // A zero-usage day that still has remaining quota is not exhausted.
        let quiet = UsageStore.memory()
        let qStart = UsageCalendar.interval(forDay:"2026-11-08").start
        _ = quiet.record(used:1e12,total:10e12,left:9e12,at:qStart)
        _ = quiet.record(used:1e12,total:10e12,left:9e12,at:qStart.addingTimeInterval(23*3600))
        let qDay = quiet.days(now:qStart.addingTimeInterval(26*3600)).first { $0.id == "2026-11-08" }
        precondition(qDay?.usedBytes == 0 || abs((qDay?.usedBytes ?? 1)) < 1)
        precondition(qDay?.isQuotaExhausted == false)
        precondition(qDay?.isUsable == true)

        // Weekend tip only when the weekend median is clearly below the weekday rate.
        precondition(UsageMath.shouldShowWeekendLaterHint(weekdayRate:20e9, weekendMedian:0.2e9))
        precondition(UsageMath.shouldShowWeekendLaterHint(weekdayRate:20e9, weekendMedian:15e9) == false)
        precondition(UsageMath.shouldShowWeekendLaterHint(weekdayRate:0.5e9, weekendMedian:0) == false)
        // 2026-10-10 (Sat) through 2026-11-08 (Sun): 30 days with low weekends.
        let hint = seedUsableDays(
            daily:(0..<30).map { i in
                let start = UsageCalendar.interval(forDay:"2026-10-10").start.addingTimeInterval(Double(i)*24*3600)
                let id = UsageCalendar.dayID(for:start.addingTimeInterval(3600))
                return UsageMath.isWeekend(id) ? 0.2e9 : 20e9
            },
            lastID:"2026-11-08")
        let hintS = UsageMath.summarize(days:hint.days,remainingBytes:200e9,now:hint.now)
        precondition(hintS.usableDaysTotal >= 14)
        precondition(hintS.showWeekdayWeekendSplit)
        precondition(hintS.showWeekendLaterHint)
        let noTip = seedUsableDays(daily:Array(repeating:20e9,count:21), lastID:"2026-11-08")
        let noTipS = UsageMath.summarize(days:noTip.days,remainingBytes:200e9,now:noTip.now)
        precondition(noTipS.showWeekdayWeekendSplit)
        precondition(noTipS.showWeekendLaterHint == false)
    }
}
