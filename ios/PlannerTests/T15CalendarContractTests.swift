import XCTest
import Foundation
@testable import Planner

// T-15 / M-10 契约测试。
// 期望值取自 baseline_commit 97a7c4c 的 CalendarView.vue / MonthGrid.vue / MonthPicker.vue
// 与 src/lib/date.js / repeat.js / quadrant.js（真实源码 oracle）。
// 全量逐字对比（2335 项）由独立 swiftc harness 执行：
//   node ios/PlannerTests/Fixtures/generate_calendar_view_fixtures.mjs
//   swiftc -O ios/Planner/Core/Models/{PlannerTask,LegacyMigration,RepeatNormalization}.swift \
//             ios/Planner/Core/Calendar/{PlannerCalendar,LunarData}.swift \
//             ios/Planner/Core/Repeat/RepeatEngine.swift \
//             ios/Planner/Features/Calendar/{CalendarContract,CalendarStrings}.swift \
//             ios/Planner/App/Skeleton/AppStrings.swift /tmp/t15_harness/main.swift \
//             -o /tmp/t15_harness/verify
//   /tmp/t15_harness/verify ios/PlannerTests/Fixtures/calendar_view_fixtures.json \
//                           ios/Planner/Resources/lunar-data.json

final class T15CalendarContractTests: XCTestCase {

    private let today = "2026-11-13"

    private func task(id: String, date: String, time: String = "", important: Bool = false,
                      urgent: Bool = false, done: Bool = false, dropped: Bool = false,
                      repeatRule: String = "") -> PlannerTask {
        PlannerTask(
            id: id, title: id, note: "", date: date, time: time,
            important: important, urgent: urgent, done: done, dropped: dropped,
            createdAt: 1_700_000_000_000, doneAt: done ? 1_700_000_100_000 : nil,
            repeatRule: repeatRule, doneDates: [], skipDates: [],
            remind: nil, parentId: "", updatedAt: 1_700_000_000_000
        )
    }

    // MARK: F-02.1 / F-02.4 几何与格子

