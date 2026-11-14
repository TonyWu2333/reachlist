import Foundation

// MARK: - M-07 提醒排程（T-11）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/lib/notify.js（115 行）中**纯逻辑部分**：
// `planReminders`（30 天 / 60 条 / 稳定排序）、`idOf`（UTF-16 32 位哈希）、
// `toNotification`（when / body / extra / channelId）、`remindLabel` / `remindShort`
// 与 `src/lib/i18n-en.js:core` 的中英文案。系统通知 API 适配在 ReminderScheduler.swift。
//
// 设计约束（与 T-06 / T-08 / T-10 一致）：
// · 只 import Foundation，可在 macOS 侧用 swiftc 做跨端逐字对比；
// · `now` / `timeZone` 显式注入，使 `new Date("YYYY-MM-DDTHH:mm:00")` 的本地时间语义
//   在 5 个时区下都能用同一份夹具复现（JS 的 Date 走进程 TZ）；
// · 语言用 `isEnglish` 显式传入，T-19 落地后包一层即可，调用点不变；
// · 日期算术复用 M-06 的 PlannerCalendar（取其 gregorian Calendar 后只替换 timeZone），
//   不另写第二套日期逻辑，避免 RISK-01 的三端分叉。

// MARK: - 排程结果

struct ReminderPlan: Equatable, Sendable {
    /// JS `new Date(...).getTime()` 的毫秒时间戳（已减去 remind 提前量）。
    let at: Double
    let task: PlannerTask
    let date: String
}

/// `toNotification` 的平台无关结果。`UNNotificationRequest` 由 ReminderScheduler 构造。
struct ReminderNotification: Equatable, Sendable {
    let id: Int
    let title: String
    let body: String
    let channelId: String
    let extraId: String
    let extraOcc: String
    let at: Date
}

enum ReminderPlanner {

    static let windowDays = 30
    static let maxCount = 60
    static let remindOptions = [0, 5, 15, 30, 60]

    // MARK: 日期（对齐 date.js:ymd / addDays / parseYmd，时区可注入）

    private static func cal(_ tz: TimeZone) -> Calendar {
        var c = PlannerCalendar.calendar
        c.timeZone = tz
        return c
    }

