import XCTest
@testable import Planner

// T-14 契约黄金测试：M-19 TaskRow + M-15 五个属性面板。
// 期望值取自 baseline_commit 97a7c4c 的 TaskRow.vue / TaskDetail.vue / 五个 *Panel.vue /
// repeat.js / date.js / notify.js / quadrant.js，跨端由 /tmp/planner_t14_oracle.mjs 对齐。

@MainActor
final class T14TaskRowPanelTests: XCTestCase {

    private let today = "2026-11-13" // 周五

    // MARK: 重复规则（repeat.js）

    func testParseRule() {
        XCTAssertEqual(RepeatRule.parse("d1"), RepeatRule.Rule(freq: "d", n: 1, days: [], until: ""))
        XCTAssertEqual(RepeatRule.parse("w2:531")?.days, [1, 3, 5], "去重并升序")
        XCTAssertEqual(RepeatRule.parse("m1~2026-12-31")?.until, "2026-12-31")
        XCTAssertNil(RepeatRule.parse(""), "空串")
        XCTAssertNil(RepeatRule.parse("w1"), "周规则必须有星期")
        XCTAssertNil(RepeatRule.parse("x1"), "未知频率")
        XCTAssertNil(RepeatRule.parse("d1000"), "超过 3 位")
        XCTAssertEqual(RepeatRule.parse("d99")?.n, 99)
        XCTAssertEqual(RepeatRule.parse("d0")?.n, 1, "n 至少为 1")
    }

    func testFormatRule() {
        XCTAssertEqual(RepeatRule.format(.init(freq: "w", n: 2, days: [5, 1, 1], until: "2026-12-31")), "w2:15~2026-12-31")
        XCTAssertEqual(RepeatRule.format(.init(freq: "d", n: 1, days: [3], until: "")), "d1", "非周规则忽略 days")
        XCTAssertEqual(RepeatRule.format(.init(freq: "m", n: 0, days: [], until: "")), "m1", "n 下限")
    }

    func testNormalizeLegacy() {
        XCTAssertEqual(RepeatRule.normalizeLegacy("daily", date: today), "d1")
        XCTAssertEqual(RepeatRule.normalizeLegacy("weekdays", date: today), "w1:12345")
        XCTAssertEqual(RepeatRule.normalizeLegacy("monthly", date: today), "m1")
        XCTAssertEqual(RepeatRule.normalizeLegacy("weekly", date: "2026-11-13"), "w1:5", "weekly 取开始日期的星期")
        XCTAssertEqual(RepeatRule.normalizeLegacy("bogus", date: today), "")
    }

    func testRepeatLabelChinese() {
        XCTAssertEqual(RepeatRule.label("d1", date: today, isEnglish: false), "每天")
        XCTAssertEqual(RepeatRule.label("d3", date: today, isEnglish: false), "每3天")
        XCTAssertEqual(RepeatRule.label("w1:12345", date: today, isEnglish: false), "工作日")
        XCTAssertEqual(RepeatRule.label("w1:06", date: today, isEnglish: false), "每周末")
        XCTAssertEqual(RepeatRule.label("w1:135", date: today, isEnglish: false), "每周一、三、五")
        XCTAssertEqual(RepeatRule.label("w2:5", date: today, isEnglish: false), "每2周的周五")
        XCTAssertEqual(RepeatRule.label("m1", date: today, isEnglish: false), "每月13日")
        XCTAssertEqual(RepeatRule.label("m2", date: today, isEnglish: false), "每2个月的13日")
        XCTAssertEqual(RepeatRule.label("y1", date: today, isEnglish: false), "每年11月13日")
        XCTAssertEqual(
            RepeatRule.label("d1~2026-12-31", date: today, isEnglish: false, withUntil: true),
            "每天，到12月31日"
        )
    }

