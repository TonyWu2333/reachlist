import XCTest
@testable import Planner

/// A-01：与 src/lib/store.js:normalizeTask 逐项对齐。
@MainActor
final class PlannerTaskNormalizationTests: XCTestCase {
    private let now: Double = 1_700_000_000_000

    private func norm(_ dict: [String: Any]) -> PlannerTask {
        PlannerTask.normalize(dict, now: now)
    }

    func testEmptyRawGetsEveryDefault() {
        let t = norm(["id": "fixed-id"])
        XCTAssertEqual(t.id, "fixed-id")
        XCTAssertEqual(t.title, "")
        XCTAssertEqual(t.note, "")
        XCTAssertEqual(t.date, "")
        XCTAssertEqual(t.time, "")
        XCTAssertFalse(t.important)
        XCTAssertFalse(t.urgent)
        XCTAssertFalse(t.done)
        XCTAssertFalse(t.dropped)
        XCTAssertEqual(t.createdAt, now)
        XCTAssertNil(t.doneAt)
        XCTAssertEqual(t.repeatRule, "")
        XCTAssertEqual(t.doneDates, [])
        XCTAssertEqual(t.skipDates, [])
        XCTAssertNil(t.remind)
        XCTAssertEqual(t.parentId, "")
        XCTAssertEqual(t.updatedAt, now)
    }

    func testMissingIdGeneratesLowercaseUUID() {
        let t = norm([:])
        XCTAssertEqual(t.id.count, 36)
        XCTAssertEqual(t.id, t.id.lowercased())
        XCTAssertEqual(t.id.filter { $0 == "-" }.count, 4)
    }

    func testTitleIsTrimmedButNoteIsNot() {
        let t = norm(["id": "a", "title": "  写周报  ", "note": "  带备注  "])
        XCTAssertEqual(t.title, "写周报")
        XCTAssertEqual(t.note, "  带备注  ")
    }

    func testDroppedImpliesDone() {
        let t = norm(["id": "a", "dropped": true])
        XCTAssertTrue(t.done)
        XCTAssertTrue(t.dropped)
    }

    func testDateAndTimeValidation() {
        XCTAssertEqual(norm(["id": "a", "date": "2026-11-13"]).date, "2026-11-13")
        XCTAssertEqual(norm(["id": "a", "date": "2026-1-13"]).date, "")
        XCTAssertEqual(norm(["id": "a", "date": "abcd-ef-gh"]).date, "")
        XCTAssertEqual(norm(["id": "a", "date": NSNull()]).date, "")
        XCTAssertEqual(norm(["id": "a", "time": "09:30"]).time, "09:30")
        XCTAssertEqual(norm(["id": "a", "time": "9:30"]).time, "")
        XCTAssertEqual(norm(["id": "a", "time": "21：00"]).time, "")
    }

    // store.js:48 —— 必须区分 undefined / null / 数字 / 字符串
    func testRemindRules() {
        XCTAssertEqual(norm(["id": "a", "time": "09:30"]).remind, 0, "缺 remind + 有时间 → 0")
        XCTAssertNil(norm(["id": "a"]).remind, "缺 remind + 无时间 → null")
        XCTAssertNil(norm(["id": "a", "time": "09:30", "remind": NSNull()]).remind, "显式 null → null")
        XCTAssertEqual(norm(["id": "a", "remind": 15]).remind, 15)
        XCTAssertEqual(norm(["id": "a", "remind": 0]).remind, 0)
        XCTAssertNil(norm(["id": "a", "remind": -1]).remind)
        XCTAssertNil(norm(["id": "a", "remind": 1.5]).remind)
        XCTAssertNil(norm(["id": "a", "remind": "5"]).remind, "Number.isInteger(字符串) = false")
        XCTAssertNil(norm(["id": "a", "remind": true]).remind)
    }

    func testDateListsFilterInvalidValues() {
        let t = norm([
            "id": "a",
            "doneDates": ["2026-11-13", "2026-1-1", 20261114, "x", "2026-12-01"],
            "skipDates": "not-an-array"
        ])
        XCTAssertEqual(t.doneDates, ["2026-11-13", "2026-12-01"])
        XCTAssertEqual(t.skipDates, [])
    }

    func testTimestampFallbackChain() {
        let t = norm(["id": "a", "createdAt": 1_000])
        XCTAssertEqual(t.createdAt, 1_000)
        XCTAssertEqual(t.updatedAt, 1_000, "缺 updatedAt 时回落到 Number(createdAt)")

        let u = norm(["id": "a", "createdAt": 1_000, "updatedAt": 2_000])
        XCTAssertEqual(u.updatedAt, 2_000)

        let z = norm(["id": "a", "createdAt": 0, "updatedAt": 0])
        XCTAssertEqual(z.createdAt, now)
        XCTAssertEqual(z.updatedAt, now, "0 在 JS 里是 falsy")
    }

    func testDoneAtKeepsZeroButMapsNullToNil() {
        XCTAssertEqual(norm(["id": "a", "doneAt": 0]).doneAt, 0)
        XCTAssertEqual(norm(["id": "a", "doneAt": 1_234]).doneAt, 1_234)
        XCTAssertNil(norm(["id": "a", "doneAt": NSNull()]).doneAt)
        XCTAssertNil(norm(["id": "a"]).doneAt)
    }

    func testParentIdUsesJSTruthiness() {
        XCTAssertEqual(norm(["id": "a", "parentId": "p1"]).parentId, "p1")
        XCTAssertEqual(norm(["id": "a", "parentId": ""]).parentId, "")
        XCTAssertEqual(norm(["id": "a", "parentId": 0]).parentId, "")
        XCTAssertEqual(norm(["id": "a", "parentId": NSNull()]).parentId, "")
    }

    func testLegacyRepeatAliases() {
        XCTAssertEqual(norm(["id": "a", "repeat": "daily"]).repeatRule, "d1")
        XCTAssertEqual(norm(["id": "a", "repeat": "weekdays"]).repeatRule, "w1:12345")
        XCTAssertEqual(norm(["id": "a", "repeat": "monthly"]).repeatRule, "m1")
        XCTAssertEqual(norm(["id": "a", "repeat": "bogus"]).repeatRule, "")
        XCTAssertEqual(norm(["id": "a", "repeat": 123]).repeatRule, "")
    }

    func testWeeklyAliasUsesStartDateWeekday() {
        // 2026-11-13 是周五 → JS getDay() = 5
        let t = norm(["id": "a", "repeat": "weekly", "date": "2026-11-13"])
        XCTAssertEqual(t.repeatRule, "w1:5")
    }

    func testRuleValidation() {
        XCTAssertTrue(RepeatNormalization.isValidRule("d1"))
        XCTAssertTrue(RepeatNormalization.isValidRule("d3~2026-12-31"))
        XCTAssertTrue(RepeatNormalization.isValidRule("w1:135"))
        XCTAssertTrue(RepeatNormalization.isValidRule("w2:5"))
        XCTAssertTrue(RepeatNormalization.isValidRule("m1"))
        XCTAssertTrue(RepeatNormalization.isValidRule("y1"))
        XCTAssertFalse(RepeatNormalization.isValidRule("w1"), "w 类型缺星期 → 无效")
        XCTAssertFalse(RepeatNormalization.isValidRule("w1:"))
        XCTAssertFalse(RepeatNormalization.isValidRule("x1"))
        XCTAssertFalse(RepeatNormalization.isValidRule("d1~2026-1-1"))
        XCTAssertFalse(RepeatNormalization.isValidRule("d1000"))
        XCTAssertEqual(norm(["id": "a", "repeat": "w1"]).repeatRule, "")
    }
}