    private static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : String(n) }

    private static func ymd(_ d: Date, _ tz: TimeZone) -> String {
        let c = cal(tz).dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(pad(c.month ?? 1))-\(pad(c.day ?? 1))"
    }

    private static func parseYmd(_ s: String, _ tz: TimeZone) -> Date {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 3 else { return Date(timeIntervalSince1970: 0) }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        return cal(tz).date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    private static func addDays(_ s: String, _ n: Int, _ tz: TimeZone) -> String {
        let base = parseYmd(s, tz)
        return ymd(cal(tz).date(byAdding: .day, value: n, to: base) ?? base, tz)
    }

    /// JS `new Date("\(d)T\(time):00")` —— 不带时区的 ISO date-time 按**本地时间**解析。
    /// 夏令时跳跃时刻由 Calendar 规范化（与 V8 一致，见 dst-spring-forward 夹具）。
    private static func localDateTime(day: String, time: String, _ tz: TimeZone) -> Date {
        let dayParts = day.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        let hm = time.split(separator: ":", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard dayParts.count == 3, hm.count >= 1 else { return Date(timeIntervalSince1970: 0) }
        var c = DateComponents()
        c.year = dayParts[0]
        c.month = dayParts[1]
        c.day = dayParts[2]
        c.hour = hm[0]
        c.minute = hm.count >= 2 ? hm[1] : 0
        c.second = 0
        return cal(tz).date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: planReminders（notify.js:26-45，逐字等价）

    /// `planReminders(tasks, now)`：30 天窗口、最多 60 条、按时间升序（稳定排序）。
    static func planReminders(
        _ tasks: [PlannerTask], now: Date, timeZone: TimeZone = .current
    ) -> [ReminderPlan] {
        let from = ymd(now, timeZone)
        let nowMs = now.timeIntervalSince1970 * 1000
        var out: [(at: Double, order: Int, task: PlannerTask, date: String)] = []
        var order = 0
        for t in tasks {
            guard t.remind != nil, !t.time.isEmpty, !t.date.isEmpty else { continue }
            let dates: [String]
            if !t.repeatRule.isEmpty {
                var ds: [String] = []
                for i in 0...windowDays {
                    let d = addDays(from, i, timeZone)
                    if RepeatEngine.occursOn(t, d) && !t.doneDates.contains(d) { ds.append(d) }
                }
                dates = ds
            } else {
                dates = t.done ? [] : [t.date]
            }
            for d in dates {
                let at = localDateTime(day: d, time: t.time, timeZone).timeIntervalSince1970 * 1000
                    - Double(t.remind ?? 0) * 60_000
                if at > nowMs {
                    out.append((at: at, order: order, task: t, date: d))
                    order += 1
                }
            }
        }
        // JS Array.prototype.sort 自 ES2019 起稳定；Swift 的 sort 不稳定，故显式带原序。
        out.sort { a, b in a.at == b.at ? a.order < b.order : a.at < b.at }
        return out.prefix(maxCount).map { ReminderPlan(at: $0.at, task: $0.task, date: $0.date) }
    }

    // MARK: idOf（notify.js:48-52）

    /// `idOf(key)` = `Math.abs(Math.imul(31,h)+charCodeAt | 0) || 1`，按 UTF-16 code unit。
    /// 用 Int64 承接 `Math.abs(Int32.min) = 2147483648`（超出 Int32 正数域，Swift 不能写成 Int32.abs）。
    static func idOf(_ key: String) -> Int {
        var h: Int32 = 0
        for unit in key.utf16 {
            h = Int32(truncatingIfNeeded: Int64(h) &* 31 + Int64(unit))
        }
        let magnitude = Int64(h).magnitude
        return magnitude == 0 ? 1 : Int(magnitude)
    }

    // MARK: 中英文案（i18n.js:t + i18n-en.js:core）

    /// `plural(n, one, many = one + 's')`
    static func plural(_ n: String, _ one: String, _ many: String? = nil) -> String {
        "\(n) \(n == "1" ? one : (many ?? one + "s"))"
    }

    /// JS 数字的字符串化：`60/60 = 1`（不带 .0）、`90/60 = 1.5`。
    private static func jsNumber(_ d: Double) -> String {
        if d == d.rounded() && d.magnitude < 1e15 { return String(Int(d)) }
        return String(d)
    }

    /// 只覆盖 notify.js / backup.js 用到的词条；T-19 落地后由 M-23 统一提供。
    static func t(_ zh: String, isEnglish: Bool, _ params: [String: String] = [:]) -> String {
        var base = zh
        if isEnglish {
            switch zh {
            case "不提醒": base = "No reminder"
            case "准时": base = "On time"
            case "提前 {n} 小时": base = plural(params["n"] ?? "", "hour") + " before"
            case "提前 {n} 分钟": base = plural(params["n"] ?? "", "minute") + " before"
            case "{n} 小时前": base = (params["n"] ?? "") + " hr before"
            case "{n} 分钟前": base = (params["n"] ?? "") + " min before"
            case "{n} 小时后开始": base = "Starts in " + plural(params["n"] ?? "", "hour")
            case "{n} 分钟后开始": base = "Starts in " + plural(params["n"] ?? "", "minute")
            case "任务提醒": base = "Task reminders"
            case "到点提醒设了时间的任务": base = "Reminders for tasks that have a time"
            case "重要且紧急": base = "Important & urgent"
            case "重要不紧急": base = "Important, not urgent"
            case "紧急不重要": base = "Urgent, not important"
            case "不重要不紧急": base = "Neither"
            default: break // 缺失词条回退中文（i18n.js:t 的行为）
            }
        }
        var out = base
        for (k, v) in params { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
        return out
    }

    static func remindLabel(_ m: Int?, isEnglish: Bool) -> String {
        guard let m else { return t("不提醒", isEnglish: isEnglish) }
        if m == 0 { return t("准时", isEnglish: isEnglish) }
        if m >= 60 {
            return t("提前 {n} 小时", isEnglish: isEnglish, ["n": jsNumber(Double(m) / 60)])
        }
        return t("提前 {n} 分钟", isEnglish: isEnglish, ["n": String(m)])
    }

    /// `remindShort` 上游对 `null` 没有特判：`null >= 60` 为 false、占位符被填成 `"null"`。
    /// 这是 JS 的真实输出（夹具 labels[0] 已固化），Swift 侧逐字保留，不擅自「修好」。
    static func remindShort(_ m: Int?, isEnglish: Bool) -> String {
        let n = m.map(String.init) ?? "null"
        if m == 0 { return t("准时", isEnglish: isEnglish) }
        if let m, m >= 60 {
            return t("{n} 小时前", isEnglish: isEnglish, ["n": jsNumber(Double(m) / 60)])
        }
        return t("{n} 分钟前", isEnglish: isEnglish, ["n": n])
    }

    /// `quadrant.js:quadrantOf` + `QUADRANTS[q].name`
    static func quadrantName(_ t: PlannerTask, isEnglish: Bool) -> String {
        let key = t.important ? (t.urgent ? "重要且紧急" : "重要不紧急")
                              : (t.urgent ? "紧急不重要" : "不重要不紧急")
        return t_(key, isEnglish: isEnglish)
    }

    private static func t_(_ zh: String, isEnglish: Bool) -> String { t(zh, isEnglish: isEnglish) }

    static func channelName(isEnglish: Bool) -> String { t("任务提醒", isEnglish: isEnglish) }
    static func channelDescription(isEnglish: Bool) -> String {
        t("到点提醒设了时间的任务", isEnglish: isEnglish)
    }

    // MARK: toNotification（notify.js:54-66）

    static func makeNotification(_ plan: ReminderPlan, isEnglish: Bool) -> ReminderNotification {
        let t = plan.task
        let r = t.remind ?? 0
        let when: String
        if r == 0 {
            when = t.time
        } else if r >= 60 {
            when = t_("{n} 小时后开始", isEnglish: isEnglish, ["n": jsNumber(Double(r) / 60)]) + " · " + t.time
        } else {
            when = t_("{n} 分钟后开始", isEnglish: isEnglish, ["n": String(r)]) + " · " + t.time
        }
        var extraParts: [String] = []
        if !t.repeatRule.isEmpty {
            extraParts.append(RepeatEngine.repeatLabel(t.repeatRule, date: t.date,
                                                       isEnglish: isEnglish, withUntil: false))
        }
        extraParts.append(quadrantName(t, isEnglish: isEnglish))
        let extra = extraParts.joined(separator: " · ")
        return ReminderNotification(
            id: idOf("\(t.id)|\(plan.date)"),
            title: t.title,
            body: "\(when) · \(extra)",
            channelId: "reminders",
            extraId: t.id,
            extraOcc: t.repeatRule.isEmpty ? "" : plan.date,
            at: Date(timeIntervalSince1970: plan.at / 1000)
        )
    }

    /// `sync()` 的第一步：`state.settings.remindOn ? planReminders(state.tasks) : []`。
    static func makeNotifications(
        _ tasks: [PlannerTask], remindOn: Bool, isEnglish: Bool,
        now: Date = Date(), timeZone: TimeZone = .current
    ) -> [ReminderNotification] {
        guard remindOn else { return [] }
        return planReminders(tasks, now: now, timeZone: timeZone)
            .map { makeNotification($0, isEnglish: isEnglish) }
    }

    // MARK: 点击通知路由（notify.js:109-112）

    static func route(from userInfo: [AnyHashable: Any]) -> (id: String, occ: String)? {
        guard let id = userInfo["id"] as? String, !id.isEmpty else { return nil }
        return (id, (userInfo["occ"] as? String) ?? "")
    }

    // 私有重载：makeNotification 内需要带参数的 t_。
    private static func t_(_ zh: String, isEnglish: Bool, _ params: [String: String]) -> String {
        t(zh, isEnglish: isEnglish, params)
    }
}