    func testRepeatLabelEnglish() {
        XCTAssertEqual(RepeatRule.label("d1", date: today, isEnglish: true), "Daily")
        XCTAssertEqual(RepeatRule.label("d3", date: today, isEnglish: true), "Every 3 days")
        XCTAssertEqual(RepeatRule.label("w1:12345", date: today, isEnglish: true), "Weekdays")
        XCTAssertEqual(RepeatRule.label("w1:06", date: today, isEnglish: true), "Weekends")
        XCTAssertEqual(RepeatRule.label("w1:135", date: today, isEnglish: true), "Every Mon, Wed, Fri")
        XCTAssertEqual(RepeatRule.label("w2:5", date: today, isEnglish: true), "Every 2 weeks on Fri")
        XCTAssertEqual(RepeatRule.label("m1", date: today, isEnglish: true), "Monthly on the 13th")
        XCTAssertEqual(RepeatRule.label("m2", date: today, isEnglish: true), "Every 2 months on the 13th")
        XCTAssertEqual(RepeatRule.label("y1", date: today, isEnglish: true), "Yearly on Nov 13")
        XCTAssertEqual(
            RepeatRule.label("d1~2026-12-31", date: today, isEnglish: true, withUntil: true),
            "Daily, until Dec 31"
        )
    }

    func testOrdinal() {
        XCTAssertEqual(DateText.ordinal(1), "1st")
        XCTAssertEqual(DateText.ordinal(2), "2nd")
        XCTAssertEqual(DateText.ordinal(3), "3rd")
        XCTAssertEqual(DateText.ordinal(4), "4th")
        XCTAssertEqual(DateText.ordinal(11), "11th")
        XCTAssertEqual(DateText.ordinal(12), "12th")
        XCTAssertEqual(DateText.ordinal(13), "13th")
        XCTAssertEqual(DateText.ordinal(21), "21st")
        XCTAssertEqual(DateText.ordinal(31), "31st")
    }

    // MARK: 日期文案（date.js:dateLabel）

    func testDateLabelChinese() {
        XCTAssertEqual(DateText.label("2026-11-13", today: today, isEnglish: false), "今天")
        XCTAssertEqual(DateText.label("2026-11-14", today: today, isEnglish: false), "明天")
        XCTAssertEqual(DateText.label("2026-11-15", today: today, isEnglish: false), "后天")
        XCTAssertEqual(DateText.label("2026-11-12", today: today, isEnglish: false), "昨天")
        XCTAssertEqual(DateText.label("2026-11-16", today: today, isEnglish: false), "下周一")
        XCTAssertEqual(DateText.label("2026-11-17", today: today, isEnglish: false), "下周二")
        XCTAssertEqual(DateText.label("2026-12-01", today: today, isEnglish: false), "12月1日")
        XCTAssertEqual(DateText.label("2027-01-05", today: today, isEnglish: false), "2027年1月5日")
    }

    func testDateLabelEnglish() {
        XCTAssertEqual(DateText.label("2026-11-13", today: today, isEnglish: true), "Today")
        XCTAssertEqual(DateText.label("2026-11-14", today: today, isEnglish: true), "Tomorrow")
        XCTAssertEqual(DateText.label("2026-11-12", today: today, isEnglish: true), "Yesterday")
        XCTAssertEqual(DateText.label("2026-11-16", today: today, isEnglish: true), "Next Mon")
        XCTAssertEqual(DateText.label("2026-11-15", today: today, isEnglish: true), "Sun", "英文 n=2 走星期分支")
        XCTAssertEqual(DateText.label("2026-12-01", today: today, isEnglish: true), "Dec 1")
        XCTAssertEqual(DateText.label("2027-01-05", today: today, isEnglish: true), "Jan 5, 2027")
    }

    func testDateHelpers() {
        XCTAssertEqual(DateText.addDays("2026-11-13", 1), "2026-11-14")
        XCTAssertEqual(DateText.addDays("2026-11-30", 1), "2026-12-01", "跨月")
        XCTAssertEqual(DateText.diffDays("2026-11-16", "2026-11-13"), 3)
        XCTAssertEqual(DateText.mondayOf("2026-11-13"), "2026-11-09")
        XCTAssertEqual(DateText.weekdayIndex("2026-11-13"), 5, "周五")
        XCTAssertEqual(DateText.weekdayName(5, short: true, isEnglish: false), "五")
        XCTAssertEqual(DateText.weekdayName(5, short: false, isEnglish: true), "Fri")
        XCTAssertEqual(DateText.pad(7), "07")
    }

