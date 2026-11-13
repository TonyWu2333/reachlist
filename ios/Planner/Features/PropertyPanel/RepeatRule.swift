import Foundation

// MARK: - M-15 重复规则：T-07 后的薄转发层
//
// T-14 阶段这里有一份 M-03 子集（parse / format / label / normalizeLegacy）。
// T-07 已把 M-03 全量实现落到 Core/Repeat/RepeatEngine.swift，本文件只保留
// T-14 调用点在用的 API 名称并转发过去，避免 Swift 侧出现第二份重复规则逻辑（RISK-01）。
// T-14 的 View / Contract / Tests 调用签名保持不变，无需改动。
//
// 下方的 DateText 是 T-06 之前的日期文案临时实现，本轮（T-07）不在范围内，保持原状；
// T-15 / T-16 接入真实界面时按 Core/Calendar/LunarData.swift 的映射表替换。

enum RepeatRule {
    typealias Rule = RepeatEngine.Rule

    static func parse(_ raw: String) -> Rule? {
        RepeatEngine.parse(raw)
    }

    static func format(_ rule: Rule) -> String {
        RepeatEngine.format(rule)
    }

    static func normalizeLegacy(_ raw: String, date: String) -> String {
        RepeatEngine.normalizeLegacy(raw, date: date)
    }

    static func label(_ raw: String, date: String, isEnglish: Bool, withUntil: Bool = false) -> String {
        RepeatEngine.repeatLabel(raw, date: date, isEnglish: isEnglish, withUntil: withUntil)
    }

    static func mondayFirst(_ a: Int, _ b: Int) -> Bool {
        RepeatEngine.mondayFirst(a, b)
    }

    static let defaultCustom = RepeatEngine.Rule(freq: "d", n: 1, days: [], until: "")
}

// MARK: - 日期文案：T-15 后的薄转发层
//
// T-14 阶段这里有一份 M-06 子集；T-06 已把全量实现落到 Core/Calendar/PlannerCalendar.swift。
// T-15 首次使用日历能力时收拢为转发层：只保留 T-14 调用点在用的 API 名称，
// 转发给 PlannerCalendar，避免 Swift 侧第二份日期逻辑。T-14 的 View / Contract / Tests 签名不变。

enum DateText {
    enum Component { case year, month, day }

    static func pad(_ n: Int) -> String { PlannerCalendar.pad(n) }
    static func today(_ now: Date = Date()) -> String { PlannerCalendar.today(now) }
    static func parse(_ s: String) -> Date { PlannerCalendar.parseYmd(s) }
    static func addDays(_ s: String, _ n: Int) -> String { PlannerCalendar.addDays(s, n) }
    static func diffDays(_ a: String, _ b: String) -> Int { PlannerCalendar.diffDays(a, b) }

    static func component(_ d: Date, _ c: Component) -> Int {
        switch c {
        case .year: return PlannerCalendar.component(d, .year)
        case .month: return PlannerCalendar.component(d, .month)
        case .day: return PlannerCalendar.component(d, .day)
        }
    }

    static func weekdayIndex(_ s: String) -> Int { PlannerCalendar.weekdayIndex(s) }
    static func mondayOf(_ s: String) -> String { PlannerCalendar.mondayOf(s) }
    static func weekdayCharacter(_ i: Int) -> String {
        PlannerCalendar.weekdayName(i, short: true, isEnglish: false)
    }
    static func weekdayName(_ i: Int, short: Bool, isEnglish: Bool) -> String {
        PlannerCalendar.weekdayName(i, short: short, isEnglish: isEnglish)
    }
    static func monthDay(_ d: Date, isEnglish: Bool) -> String {
        PlannerCalendar.monthDay(d, isEnglish: isEnglish)
    }
    static func ordinal(_ n: Int) -> String { PlannerCalendar.ordinal(n) }
    static func label(_ s: String, today: String, isEnglish: Bool) -> String {
        PlannerCalendar.dateLabel(s, today: today, isEnglish: isEnglish)
    }

    /// quadrant.js:isOverdue —— 重复任务不算过期。
    static func isOverdue(date: String, repeatRule: String, done: Bool, today: String) -> Bool {
        repeatRule.isEmpty && !done && !date.isEmpty && date < today
    }
}
