import Foundation

// MARK: - M-15 属性面板：事实层
//
// 逐字对齐 baseline_commit 97a7c4c：
// · 面板内容与选项：DatePanel.vue / TimePanel.vue / RepeatPanel.vue / QuadPanel.vue / RemindPanel.vue
// · 联动规则：TaskDetail.vue:setDate / setTime / setRepeat / openRemind（F-06.4）
// · 选项值：notify.js:REMIND_OPTIONS / remindLabel / remindShort、quadrant.js:QUADRANTS
//
// 纯逻辑，不依赖 SwiftUI，可在 macOS 侧做跨端对比与单测。

enum PropertyPanel: String, CaseIterable, Sendable {
    case date, time, remind, `repeat`
}

/// 一次属性修改：set 里的键要写值，cleared 里的键要清空。
/// 用这种结构是为了保留上游 patch 的语义（`{ date: '' }` 与「不改 date」是两回事）。
struct TaskPatch: Equatable, Sendable {
    var values: [String: String] = [:]
    var cleared: Set<String> = []

    var isEmpty: Bool { values.isEmpty && cleared.isEmpty }

    func apply(to task: PlannerTask) -> PlannerTask {
        var t = task
        for key in cleared {
            switch key {
            case "date": t.date = ""
            case "time": t.time = ""
            case "repeat": t.repeatRule = ""
            case "remind": t.remind = nil
            default: break
            }
        }
        for (key, value) in values {
            switch key {
            case "date": t.date = value
            case "time": t.time = value
            case "repeat": t.repeatRule = value
            case "remind": t.remind = Int(Double(value) ?? 0)
            default: break
            }
        }
        return t
    }
}

enum PanelLinkage {

    /// TaskDetail.vue:setDate —— 清日期时连带清空时间与重复（F-06.4）。
    static func setDate(_ value: String) -> TaskPatch {
        if value.isEmpty {
            return TaskPatch(cleared: ["date", "time", "repeat"])
        }
        return TaskPatch(values: ["date": value])
    }

    /// TaskDetail.vue:setTime ——
    /// · 设时间但没日期：补今天；
    /// · 第一次设时间且还没设提醒：用「我的」里的 defaultRemind；
    /// · 清空时间只改 time，不动 remind（与上游一致：没时间的提醒不会触发）。
    static func setTime(
        _ value: String,
        taskDate: String,
        taskTime: String,
        remind: Int?,
        defaultRemind: Int,
        today: String
    ) -> TaskPatch {
        var patch = TaskPatch(values: ["time": value])
        if !value.isEmpty && taskDate.isEmpty {
            patch.values["date"] = today
        }
        if !value.isEmpty && taskTime.isEmpty && remind == nil {
            patch.values["remind"] = String(defaultRemind)
        }
        return patch
    }

    /// TaskDetail.vue:setRepeat —— 设重复但没日期：补今天。
    static func setRepeat(_ value: String, taskDate: String, today: String) -> TaskPatch {
        var patch = TaskPatch(values: ["repeat": value])
        if !value.isEmpty && taskDate.isEmpty {
            patch.values["date"] = today
        }
        return patch
    }

    /// TaskDetail.vue:setRemind
    static func setRemind(_ value: Int?) -> TaskPatch {
        if let value { return TaskPatch(values: ["remind": String(value)]) }
        return TaskPatch(cleared: ["remind"])
    }

    /// TaskDetail.vue:openRemind —— 没设时间就先去选时间。
    static func panelToOpen(_ requested: PropertyPanel, hasTime: Bool) -> PropertyPanel {
        requested == .remind && !hasTime ? .time : requested
    }

    /// TaskDetail.vue:setQ —— 象限写回 important / urgent 两个布尔。
    static func setQuadrant(_ q: Int) -> (important: Bool, urgent: Bool) {
        (q <= 2, q == 1 || q == 3)
    }
}

enum PanelCatalog {

    // MARK: 日期面板（DatePanel.vue:quick，默认「今天 / 明天 / 下周一 / 无日期」）