    func testIsOverdueOnlyForNonRepeating() {
        XCTAssertTrue(DateText.isOverdue(date: "2026-11-12", repeatRule: "", done: false, today: today))
        XCTAssertFalse(DateText.isOverdue(date: "2026-11-12", repeatRule: "d1", done: false, today: today))
        XCTAssertFalse(DateText.isOverdue(date: "2026-11-12", repeatRule: "", done: true, today: today))
        XCTAssertFalse(DateText.isOverdue(date: today, repeatRule: "", done: false, today: today))
    }

    // MARK: 面板选项（五个 *Panel.vue / notify.js / quadrant.js）

    func testRemindCatalog() {
        XCTAssertEqual(PanelCatalog.remindOptions, [0, 5, 15, 30, 60])
        XCTAssertEqual(PanelCatalog.remindLabel(nil, isEnglish: false), "不提醒")
        XCTAssertEqual(PanelCatalog.remindLabel(0, isEnglish: false), "准时")
        XCTAssertEqual(PanelCatalog.remindLabel(5, isEnglish: false), "提前 5 分钟")
        XCTAssertEqual(PanelCatalog.remindLabel(60, isEnglish: false), "提前 1 小时")
        XCTAssertEqual(PanelCatalog.remindLabel(5, isEnglish: true), "5 minutes before")
        XCTAssertEqual(PanelCatalog.remindLabel(60, isEnglish: true), "1 hour before")
        XCTAssertEqual(PanelCatalog.remindShort(0, isEnglish: false), "准时")
        XCTAssertEqual(PanelCatalog.remindShort(15, isEnglish: false), "15 分钟前")
        XCTAssertEqual(PanelCatalog.remindShort(60, isEnglish: false), "1 小时前")
        XCTAssertEqual(PanelCatalog.remindShort(15, isEnglish: true), "15 min before", "英文短文案固定 min")
        XCTAssertEqual(PanelCatalog.remindShort(60, isEnglish: true), "1 hr before")
    }

    func testQuadrantCatalog() {
        XCTAssertEqual(PanelCatalog.quadrants.map(\.index), [1, 2, 3, 4])
        XCTAssertEqual(PanelCatalog.quadrants.map(\.colorToken), ["--q1", "--q2", "--q3", "--q4"])
        XCTAssertEqual(PanelCatalog.quadrantOf(important: true, urgent: true), 1)
        XCTAssertEqual(PanelCatalog.quadrantOf(important: true, urgent: false), 2)
        XCTAssertEqual(PanelCatalog.quadrantOf(important: false, urgent: true), 3)
        XCTAssertEqual(PanelCatalog.quadrantOf(important: false, urgent: false), 4)
        XCTAssertEqual(AppStrings.t("重要且紧急", lang: "en"), "Important & urgent")
        XCTAssertEqual(AppStrings.t("立即处理", lang: "en"), "Do it now")
        XCTAssertEqual(AppStrings.t("有空再做", lang: "en"), "When free")
    }

    func testDateQuickValues() {
        XCTAssertEqual(PanelCatalog.dateQuickValue(.today, today: today), "2026-11-13")
        XCTAssertEqual(PanelCatalog.dateQuickValue(.tomorrow, today: today), "2026-11-14")
        XCTAssertEqual(PanelCatalog.dateQuickValue(.nextMonday, today: today), "2026-11-16")
        XCTAssertEqual(PanelCatalog.dateQuickValue(.none, today: today), "")
    }

    func testTimePresets() {
        XCTAssertEqual(PanelCatalog.timePresets.count, 10)
        XCTAssertEqual(PanelCatalog.timePresets.first, "08:00")
        XCTAssertEqual(PanelCatalog.timePresets.last, "22:00")
    }

