import SwiftUI

// MARK: - M-19 TaskRow：事实层
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/components/TaskRow.vue：
// COMPLETE_AT = 76、按钮 64 + 间隔 8、右滑阻尼上限 110、左滑吸附阈值 actionsW/2.4、
// 勾选延迟 380ms、滑动结束后的 250ms 点击守卫、canDrop 条件、元信息显示条件。
//
// 呈现层按 §5.0 / OPEN-18 交给系统 List + swipeActions：
// · 系统决定实际触发距离，不硬编码 76pt（VERIFY-04 已登记，差异待真机体感复核）；
// · 「同一时间只展开一行」由系统 List 的 swipeActions 行为保证，不自建 openRow 单例。

struct TaskRowModel {
    var task: PlannerTask
    /// 重复任务的实例日期（对应上游运行时字段 occ）；空表示非重复实例。
    var occ: String = ""
    var subDone: Int = 0
    var subTotal: Int = 0
    var parentTitle: String = ""
    var streak: Int = 0
    /// 中文单位：天 / 周 / 个月 / 年 / 次
    var streakUnit: String = "天"
    var today: String = DateText.today()

    var isEnglish: Bool = false

    var quadrant: Int {
        PanelCatalog.quadrantOf(important: task.important, urgent: task.urgent)
    }

    var isDone: Bool {
        // 重复任务看实例日期是否在 doneDates 里；普通任务看 done。
        task.repeatRule.isEmpty ? task.done : task.doneDates.contains(occ.isEmpty ? task.date : occ)
    }

    var isOverdue: Bool {
        DateText.isOverdue(date: task.date, repeatRule: task.repeatRule, done: isDone, today: today)
    }

    var dateText: String {
        DateText.label(task.date, today: today, isEnglish: isEnglish)
    }

    var repeatText: String {
        RepeatRule.label(task.repeatRule, date: task.date, isEnglish: isEnglish)
    }

    var streakText: String {
        TaskRowFormattingDefault.streak(streak, unit: streakUnit, isEnglish: isEnglish)
    }
}

enum TaskRowContract {

    /// 非紧凑态的水平内边距与图标—文字间距；分割线的缩进由它们推导，不写死数字。
    static let rowHorizontalInset: CGFloat = 14
    static let rowSpacing: CGFloat = 12
    /// 分割线起点对齐标题文字：内边距 + 勾选触点宽 + 间距。
    static var separatorInset: CGFloat {
        rowHorizontalInset + DesignTokens.touchTarget + rowSpacing
    }

    /// TaskRow.vue:COMPLETE_AT
    static let completeAt: Double = 76
    /// TaskRow.vue:actionsW 里的按钮宽与间隔
    static let actionWidth: Double = 64
    static let actionGap: Double = 8
    /// TaskRow.vue:rubber(v, 110)
    static let rightRubberLimit: Double = 110
    /// TaskRow.vue:dx < -actionsW / 2.4
    static let snapDivisor: Double = 2.4
    /// TaskRow.vue:toggle 的 380ms
    static let toggleDelayMilliseconds = 380
    /// TaskRow.vue:onUp 写入的点击守卫窗口（与 FeedbackContract 同源）
    static let guardMilliseconds = FeedbackContract.clickGuardMilliseconds

    /// TaskRow.vue:canDrop —— 「放弃」只给还没完成的一次性任务（重复任务用「跳过」）
    static func canDrop(postpone: Bool, repeatRule: String, done: Bool) -> Bool {
        postpone && repeatRule.isEmpty && !done
    }

    /// 左滑按钮数量：推迟/跳过 + 放弃（可选） + 删除
    static func actionCount(postpone: Bool, canDrop: Bool) -> Int {
        1 + (postpone ? 1 : 0) + (canDrop ? 1 : 0)
    }

    static func actionsWidth(postpone: Bool, canDrop: Bool) -> Double {
        let n = Double(actionCount(postpone: postpone, canDrop: canDrop))
        return n * actionWidth + (n - 1) * actionGap
    }

    /// TaskRow.vue:rubber
    static func rubber(_ value: Double, limit: Double) -> Double {
        value <= limit ? value : limit + (value - limit) * 0.25
    }

    /// TaskRow.vue:onMove 里的位移合成
    static func offset(base: Double, translation: Double, actionsWidth: Double, rightLimit: Double = rightRubberLimit) -> Double {
        let v = base + translation
        return v >= 0 ? rubber(v, limit: rightLimit) : -rubber(-v, limit: actionsWidth)
    }

    static func isPastCompleteThreshold(_ dx: Double) -> Bool { dx > completeAt }

    static func shouldSnapOpen(_ dx: Double, actionsWidth: Double) -> Bool {
        dx < -actionsWidth / snapDivisor
    }

    /// 左滑第一个动作的文案与图标：重复任务「跳过 + skip」，一次性任务「推迟 + arrow-right」
    static func postponeAction(repeatRule: String) -> (key: String, icon: String) {
        repeatRule.isEmpty ? ("推迟", "arrow-right") : ("跳过", "skip")
    }

    /// TaskRow.vue:template.trow-meta 的显示条件（逐项）
    struct MetaFlags: Equatable, Sendable {
        var dropped = false
        var date = false
        var streak = false
        var repeatRule = false
        var compactTime = false
        var subProgress = false
        var note = false
        var parent = false

        var any: Bool {
            dropped || date || streak || repeatRule || compactTime || subProgress || note || parent
        }
    }

    static func metaFlags(
        showDate: Bool,
        compact: Bool,
        hideRepeat: Bool,
        hideParent: Bool,
        date: String,
        time: String,
        note: String,
        repeatRule: String,
        streak: Int,
        subTotal: Int,
        parentTitle: String,
        dropped: Bool
    ) -> MetaFlags {
        MetaFlags(
            dropped: dropped,
            date: showDate && !date.isEmpty,
            streak: streak > 1,
            repeatRule: !repeatRule.isEmpty && !hideRepeat,
            compactTime: compact && !time.isEmpty,
            subProgress: subTotal > 0,
            note: !note.isEmpty,
            parent: !parentTitle.isEmpty && !hideParent
        )
    }

    /// TaskRow.vue:38-44 —— 点圆圈先播 380ms 动画再真正提交；期间 pending。
    /// 这里只表达状态机：pending 时按钮不可重复触发。
    struct ToggleState: Equatable, Sendable {
        private(set) var pending = false

        mutating func begin() -> Bool {
            guard !pending else { return false }
            pending = true
            return true
        }

        mutating func finish() { pending = false }
    }

    /// 视觉上的完成态：pending 期间先翻转，让动画立刻开始（TaskRow.vue:done computed）
    static func visualDone(taskDone: Bool, pending: Bool) -> Bool {
        pending ? !taskDone : taskDone
    }
}

/// T-14 的临时格式化实现（M-06 / M-03 完成前的子集）。T-06 / T-07 接入后替换本类型，
/// TaskRow 的调用点不变；A-38 的日期/重复文案子项届时复核。
enum TaskRowFormattingDefault {
    static func streak(_ n: Int, unit: String, isEnglish: Bool) -> String {
        guard isEnglish else { return "连续 \(n) \(unit)" }
        switch unit {
        case "周": return "\(n)-week streak"
        case "个月": return "\(n)-month streak"
        case "年": return "\(n)-year streak"
        case "次": return "\(n) in a row"
        default: return "\(n)-day streak"
        }
    }
}
