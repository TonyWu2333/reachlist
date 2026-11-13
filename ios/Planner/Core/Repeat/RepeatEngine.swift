import Foundation

// MARK: - M-03 RepeatEngine（T-07）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/lib/repeat.js（164 行）：
// parseRule / formatRule / normalizeRepeat / occursOn / nextOccurrence / instanceOf /
// repeatLabel（中英两套）/ repeatGroup / streakOf，另提供 F-01.9 的 tasksOn 纯函数版本。
//
// 设计约束：
// · 纯 Foundation，日期一律走 M-06 的 PlannerCalendar（同一份本地时间语义），
//   不在本文件另写日期运算；Task 用 M-01 的 PlannerTask，不另定义任务结构。
// · 语言用显式 `isEnglish` 参数（与 T-06 一致），不等 M-23 / T-19；T-19 落地后包一层即可。
// · 所有日期由调用方注入，除 `date` 为空时退回系统今天外不读当前时间，保证夹具可复现。
// · T-14 的 Features/PropertyPanel/RepeatRule.swift 已改为转发到本类型，
//   调用点签名不变；Swift 侧只保留这一份重复规则逻辑（RISK-01）。

struct RepeatInstance: Equatable, Sendable {
    var task: PlannerTask
    /// 重复实例的日期（对应 JS 运行时字段 occ）；一次性任务为空串。
    var occ: String
}

enum RepeatEngine {

    struct Rule: Equatable, Sendable {
        var freq: String          // d / w / m / y
        var n: Int
        var days: [Int]           // 0 = 周日 … 6 = 周六，仅 freq == w
        var until: String
    }

    // MARK: 规则串（repeat.js:14-45）

    private static let pattern = #"^([dwmy])(\d{1,3})(?::([0-6]{1,7}))?(?:~(\d{4}-\d{2}-\d{2}))?$"#
    private static let legacy: [String: String] = [
        "daily": "d1", "weekdays": "w1:12345", "monthly": "m1",
    ]

    /// parseRule：不认识返回 nil。w 规则没有星期时无效。
    static func parse(_ raw: String) -> Rule? {
        guard !raw.isEmpty else { return nil }
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let fr = Range(m.range(at: 1), in: raw),
              let nr = Range(m.range(at: 2), in: raw) else { return nil }
        let freq = String(raw[fr])
        let n = max(1, Int(raw[nr]) ?? 1)
        var days: [Int] = []
        if freq == "w", m.range(at: 3).location != NSNotFound,
           let dr = Range(m.range(at: 3), in: raw) {
            // JS: [...new Set(chars.map(Number))].sort()；0~6 单字符下字典序 = 数值序。
            days = Array(Set(raw[dr].compactMap { $0.wholeNumberValue })).sorted()
        }
        var until = ""
        if m.range(at: 4).location != NSNotFound, let ur = Range(m.range(at: 4), in: raw) {
            until = String(raw[ur])
        }
        if freq == "w" && days.isEmpty { return nil }
        return Rule(freq: freq, n: n, days: days, until: until)
    }

    static func format(_ rule: Rule) -> String {
        var s = rule.freq + String(max(1, rule.n))
        if rule.freq == "w" {
            s += ":" + Array(Set(rule.days)).sorted().map(String.init).joined()
        }
        if !rule.until.isEmpty { s += "~" + rule.until }
        return s
    }

    /// normalizeRepeat：老写法换掉，不认识的一律丢弃为 ''。
    static func normalizeLegacy(_ raw: String, date: String) -> String {
        guard !raw.isEmpty else { return "" }
        if let mapped = legacy[raw] { return mapped }
        if raw == "weekly" {
            let d = date.isEmpty ? PlannerCalendar.today() : date
            return "w1:" + String(PlannerCalendar.weekdayIndex(d))
        }
        return parse(raw) != nil ? raw : ""
    }

    // MARK: 发生判定（repeat.js:47-85）

