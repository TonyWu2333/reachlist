import XCTest
import Foundation
@testable import Planner

// T-07 / M-03 契约测试。
// 期望值取自 baseline_commit 97a7c4c 的 src/lib/repeat.js（真实源码 oracle）。
// 全量逐字对比（791 项）由独立 swiftc harness 执行：
//   node ios/PlannerTests/Fixtures/generate_repeat_fixtures.mjs
//   swiftc -O ios/Planner/Core/Models/{PlannerTask,LegacyMigration,RepeatNormalization}.swift \
//             ios/Planner/Core/Calendar/{PlannerCalendar,LunarData}.swift \
//             ios/Planner/Core/Repeat/RepeatEngine.swift /tmp/t07_harness/main.swift \
//             -o /tmp/t07_harness/verify
//   /tmp/t07_harness/verify ios/PlannerTests/Fixtures/repeat_fixtures.json

final class T07RepeatEngineTests: XCTestCase {

    private func makeTask(
        id: String = "t1", date: String, repeatRule: String,
        doneDates: [String] = [], skipDates: [String] = []
    ) -> PlannerTask {
        let arr = { (a: [String]) in "[" + a.map { "\"\($0)\"" }.joined(separator: ",") + "]" }
        let json = """
        {"id":"\(id)","title":"x","note":"","date":"\(date)","time":"","important":false,"urgent":false,
         "done":false,"dropped":false,"createdAt":1700000000000,"doneAt":null,"repeat":"\(repeatRule)",
         "doneDates":\(arr(doneDates)),"skipDates":\(arr(skipDates)),"remind":null,"parentId":"","updatedAt":1700000000000}
        """
        return try! JSONDecoder().decode(PlannerTask.self, from: Data(json.utf8))
    }

    // MARK: 规则串（repeat.js:14-45）

    func testParseRuleBoundaries() {
        XCTAssertEqual(RepeatEngine.parse("d1"), .init(freq: "d", n: 1, days: [], until: ""))
        XCTAssertEqual(RepeatEngine.parse("d0")?.n, 1, "n 下限")
        XCTAssertEqual(RepeatEngine.parse("d99")?.n, 99)
        XCTAssertNil(RepeatEngine.parse("d1000"), "超过 3 位")
        XCTAssertEqual(RepeatEngine.parse("w2:5"), .init(freq: "w", n: 2, days: [5], until: ""))
        XCTAssertEqual(RepeatEngine.parse("w1:531")?.days, [1, 3, 5], "去重并升序")
        XCTAssertEqual(RepeatEngine.parse("m1~2026-12-31")?.until, "2026-12-31")
        XCTAssertNil(RepeatEngine.parse(""))
        XCTAssertNil(RepeatEngine.parse("w1"), "周规则必须有星期")
        XCTAssertNil(RepeatEngine.parse("x1"))
        XCTAssertNil(RepeatEngine.parse(" d1"))
    }

    func testFormatRule() {
        XCTAssertEqual(RepeatEngine.format(.init(freq: "w", n: 2, days: [5, 1, 1], until: "2026-12-31")), "w2:15~2026-12-31")
        XCTAssertEqual(RepeatEngine.format(.init(freq: "d", n: 1, days: [3], until: "")), "d1", "非周规则忽略 days")
        XCTAssertEqual(RepeatEngine.format(.init(freq: "m", n: 0, days: [], until: "")), "m1", "n 下限")
    }

    func testNormalizeLegacy() {
        XCTAssertEqual(RepeatEngine.normalizeLegacy("daily", date: "2026-11-13"), "d1")
        XCTAssertEqual(RepeatEngine.normalizeLegacy("weekdays", date: "2026-11-13"), "w1:12345")
        XCTAssertEqual(RepeatEngine.normalizeLegacy("monthly", date: "2026-11-13"), "m1")
        XCTAssertEqual(RepeatEngine.normalizeLegacy("weekly", date: "2026-11-13"), "w1:5", "取开始日期星期")
        XCTAssertEqual(RepeatEngine.normalizeLegacy("weekly", date: "2024-02-29"), "w1:4")
        XCTAssertEqual(RepeatEngine.normalizeLegacy("bogus", date: "2026-11-13"), "")
        XCTAssertEqual(RepeatEngine.normalizeLegacy("", date: "2026-11-13"), "")
    }

    // MARK: 发生判定（含 §8.2 第 2 条边界）