    struct DateQuick: Equatable, Sendable {
        let key: String       // 中文原文键，交给 AppStrings.t
        let icon: String      // ReachIconName.rawValue
        let kind: Kind
        enum Kind: Equatable, Sendable { case today, tomorrow, nextMonday, none }
    }

    static let dateQuick: [DateQuick] = [
        .init(key: "今天", icon: "sun", kind: .today),
        .init(key: "明天", icon: "sunrise", kind: .tomorrow),
        .init(key: "下周一", icon: "week", kind: .nextMonday),
        .init(key: "无日期", icon: "ban", kind: .none),
    ]

    static func dateQuickValue(_ kind: DateQuick.Kind, today: String) -> String {
        switch kind {
        case .today: return today
        case .tomorrow: return DateText.addDays(today, 1)
        case .nextMonday: return DateText.addDays(DateText.mondayOf(today), 7)
        case .none: return ""
        }
    }

    // MARK: 时间面板（TimePanel.vue:PRESETS）

    static let timePresets = ["08:00", "09:00", "10:00", "12:00", "14:00", "16:00", "18:00", "20:00", "21:00", "22:00"]

    // MARK: 提醒面板（notify.js:REMIND_OPTIONS）

    static let remindOptions = [0, 5, 15, 30, 60]

    /// notify.js:remindLabel —— 属性行上的值
    static func remindLabel(_ minutes: Int?, isEnglish: Bool) -> String {
        guard let m = minutes else { return isEnglish ? "No reminder" : "不提醒" }
        if m == 0 { return isEnglish ? "On time" : "准时" }
        if m >= 60 {
            let h = m / 60
            return isEnglish ? "\(AppStrings.plural(h, "hour")) before" : "提前 \(h) 小时"
        }
        return isEnglish ? "\(AppStrings.plural(m, "minute")) before" : "提前 \(m) 分钟"
    }

    /// notify.js:remindShort —— 选项按钮上的短文字（英文固定 hr / min，不随复数变化）
    static func remindShort(_ minutes: Int, isEnglish: Bool) -> String {
        if minutes == 0 { return isEnglish ? "On time" : "准时" }
        if minutes >= 60 { return isEnglish ? "\(minutes / 60) hr before" : "\(minutes / 60) 小时前" }
        return isEnglish ? "\(minutes) min before" : "\(minutes) 分钟前"
    }

    // MARK: 象限面板（quadrant.js:QUADRANTS）

    struct Quadrant: Equatable, Sendable {
        let index: Int
        let icon: String
        let colorToken: String
        let nameKey: String
        let shortKey: String
        let hintKey: String
    }

    /// 名称 / 短名 / hint 都以中文原文为键，英文由 AppStrings 解析；颜色按 §5.1 第 5 条保留。
    static let quadrants: [Quadrant] = [
        .init(index: 1, icon: "fire", colorToken: "--q1",
              nameKey: "重要且紧急", shortKey: "重要紧急", hintKey: "立即处理"),
        .init(index: 2, icon: "star", colorToken: "--q2",
              nameKey: "重要不紧急", shortKey: "重要", hintKey: "计划去做"),
        .init(index: 3, icon: "bolt", colorToken: "--q3",
              nameKey: "紧急不重要", shortKey: "紧急", hintKey: "快速处理"),
        .init(index: 4, icon: "coffee", colorToken: "--q4",
              nameKey: "不重要不紧急", shortKey: "一般", hintKey: "有空再做"),
    ]

    static func quadrantOf(important: Bool, urgent: Bool) -> Int {
        important ? (urgent ? 1 : 2) : (urgent ? 3 : 4)
    }

    // MARK: 重复面板（RepeatPanel.vue:presets / endOptions）

    /// 5 个预设：每天 / 工作日 / 每周{开始日期的星期} / 每月 / 每年。
    /// 第 3 个依赖开始日期的星期几，用 `repeatPresets(date:)` 生成。
    static func repeatPresets(date: String) -> [String] {
        let dow = DateText.weekdayIndex(date.isEmpty ? DateText.today() : date)
        return ["d1", "w1:12345", "w1:\(dow)", "m1", "y1"]
    }