    func testRepeatPresetsAndEndOptions() {
        XCTAssertEqual(PanelCatalog.repeatPresets(date: today), ["d1", "w1:12345", "w1:5", "m1", "y1"])
        XCTAssertEqual(PanelCatalog.repeatPresetLabel("m1", date: today, isEnglish: true), "Monthly", "英文格子只写 Monthly")
        XCTAssertEqual(PanelCatalog.repeatPresetLabel("y1", date: today, isEnglish: true), "Yearly")
        XCTAssertEqual(PanelCatalog.repeatPresetLabel("d1", date: today, isEnglish: true), "Daily")
        XCTAssertEqual(PanelCatalog.repeatPresetLabel("m1", date: today, isEnglish: false), "每月13日")
        XCTAssertEqual(PanelCatalog.endOptionValue(.never, startDate: today, today: today), "")
        XCTAssertEqual(PanelCatalog.endOptionValue(.month1, startDate: today, today: today), "2026-12-13")
        XCTAssertEqual(PanelCatalog.endOptionValue(.month3, startDate: today, today: today), "2027-02-12")
        XCTAssertEqual(PanelCatalog.endOptionValue(.yearEnd, startDate: today, today: today), "2026-12-31")
        XCTAssertEqual(PanelCatalog.clampUntil("2026-11-10", startDate: today), today)
        XCTAssertEqual(PanelCatalog.clampUntil("2026-12-01", startDate: today), "2026-12-01")
    }

    func testRepeatCustomEditing() {
        XCTAssertEqual(PanelCatalog.steppedCount(99, delta: 1), 99)
        XCTAssertEqual(PanelCatalog.steppedCount(1, delta: -1), 1)
        XCTAssertEqual(PanelCatalog.steppedCount(3, delta: 1), 4)
        XCTAssertEqual(PanelCatalog.toggledDays([1, 3], 3), [1])
        XCTAssertEqual(PanelCatalog.toggledDays([1], 1), [1], "至少留一天")
        XCTAssertEqual(PanelCatalog.toggledDays([3, 1], 5), [1, 3, 5])
        XCTAssertEqual(PanelCatalog.daysWhenSwitching(freq: "w", current: [], dow: 5), [5])
        XCTAssertEqual(PanelCatalog.daysWhenSwitching(freq: "d", current: [1, 3], dow: 5), [], "非周规则清空星期")
        XCTAssertEqual(PanelCatalog.repeatSummary("", date: today, isEnglish: false), "不重复")
        XCTAssertEqual(PanelCatalog.repeatSummary("m1", date: today, isEnglish: false), "每月13日")
        XCTAssertEqual(PanelCatalog.repeatSummary("m1", date: today, isEnglish: true), "Monthly on the 13th")
    }

    // MARK: 面板联动（TaskDetail.vue:setDate / setTime / setRepeat / openRemind）

    func testClearDateAlsoClearsTimeAndRepeat() {
        let patch = PanelLinkage.setDate("")
        XCTAssertEqual(patch.cleared, ["date", "time", "repeat"])
        XCTAssertTrue(patch.values.isEmpty)

        let set = PanelLinkage.setDate("2026-11-20")
        XCTAssertEqual(set.values, ["date": "2026-11-20"])
        XCTAssertTrue(set.cleared.isEmpty)
    }