    func testOccursOnMonthEndAndLeapYear() {
        let monthly = makeTask(date: "2024-01-31", repeatRule: "m1")
        XCTAssertTrue(RepeatEngine.occursOn(monthly, "2024-02-29"), "1 月 31 日的 m1 → 2 月月底")
        XCTAssertTrue(RepeatEngine.occursOn(monthly, "2024-03-31"))
        XCTAssertTrue(RepeatEngine.occursOn(monthly, "2024-04-30"))
        let yearly = makeTask(date: "2024-02-29", repeatRule: "y1")
        XCTAssertTrue(RepeatEngine.occursOn(yearly, "2024-02-29"))
        XCTAssertTrue(RepeatEngine.occursOn(yearly, "2025-02-28"), "非闰年取月底")
        XCTAssertTrue(RepeatEngine.occursOn(yearly, "2028-02-29"))
    }

    func testOccursOnWeeklyCrossYear() {
        let everyOtherFriday = makeTask(date: "2026-12-25", repeatRule: "w2:5")
        XCTAssertTrue(RepeatEngine.occursOn(everyOtherFriday, "2026-12-25"))
        XCTAssertFalse(RepeatEngine.occursOn(everyOtherFriday, "2027-01-01"))
        XCTAssertTrue(RepeatEngine.occursOn(everyOtherFriday, "2027-01-08"))
    }

    func testOccursOnUntilAndSkipDates() {
        let until = makeTask(date: "2026-11-01", repeatRule: "d1~2026-11-15")
        XCTAssertTrue(RepeatEngine.occursOn(until, "2026-11-15"), "结束日期当天仍发生")
        XCTAssertFalse(RepeatEngine.occursOn(until, "2026-11-16"))
        let skipped = makeTask(date: "2026-11-01", repeatRule: "d1", skipDates: ["2026-11-13", "2026-11-14"])
        XCTAssertFalse(RepeatEngine.occursOn(skipped, "2026-11-13"))
        XCTAssertTrue(RepeatEngine.occursOn(skipped, "2026-11-15"))
        let ended = makeTask(date: "2026-01-01", repeatRule: "d1~2026-01-31")
        XCTAssertFalse(RepeatEngine.occursOn(ended, "2026-11-13"))
    }

    func testNextOccurrence() {
        let daily = makeTask(date: "2026-11-01", repeatRule: "d1")
        XCTAssertEqual(RepeatEngine.nextOccurrence(daily, from: "2026-11-13"), "2026-11-13")
        let until = makeTask(date: "2026-11-01", repeatRule: "d1~2026-11-15")
        XCTAssertEqual(RepeatEngine.nextOccurrence(until, from: "2026-11-20"), "", "until 已过")
        let skipped = makeTask(date: "2026-11-01", repeatRule: "d1", skipDates: ["2026-11-13", "2026-11-14"])
        XCTAssertEqual(RepeatEngine.nextOccurrence(skipped, from: "2026-11-13"), "2026-11-15")
        let crossYear = makeTask(date: "2026-12-25", repeatRule: "w2:5")
        XCTAssertEqual(RepeatEngine.nextOccurrence(crossYear, from: "2026-12-26"), "2027-01-08")
        let leap = makeTask(date: "2024-01-31", repeatRule: "m1")
        XCTAssertEqual(RepeatEngine.nextOccurrence(leap, from: "2024-02-01"), "2024-02-29")
        XCTAssertEqual(RepeatEngine.nextOccurrence(makeTask(date: "2026-01-01", repeatRule: ""), from: "2026-11-13"), "")
    }

    func testInstanceOf() {
        let t = makeTask(date: "2026-01-01", repeatRule: "d1", doneDates: ["2026-11-13"])
        let inst = RepeatEngine.instanceOf(t, "2026-11-13")
        XCTAssertEqual(inst.occ, "2026-11-13")
        XCTAssertEqual(inst.task.date, "2026-11-13")
        XCTAssertTrue(inst.task.done)
        XCTAssertFalse(RepeatEngine.instanceOf(t, "2026-11-14").task.done)
    }

    // MARK: 文案 / 分组 / 连续次数

