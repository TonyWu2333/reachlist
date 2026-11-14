import Foundation

// MARK: - M-16 搜索：事实层（T-16）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/components/SearchSheet.vue:27-63：
// 多词 AND（标题 + '\n' + 备注）、待办 / 已完成分组与排序、命中高亮（不用 v-html）、
// 备注命中片段（前 8 后 40）、结果行副标题、结果打开详情。
// 呈现层按 §5.0 / OPEN-18 用系统 sheet + List + AttributedString/Text 拼接。

struct SearchMark: Equatable, Sendable {
    var text: String
    var hit: Bool
}

enum SearchContract {

    /// ES spec WhiteSpace（与 T-08 的结论一致）：**不含 U+200B 零宽空格**。
    /// ICU `\s` 会把 U+200B 当空白，故这里显式列举，不复刻 ICU 行为。
    private static let whitespacePattern =
        "[\t\n\u{000B}\u{000C}\r \u{00A0}\u{1680}\u{2000}-\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}]+"

    private static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    /// `q.trim().toLowerCase().split(/\s+/).filter(Boolean)`
    static func terms(_ q: String) -> [String] {
        let trimmed = regex("^" + whitespacePattern + "|" + whitespacePattern + "$")
            .stringByReplacingMatches(in: q, range: NSRange(q.startIndex..., in: q), withTemplate: "")
            .lowercased()
        let ns = trimmed as NSString
        let full = NSRange(location: 0, length: ns.length)
        let separators = regex(whitespacePattern).matches(in: trimmed, range: full)
        var out: [String] = []
        var cursor = 0
        for m in separators {
            if m.range.location > cursor {
                out.append(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            }
            cursor = NSMaxRange(m.range)
        }
        if cursor < ns.length { out.append(ns.substring(from: cursor)) }
        return out.filter { !$0.isEmpty }
    }

    /// 空格分词全部命中 `title + '\n' + note`（大小写不敏感）。
    static func results(_ tasks: [PlannerTask], query: String) -> (open: [PlannerTask], done: [PlannerTask]) {
        let words = terms(query)
        guard !words.isEmpty else { return ([], []) }
        let hit = tasks.enumerated().filter { _, t in
            let hay = (t.title + "\n" + t.note).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
        // JS Array.sort 稳定：显式带原序做 tie-break。
        let open = hit.filter { !$0.element.repeatRule.isEmpty || !$0.element.done }
            .sorted { a, b in
                if CalendarContract.byDate(a.element, b.element) { return true }
                if CalendarContract.byDate(b.element, a.element) { return false }
                return a.offset < b.offset
            }.map(\.element)
        let done = hit.filter { $0.element.repeatRule.isEmpty && $0.element.done }
            .sorted { a, b in
                let da = a.element.doneAt ?? 0, db = b.element.doneAt ?? 0
                if da != db { return da > db }
                return a.offset < b.offset
            }.map(\.element)
        return (open, done)
    }

    /// `text.split(/(term1|term2)/gi)` 的奇数位为命中片段；不用 v-html，交给 SwiftUI 拼 Text。
    static func marks(_ text: String, query: String) -> [SearchMark] {
        let words = terms(query)
        guard !words.isEmpty else { return [SearchMark(text: text, hit: false)] }
        let pattern = "(" + words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")"
        let ns = text as NSString
        let re = regex(pattern, caseInsensitive: true)
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var out: [SearchMark] = []
        var cursor = 0
        for m in matches {
            if m.range.location > cursor {
                out.append(SearchMark(
                    text: ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)),
                    hit: false
                ))
            }
            out.append(SearchMark(text: ns.substring(with: m.range), hit: true))
            cursor = NSMaxRange(m.range)
        }
        if cursor < ns.length {
            out.append(SearchMark(text: ns.substring(from: cursor), hit: false))
        }
        return out.filter { !$0.text.isEmpty }
    }

    /// 备注里命中的那一段：空白折叠成单空格，命中点前 8 / 后 40（UTF-16 位置，复刻 JS slice）。
    static func noteSnippet(_ note: String, query: String) -> String {
        let words = terms(query)
        guard !words.isEmpty else { return "" }
        let collapsed = regex(whitespacePattern)
            .stringByReplacingMatches(in: note, range: NSRange(note.startIndex..., in: note), withTemplate: " ")
        let lower = collapsed.lowercased() as NSString
        var positions: [Int] = []
        for w in words {
            let r = lower.range(of: w)
            if r.location >= 0 { positions.append(r.location) }
        }
        guard let i = positions.min() else { return "" }
        let start = max(0, i - 8)
        let ns = collapsed as NSString
        let location = min(start, ns.length)
        let length = min(40, ns.length - location)
        let body = ns.substring(with: NSRange(location: location, length: length))
        return (start > 0 ? "…" : "") + body
    }

    /// 结果行副标题（SearchSheet.vue:sub）：已放弃 / 日期或重复 / 时间 / 父任务。
    static func sub(_ t: PlannerTask, tasks: [PlannerTask], lang: String, today: String) -> String {
        let en = lang == "en"
        var parts: [String] = []
        if t.dropped { parts.append(AppStrings.t("已放弃", lang: lang)) }
        if !t.repeatRule.isEmpty {
            parts.append(RepeatEngine.repeatLabel(t.repeatRule, date: t.date, isEnglish: en))
        } else if !t.date.isEmpty {
            parts.append(PlannerCalendar.dateLabel(t.date, today: today, isEnglish: en))
        } else {
            parts.append(AppStrings.t("无日期", lang: lang))
        }
        if !t.time.isEmpty { parts.append(t.time) }
        if !t.parentId.isEmpty {
            let parent = tasks.first { $0.id == t.parentId }?.title ?? ""
            parts.append("↳ " + parent)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func noResultText(_ query: String, lang: String) -> String {
        FeatureStrings.t("没有找到包含「{q}」的任务", lang: lang, ["q": trimmed(query)])
    }

    static func trimmed(_ q: String) -> String {
        regex("^" + whitespacePattern + "|" + whitespacePattern + "$")
            .stringByReplacingMatches(in: q, range: NSRange(q.startIndex..., in: q), withTemplate: "")
    }
}