    private static func daysInMonth(_ date: Date) -> Int {
        PlannerCalendar.calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    static func occursOn(_ task: PlannerTask, _ d: String) -> Bool {
        guard !task.repeatRule.isEmpty, !task.date.isEmpty,
              d >= task.date, !task.skipDates.contains(d) else { return false }
        guard let r = parse(task.repeatRule) else { return false }
        if !r.until.isEmpty && d > r.until { return false }

        let day = PlannerCalendar.parseYmd(d)
        let start = PlannerCalendar.parseYmd(task.date)
        switch r.freq {
        case "d":
            return PlannerCalendar.diffDays(d, task.date) % r.n == 0
        case "w":
            guard r.days.contains(PlannerCalendar.weekdayIndex(d)) else { return false }
            if r.n == 1 { return true }
            let weeks = PlannerCalendar.diffDays(
                PlannerCalendar.mondayOf(d), PlannerCalendar.mondayOf(task.date)
            ) / 7
            return weeks % r.n == 0
        case "m":
            let months = (PlannerCalendar.component(day, .year) - PlannerCalendar.component(start, .year)) * 12
                + PlannerCalendar.component(day, .month) - PlannerCalendar.component(start, .month)
            guard months % r.n == 0 else { return false }
            return PlannerCalendar.component(day, .day)
                == min(PlannerCalendar.component(start, .day), daysInMonth(day))
        case "y":
            guard PlannerCalendar.component(day, .month) == PlannerCalendar.component(start, .month),
                  (PlannerCalendar.component(day, .year) - PlannerCalendar.component(start, .year)) % r.n == 0
            else { return false }
            return PlannerCalendar.component(day, .day)
                == min(PlannerCalendar.component(start, .day), daysInMonth(day))
        default:
            return false
        }
    }

    /// from 当天或之后第一次发生；找不到（如已过 until）返回 ''。
    static func nextOccurrence(_ task: PlannerTask, from: String) -> String {
        guard let r = parse(task.repeatRule), !task.date.isEmpty else { return "" }
        let span: Int
        switch r.freq {
        case "d": span = r.n
        case "w": span = 7 * r.n
        case "m": span = 31 * r.n
        default: span = 366 * r.n
        }
        var d = from < task.date ? task.date : from
        for _ in 0..<(span * 3 + 31) {
            if !r.until.isEmpty && d > r.until { return "" }
            if occursOn(task, d) { return d }
            d = PlannerCalendar.addDays(d, 1)
        }
        return ""
    }

    /// 某一天的实例：任务副本带 occ 与当天完成状态。
    static func instanceOf(_ task: PlannerTask, _ d: String) -> RepeatInstance {
        var copy = task
        copy.date = d
        copy.done = task.doneDates.contains(d)
        return RepeatInstance(task: copy, occ: d)
    }

    // MARK: 规则文案（repeat.js:90-141）

    /// 周一在前的排序：0（周日）排到最后。
    static func mondayFirst(_ a: Int, _ b: Int) -> Bool {
        ((a + 6) % 7) < ((b + 6) % 7)
    }

    static func repeatLabel(_ raw: String, date: String, isEnglish: Bool, withUntil: Bool = false) -> String {
        guard let r = parse(raw) else { return "" }
        let start = PlannerCalendar.parseYmd(date.isEmpty ? PlannerCalendar.today() : date)
        let n = r.n
        var s = ""

        if isEnglish {
            switch r.freq {
            case "d":
                s = n == 1 ? "Daily" : "Every \(n) days"
            case "w":
                let set = r.days.map(String.init).joined()
                if n == 1 && set == "0123456" { s = "Daily" }
                else if n == 1 && set == "12345" { s = "Weekdays" }
                else if n == 1 && set == "06" { s = "Weekends" }
                else {
                    let list = r.days.sorted(by: mondayFirst)
                        .map { PlannerCalendar.weekdayName($0, isEnglish: true) }
                        .joined(separator: ", ")
                    s = n == 1 ? "Every \(list)" : "Every \(n) weeks on \(list)"
                }
            case "m":
                let head = n == 1 ? "Monthly" : "Every \(n) months"
                s = "\(head) on the \(PlannerCalendar.ordinal(PlannerCalendar.component(start, .day)))"
            default:
                let head = n == 1 ? "Yearly" : "Every \(n) years"
                s = "\(head) on \(PlannerCalendar.monthDay(start, isEnglish: true))"
            }
            if withUntil && !r.until.isEmpty {
                s += ", until " + PlannerCalendar.monthDay(PlannerCalendar.parseYmd(r.until), isEnglish: true)
            }
            return s
        }

        switch r.freq {
        case "d":
            s = n == 1 ? "每天" : "每\(n)天"
        case "w":
            let set = r.days.map(String.init).joined()
            if n == 1 && set == "0123456" { s = "每天" }
            else if n == 1 && set == "12345" { s = "工作日" }
            else if n == 1 && set == "06" { s = "每周末" }
            else {
                let list = r.days.sorted(by: mondayFirst)
                    .map { PlannerCalendar.weekdayName($0, short: true, isEnglish: false) }
                    .joined(separator: "、")
                s = n == 1 ? "每周\(list)" : "每\(n)周的周\(list)"
            }
        case "m":
            s = "\(n == 1 ? "每月" : "每\(n)个月的")\(PlannerCalendar.component(start, .day))日"
        default:
            s = "\(n == 1 ? "每年" : "每\(n)年的")\(PlannerCalendar.monthDay(start, isEnglish: false))"
        }
        if withUntil && !r.until.isEmpty {
            s += "，到" + PlannerCalendar.monthDay(PlannerCalendar.parseYmd(r.until), isEnglish: false)
        }
        return s
    }

    // MARK: 分组与连续次数（repeat.js:143-164）

    static func repeatGroup(_ raw: String) -> String {
        guard let r = parse(raw) else { return "" }
        switch r.freq {
        case "d": return r.n == 1 ? "daily" : "interval"
        case "w": return r.n == 1 && r.days.count == 7 ? "daily" : "weekly"
        case "m": return "monthly"
        default: return "yearly"
        }
    }

    /// 今天还没完成不算断；跳过的日子不算断也不计数；最多回溯 800 次。
    static func streakOf(_ task: PlannerTask, _ d0: String) -> Int {
        var d = d0
        if occursOn(task, d) && !task.doneDates.contains(d) {
            d = PlannerCalendar.addDays(d, -1)
        }
        var n = 0
        var i = 0
        while i < 800 && d >= task.date {
            if !occursOn(task, d) {
                d = PlannerCalendar.addDays(d, -1)
                i += 1
                continue
            }
            if !task.doneDates.contains(d) { break }
            n += 1
            d = PlannerCalendar.addDays(d, -1)
            i += 1
        }
        return n
    }

    // MARK: F-01.9 某日任务展开（store.js:tasksOn 的纯函数版本）

    static func tasksOn(_ tasks: [PlannerTask], day: String) -> [RepeatInstance] {
        tasks.flatMap { t -> [RepeatInstance] in
            if !t.repeatRule.isEmpty {
                return occursOn(t, day) ? [instanceOf(t, day)] : []
            }
            return t.date == day ? [RepeatInstance(task: t, occ: "")] : []
        }
    }
}