    func testSetTimeFillsDateAndDefaultRemind() {
        let first = PanelLinkage.setTime(
            "18:00", taskDate: "", taskTime: "", remind: nil, defaultRemind: 15, today: today
        )
        XCTAssertEqual(first.values["time"], "18:00")
        XCTAssertEqual(first.values["date"], today, "没日期补今天")
        XCTAssertEqual(first.values["remind"], "15", "首次设时间补 defaultRemind")

        let second = PanelLinkage.setTime(
            "19:00", taskDate: "2026-11-20", taskTime: "18:00", remind: 5, defaultRemind: 15, today: today
        )
        XCTAssertEqual(second.values["time"], "19:00")
        XCTAssertNil(second.values["date"], "已有日期不覆盖")
        XCTAssertNil(second.values["remind"], "已有提醒不改")

        let cleared = PanelLinkage.setTime(
            "", taskDate: "2026-11-20", taskTime: "18:00", remind: 5, defaultRemind: 15, today: today
        )
        XCTAssertEqual(cleared.values["time"], "")
        XCTAssertNil(cleared.values["remind"], "清时间不动提醒（与上游一致）")
        XCTAssertNil(cleared.values["date"])
    }

    func testSetRepeatFillsDate() {
        let patch = PanelLinkage.setRepeat("d1", taskDate: "", today: today)
        XCTAssertEqual(patch.values["repeat"], "d1")
        XCTAssertEqual(patch.values["date"], today)

        let existing = PanelLinkage.setRepeat("d1", taskDate: "2026-11-20", today: today)
        XCTAssertNil(existing.values["date"])
        XCTAssertEqual(existing.values["repeat"], "d1")
    }

    func testOpenRemindRedirectsToTimeWhenNoTime() {
        XCTAssertEqual(PanelLinkage.panelToOpen(.remind, hasTime: false), .time)
        XCTAssertEqual(PanelLinkage.panelToOpen(.remind, hasTime: true), .remind)
        XCTAssertEqual(PanelLinkage.panelToOpen(.date, hasTime: false), .date)
    }

    func testSetQuadrantFlags() {
        XCTAssertEqual(PanelLinkage.setQuadrant(1).important, true)
        XCTAssertEqual(PanelLinkage.setQuadrant(1).urgent, true)
        XCTAssertEqual(PanelLinkage.setQuadrant(2).important, true)
        XCTAssertEqual(PanelLinkage.setQuadrant(2).urgent, false)
        XCTAssertEqual(PanelLinkage.setQuadrant(3).important, false)
        XCTAssertEqual(PanelLinkage.setQuadrant(3).urgent, true)
        XCTAssertEqual(PanelLinkage.setQuadrant(4).important, false)
        XCTAssertEqual(PanelLinkage.setQuadrant(4).urgent, false)
    }

    func testPatchApply() {
        var task = TaskRowGallery.task(id: "x", title: "t", date: "2026-11-20", time: "18:00", repeatRule: "d1", remind: 15)
        task = PanelLinkage.setDate("").apply(to: task)
        XCTAssertEqual(task.date, "")
        XCTAssertEqual(task.time, "")
        XCTAssertEqual(task.repeatRule, "")
        XCTAssertEqual(task.remind, 15, "清日期不清提醒（上游同样不处理 remind）")
    }

    // MARK: TaskRow（TaskRow.vue）

    func testCanDropAndActionWidth() {
        XCTAssertTrue(TaskRowContract.canDrop(postpone: true, repeatRule: "", done: false))
        XCTAssertFalse(TaskRowContract.canDrop(postpone: true, repeatRule: "d1", done: false), "重复任务用跳过")
        XCTAssertFalse(TaskRowContract.canDrop(postpone: true, repeatRule: "", done: true), "已完成没有放弃")
        XCTAssertFalse(TaskRowContract.canDrop(postpone: false, repeatRule: "", done: false), "子任务列表只留删除")

        XCTAssertEqual(TaskRowContract.actionCount(postpone: true, canDrop: true), 3)
        XCTAssertEqual(TaskRowContract.actionCount(postpone: true, canDrop: false), 2)
        XCTAssertEqual(TaskRowContract.actionCount(postpone: false, canDrop: false), 1)
        XCTAssertEqual(TaskRowContract.actionsWidth(postpone: true, canDrop: true), 208, "3×64 + 2×8")
        XCTAssertEqual(TaskRowContract.actionsWidth(postpone: false, canDrop: false), 64)
    }

