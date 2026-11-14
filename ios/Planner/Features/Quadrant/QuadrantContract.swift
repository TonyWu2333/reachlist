import Foundation

// MARK: - M-11 四象限：事实层（T-16）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/views/QuadrantView.vue:13-107 与
// src/lib/quadrant.js：范围筛选、成员排除规则、按 byDate 排序、未完成计数、
// 象限 flags、空态文案、长按拖拽的时序常量与状态机。
// 纯 Foundation，可在 Xcode 外用 swiftc + JS oracle 夹具逐字对比。
//
// 呈现层按 §5.0 / OPEN-18 用系统 Picker / 系统 List；拖拽语义（340ms、8pt、落区高亮、
// 撤销 toast、300ms 点击守卫）属功能语义，完整保留，见 QuadrantScreen。

enum QuadrantRange: String, CaseIterable, Sendable {
    case all, today, week
}

enum QuadrantContract {

    /// QuadrantView.vue:RANGES —— 顺序与文案键，中文原文为键。
    static let ranges: [(key: QuadrantRange, label: String)] = [
        (.all, "全部"), (.today, "今天"), (.week, "本周"),
    ]

    static let emptyText: [Int: String] = [
        1: "没有需要马上处理的事",
        2: "规划一些长期重要的事",
        3: "没有打扰你的琐事",
        4: "清清爽爽",
    ]

    // MARK: 长按拖拽（QuadrantView.vue:51-108）
    static let pressMilliseconds = 340
    static let pressCancelDistance: Double = 8
    static let dropGuardMilliseconds = 300
    static let dropAnimationMilliseconds = 180

    /// `inRange`：无日期任务任何范围都显示；今天含逾期；本周到本周日。
    static func inRange(_ t: PlannerTask, range: QuadrantRange, today: String) -> Bool {
        if range == .all || t.date.isEmpty { return true }
        if range == .today { return t.date <= today }
        return t.date <= PlannerCalendar.addDays(PlannerCalendar.mondayOf(today), 6)
    }

    /// `groups`：排除子任务与重复任务；按 showDone 过滤；组内 byDate 排序。
    static func groups(
        _ tasks: [PlannerTask], range: QuadrantRange, showDone: Bool, today: String
    ) -> [Int: [PlannerTask]] {
        var g: [Int: [(order: Int, task: PlannerTask)]] = [1: [], 2: [], 3: [], 4: []]
        for (index, t) in tasks.enumerated() {
            if !t.parentId.isEmpty || !t.repeatRule.isEmpty { continue }
            if (showDone || !t.done) && inRange(t, range: range, today: today) {
                g[CalendarContract.quadrantOf(t), default: []].append((index, t))
            }
        }
        var out: [Int: [PlannerTask]] = [:]
        for q in 1...4 {
            // JS Array.sort 稳定：比较器相等时保留原数组顺序，显式带原序做 tie-break。
            out[q] = (g[q] ?? []).sorted { a, b in
                if CalendarContract.byDate(a.task, b.task) { return true }
                if CalendarContract.byDate(b.task, a.task) { return false }
                return a.order < b.order
            }.map(\.task)
        }
        return out
    }

    static func openCount(_ list: [PlannerTask]) -> Int {
        list.filter { !$0.done }.count
    }

    /// `quadrantFlags(q)`：q ≤ 2 重要，q 为 1/3 紧急。
    static func flags(_ q: Int) -> (important: Bool, urgent: Bool) {
        (q <= 2, q == 1 || q == 3)
    }

    // MARK: 拖拽状态机（不依赖 SwiftUI，便于单测）

    struct DragState: Equatable, Sendable {
        var pressedID: String? = nil
        var draggingID: String? = nil
        var dropQ: Int = 0

        var isDragging: Bool { draggingID != nil }

        /// 340ms 长按到点：进入拖拽，清除按下态。
        mutating func longPressFired(id: String) {
            guard pressedID == id else { return }
            pressedID = nil
            draggingID = id
        }

        /// 位移超过 8pt 且还没开始拖拽：取消长按（QuadrantView.vue:onMove）。
        mutating func moved(distance: Double) {
            guard draggingID == nil, pressedID != nil,
                  distance > pressCancelDistance else { return }
            pressedID = nil
        }

        /// 落区变化时由 UI 触发 select 触感；返回是否变化。
        @discardableResult
        mutating func updateDrop(_ q: Int) -> Bool {
            let changed = q != dropQ
            dropQ = q
            return changed
        }

        /// 松手：返回 (任务 id, 落区)，并复位；调用方据此写回并弹撤销 toast。
        mutating func end() -> (id: String, q: Int)? {
            defer { pressedID = nil; draggingID = nil; dropQ = 0 }
            guard let id = draggingID else { return nil }
            return (id, dropQ)
        }
    }

    /// 是否需要真正写回：落到别的象限、且任务存在。
    static func shouldMove(_ t: PlannerTask?, to q: Int) -> Bool {
        guard let t, (1...4).contains(q) else { return false }
        return q != CalendarContract.quadrantOf(t)
    }

    /// 拖拽 ghost 的起手位置。
    ///
    /// 长按到点那一刻，`DragGesture` 往往还没回调过 location，所以不能拿手势坐标当起点，
    /// 更不能退回网格中心——那样卡片会在长按瞬间蹦到屏幕正中。行位置由调用方用
    /// `onGeometryChange` 记录；只有真的拿不到时（行还没布局完）才退回网格中心。
    static func ghostOrigin(rowFrame: CGRect?, grid: CGSize) -> CGPoint {
        if let rowFrame, rowFrame.width > 0, rowFrame.height > 0 {
            return CGPoint(x: rowFrame.midX, y: rowFrame.midY)
        }
        return CGPoint(x: grid.width / 2, y: grid.height / 2)
    }

    /// 「已移到「{name}」」的 name 是象限 name getter（中英动态）。
    static func movedText(_ q: Int, lang: String) -> String {
        let item = PanelCatalog.quadrants[q - 1]
        return FeatureStrings.t("已移到「{name}」", lang: lang,
                                ["name": AppStrings.t(item.nameKey, lang: lang)])
    }
}