    func testRepeatLabelChineseAndEnglish() {
        XCTAssertEqual(RepeatEngine.repeatLabel("w2:5", date: "2026-11-13", isEnglish: false), "每2周的周五")
        XCTAssertEqual(RepeatEngine.repeatLabel("w2:5", date: "2026-11-13", isEnglish: true), "Every 2 weeks on Fri")
        XCTAssertEqual(RepeatEngine.repeatLabel("w1:0123456", date: "2026-11-13", isEnglish: false), "每天")
        XCTAssertEqual(RepeatEngine.repeatLabel("m1", date: "2026-11-13", isEnglish: true), "Monthly on the 13th")
        XCTAssertEqual(RepeatEngine.repeatLabel("d1~2026-12-31", date: "2026-11-13", isEnglish: false, withUntil: true), "每天，到12月31日")
        XCTAssertEqual(RepeatEngine.repeatLabel("d1~2026-12-31", date: "2026-11-13", isEnglish: true, withUntil: true), "Daily, until Dec 31")
        XCTAssertEqual(RepeatEngine.repeatLabel("w1", date: "2026-11-13", isEnglish: false), "")
    }

    func testRepeatGroup() {
        XCTAssertEqual(RepeatEngine.repeatGroup("d1"), "daily")
        XCTAssertEqual(RepeatEngine.repeatGroup("d3"), "interval")
        XCTAssertEqual(RepeatEngine.repeatGroup("w1:0123456"), "daily")
        XCTAssertEqual(RepeatEngine.repeatGroup("w1:12345"), "weekly")
        XCTAssertEqual(RepeatEngine.repeatGroup("m1"), "monthly")
        XCTAssertEqual(RepeatEngine.repeatGroup("y1"), "yearly")
        XCTAssertEqual(RepeatEngine.repeatGroup(""), "")
    }

    func testStreakOf() {
        let three = makeTask(date: "2026-11-01", repeatRule: "d1",
                             doneDates: ["2026-11-10", "2026-11-11", "2026-11-12"])
        XCTAssertEqual(RepeatEngine.streakOf(three, "2026-11-13"), 3, "今天未完成不算断")
        let broken = makeTask(date: "2026-11-01", repeatRule: "d1", doneDates: ["2026-11-10", "2026-11-12"])
        XCTAssertEqual(RepeatEngine.streakOf(broken, "2026-11-13"), 1)
        let skip = makeTask(date: "2026-11-01", repeatRule: "d1",
                            doneDates: ["2026-11-12"], skipDates: ["2026-11-11"])
        XCTAssertEqual(RepeatEngine.streakOf(skip, "2026-11-13"), 1, "跳过日不算断也不计数")
        XCTAssertEqual(RepeatEngine.streakOf(makeTask(date: "2026-11-13", repeatRule: "d1"), "2026-11-13"), 0)
    }

    // MARK: F-01.9 某日任务展开

    func testTasksOnMixesOnceAndRepeatInstances() {
        let tasks = [
            makeTask(id: "once", date: "2026-11-13", repeatRule: ""),
            makeTask(id: "other", date: "2026-11-14", repeatRule: ""),
            makeTask(id: "daily", date: "2026-11-01", repeatRule: "d1"),
            makeTask(id: "skipped", date: "2026-11-01", repeatRule: "d1", skipDates: ["2026-11-13"]),
            makeTask(id: "done", date: "2026-11-01", repeatRule: "d1", doneDates: ["2026-11-13"]),
        ]
        let got = RepeatEngine.tasksOn(tasks, day: "2026-11-13")
        XCTAssertEqual(got.map(\.task.id), ["once", "daily", "done"])
        XCTAssertEqual(got[0].occ, "", "一次性任务没有 occ")
        XCTAssertEqual(got[1].occ, "2026-11-13")
        XCTAssertFalse(got[1].task.done)
        XCTAssertTrue(got[2].task.done)
        XCTAssertEqual(got[2].task.date, "2026-11-13")
    }

    // MARK: T-14 转发层签名与语义保持不变

    func testT14ForwardingLayerKeepsContract() {
        XCTAssertEqual(RepeatRule.parse("w2:5"), RepeatEngine.parse("w2:5"))
        XCTAssertEqual(RepeatRule.format(.init(freq: "w", n: 2, days: [5], until: "2026-12-31")),
                       RepeatEngine.format(.init(freq: "w", n: 2, days: [5], until: "2026-12-31")))
        XCTAssertEqual(RepeatRule.normalizeLegacy("weekly", date: "2026-11-13"), "w1:5")
        XCTAssertEqual(RepeatRule.label("d1", date: "2026-11-13", isEnglish: false), "每天")
        XCTAssertEqual(RepeatRule.label("m1", date: "2026-11-13", isEnglish: true), "Monthly on the 13th")
        XCTAssertEqual(RepeatRule.defaultCustom, RepeatEngine.Rule(freq: "d", n: 1, days: [], until: ""))
        XCTAssertTrue(RepeatRule.mondayFirst(1, 0), "周一排在周日前")
    }
}
