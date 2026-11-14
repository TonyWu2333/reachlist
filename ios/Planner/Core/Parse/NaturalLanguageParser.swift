import Foundation

// MARK: - M-04 NaturalLanguageParser（T-08）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/lib/parse.js（183 行，未改动）。
// `parseInput(text) -> { title, date, time, repeat, hits[] }`，纯函数，只识别中文（F-07.7 / A-45：
// 英文 UI 下自然语言添加仍只识别中文，不得扩展英文解析）。
//
// 设计约束：
// · 纯 Foundation，不依赖 SwiftUI / M-02 TaskStore / M-23 本地化服务；日期一律走 M-06 PlannerCalendar。
// · 日期与「今天」由调用方注入 `now`（默认 Date()），便于黄金夹具固定时间、跨时区可复现；
//   parse.js 里的每个 `new Date()` 在这里都从同一个 now 派生。
// · 全文在 NSString / NSRange（UTF-16）上做匹配与替换，复现 JS 字符串的 UTF-16 语义：
//   `rest.replace(m[0], ' ')` 是「字面串替换首次出现」，不能写成 replacingOccurrences（会替换全部）。
// · JS 的 `\d` 只匹配 ASCII；ICU 的 `\d` 会匹配 Unicode 十进制数字，故所有 `\d` 一律写成 `[0-9]`。
// · 规则顺序敏感：REPEAT_RULES 10 条 →（仅未命中重复时）DATE_RULES 7 条 → TIME_RULES 2 条。
// · `repeat` 是 Swift 关键字，输出字段命名为 `repeatRule`；夹具 JSON 的键仍是 "repeat"。

struct ParsedInput: Equatable, Sendable {
    var title: String
    var date: String
    var time: String
    var repeatRule: String
    var hits: [String]
}

enum NaturalLanguageParser {

    // MARK: 对外入口

    /// 对齐 parse.js:126-177。
    static func parseInput(_ text: String, now: Date = Date()) -> ParsedInput {
        let ctx = Ctx(now: now)
        var rest: NSString = text as NSString
        var date = ""
        var time = ""
        var repeatRule = ""
        var hits: [String] = []

        // 1) 重复规则（10 条，顺序敏感）。命中后可再解析「到 M月D日」结束日期。
        for rule in repeatRules {
            guard let m = firstMatch(rule.re, in: rest) else { continue }
            guard let r = rule.run(m, ctx) else { continue }
            repeatRule = r.0
            date = r.1
            hits.append(m.text)
            rest = replaceFirstLiteral(m.text, in: rest, with: " ")
            if let u = firstMatch(untilRE, in: rest) {
                let until = nextMonthDay(cnNum(u[1]), cnNum(u[2]), ctx)
                if !until.isEmpty && until >= date {
                    repeatRule += "~" + until
                    hits.append(u.text)
                    rest = replaceFirstLiteral(u.text, in: rest, with: " ")
                }
            }
            break
        }

        // 2) 日期规则：仅在未命中重复规则时执行。
        if repeatRule.isEmpty {
            for rule in dateRules {
                guard let m = firstMatch(rule.re, in: rest) else { continue }
                date = rule.run(m, ctx)
                hits.append(m.text)
                // 「今晚 / 明早」这类词同时带时段，留给 TIME_RULES 当 PERIOD 用，故不从标题里删。
                let endsWithPeriodWord = m.text.hasSuffix("晚") || m.text.hasSuffix("早")
                let hasWeekWord = m.text.contains("周") || m.text.contains("星期") || m.text.contains("礼拜")
                if !endsWithPeriodWord || hasWeekWord {
                    rest = replaceFirstLiteral(m.text, in: rest, with: " ")
                }
                break
            }
        }

        // 3) 时间规则：命中但 toTime 判废时继续尝试下一条。
        for rule in timeRules {
            guard let m = firstMatch(rule.re, in: rest) else { continue }
            let hit = rule.run(m)
            guard let t = toTime(hit.period, hit.hour, hit.minute) else { continue }
            time = t
            hits.append(jsTrim(m.text))
            rest = replaceFirstLiteral(m.text, in: rest, with: " ")
            break
        }

        // 4) 时段词单独出现（「今晚」）但没有具体几点时，把它从标题里去掉。
        rest = replaceFirstRegex(leadingPeriodWordRE, in: rest, with: " ")
        if !time.isEmpty && date.isEmpty { date = ctx.today }

        let collapsed = jsTrim(collapseWhitespace(rest))
        let original = jsTrim(text)
        let title = collapsed.isEmpty ? original : collapsed
        return ParsedInput(title: title, date: date, time: time, repeatRule: repeatRule, hits: hits)
    }