    /// RepeatPanel.vue:presetLabel —— 英文的 Monthly on the 13th 在三列格子里放不下，只写 Monthly / Yearly。
    static func repeatPresetLabel(_ rule: String, date: String, isEnglish: Bool) -> String {
        if isEnglish, let first = rule.first {
            if first == "m" { return "Monthly" }
            if first == "y" { return "Yearly" }
        }
        return RepeatRule.label(rule, date: date, isEnglish: isEnglish)
    }

    struct EndOption: Equatable, Sendable {
        let key: String       // 中文原文键
        let icon: String
        let kind: Kind
        enum Kind: Equatable, Sendable { case never, month1, month3, yearEnd }
    }

    static let repeatEndOptions: [EndOption] = [
        .init(key: "永不结束", icon: "ban", kind: .never),
        .init(key: "1个月后", icon: "week", kind: .month1),
        .init(key: "3个月后", icon: "week", kind: .month3),
        .init(key: "今年年底", icon: "calendar", kind: .yearEnd),
    ]

    /// RepeatPanel.vue:endOptions —— from = 开始日期晚于今天就用开始日期，否则今天。
    static func endOptionValue(_ kind: EndOption.Kind, startDate: String, today: String) -> String {
        let from = (!startDate.isEmpty && startDate > today) ? startDate : today
        switch kind {
        case .never: return ""
        case .month1: return DateText.addDays(from, 30)
        case .month3: return DateText.addDays(from, 91)
        case .yearEnd: return "\(DateText.component(DateText.parse(from), .year))-12-31"
        }
    }

    /// RepeatPanel.vue:setUntil —— 结束日期不能早于开始日期。
    static func clampUntil(_ until: String, startDate: String) -> String {
        if !until.isEmpty && !startDate.isEmpty && until < startDate { return startDate }
        return until
    }

    /// RepeatPanel.vue:cur —— 还没设重复时，自定义区从「每天」开始改。
    static func customBase(_ repeatRule: String) -> RepeatRule.Rule {
        RepeatRule.parse(repeatRule) ?? RepeatRule.defaultCustom
    }

    /// RepeatPanel.vue:step —— 1…99
    static func steppedCount(_ n: Int, delta: Int) -> Int {
        min(99, max(1, n + delta))
    }

    /// RepeatPanel.vue:toggleDay —— 至少留一天。
    static func toggledDays(_ days: [Int], _ day: Int) -> [Int] {
        let next = days.contains(day) ? days.filter { $0 != day } : days + [day]
        return next.isEmpty ? days : next.sorted()
    }

    /// RepeatPanel.vue:setFreq —— 切到「周」时若还没选过天，默认选开始日期的星期。
    static func daysWhenSwitching(freq: String, current: [Int], dow: Int) -> [Int] {
        guard freq == "w" else { return [] }
        return current.isEmpty ? [dow] : current
    }

    // MARK: 视图用的快捷项（把 kind 解析成具体日期，供 DatePanelView 复用）

    struct DateQuickOption: Identifiable, Equatable, Sendable {
        let key: String
        let icon: String
        let value: String
        var id: String { key + "|" + value }
    }

    static func dateOptions(today: String) -> [DateQuickOption] {
        dateQuick.map {
            DateQuickOption(key: $0.key, icon: $0.icon, value: dateQuickValue($0.kind, today: today))
        }
    }

    static func repeatEndQuickOptions(startDate: String, today: String) -> [DateQuickOption] {
        repeatEndOptions.map {
            DateQuickOption(key: $0.key, icon: $0.icon, value: endOptionValue($0.kind, startDate: startDate, today: today))
        }
    }

    /// RepeatPanel.vue:summary —— 面板底部的规则摘要
    static func repeatSummary(_ rule: String, date: String, isEnglish: Bool) -> String {
        rule.isEmpty
            ? (isEnglish ? "Never" : "不重复")
            : RepeatRule.label(rule, date: date, isEnglish: isEnglish, withUntil: true)
    }
}