    func testSwipeGeometry() {
        XCTAssertEqual(TaskRowContract.rubber(100, limit: 110), 100)
        XCTAssertEqual(TaskRowContract.rubber(120, limit: 110), 112.5, "超出部分 1/4 阻尼")
        XCTAssertEqual(TaskRowContract.offset(base: 0, translation: 100, actionsWidth: 208), 100)
        XCTAssertEqual(TaskRowContract.offset(base: 0, translation: -300, actionsWidth: 208), -231)
        XCTAssertFalse(TaskRowContract.isPastCompleteThreshold(76), "必须大于 76")
        XCTAssertTrue(TaskRowContract.isPastCompleteThreshold(76.1))
        XCTAssertTrue(TaskRowContract.shouldSnapOpen(-100, actionsWidth: 208), "超过 actionsW/2.4 才吸附")
        XCTAssertFalse(TaskRowContract.shouldSnapOpen(-50, actionsWidth: 208))
    }

    func testPostponeActionLabelDependsOnRepeat() {
        XCTAssertEqual(TaskRowContract.postponeAction(repeatRule: "").key, "推迟")
        XCTAssertEqual(TaskRowContract.postponeAction(repeatRule: "d1").key, "跳过")
        XCTAssertEqual(TaskRowContract.postponeAction(repeatRule: "d1").icon, "skip")
    }

    func testMetaFlags() {
        let none = TaskRowContract.metaFlags(
            showDate: false, compact: false, hideRepeat: false, hideParent: false,
            date: "", time: "", note: "", repeatRule: "", streak: 0, subTotal: 0,
            parentTitle: "", dropped: false
        )
        XCTAssertFalse(none.any)

        let full = TaskRowContract.metaFlags(
            showDate: true, compact: false, hideRepeat: false, hideParent: false,
            date: today, time: "", note: "n", repeatRule: "d1", streak: 2, subTotal: 3,
            parentTitle: "p", dropped: true
        )
        XCTAssertTrue(full.any)
        XCTAssertTrue(full.dropped && full.date && full.streak && full.repeatRule)
        XCTAssertTrue(full.subProgress && full.note && full.parent)
        XCTAssertFalse(full.compactTime, "非 compact 不显示 meta 里的时间")

        let compact = TaskRowContract.metaFlags(
            showDate: false, compact: true, hideRepeat: true, hideParent: true,
            date: today, time: "18:00", note: "", repeatRule: "d1", streak: 0, subTotal: 0,
            parentTitle: "p", dropped: false
        )
        XCTAssertTrue(compact.compactTime)
        XCTAssertFalse(compact.date, "showDate=false 不显示日期")
        XCTAssertFalse(compact.repeatRule, "hideRepeat")
        XCTAssertFalse(compact.parent, "hideParent")
    }

    func testVisualDoneAndToggleState() {
        XCTAssertTrue(TaskRowContract.visualDone(taskDone: false, pending: true))
        XCTAssertFalse(TaskRowContract.visualDone(taskDone: true, pending: true))
        XCTAssertTrue(TaskRowContract.visualDone(taskDone: true, pending: false))
        XCTAssertEqual(TaskRowContract.toggleDelayMilliseconds, 380)
        XCTAssertEqual(TaskRowContract.guardMilliseconds, 250)

        var state = TaskRowContract.ToggleState()
        XCTAssertTrue(state.begin())
        XCTAssertFalse(state.begin(), "pending 期间不可重复触发")
        state.finish()
        XCTAssertTrue(state.begin(), "结束后可再次触发")
    }

    func testStreakText() {
        XCTAssertEqual(TaskRowFormattingDefault.streak(3, unit: "天", isEnglish: false), "连续 3 天")
        XCTAssertEqual(TaskRowFormattingDefault.streak(3, unit: "天", isEnglish: true), "3-day streak")
        XCTAssertEqual(TaskRowFormattingDefault.streak(2, unit: "周", isEnglish: true), "2-week streak")
        XCTAssertEqual(TaskRowFormattingDefault.streak(2, unit: "次", isEnglish: true), "2 in a row")
    }
}