    func testGeometryAndMonthGrid() {
        let g = CalendarContract.geom(today)
        XCTAssertEqual(g.year, 2026)
        XCTAssertEqual(g.month0, 10)
        XCTAssertEqual(g.rows, 6)
        XCTAssertEqual(g.row, 2)

        let grid = CalendarContract.monthGrid(year: 2026, month0: 10, today: today)
        XCTAssertEqual(grid.count, 6)
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })
        XCTAssertEqual(grid[0][0].key, "2026-10-26", "7 列周一起始、相邻月")
        XCTAssertTrue(grid[0][0].isOut)
        XCTAssertEqual(grid[2][4].key, today)
        XCTAssertTrue(grid[2][5].isWeekend)
        XCTAssertTrue(grid[2][6].isWeekend)
    }

    func testThreePaneTrackAndMonthWeekDisplacement() {
        let prev = CalendarContract.neighbour(selected: today, mode: .month, n: -1, today: today)
        let nextWeek = CalendarContract.neighbour(selected: today, mode: .week, n: 1, today: today)
        XCTAssertEqual(prev, "2026-10-01")
        XCTAssertEqual(nextWeek, "2026-11-20")

        let month = CalendarContract.panes(selected: today, mode: .month, today: today)
        let slots = CalendarContract.slots(month, mode: .month)
        XCTAssertEqual(slots.map(\.geometry.date), ["2026-10-01", today, "2026-12-01"])
        XCTAssertEqual(slots.map(\.n), [-1, 0, 1])

        let week = CalendarContract.panes(selected: today, mode: .week, today: today)
        let weekSlots = CalendarContract.slots(week, mode: .week)
        XCTAssertEqual(weekSlots.map(\.geometry.date), [today, "2026-11-20", "2026-11-06"])
        XCTAssertEqual(weekSlots.map(\.n), [0, 1, -1])

        XCTAssertEqual(CalendarContract.drop(rows: g_rows(), mode: .month), 270, "月视图下推 (rows-1)*54")
        XCTAssertEqual(CalendarContract.drop(rows: g_rows(), mode: .week), 0, "周视图不下推")
        XCTAssertEqual(CalendarContract.shiftOf(month[1], mode: .week), -108)
        XCTAssertEqual(CalendarContract.shiftOf(month[1], mode: .month), 0)
    }

    private func g_rows() -> Int { CalendarContract.geom(today).rows }

    func testTodayColumnAndWeekdayHeader() {
        XCTAssertEqual(CalendarContract.todayColumn(selected: today, mode: .month, today: today), 4)
        XCTAssertEqual(CalendarContract.todayColumn(selected: "2026-12-01", mode: .month, today: today), -1)
        XCTAssertEqual(CalendarContract.todayColumn(selected: "2026-11-09", mode: .week, today: today), 4)
        let zh = CalendarContract.weekdayColumnOrder.map {
            PlannerCalendar.weekdayName($0, short: true, isEnglish: false)
        }
        XCTAssertEqual(zh, ["一", "二", "三", "四", "五", "六", "日"])
        let en = CalendarContract.weekdayColumnOrder.map {
            PlannerCalendar.weekdayName($0, short: true, isEnglish: true)
        }
        XCTAssertEqual(en, ["M", "T", "W", "T", "F", "S", "S"])
    }

    func testSlideThreshold() {
        XCTAssertTrue(CalendarContract.shouldSlide(dx: 100, width: 390, velocity: 0))
        XCTAssertTrue(CalendarContract.shouldSlide(dx: 40, width: 390, velocity: 0.5))
        XCTAssertFalse(CalendarContract.shouldSlide(dx: 30, width: 390, velocity: 0.1))
    }

    // MARK: F-02.3 把手跟手收拢（iOS 交互适配，替代 Web 固定 35pt 竖滑阈值）

    func testCollapseFractionFollowsTranslation() {
        let full = CalendarContract.drop(rows: 6, mode: .month)   // 270
        XCTAssertEqual(CalendarContract.collapseFraction(mode: .month, translation: 0, fullDrop: full), 1)
        XCTAssertEqual(CalendarContract.collapseFraction(mode: .month, translation: -135, fullDrop: full), 0.5)
        XCTAssertEqual(CalendarContract.collapseFraction(mode: .month, translation: -400, fullDrop: full), 0, "夹在下界")
        XCTAssertEqual(CalendarContract.collapseFraction(mode: .week, translation: 90, fullDrop: full), 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(CalendarContract.collapseFraction(mode: .week, translation: 500, fullDrop: full), 1, "夹在上界")
        XCTAssertEqual(CalendarContract.collapseFraction(mode: .week, translation: -50, fullDrop: full), 0)
        XCTAssertEqual(CalendarContract.collapseFraction(mode: .week, translation: 10, fullDrop: 0), 0, "全程为 0 退回基准")
        XCTAssertEqual(CalendarContract.collapseFraction(mode: .month, translation: 10, fullDrop: 0), 1)
    }

    func testCollapseTargetUsesProjectedEnd() {
        let full = CalendarContract.drop(rows: 6, mode: .month)
        XCTAssertEqual(CalendarContract.collapseTarget(mode: .month, predictedTranslation: -200, fullDrop: full), .week)
        XCTAssertEqual(CalendarContract.collapseTarget(mode: .month, predictedTranslation: -100, fullDrop: full), .month, "未过半收回原模式")
        XCTAssertEqual(CalendarContract.collapseTarget(mode: .week, predictedTranslation: 140, fullDrop: full), .month)
        XCTAssertEqual(CalendarContract.collapseTarget(mode: .week, predictedTranslation: 20, fullDrop: full), .week)
        XCTAssertEqual(CalendarContract.collapseTarget(mode: .month, predictedTranslation: -135, fullDrop: full), .month, "恰好一半保持展开（>= 0.5）")
        XCTAssertEqual(CalendarContract.collapseTarget(mode: .month, predictedTranslation: -136, fullDrop: full), .week)
    }

    // MARK: F-02.5 / 标题区

    func testHeadingChineseAndEnglish() throws {
        guard let lunar = LunarData.bundled else {
            throw XCTSkip("lunar-data.json 未随 App target 打包")
        }
        let zh = CalendarContract.heading(selected: "2026-11-15", today: today, isEnglish: false, lunar: lunar)
        XCTAssertEqual(zh.title, "后天")
        XCTAssertEqual(zh.sub, "11月15日 · 周日 · 农历十月初七")

        let en = CalendarContract.heading(selected: today, today: today, isEnglish: true, lunar: lunar)
        XCTAssertEqual(en.title, "Today")
        XCTAssertEqual(en.sub, "Nov 13 · Fri · 农历十月初五", "农历名称在英文界面仍为中文（A-13）")
    }

    func testMonthPickerLabels() throws {
        guard let lunar = LunarData.bundled else {
            throw XCTSkip("lunar-data.json 未随 App target 打包")
        }
        XCTAssertEqual(lunar.lunarYearLabel(2026), "丙午马年")
        XCTAssertEqual(PlannerCalendar.monthName(0, isEnglish: true), "Jan")
        XCTAssertEqual(PlannerCalendar.monthName(0, isEnglish: false), "1月")
    }

    // MARK: F-03 列表 / 分组 / 进度

    func testDayTasksOverdueAndProgress() {
        let tasks = [
            task(id: "open", date: today, time: "09:00", important: true, urgent: true),
            task(id: "done", date: today, time: "08:00", done: true),
            task(id: "dropped", date: today, done: true, dropped: true),
            task(id: "late", date: "2026-11-10"),
            task(id: "repeat", date: "2026-11-01", repeatRule: "d1"),
        ]
        let instances = CalendarContract.dayTasks(tasks, selected: today)
        // byTime：未完成在前，有时间的在前，没时间的排后面。
        XCTAssertEqual(instances.map(\.task.id), ["open", "repeat", "done", "dropped"], "按 byTime 排序")
        XCTAssertEqual(instances.first { !$0.task.repeatRule.isEmpty }?.occ, today, "重复任务带 occ")

        XCTAssertEqual(CalendarContract.overdue(tasks, selected: today, today: today).map(\.id), ["late"])
        XCTAssertTrue(CalendarContract.overdue(tasks, selected: "2026-11-14", today: today).isEmpty,
                     "逾期分组仅今天显示")

        let p = CalendarContract.progress(instances)
        XCTAssertEqual(p.total, 3, "进度环排除 dropped")
        XCTAssertEqual(p.done, 1, "放弃的任务不算完成")
        let s = CalendarContract.doneSummary(instances)
        XCTAssertEqual(s.done, 1)
        XCTAssertEqual(s.dropped, 1)
    }

    func testDotsAtMostThreeAndGreyWhenAllDone() {
        let tasks = [
            task(id: "a", date: today, important: true, urgent: true),
            task(id: "b", date: today, important: true),
            task(id: "c", date: today, urgent: true),
            task(id: "d", date: today),
            task(id: "allDone", date: "2026-11-14", done: true),
        ]
        let panes = CalendarContract.panes(selected: today, mode: .month, today: today)
        let dots = CalendarContract.dots(tasks: tasks, panes: panes)
        XCTAssertEqual(dots[today]?.count, 3, "最多 3 个彩点")
        XCTAssertEqual(dots[today]?.first, .quadrant(1))
        XCTAssertEqual(dots["2026-11-14"], [.done], "全完成显示灰点")
    }

    // MARK: 中英词条 / 函数值词条

    func testStringsAndFunctionValuedEntries() {
        XCTAssertEqual(AppStrings.t("选择年月", lang: "en"), "Choose month")
        XCTAssertEqual(AppStrings.t("全部移到今天", lang: "en"), "Move all to today")
        XCTAssertEqual(AppStrings.t("今天还没有安排", lang: "zh"), "今天还没有安排")
        XCTAssertEqual(AppStrings.t("已过期 · {n}", lang: "en", ["n": "3"]), "Overdue · 3")

        XCTAssertEqual(CalendarStrings.postponed("Tomorrow", lang: "en"), "Postponed to tomorrow")
        XCTAssertEqual(CalendarStrings.postponed("2026-11-14", lang: "zh"), "已推迟到2026-11-14")
        XCTAssertEqual(CalendarStrings.movedAll(1, lang: "en"), "Moved 1 task to today")
        XCTAssertEqual(CalendarStrings.movedAll(3, lang: "en"), "Moved 3 tasks to today")
        XCTAssertEqual(CalendarStrings.deleted(title: "晨会", kids: 0, isRepeat: false, lang: "en"),
                       "Deleted “晨会”")
        XCTAssertEqual(CalendarStrings.deleted(title: "晨会", kids: 2, isRepeat: false, lang: "en"),
                       "Deleted “晨会” and 2 subtasks")
        XCTAssertEqual(CalendarStrings.deleted(title: "跑步", kids: 1, isRepeat: true, lang: "en"),
                       "Deleted “跑步”, future repeats and 1 subtask")
    }
}
