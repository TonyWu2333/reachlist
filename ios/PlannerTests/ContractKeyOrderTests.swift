import XCTest
@testable import Planner

/// §2.6.1 / VERIFY-01 的契约检查。
/// shared/merge.js:taskSig 用 JSON.stringify 做确定性平局裁决，键序敏感。
///
/// VERIFY-01 实测结论（2026-11-13）：Apple 平台的 JSONEncoder **不保证键序**，
/// 显式 encode(to:) 的调用顺序会被内部哈希顺序覆盖（15 条 fixture 出现 15 种顺序）。
/// 故契约输出改用 PlannerTask.jsJSONString() 显式有序拼接；
/// 下面验证它的键序、null 键、数字表示与 JS 一致。
@MainActor
final class ContractKeyOrderTests: XCTestCase {
    private let now: Double = 1_700_000_000_000

    func testCodingKeysDeclarationOrderMatchesJS() {
        XCTAssertEqual(
            PlannerTask.CodingKeys.allCases.map(\.stringValue),
            PlannerTask.jsonKeyOrder
        )
    }

    func testOrderedJSONOutputUsesJSKeyOrder() throws {
        let t = PlannerTask.normalize(["id": "a", "title": "任务", "createdAt": 1_000], now: now)
        let s = try XCTUnwrap(String(data: t.jsonData(), encoding: .utf8))

        // 逐个键按期望顺序向前查找：若 JSONEncoder 重排了键，这里会失败。
        var cursor = s.startIndex
        for key in PlannerTask.jsonKeyOrder {
            let needle = "\"\(key)\""
            guard let found = s.range(of: needle, range: cursor..<s.endIndex) else {
                XCTFail("键 \(key) 缺失或未按顺序出现。实际输出：\(s)")
                return
            }
            cursor = found.upperBound
        }
    }

    func testNilOptionalsAreExplicitNullNotOmitted() throws {
        let t = PlannerTask.normalize(["id": "a", "createdAt": 1_000], now: now)
        let s = try XCTUnwrap(String(data: t.jsonData(), encoding: .utf8))
        XCTAssertTrue(s.contains("\"doneAt\":null"), "实际输出：\(s)")
        XCTAssertTrue(s.contains("\"remind\":null"), "实际输出：\(s)")
    }

    func testIntegerValuedDoublesHaveNoFractionSuffix() throws {
        // JS JSON.stringify(1000) === "1000"，不能写成 "1000.0"
        let t = PlannerTask.normalize(["id": "a", "createdAt": 1_000, "doneAt": 2_000], now: now)
        let s = try XCTUnwrap(String(data: t.jsonData(), encoding: .utf8))
        XCTAssertTrue(s.contains("\"createdAt\":1000"), "实际输出：\(s)")
        XCTAssertTrue(s.contains("\"doneAt\":2000"), "实际输出：\(s)")
        XCTAssertFalse(s.contains(".0"))
    }

    func testRepeatKeyIsNamedRepeatNotRepeatRule() throws {
        let t = PlannerTask.normalize(["id": "a", "repeat": "d1", "createdAt": 1_000], now: now)
        let s = try XCTUnwrap(String(data: t.jsonData(), encoding: .utf8))
        XCTAssertTrue(s.contains("\"repeat\":\"d1\""), "实际输出：\(s)")
        XCTAssertFalse(s.contains("repeatRule"))
    }

    func testCodableDecodeGoesThroughSameNormalizer() throws {
        let json = #"{"id":"a","title":"  hi  ","time":"09:30","dropped":true,"createdAt":1000}"#
        let t = try JSONDecoder().decode(PlannerTask.self, from: XCTUnwrap(json.data(using: .utf8)))
        XCTAssertEqual(t.title, "hi")
        XCTAssertTrue(t.done, "dropped 同时算 done")
        XCTAssertTrue(t.dropped)
        XCTAssertEqual(t.remind, 0, "remind 缺失 + 有 time → 0")
        XCTAssertEqual(t.createdAt, 1_000)
        XCTAssertEqual(t.updatedAt, 1_000)
        XCTAssertNil(t.doneAt)

        let explicitNull = #"{"id":"a","time":"09:30","remind":null,"createdAt":1000}"#
        let t2 = try JSONDecoder().decode(PlannerTask.self, from: XCTUnwrap(explicitNull.data(using: .utf8)))
        XCTAssertNil(t2.remind, "显式 null 与缺失必须区分")
    }

    func testOrderedJSONHasSameValuesAsCodableEncoder() throws {
        // 有序拼接不能漏字段或改值：与 Codable 输出按解析后的字典比较。
        let raw: [String: Any] = [
            "id": "a", "title": "写周报", "note": "带 \"引号\" 和换行\n",
            "date": "2026-11-13", "time": "09:30", "important": true,
            "createdAt": 1_000, "doneAt": 2_000, "repeat": "d1",
            "doneDates": ["2026-11-13"], "remind": 15, "updatedAt": 3_000
        ]
        let t = PlannerTask.normalize(raw, now: now)
        let ordered = try JSONSerialization.jsonObject(with: t.jsonData()) as! NSDictionary
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(t)) as! NSDictionary
        XCTAssertEqual(ordered, encoded)
    }

    func testRoundTripIsIdempotent() throws {
        let raw: [String: Any] = [
            "id": "a", "title": "写周报", "note": "带上数据", "date": "2026-11-13",
            "time": "09:30", "important": true, "urgent": false, "done": true,
            "dropped": false, "createdAt": 1_000, "doneAt": 2_000,
            "repeat": "w1:135", "doneDates": ["2026-11-13"], "skipDates": ["2026-11-14"],
            "remind": 15, "parentId": "p", "updatedAt": 3_000
        ]
        let t1 = PlannerTask.normalize(raw, now: now)
        let data = try t1.jsonData()
        let t2 = try JSONDecoder().decode(PlannerTask.self, from: data)
        XCTAssertEqual(t1, t2)
        XCTAssertEqual(try t2.jsonData(), data)
    }
}
