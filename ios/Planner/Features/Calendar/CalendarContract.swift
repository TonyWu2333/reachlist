import Foundation

// MARK: - M-10 日历与日程列表：事实层（T-15）
//
// 逐字对齐 baseline_commit 97a7c4c 的：
// · src/views/CalendarView.vue:geom / neighbour / panes / pageIndex / slots / drop / shiftOf /
//   dots / dayTasks / openTasks / doneTasks / overdue / heading / todayCol / ringTotal / ringDone / doneHead
// · src/components/MonthGrid.vue:rows
// · src/lib/quadrant.js:quadrantOf / byTime / byDate / isOverdue
// · src/lib/store.js:tasksOn / countsAsDone
//
// 纯 Foundation + M-01/M-03/M-06，不依赖 SwiftUI，可独立编译与跨端逐字对比。
// 呈现层按 §5.0 / OPEN-18 交给系统组件；本文件只负责"算什么"，不负责"长什么样"。

enum CalendarMode: String, CaseIterable, Sendable {
    case month, week
}

struct MonthGeometry: Equatable, Sendable {
    var date: String
    var year: Int
    var month0: Int          // 0-11
    var rows: Int            // 该月占几行
    var row: Int             // 选中日期在第几行
}

struct CalendarDayCell: Equatable, Sendable, Identifiable {
    var key: String
    var day: Int
    var isOut: Bool          // 相邻月份
    var isToday: Bool
    var isWeekend: Bool      // 周六/周日列
    var weekdayIndex: Int    // JS getDay()，0 = 周日
    var id: String { key }
}

struct CalendarPaneSlot: Equatable, Sendable {
    var geometry: MonthGeometry
    var n: Int               // -1 / 0 / +1，相对当前页
}

enum CalendarDot: Equatable, Sendable {
    case quadrant(Int)
    case done
}

struct CalendarHeading: Equatable, Sendable {
    var title: String
    var sub: String
}

enum CalendarContract {

    // MARK: 常量（CalendarView.vue:27, 96, 199；MonthGrid.vue:69-70）

    static let rowHeight: Double = 54          // showLunar = true
    static let rowHeightCompact: Double = 46   // showLunar = false
    static let slideMilliseconds = 340
    static let horizontalThresholdRatio = 0.22
    static let velocityThreshold = 0.4
    static let velocityMinDistance = 30.0
    static let agendaCollapseDistance = 40.0
    static let agendaExpandDistance = 60.0
    /// 表头星期顺序：周一 … 周日（JS `[1,2,3,4,5,6,0]`）
    static let weekdayColumnOrder = [1, 2, 3, 4, 5, 6, 0]

    private static func pad(_ n: Int) -> String { PlannerCalendar.pad(n) }
    private static func comp(_ d: Date, _ c: PlannerCalendar.Component) -> Int {
        PlannerCalendar.component(d, c)
    }
    private static func daysInMonth(year: Int, month0: Int) -> Int {
        let first = PlannerCalendar.parseYmd("\(year)-\(pad(month0 + 1))-01")
        return PlannerCalendar.calendar.range(of: .day, in: .month, for: first)?.count ?? 30
    }
    static func monthFirstDay(_ year: Int, _ month0: Int) -> String {
        "\(year)-\(pad(month0 + 1))-01"
    }

    // MARK: 月/周几何（CalendarView.vue:28-40）

    static func geom(_ date: String) -> MonthGeometry {
        let d = PlannerCalendar.parseYmd(date)
        let y = comp(d, .year), m0 = comp(d, .month) - 1
        let first = monthFirstDay(y, m0)
        let offset = (PlannerCalendar.weekdayIndex(first) + 6) % 7
        let days = daysInMonth(year: y, month0: m0)
        return MonthGeometry(
            date: date, year: y, month0: m0,
            rows: (offset + days + 6) / 7,
            row: (offset + comp(d, .day) - 1) / 7
        )
    }

    /// MonthGrid.vue:rows —— 7 列、周一起始、相邻月、今天、周末。
    static func monthGrid(year: Int, month0: Int, today: String) -> [[CalendarDayCell]] {
        let first = monthFirstDay(year, month0)
        let offset = (PlannerCalendar.weekdayIndex(first) + 6) % 7
        let days = daysInMonth(year: year, month0: month0)
        let count = (offset + days + 6) / 7
        var out: [[CalendarDayCell]] = []
        for r in 0..<count {
            var row: [CalendarDayCell] = []
            for c in 0..<7 {
                // MonthGrid.vue:26 用 new Date(year, month0, 1-offset+r*7+c)：
                // 该月第 D 天 = 1 号 + (D-1) 天，因此相对 first 的偏移是 -offset+r*7+c。
                let key = PlannerCalendar.addDays(first, -offset + r * 7 + c)
                let d = PlannerCalendar.parseYmd(key)
                row.append(CalendarDayCell(
                    key: key, day: comp(d, .day),
                    isOut: comp(d, .month) - 1 != month0,
                    isToday: key == today,
                    isWeekend: c >= 5,
                    weekdayIndex: PlannerCalendar.weekdayIndex(key)
                ))
            }
            out.append(row)
        }
        return out
    }

