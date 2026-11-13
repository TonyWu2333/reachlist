import Foundation

// MARK: - 重复规则规范化（M-03 的 M-01 前置子集）
//
// 来源：src/lib/repeat.js:14 (RE), :15 (LEGACY), :19-32 (parseRule), :40-45 (normalizeRepeat)
//
// 【为什么在 T-04 就实现】
// store.js:3 import { normalizeRepeat } from './repeat.js'，
// 且 store.js:44 在 normalizeTask 内调用它。计划书 §6.4 把 M-01 标为「依赖 —」，
// 但按 §0.3 第 2 条（先读契约），不实现这一小块就无法让 A-01 与 JS 等价。
// 本文件只做「读入时的规范化与合法性判断」；occursOn / nextOccurrence /
// instanceOf / repeatLabel / repeatGroup / streakOf 属于 T-07，届时在此扩展。

enum RepeatNormalization {
    private static let legacy: [String: String] = [
        "daily": "d1",
        "weekdays": "w1:12345",
        "monthly": "m1"
    ]

    // JS 的 \d 为 ASCII 数字，故写 [0-9] 而非 \d（NSRegularExpression 的 \d 含 Unicode 数字）。
    private static let rulePattern =
        "^([dwmy])([0-9]{1,3})(?::([0-6]{1,7}))?(?:~([0-9]{4}-[0-9]{2}-[0-9]{2}))?$"

    /// repeat.js:parseRule 的「是否合法」部分。
    /// w 类型必须带 :<星期>，否则 JS 里 days 为空 → 规则无效。
    static func isValidRule(_ s: String) -> Bool {
        let re = try! NSRegularExpression(pattern: rulePattern)
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else {
            return false
        }
        if ns.substring(with: m.range(at: 1)) == "w" {
            let daysRange = m.range(at: 3)
            if daysRange.location == NSNotFound || daysRange.length == 0 { return false }
        }
        return true
    }

    /// 复现 date.js:parseYmd(s).getDay()：0 = 周日 … 6 = 周六。
    /// JS 的 new Date(y, m-1, d) 用本地时区，故 Calendar 用 .current。
    /// M-06（T-06）会提供统一的日期助手；此处只保留 weekly 分支所需的最小实现。
    static func jsWeekdayOf(_ date: String) -> String {
        let p = date.split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 3,
              let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else {
            return "NaN" // JS Invalid Date → getDay() = NaN → 'w1:NaN'
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let comps = DateComponents(calendar: cal, year: y, month: m, day: d)
        guard let built = comps.date else { return "NaN" }
        // Calendar.weekday: 1 = 周日 … 7 = 周六 → JS getDay() = weekday - 1
        return String(cal.component(.weekday, from: built) - 1)
    }

    /// store.js:44 normalizeRepeat(t.repeat, t.date) —— date 传的是「原始值」。
    static func normalize(_ value: Any?, date: Any?) -> String {
        guard let s = value as? String, !s.isEmpty else { return "" }
        if let mapped = legacy[s] { return mapped }
        if s == "weekly" {
            return "w1:" + jsWeekdayOf((date as? String) ?? "")
        }
        return isValidRule(s) ? s : ""
    }
}
