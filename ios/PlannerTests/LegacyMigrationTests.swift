import XCTest
@testable import Planner

/// A-02：与 src/lib/store.js:migrate / initStore 对齐。
@MainActor
final class LegacyMigrationTests: XCTestCase {
    private let now: Double = 1_700_000_000_000

    func testMigratesSubtasksInheritsQuadrantAndOffsetsCreatedAt() {
        let parent: [String: Any] = [
            "id": "p1", "title": "父任务", "createdAt": 1_000,
            "important": true, "urgent": false,
            "subtasks": [
                ["id": "c1", "title": "子任务一", "done": true, "doneDates": ["2026-11-13"]],
                ["id": "c2", "title": "   "],                 // 空标题 → 被 filter 丢弃
                ["id": "c3", "title": "子任务三"],           // 过滤后索引 i = 1
                NSNull()                                     // 非对象 → 丢弃
            ]
        ]
        let raw: [Any] = [parent]

        XCTAssertTrue(LegacyMigration.containsLegacySubtasks(raw))

        let tasks = LegacyMigration.normalizedTasks(raw, now: now)
        XCTAssertEqual(tasks.count, 3, "父任务 + 2 个有效子任务")
        XCTAssertEqual(tasks[0].id, "p1")

        let c1 = tasks[1]
        XCTAssertEqual(c1.id, "c1")
        XCTAssertEqual(c1.parentId, "p1")
        XCTAssertTrue(c1.important, "继承父任务象限")
        XCTAssertFalse(c1.urgent)
        XCTAssertTrue(c1.done)
        XCTAssertEqual(c1.doneDates, ["2026-11-13"])
        XCTAssertEqual(c1.createdAt, 1_001)
        XCTAssertEqual(c1.updatedAt, 1_001)
        XCTAssertEqual(c1.date, "")
        XCTAssertEqual(c1.repeatRule, "", "子任务不可重复")

        let c3 = tasks[2]
        XCTAssertEqual(c3.id, "c3")
        XCTAssertEqual(c3.createdAt, 1_002, "i 是过滤后的索引")
        XCTAssertFalse(c3.done)
        XCTAssertNil(c3.remind)
    }

    func testSubtaskWithoutIdGetsGeneratedId() {
        let parent: [String: Any] = [
            "id": "p1", "title": "父", "createdAt": 1_000,
            "subtasks": [["title": "没有 id 的子任务"]]
        ]
        let t = LegacyMigration.normalizedTasks([parent], now: now)[1]
        XCTAssertEqual(t.id.count, 36)
        XCTAssertEqual(t.id, t.id.lowercased())
        XCTAssertEqual(t.title, "没有 id 的子任务")
    }

    func testParentCreatedAtFallbackUsesNow() {
        let parent: [String: Any] = [
            "id": "p1", "title": "父", "subtasks": [["id": "c1", "title": "子"]]
        ]
        let t = LegacyMigration.normalizedTasks([parent], now: now)[1]
        XCTAssertEqual(t.createdAt, now + 1)
    }

    func testNoLegacyFormatKeepsTasksUntouched() {
        let raw: [Any] = [
            ["id": "a", "title": "A"],
            ["id": "b", "title": "B"]
        ]
        XCTAssertFalse(LegacyMigration.containsLegacySubtasks(raw))
        let tasks = LegacyMigration.normalizedTasks(raw, now: now)
        XCTAssertEqual(tasks.map(\.id), ["a", "b"])
        XCTAssertEqual(tasks.map(\.title), ["A", "B"])
    }

    func testReadingPlannerDataJSONAppliesMigration() throws {
        let json = """
        {"version":1,"tasks":[
          {"id":"p","title":"父","createdAt":1000,
           "subtasks":[{"id":"c","title":"子"}]}
        ],"deleted":{}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let tasks = try PlannerTask.normalizedTasks(from: data, now: now)
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[1].parentId, "p")
        XCTAssertEqual(tasks[1].createdAt, 1_001)
    }

    func testEmptySubtasksArrayStillTriggersLegacyFlag() {
        let raw: [Any] = [["id": "p", "subtasks": []]]
        XCTAssertTrue(LegacyMigration.containsLegacySubtasks(raw),
                      "initStore:142 用 Array.isArray 判断，空数组也算")
        XCTAssertEqual(LegacyMigration.normalizedTasks(raw, now: now).count, 1)
    }
}