    // MARK: 三页轨道（CalendarView.vue:41-63, 118-137）

    static func neighbour(selected: String, mode: CalendarMode, n: Int, today: String) -> String {
        if mode == .week { return PlannerCalendar.addDays(selected, 7 * n) }
        let d = PlannerCalendar.parseYmd(selected)
        let first = monthFirstDay(comp(d, .year), comp(d, .month) - 1)
        let shifted = PlannerCalendar.calendar.date(byAdding: .month, value: n, to: PlannerCalendar.parseYmd(first)) ?? PlannerCalendar.parseYmd(first)
        let key = "\(comp(shifted, .year))-\(pad(comp(shifted, .month)))-01"
        return today.hasPrefix(String(key.prefix(7))) ? today : key
    }

    static func panes(selected: String, mode: CalendarMode, today: String, override: (n: Int, date: String)? = nil) -> [MonthGeometry] {
        (-1...1).map { n in
            let date: String
            if n == 0 { date = selected }
            else if let o = override, o.n == n { date = o.date }
            else { date = neighbour(selected: selected, mode: mode, n: n, today: today) }
            return geom(date)
        }
    }

    /// week 模式以 2000-01-03（周一）为第 0 周；month 模式用 year*12+month0。
    static func pageIndex(_ p: MonthGeometry, mode: CalendarMode) -> Int {
        if mode == .week {
            let diff = PlannerCalendar.diffDays(PlannerCalendar.mondayOf(p.date), "2000-01-03")
            return Int((Double(diff) / 7.0).rounded(.down))
        }
        return p.year * 12 + p.month0
    }

    static func slots(_ panes: [MonthGeometry], mode: CalendarMode) -> [CalendarPaneSlot] {
        var out = [CalendarPaneSlot?](repeating: nil, count: 3)
        for (i, p) in panes.enumerated() {
            let idx = ((pageIndex(p, mode: mode) % 3) + 3) % 3
            out[idx] = CalendarPaneSlot(geometry: p, n: i - 1)
        }
        return out.compactMap { $0 }
    }

    /// 月/周切换只做位移不改高度：月视图把列表整体下推 (rows-1)*rowH。
    static func drop(rows: Int, rowHeight: Double = rowHeight, mode: CalendarMode) -> Double {
        mode == .month ? Double(rows - 1) * rowHeight : 0
    }

    static func shiftOf(_ p: MonthGeometry, mode: CalendarMode, rowHeight: Double = rowHeight) -> Double {
        mode == .month ? 0 : -Double(p.row) * rowHeight
    }

    /// 把手 / 网格竖拖的跟手收拢进度：0 = 周视图，1 = 月视图。
    /// 以当前模式为基准叠加位移占全程 (rows-1)*rowH 的比例，夹在 0…1。
    static func collapseFraction(mode: CalendarMode, translation: Double, fullDrop: Double) -> Double {
        let base = mode == .month ? 1.0 : 0.0
        guard fullDrop > 0 else { return base }
        return min(1, max(0, base + translation / fullDrop))
    }

    /// 松手落点：用预测终点（含惯性）投影，过半展开收在月视图，否则收在周视图。
    static func collapseTarget(mode: CalendarMode, predictedTranslation: Double, fullDrop: Double) -> CalendarMode {
        collapseFraction(mode: mode, translation: predictedTranslation, fullDrop: fullDrop) >= 0.5 ? .month : .week
    }

    /// 跟手翻页判定：超视宽 22%，或速度 > 0.4 且位移 > 30。
    static func shouldSlide(dx: Double, width: Double, velocity: Double) -> Bool {
        abs(dx) > width * horizontalThresholdRatio
            || (velocity > velocityThreshold && abs(dx) > velocityMinDistance)
    }

    // MARK: 象限彩点（CalendarView.vue:66-88）

    static func dots(tasks: [PlannerTask], panes: [MonthGeometry]) -> [String: [CalendarDot]] {
        var days = Set<String>()
        for p in panes {
            let start = PlannerCalendar.mondayOf(monthFirstDay(p.year, p.month0))
            for i in 0..<42 { days.insert(PlannerCalendar.addDays(start, i)) }
        }
        var byDay: [String: [PlannerTask]] = [:]
        for t in tasks {
            if !t.repeatRule.isEmpty {
                for d in days where RepeatEngine.occursOn(t, d) {
                    var inst = t
                    inst.done = t.doneDates.contains(d)
                    byDay[d, default: []].append(inst)
                }
            } else if !t.date.isEmpty {
                byDay[t.date, default: []].append(t)
            }
        }
        var result: [String: [CalendarDot]] = [:]
        for (d, list) in byDay {
            let open = list.filter { !$0.done }.map(quadrantOf).sorted()
            result[d] = open.isEmpty ? [.done] : open.prefix(3).map { .quadrant($0) }
        }
        return result
    }