    // MARK: 常量（parse.js:8-17）

    /// JS `CN`：零〇一二两三四五六七八九十。
    private static let cn: [String: Int] = [
        "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
        "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10,
    ]

    /// JS `WD`：周日 = 7，同时接受 1~7 的阿拉伯数字。
    private static let wd: [String: Int] = [
        "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6,
        "日": 7, "天": 7, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
    ]

    private static let numPattern = "([0-9]{1,2}|[一二两三四五六七八九十]{1,3})"
    private static let wdsPattern = "[一二三四五六日天1-7]"
    private static let periodPattern =
        "(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|今晚|明晚|今早|明早|晚|早)?"

    /// JS RegExp `\s` / `String.prototype.trim()` 的 WhiteSpace 精确集合（ES spec）。
    /// 实测差异：ICU 的 `\s` 把 U+200B 零宽空格也当空白，JS 不会（夹具 EDGES 组第 11 条）。
    /// 故 `\s` 一律改用这个显式字符类，`trim` 改用下面的 jsTrim，避免静默不等价。
    private static let jsSpaceClass =
        "[\\t\\n\\u000B\\u000C\\r \\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]"

    private static let jsTrimSet: CharacterSet = {
        var cs = CharacterSet()
        for cp in [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0xFEFF] {
            cs.insert(Unicode.Scalar(UInt32(cp))!)
        }
        for cp in 0x2000...0x200A { cs.insert(Unicode.Scalar(UInt32(cp))!) }
        for cp in [0x2028, 0x2029, 0x202F, 0x205F, 0x3000] {
            cs.insert(Unicode.Scalar(UInt32(cp))!)
        }
        return cs
    }()

    /// JS `String.prototype.trim()`：只裁掉上面的集合，不裁 U+200B。
    private static func jsTrim(_ s: String) -> String {
        var scalars = Array(s.unicodeScalars)
        while let f = scalars.first, jsTrimSet.contains(f) { scalars.removeFirst() }
        while let l = scalars.last, jsTrimSet.contains(l) { scalars.removeLast() }
        return String(String.UnicodeScalarView(scalars))
    }

    // MARK: 上下文与日期助手

    private struct Ctx: Sendable {
        let today: String
        let year: Int
        init(now: Date) {
            self.today = PlannerCalendar.today(now)
            self.year = PlannerCalendar.component(now, .year)
        }
    }

