import Foundation

// MARK: - M-06 PlannerCalendar（T-06）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/lib/date.js（89 行）：
// ymd / today / parseYmd / addDays / diffDays / WEEKDAY / weekdayOf / weekdayName /
// monthDay / monthName / ordinal / mondayOf / dateLabel / lunarYearLabel / dayInfo。
//
// 设计约束：
// · 纯 Foundation，不依赖 SwiftUI、不依赖 M-23 本地化服务，语言用显式 `isEnglish` 参数传入；
//   T-19 落地后包一层即可，调用点无需改动。
// · `dateLabel` 的「今天」由调用方注入（默认取系统当天），便于夹具固定时间、跨天可复现；
//   JS 里读到的 `new Date().getFullYear()` 在这里从注入的 today 派生。
// · 本文件刻意**不定义** `DateText` / `RepeatRule` 等符号：T-14 的 Features/ 下已有同名临时实现，
//   并行期间不得造成 Swift 全局命名冲突。T-14 收尾时把 `DateText.xxx` 换成 `PlannerCalendar.xxx`
//   即可，映射见同目录 LunarData.swift 的注释与计划书 §12 变更记录。
// · 农历/节气/节日/休班不走 i18n，中英界面下名称均为中文（A-13）。

enum PlannerCalendar {

    // MARK: 常量（date.js:18-21）

    static let weekdayZH = ["日", "一", "二", "三", "四", "五", "六"]
    static let weekdayEN = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let monthEN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// JS `Date` 恒为公历 + 本地时区。显式指定，避免系统「日历」偏好（佛历等）改变结果。
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    enum Component { case year, month, day }

    static func component(_ d: Date, _ c: Component) -> Int {
        let comps = calendar.dateComponents([.year, .month, .day], from: d)
        switch c {
        case .year: return comps.year ?? 0
        case .month: return comps.month ?? 1
        case .day: return comps.day ?? 1
        }
    }

    // MARK: 基础日期（date.js:4-17, 31）

    static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : String(n) }

    static func ymd(_ d: Date) -> String {
        "\(component(d, .year))-\(pad(component(d, .month)))-\(pad(component(d, .day)))"
    }

    static func today(_ now: Date = Date()) -> String { ymd(now) }

    /// 只接受 `yyyy-MM-dd`；非法输入不在契约范围内，返回 epoch 以避免隐式取当前时间。
    static func parseYmd(_ s: String) -> Date {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 3 else { return Date(timeIntervalSince1970: 0) }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        return calendar.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    static func addDays(_ s: String, _ n: Int) -> String {
        ymd(calendar.date(byAdding: .day, value: n, to: parseYmd(s)) ?? parseYmd(s))
    }

    /// date.js:17 用 `Math.round((parseYmd(a) - parseYmd(b)) / 864e5)`。
    /// 这里同样用毫秒差四舍五入，而不是日历日组件差：后者在历史时区偏移 / 夏令时下
    /// 会与 JS 产生不同结果（VERIFY-08 关注的语义）。
    static func diffDays(_ a: String, _ b: String) -> Int {
        let ms = parseYmd(a).timeIntervalSince(parseYmd(b)) * 1000
        return Int((ms / 86_400_000).rounded())
    }

    /// JS `getDay()`：0 = 周日；Swift `.weekday`：1 = 周日。
    static func weekdayIndex(_ s: String) -> Int {
        calendar.component(.weekday, from: parseYmd(s)) - 1
    }

    static func weekdayOf(_ s: String) -> String { weekdayZH[normalizedWeekday(weekdayIndex(s))] }

    static func mondayOf(_ s: String) -> String {
        addDays(s, -((weekdayIndex(s) + 6) % 7))
    }

    private static func normalizedWeekday(_ i: Int) -> Int { ((i % 7) + 7) % 7 }

    // MARK: 中英文案（date.js:23-29）

    static func weekdayName(_ i: Int, short: Bool = false, isEnglish: Bool) -> String {
        let idx = normalizedWeekday(i)
        if isEnglish {
            let full = weekdayEN[idx]
            return short ? String(full.prefix(1)) : full
        }
        let zh = weekdayZH[idx]
        return short ? zh : "周\(zh)"
    }

    static func monthDay(_ d: Date, isEnglish: Bool) -> String {
        let m = component(d, .month), day = component(d, .day)
        return isEnglish ? "\(monthEN[m - 1]) \(day)" : "\(m)月\(day)日"
    }

    static func monthDay(_ s: String, isEnglish: Bool) -> String {
        monthDay(parseYmd(s), isEnglish: isEnglish)
    }

    static func monthName(_ m0: Int, isEnglish: Bool) -> String {
        isEnglish ? monthEN[normalizedIndex(m0, count: 12)] : "\(m0 + 1)月"
    }

    static func ordinal(_ n: Int) -> String {
        if n % 100 >= 11 && n % 100 <= 13 { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    private static func normalizedIndex(_ i: Int, count: Int) -> Int { ((i % count) + count) % count }

    // MARK: dateLabel（date.js:33-52）

    /// `today` 注入 fixture 的当天字符串；不注入时取系统当天。
    static func dateLabel(_ s: String, today: String? = nil, isEnglish: Bool) -> String {
        guard !s.isEmpty else { return "" }
        let t = today ?? PlannerCalendar.today()
        let n = diffDays(s, t)
        let currentYear = Int(t.prefix(4)) ?? 0
        let d = parseYmd(s)
        let sameWeek = mondayOf(s) == mondayOf(t)

        if isEnglish {
            if n == 0 { return "Today" }
            if n == 1 { return "Tomorrow" }
            if n == -1 { return "Yesterday" }
            if n > 1 && n < 7 {
                return (sameWeek ? "" : "Next ") + weekdayEN[normalizedWeekday(weekdayIndex(s))]
            }
            let md = monthDay(d, isEnglish: true)
            return component(d, .year) == currentYear ? md : "\(md), \(component(d, .year))"
        }

        if n == 0 { return "今天" }
        if n == 1 { return "明天" }
        if n == 2 { return "后天" }
        if n == -1 { return "昨天" }
        if n > 2 && n < 7 {
            return (sameWeek ? "" : "下") + "周" + weekdayZH[normalizedWeekday(weekdayIndex(s))]
        }
        let md = monthDay(d, isEnglish: false)
        return component(d, .year) == currentYear ? md : "\(component(d, .year))年\(md)"
    }

    // MARK: M-06 统一入口（静态表由调用方持有，避免隐式全局状态）

    static func dayInfo(_ s: String, using data: LunarData) -> PlannerDayInfo? {
        data.dayInfo(s)
    }

    static func lunarYearLabel(_ year: Int, using data: LunarData) -> String? {
        data.lunarYearLabel(year)
    }
}