    // MARK: 标题 / 今天列（CalendarView.vue:238-254）

    static func heading(selected: String, today: String, isEnglish: Bool, lunar: LunarData?) -> CalendarHeading {
        let rel = PlannerCalendar.dateLabel(selected, today: today, isEnglish: isEnglish)
        let d = PlannerCalendar.parseYmd(selected)
        let md = PlannerCalendar.monthDay(d, isEnglish: isEnglish)
        let n = PlannerCalendar.diffDays(selected, today)
        let isRel = n >= -1 && n <= (isEnglish ? 1 : 2)
        let weekday = PlannerCalendar.weekdayName(PlannerCalendar.weekdayIndex(selected), isEnglish: isEnglish)
        let full = lunar?.dayInfo(selected)?.full ?? ""
        let parts = [isRel ? md : nil, weekday, full.isEmpty ? nil : full].compactMap { $0 }
        return CalendarHeading(title: isRel ? rel : md, sub: parts.joined(separator: " · "))
    }

    static func todayColumn(selected: String, mode: CalendarMode, today: String) -> Int {
        let visible = mode == .week
            ? PlannerCalendar.mondayOf(today) == PlannerCalendar.mondayOf(selected)
            : String(today.prefix(7)) == String(selected.prefix(7))
        return visible ? (PlannerCalendar.weekdayIndex(today) + 6) % 7 : -1
    }

    // MARK: 象限 / 排序（quadrant.js）

    static func quadrantOf(_ t: PlannerTask) -> Int {
        t.important ? (t.urgent ? 1 : 2) : (t.urgent ? 3 : 4)
    }

    static func countsAsDone(_ t: PlannerTask) -> Bool { t.done && !t.dropped }

    static func isOverdue(_ t: PlannerTask, today: String) -> Bool {
        t.repeatRule.isEmpty && !t.done && !t.date.isEmpty && t.date < today
    }

    static func byTime(_ a: PlannerTask, _ b: PlannerTask) -> Bool {
        if a.done != b.done { return !a.done }
        if a.time != b.time {
            if a.time.isEmpty { return false }
            if b.time.isEmpty { return true }
            return a.time < b.time
        }
        let qa = quadrantOf(a), qb = quadrantOf(b)
        return qa == qb ? a.createdAt < b.createdAt : qa < qb
    }

    static func byDate(_ a: PlannerTask, _ b: PlannerTask) -> Bool {
        if a.done != b.done { return !a.done }
        if a.date != b.date {
            if a.date.isEmpty { return false }
            if b.date.isEmpty { return true }
            return a.date < b.date
        }
        return byTime(a, b)
    }

    // MARK: 当天任务 / 逾期 / 进度（CalendarView.vue:229-263）

    static func dayTasks(_ tasks: [PlannerTask], selected: String) -> [RepeatInstance] {
        RepeatEngine.tasksOn(tasks, day: selected).sorted {
            CalendarContract.byTime($0.task, $1.task)
        }
    }

    static func overdue(_ tasks: [PlannerTask], selected: String, today: String) -> [PlannerTask] {
        guard selected == today else { return [] }
        return tasks.filter { isOverdue($0, today: today) }.sorted(by: byDate)
    }

    struct Progress: Equatable, Sendable {
        var done: Int
        var total: Int
        var ratio: Double { total == 0 ? 0 : Double(done) / Double(total) }
    }

    /// 进度环排除 dropped；放弃的任务不算完成。
    static func progress(_ instances: [RepeatInstance]) -> Progress {
        let total = instances.filter { !$0.task.dropped }.count
        let done = instances.filter { countsAsDone($0.task) }.count
        return Progress(done: done, total: total)
    }

    /// 分组头「已完成 N · 已放弃 M」，为 0 的项不写。
    static func doneSummary(_ instances: [RepeatInstance]) -> (done: Int, dropped: Int) {
        let doneTasks = instances.filter { $0.task.done }
        let counted = doneTasks.filter { countsAsDone($0.task) }.count
        return (counted, doneTasks.count - counted)
    }

    static func split(_ instances: [RepeatInstance]) -> (open: [RepeatInstance], done: [RepeatInstance]) {
        (instances.filter { !$0.task.done }, instances.filter { $0.task.done })
    }

    static func childrenOf(_ id: String, _ tasks: [PlannerTask]) -> [PlannerTask] {
        tasks.filter { $0.parentId == id }.sorted { $0.createdAt < $1.createdAt }
    }
}