    /// JS `new Date(y, m-1, d)`：DateComponents 的 month 是 1-based，越界自动滚月（如 2 月 30 日）。
    private static func makeDate(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        return PlannerCalendar.calendar.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    private static func comps(_ d: Date) -> (year: Int, month: Int, day: Int) {
        let c = PlannerCalendar.calendar.dateComponents([.year, .month, .day], from: d)
        return (c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// JS `cnNum`（parse.js:9-15），nil 代表 NaN。
    private static func cnNum(_ s: String?) -> Int? {
        guard let s, !s.isEmpty else { return nil }
        if s.allSatisfy({ $0.isASCII && $0.isNumber }) { return Int(s) }
        if s == "十" { return 10 }
        let chars = Array(s)
        if chars.first == "十" {
            return 10 + (chars.count > 1 ? cn[String(chars[1])] ?? 0 : 0)
        }
        if let idx = chars.firstIndex(of: "十") {
            let tens = cn[String(chars[0])] ?? 0
            let ones = idx + 1 < chars.count ? cn[String(chars[idx + 1])] ?? 0 : 0
            return tens * 10 + ones
        }
        return cn[s]
    }

    /// JS `every`（parse.js:59-64）：「每隔一天」= 隔一天做一次 = 每 2 天。
    private static func every(_ num: String?, _ prefix: String?) -> Int? {
        if prefix == "隔" { return 2 }
        let n: Int?
        if let num, !num.isEmpty { n = cnNum(num) } else { n = 1 }
        guard let n, n >= 1, n <= 99 else { return nil }
        if let prefix, prefix.contains("隔") { return n + 1 }
        return n
    }

    /// JS `nextWeekday`（parse.js:46-49）：下一个星期 w（1-7，含今天）。
    private static func nextWeekday(_ w: Int, _ ctx: Ctx) -> String {
        var target = PlannerCalendar.addDays(PlannerCalendar.mondayOf(ctx.today), w - 1)
        if target < ctx.today { target = PlannerCalendar.addDays(target, 7) }
        return target
    }

    /// JS `nextMonthDay`（parse.js:51-57）：下一个 M月D日（含今天）；无效月日返回空串。
    private static func nextMonthDay(_ m: Int?, _ d: Int?, _ ctx: Ctx) -> String {
        guard let m, let d else { return "" }
        let x = makeDate(year: ctx.year, month: m, day: d)
        if comps(x).month != m { return "" }
        if PlannerCalendar.ymd(x) < ctx.today {
            let c = comps(x)
            return PlannerCalendar.ymd(makeDate(year: c.year + 1, month: c.month, day: c.day))
        }
        return PlannerCalendar.ymd(x)
    }

    // MARK: 正则与匹配

    private struct Match: Sendable {
        let text: String
        let groups: [String?]
        /// 下标与 JS `m[i]` 对齐：0 是整段命中文本，1..n 是捕获组（未参与匹配为 nil）。
        subscript(_ i: Int) -> String? {
            if i == 0 { return text }
            let k = i - 1
            return k >= 0 && k < groups.count ? groups[k] : nil
        }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // 契约内的 pattern 均为静态常量，编译失败属于实现缺陷而非运行时输入。
        try! NSRegularExpression(pattern: pattern)
    }

    private static func firstMatch(_ re: NSRegularExpression, in s: NSString) -> Match? {
        let full = NSRange(location: 0, length: s.length)
        guard let r = re.firstMatch(in: s as String, options: [], range: full) else { return nil }
        var groups: [String?] = []
        if r.numberOfRanges > 1 {
            for i in 1..<r.numberOfRanges {
                let rr = r.range(at: i)
                groups.append(rr.location == NSNotFound ? nil : s.substring(with: rr))
            }
        }
        return Match(text: s.substring(with: r.range), groups: groups)
    }

    /// JS `String.replace(literal, ' ')`：字面串、只替换首次出现。
    private static func replaceFirstLiteral(_ needle: String, in s: NSString, with replacement: String) -> NSString {
        let r = s.range(of: needle)
        guard r.location != NSNotFound else { return s }
        return s.replacingCharacters(in: r, with: replacement) as NSString
    }

    private static func replaceFirstRegex(_ re: NSRegularExpression, in s: NSString, with replacement: String) -> NSString {
        let out = re.stringByReplacingMatches(
            in: s as String, options: [],
            range: NSRange(location: 0, length: s.length), withTemplate: replacement)
        return out as NSString
    }

    private static let collapseRE = regex("\(jsSpaceClass)+")
    private static let leadingPeriodWordRE = regex(
        "^\(jsSpaceClass)*(今晚|明晚|今早|明早)\(jsSpaceClass)*")

    private static func collapseWhitespace(_ s: NSString) -> String {
        collapseRE.stringByReplacingMatches(
            in: s as String, options: [],
            range: NSRange(location: 0, length: s.length), withTemplate: " ")
    }

    // MARK: 规则表

    private struct RepeatRule: Sendable {
        let re: NSRegularExpression
        let run: @Sendable (Match, Ctx) -> (String, String)?
    }

    private struct DateRule: Sendable {
        let re: NSRegularExpression
        let run: @Sendable (Match, Ctx) -> String
    }

    private struct TimeRule: Sendable {
        let re: NSRegularExpression
        let run: @Sendable (Match) -> TimeHit
    }

    private struct TimeHit: Sendable {
        let period: String?
        let hour: Int?
        let minute: Int
    }

    /// parse.js:104
    private static let untilRE = regex(
        "(?:直到|截止到?|到|至)\(numPattern)月\(numPattern)[日号]?(?:为止|结束)?")

    /// parse.js:66-102，10 条，顺序敏感。
    private static let repeatRules: [RepeatRule] = {
        var out: [RepeatRule] = []

        out.append(RepeatRule(re: regex("(每隔|每)\(numPattern)个?天")) { m, ctx in
            guard let n = every(m[2], m[1]) else { return nil }
            return ("d\(n)", ctx.today)
        })
        out.append(RepeatRule(re: regex("隔天")) { _, ctx in ("d2", ctx.today) })
        out.append(RepeatRule(re: regex("每天|每日|天天")) { _, ctx in ("d1", ctx.today) })
        out.append(RepeatRule(re: regex("(?:每个?)?工作日")) { _, ctx in ("w1:12345", ctx.today) })
        out.append(RepeatRule(re: regex("每个?周末")) { _, ctx in
            let start = [nextWeekday(6, ctx), nextWeekday(7, ctx)].sorted().first ?? ctx.today
            return ("w1:06", start)
        })
        // 每周一三五 / 每周一、周三 / 每两周五 / 隔周周五 / 每隔一周的周二
        out.append(RepeatRule(re: regex(
            "(每隔|每|隔)\(numPattern)?个?(?:周|星期|礼拜)的?(?:周|星期|礼拜)?(\(wdsPattern)(?:[、,，和及与]?(?:周|星期|礼拜)?\(wdsPattern))*)"
        )) { m, ctx in
            guard let list = m[3] else { return nil }
            let ns = list as NSString
            let charsRE = regex(wdsPattern)
            let matches = charsRE.matches(
                in: list, options: [], range: NSRange(location: 0, length: ns.length))
            var ws: [Int] = []
            for r in matches {
                let c = ns.substring(with: r.range)
                if let w = wd[c], !ws.contains(w) { ws.append(w) }
            }
            guard let n = every(m[2], m[1]) else { return nil }
            let days = ws.map { String($0 % 7) }.joined()
            let start = ws.map { nextWeekday($0, ctx) }.sorted().first ?? ctx.today
            return ("w\(n):\(days)", start)
        })
        out.append(RepeatRule(re: regex("(每隔|每|隔)\(numPattern)?个?(?:周|星期|礼拜)")) { m, ctx in
            guard let n = every(m[2], m[1]) else { return nil }
            return ("w\(n):\(PlannerCalendar.weekdayIndex(ctx.today))", ctx.today)
        })
        out.append(RepeatRule(re: regex("(每隔|每)\(numPattern)?个?月的?\(numPattern)[日号]")) { m, ctx in
            guard let n = every(m[2], m[1]), let day = cnNum(m[3]), day >= 1, day <= 31 else { return nil }
            let c = comps(PlannerCalendar.parseYmd(ctx.today))
            var d = makeDate(year: c.year, month: c.month, day: day)
            if PlannerCalendar.ymd(d) < ctx.today || comps(d).day != day {
                let c2 = comps(d)
                d = makeDate(year: c2.year, month: c2.month + 1, day: day)
            }
            return ("m\(n)", PlannerCalendar.ymd(d))
        })
        out.append(RepeatRule(re: regex("(每隔|每)\(numPattern)?年的?\(numPattern)月\(numPattern)[日号]")) { m, ctx in
            guard let n = every(m[2], m[1]) else { return nil }
            let d = nextMonthDay(cnNum(m[3]), cnNum(m[4]), ctx)
            guard !d.isEmpty else { return nil }
            return ("y\(n)", d)
        })
        out.append(RepeatRule(re: regex("每个?月")) { _, ctx in ("m1", ctx.today) })
        out.append(RepeatRule(re: regex("每年")) { _, ctx in ("y1", ctx.today) })
        return out
    }()

    /// parse.js:19-43，7 条，顺序敏感。
    private static let dateRules: [DateRule] = [
        DateRule(re: regex("大后天")) { _, ctx in PlannerCalendar.addDays(ctx.today, 3) },
        DateRule(re: regex("后天")) { _, ctx in PlannerCalendar.addDays(ctx.today, 2) },
        DateRule(re: regex("明天|明日|明早|明晚")) { _, ctx in PlannerCalendar.addDays(ctx.today, 1) },
        DateRule(re: regex("今天|今日|今晚|今早")) { _, ctx in ctx.today },
        DateRule(re: regex("(下下|下)?(?:周|星期|礼拜)([一二三四五六日天1-7])")) { m, ctx in
            guard let key = m[2], let w = wd[key] else { return ctx.today }
            var target = PlannerCalendar.addDays(PlannerCalendar.mondayOf(ctx.today), w - 1)
            if m[1] == "下" { return PlannerCalendar.addDays(target, 7) }
            if m[1] == "下下" { return PlannerCalendar.addDays(target, 14) }
            if target < ctx.today { target = PlannerCalendar.addDays(target, 7) }
            return target
        },
        DateRule(re: regex("\(numPattern)月\(numPattern)[日号]?")) { m, ctx in
            guard let mo = cnNum(m[1]), let dy = cnNum(m[2]) else { return "" }
            var d = makeDate(year: ctx.year, month: mo, day: dy)
            if PlannerCalendar.ymd(d) < ctx.today {
                let c = comps(d)
                d = makeDate(year: c.year + 1, month: c.month, day: c.day)
            }
            return PlannerCalendar.ymd(d)
        },
        DateRule(re: regex("(?<![0-9月])\(numPattern)[号]")) { m, ctx in
            guard let dy = cnNum(m[1]) else { return "" }
            let c = comps(PlannerCalendar.parseYmd(ctx.today))
            var d = makeDate(year: c.year, month: c.month, day: dy)
            if PlannerCalendar.ymd(d) < ctx.today {
                let c2 = comps(d)
                d = makeDate(year: c2.year, month: c2.month + 1, day: c2.day)
            }
            return PlannerCalendar.ymd(d)
        },
    ]

    /// parse.js:107-115，2 条。
    private static let timeRules: [TimeRule] = [
        TimeRule(re: regex("\(periodPattern)\(jsSpaceClass)*([0-9]{1,2})[:：]([0-9]{2})")) { m in
            TimeHit(period: m[1], hour: Int(m[2] ?? ""), minute: Int(m[3] ?? "") ?? 0)
        },
        TimeRule(re: regex("\(periodPattern)\(jsSpaceClass)*\(numPattern)[点时](半|一刻|三刻|([0-9]{1,2})分?)?")) { m in
            let part = m[3]
            let min: Int
            if part == "半" { min = 30 }
            else if part == "一刻" { min = 15 }
            else if part == "三刻" { min = 45 }
            else if let digits = m[4], !digits.isEmpty { min = Int(digits) ?? 0 }
            else { min = 0 }
            return TimeHit(period: m[1], hour: cnNum(m[2]), minute: min)
        },
    ]

    /// parse.js:117-124。
    private static func toTime(_ period: String?, _ h: Int?, _ min: Int) -> String? {
        guard let h else { return nil }
        if h > 24 || min > 59 { return nil }
        var hour = h
        let p = period ?? ""
        if p.contains("下午") || p.contains("傍晚") || p.contains("晚") {
            if hour < 12 { hour += 12 }
        } else if p == "中午" {
            if hour < 11 { hour += 12 }
        } else if period == nil, hour >= 1, hour <= 6 {
            hour += 12
        }
        if hour == 24 { hour = 0 }
        return "\(PlannerCalendar.pad(hour)):\(PlannerCalendar.pad(min))"
    }
}
