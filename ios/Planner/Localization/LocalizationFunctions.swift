import Foundation

// MARK: - M-23 函数值词条（19 条）
//
// 上游 src/lib/i18n-en*.js 里有 19 个「值 = 函数」的词条（复数 / 分支 / 月份名 / 相对日期）。
// 这里按函数体逐字组装，返回值是**未 fill 的模板**：i18n.js:t 在拿到函数结果后
// 仍会执行一次 fill(result, p)，故由 LocalizationService.t 统一收尾，与 JS 一致。
//
// oracle / 逐字对比：node ios/PlannerTests/Fixtures/generate_t19_fixtures.mjs
// 覆盖顺序与运行时一致：core → calendar → sheets → pages（同名 key 后者覆盖前者），
// 因此「已删除「{title}」及{n} 个子任务」等两条以 sheets.js 的 `${p.title}` 版本为准。

enum LocalizationFunctions {

    private static let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// JS 的 `${p.k}`：缺参数时输出字面 `undefined`（真实调用方均传齐）。
    private static func p(_ params: [String: String], _ k: String) -> String {
        params[k] ?? "undefined"
    }

    /// JS 的 `p.n` 用在 plural / 严格相等 / 数组下标时是 number。
    private static func num(_ params: [String: String], _ k: String) -> Int {
        Int(params[k] ?? "") ?? 0
    }

    private static func plural(_ n: Int, _ one: String) -> String {
        LocalizationService.plural(n, one)
    }

    /// i18n-en/calendar.js:5 —— `String(s).replace(/^(Today|Tomorrow|Yesterday|Next)\b/, w => w.toLowerCase())`
    /// `\b` 必须落在非单词字符或串尾，否则「TomorrowX」不该被改写。
    private static func lowerRel(_ s: String) -> String {
        for word in ["Today", "Tomorrow", "Yesterday", "Next"] where s.hasPrefix(word) {
            let idx = s.index(s.startIndex, offsetBy: word.count)
            let boundaryOK = idx == s.endIndex || !isWordChar(s[idx])
            return boundaryOK ? word.lowercased() + s[idx...] : s
        }
        return s
    }

    private static func isWordChar(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return true }
        let v = scalar.value
        return (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122) || v == 95
    }

    /// 返回 nil 表示该 key 不是函数值词条，交给纯字符串字典处理。
    static func evaluate(_ key: String, _ params: [String: String]) -> String? {
        switch key {
        // i18n-en.js:26-31 —— 提醒短文案（sheets.js:32 同族）
        case "提前 {n} 小时":
            return plural(num(params, "n"), "hour") + " before"
        case "提前 {n} 分钟":
            return plural(num(params, "n"), "minute") + " before"
        case "{n} 小时前":
            return p(params, "n") + " hr before"
        case "{n} 分钟前":
            return p(params, "n") + " min before"
        case "{n} 小时后开始":
            return "Starts in " + plural(num(params, "n"), "hour")
        case "{n} 分钟后开始":
            return "Starts in " + plural(num(params, "n"), "minute")

        // i18n-en.js:57-58 —— 备份导入确认与结果
        case "用备份里的 {a} 条任务替换当前的 {b} 条？":
            return "Replace your \(plural(num(params, "b"), "task")) with the "
                + "\(plural(num(params, "a"), "task")) in the backup?"
        case "已恢复 {n} 条任务":
            return "Restored " + plural(num(params, "n"), "task")

        // i18n-en/sheets.js:42-43（覆盖 calendar.js:35-36 的同名字面量版本）
        case "已删除「{title}」及{n} 个子任务":
            return "Deleted “\(p(params, "title"))” and " + plural(num(params, "n"), "subtask")
        case "已删除「{title}」及以后的重复和{n} 个子任务":
            return "Deleted “\(p(params, "title"))”, future repeats and "
                + plural(num(params, "n"), "subtask")

        // i18n-en/calendar.js:39-40
        case "已推迟到{date}":
            return "Postponed to " + lowerRel(p(params, "date"))
        case "{n} 个任务已移到今天":
            return "Moved \(plural(num(params, "n"), "task")) to today"

        // i18n-en/sheets.js:32 —— `p.n === 1` 是严格相等，调用方传 number
        case "已完成 {n} 次":
            return num(params, "n") == 1 ? "Done once" : "Done \(p(params, "n")) times"
        // i18n-en/sheets.js:73 —— MONTHS[p.m - 1]，越界时 JS 为 undefined
        case "{y}年{m}月":
            let m = num(params, "m")
            let name = (1...12).contains(m) ? months[m - 1] : "undefined"
            return "\(name) \(p(params, "y"))"

        // i18n-en/pages.js:14 / 37 / 66（后者带空格的 key 与上面两条不是同一条）
        case "今天还有 {n} 个任务待完成":
            return plural(num(params, "n"), "task") + " left today"
        case "会替换当前全部 {n} 条任务":
            return "Replaces all " + plural(num(params, "n"), "current task")
        case "已删除「{title}」及 {n} 个子任务":
            return "Deleted “\(p(params, "title"))” and " + plural(num(params, "n"), "subtask")

        // i18n-en/pages.js:73-74
        case "今天还剩 {n} 项":
            return p(params, "n") + " left today"
        case "今天 {done}/{total} · 共 {n} 项打卡":
            return "Today \(p(params, "done"))/\(p(params, "total")) · "
                + plural(num(params, "n"), "routine")

        default:
            return nil
        }
    }
}
