import XCTest
import Foundation
@testable import Planner

// T-05 / M-05 合并算法契约测试。
// 期望值取自 baseline_commit 97a7c4c 的真实源码 shared/merge.js（纯函数，未复制、未改写）。
//
// 两层验证：
// 1) 本文件的 fixture 测试：175 条用例（20 条结构化 + 150 条确定性模糊 + 5 条边界）
//    与 11 条 taskSig 单值夹具，逐字对比 oracle 输出。夹具作为测试资源随 target 打包。
//    重新生成：node ios/PlannerTests/Fixtures/generate_merge_fixtures.mjs
// 2) 独立 swiftc harness（不依赖真机，见 docs §12 v0.21）跑同一份夹具。
//
// dump 格式与生成器中的 dump() 必须逐字一致：
//   ids:<id|id>
//   tasks:<JSON.stringify(t) 每行一条，顺序即合并结果顺序>
//   deleted:<id:ms 按 id 排序>
//   meta:<k:v 按 k 排序>
// 字典按键排序是刻意的：Swift 字典无插入序，而 §2.6.1 只要求任务数组有序、
// taskSig 键序敏感，`deleted` / `meta` 的键序不属契约。

final class T05MergeEngineTests: XCTestCase {

    // MARK: - 夹具

    private struct Fixtures: Decodable {
        struct Meta: Decodable {
            let baseline_commit: String
            let case_count: Int
            let sig_case_count: Int
        }
        struct Expect: Decodable {
            let taskIds: [String]
            let dump: String
        }
        struct InputSigs: Decodable {
            let a: [String]
            let b: [String]
        }
        struct FixtureCase: Decodable {
            let name: String
            let now: Double
            let a: MergeState
            let b: MergeState
            let expect: Expect
            let inputSigs: InputSigs
        }
        struct SigCase: Decodable {
            let name: String
            let task: PlannerTask
            let sig: String
        }
        let meta: Meta
        let cases: [FixtureCase]
        let sigCases: [SigCase]
    }

    private static let baseline = "97a7c4c17602327a42d30110806a6a1e6fa0e798"

    private func loadFixtures(
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> Fixtures {
        guard let url = Bundle(for: T05MergeEngineTests.self)
            .url(forResource: "merge_fixtures", withExtension: "json") else {
            XCTFail("merge_fixtures.json 未打进测试 bundle（检查 Resources phase）", file: file, line: line)
            throw XCTSkip("fixture missing")
        }
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }

    /// 与生成器 dump() 逐字对应的规范化输出。
    private func dump(_ s: MergeState) -> String {
        let ids = s.tasks.map(\.id).joined(separator: "|")
        let tasks = s.tasks.map { $0.jsJSONString() }.joined(separator: "\n")
        let deleted = s.deleted.map { "\($0.key):\(Self.jsNumber($0.value))" }
            .sorted().joined(separator: ",")
        let meta = s.meta.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ",")
        return "ids:\(ids)\ntasks:\(tasks)\ndeleted:\(deleted)\nmeta:\(meta)"
    }

    /// JS `String(1700000000000)` == "1700000000000"；Swift 的 Double 插值会补 ".0"。
    private static func jsNumber(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 9e15 { return String(Int64(v)) }
        return String(v)
    }

    // MARK: - 1. 全量夹具（oracle 逐字对比）

    func testFixturesMatchJSOracle() throws {
        let f = try loadFixtures()
        XCTAssertEqual(f.meta.baseline_commit, Self.baseline, "夹具基线必须与计划书一致")
        XCTAssertEqual(f.cases.count, f.meta.case_count)
        XCTAssertEqual(f.sigCases.count, f.meta.sig_case_count)
        XCTAssertGreaterThanOrEqual(f.cases.count, 175, "结构化 20 + 模糊 150 + 边界 5")

        var failures: [String] = []
        for c in f.cases {
            // 序列化等价：输入任务的 taskSig 必须与 JS 逐字一致，否则合并裁决必然跑偏。
            let sigsA = c.a.tasks.map(MergeEngine.taskSig)
            let sigsB = c.b.tasks.map(MergeEngine.taskSig)
            if sigsA != c.inputSigs.a { failures.append("\(c.name): a 侧 taskSig 不一致") }
            if sigsB != c.inputSigs.b { failures.append("\(c.name): b 侧 taskSig 不一致") }

            let merged = MergeEngine.mergeState(c.a, c.b, now: c.now)
            if merged.tasks.map(\.id) != c.expect.taskIds {
                failures.append("\(c.name): 任务顺序/成员不一致 期望 \(c.expect.taskIds) 实际 \(merged.tasks.map(\.id))")
            }
            let actual = dump(merged)
            if actual != c.expect.dump {
                failures.append("\(c.name): dump 不一致\n--- 期望 ---\n\(c.expect.dump)\n--- 实际 ---\n\(actual)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "共 \(failures.count) 条不一致：\n" + failures.prefix(5).joined(separator: "\n\n"))
    }

    func testSigFixturesMatchJSOracle() throws {
        let f = try loadFixtures()
        var failures: [String] = []
        for c in f.sigCases where MergeEngine.taskSig(c.task) != c.sig {
            failures.append("\(c.name):\n期望 \(c.sig)\n实际 \(MergeEngine.taskSig(c.task))")
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n\n"))
    }

    // MARK: - 2. taskSig 语义（merge.js:10-13）

    func testTaskSigExcludesUpdatedAtOnly() {
        let t = Self.task(id: "t1", title: "写周报", updatedAt: 1700000000000)
        var t2 = t
        t2.updatedAt = 1800000000000
        XCTAssertEqual(MergeEngine.taskSig(t), MergeEngine.taskSig(t2), "updatedAt 不参与签名")

        var t3 = t
        t3.title = "写周报 "
        XCTAssertNotEqual(MergeEngine.taskSig(t), MergeEngine.taskSig(t3), "任一其他字段变化都要改签名")
    }

    func testTaskSigKeyOrderFollowsContract() {
        let sig = MergeEngine.taskSig(Self.task(id: "t1"))
        // 16 个键、键序 = jsonKeyOrder 去掉 updatedAt。
        let expectedOrder = PlannerTask.jsonKeyOrder.filter { $0 != "updatedAt" }
        var cursor = sig.startIndex
        for key in expectedOrder {
            let token = "\"\(key)\":"
            guard let r = sig.range(of: token, range: cursor..<sig.endIndex) else {
                return XCTFail("缺少键 \(key)")
            }
            cursor = r.upperBound
        }
        XCTAssertFalse(sig.contains("\"updatedAt\""))
        XCTAssertEqual(sig.filter { $0 == ":" }.count, expectedOrder.count, "16 个键各一个冒号")
    }

    // MARK: - 3. 平局裁决必须按 UTF-16 code unit（不能用 Swift 原生比较）

    func testJSStringGreaterUsesUTF16CodeUnits() {
        // emoji（代理对）vs BMP 高码位：UTF-16 序 D83D < FFFD，标量序 1F600 > FFFD。
        XCTAssertFalse(MergeEngine.jsStringGreater("😀", "\u{FFFD}"))
        // 组合字符 vs 预组合：Swift 原生 `==` 认为相等，JS 逐 code unit 能分出大小。
        XCTAssertFalse(MergeEngine.jsStringGreater("e\u{0301}", "\u{00E9}"))
        XCTAssertTrue(MergeEngine.jsStringGreater("\u{00E9}", "e\u{0301}"))
        // 前缀 / 相等 / 普通 ASCII
        XCTAssertFalse(MergeEngine.jsStringGreater("ab", "abc"))
        XCTAssertTrue(MergeEngine.jsStringGreater("abc", "ab"))
        XCTAssertFalse(MergeEngine.jsStringGreater("abc", "abc"))
        XCTAssertTrue(MergeEngine.jsStringGreater("b", "a"))
        XCTAssertFalse(MergeEngine.jsStringGreater("A", "a"), "UTF-16 序里大写字母更小")
    }

    func testNewerTieBreakIsDeterministicAndAsymmetric() {
        let a = Self.task(id: "t1", title: "甲", updatedAt: 1700000002000)
        let b = Self.task(id: "t1", title: "乙", updatedAt: 1700000002000)
        XCTAssertTrue(MergeEngine.newer(a, b) != MergeEngine.newer(b, a), "平局裁决必须严格二选一")
        XCTAssertFalse(MergeEngine.newer(a, a), "同一条任务不比自身新")

        let older = Self.task(id: "t1", updatedAt: 1700000001000)
        XCTAssertTrue(MergeEngine.newer(a, older))
        XCTAssertFalse(MergeEngine.newer(older, a))
    }

    // MARK: - 4. 规则逐条（§2.6.1 第 3~8 条）

    func testMergeTakesLaterTombstonePerId() {
        let merged = MergeEngine.mergeState(
            MergeState(tasks: [], deleted: ["x": 100], meta: [:]),
            MergeState(tasks: [], deleted: ["x": 50, "y": 200], meta: [:]),
            now: 1000
        )
        XCTAssertEqual(merged.deleted["x"], 100, "取较晚的墓碑")
        XCTAssertEqual(merged.deleted["y"], 200)
    }

    func testTombstoneKillsEqualOrOlderTask() {
        let t = Self.task(id: "t1", updatedAt: 500)
        let equal = MergeEngine.mergeState(
            MergeState(deleted: ["t1": 500]), MergeState(tasks: [t]), now: 1000
        )
        XCTAssertTrue(equal.tasks.isEmpty, "墓碑不早于任务 → 丢弃")

        let older = MergeEngine.mergeState(
            MergeState(deleted: ["t1": 200]), MergeState(tasks: [t]), now: 1000
        )
        XCTAssertEqual(older.tasks.map(\.id), ["t1"], "墓碑更早 → 任务是撤销删除，复活")
        XCTAssertNil(older.deleted["t1"], "复活时必须清掉墓碑")
    }

    func testTombstoneWithZeroValueIsFalsyInJS() {
        // merge.js 的两处判断都以 `gone` 的真假为前提，0 是 falsy：任务保留、墓碑不清。
        let t = Self.task(id: "t1", updatedAt: 500)
        let merged = MergeEngine.mergeState(
            MergeState(tasks: [t], deleted: ["t1": 0]), MergeState(), now: 1000
        )
        XCTAssertEqual(merged.tasks.map(\.id), ["t1"])
        XCTAssertEqual(merged.deleted["t1"], 0)
    }

    func testTombstoneTTLIs90DaysExclusive() {
        let ttl = MergeEngine.tombstoneTTL
        XCTAssertEqual(ttl, 90 * 864e5)

        let exact = MergeEngine.mergeState(
            MergeState(deleted: ["t": 1000 - ttl]), MergeState(), now: 1000
        )
        XCTAssertEqual(exact.deleted["t"], 1000 - ttl, "恰好 90 天不清（条件是 >）")

        let expired = MergeEngine.mergeState(
            MergeState(deleted: ["t": 1000 - ttl - 1]), MergeState(), now: 1000
        )
        XCTAssertNil(expired.deleted["t"], "超过 90 天清理")
    }

    func testParentDroppedTakesChildrenAlong() {
        let parent = Self.task(id: "p1")
        let child = Self.task(id: "c1", parentId: "p1")
        let merged = MergeEngine.mergeState(
            MergeState(tasks: [parent, child], deleted: ["p1": 1700000009000]), MergeState(), now: 1700000010000
        )
        XCTAssertTrue(merged.tasks.isEmpty, "父任务被墓碑丢弃时子任务一并丢弃")
    }

    func testOrphanChildDropped() {
        let child = Self.task(id: "c1", parentId: "nobody")
        let merged = MergeEngine.mergeState(MergeState(tasks: [child]), MergeState(), now: 1700000010000)
        XCTAssertTrue(merged.tasks.isEmpty, "父任务不在合并结果里 → 子任务也丢弃")
    }

    func testMetaShallowMergeBOverridesA() {
        let merged = MergeEngine.mergeState(
            MergeState(meta: ["tz": "Asia/Shanghai", "app": "android"]),
            MergeState(meta: ["tz": "Europe/London"]),
            now: 1000
        )
        XCTAssertEqual(merged.meta["tz"], "Europe/London")
        XCTAssertEqual(merged.meta["app"], "android", "a 独有的键保留（浅合并，不整体替换）")
    }

    func testFirstOccurrenceOrderAndNewerWins() {
        let aOld = Self.task(id: "t1", title: "旧", updatedAt: 100)
        let bNew = Self.task(id: "t1", title: "新", updatedAt: 200)
        let merged = MergeEngine.mergeState(
            MergeState(tasks: [aOld, Self.task(id: "t2")]),
            MergeState(tasks: [Self.task(id: "t3"), bNew]),
            now: 1000
        )
        XCTAssertEqual(merged.tasks.map(\.id), ["t1", "t2", "t3"], "位置取首次出现的顺序")
        XCTAssertEqual(merged.tasks[0].title, "新", "内容取 updatedAt 较新的版本")
    }

    func testMergeWithItselfIsStableWhenNoTombstoneConflict() {
        // 注意：mergeState(a, a) 一般「不等于」a —— 状态里若同时有任务与其墓碑，
        // JS 会照【5】丢弃该任务。只有无墓碑冲突时自合并才是幂等的，本用例只断言这一情形。
        let state = MergeState(
            tasks: [Self.task(id: "t1"), Self.task(id: "t2"), Self.task(id: "c1", parentId: "t2")],
            deleted: ["z": 1700000009000],   // 距今 1 秒，未超 90 天，不会被 TTL 清掉
            meta: ["tz": "Asia/Shanghai"]
        )
        let once = MergeEngine.mergeState(state, state, now: 1700000010000)
        XCTAssertEqual(dump(once), dump(state), "无墓碑冲突时自合并等于自身")
        let twice = MergeEngine.mergeState(once, state, now: 1700000010000)
        XCTAssertEqual(dump(twice), dump(once), "重复合并结果稳定")
    }

    /// 【6】是单趟过滤：`ids` 取自过滤前的列表，所以「父任务自己被丢、子任务却被保留」
    /// 是 shared/merge.js 的既定行为。已在 JS 侧复现（fuzz-033 / fuzz-127），
    /// 二次合并才会把该悬挂子任务丢掉。iOS 必须与之一致，不得「顺手修正」。
    func testDanglingChildSurvivesFirstPassThenDropsOnSecond() {
        let state = MergeState(
            tasks: [
                Self.task(id: "a1", parentId: "p1"),
                Self.task(id: "p1", parentId: "b2"),
            ],
            deleted: ["b2": 1700000009000]
        )
        let first = MergeEngine.mergeState(state, MergeState(), now: 1700000010000)
        XCTAssertEqual(first.tasks.map(\.id), ["a1"], "父 p1 被丢，但 ids 取自过滤前列表 → 子 a1 保留")

        let second = MergeEngine.mergeState(first, MergeState(), now: 1700000010000)
        XCTAssertTrue(second.tasks.isEmpty, "与 JS 一致：二次合并丢掉悬挂子任务")
    }

    func testEmptyInputsAreSafe() {
        let merged = MergeEngine.mergeState(MergeState(), MergeState(), now: 1000)
        XCTAssertTrue(merged.tasks.isEmpty)
        XCTAssertTrue(merged.deleted.isEmpty)
        XCTAssertTrue(merged.meta.isEmpty)
    }

    // MARK: - 5. 缺字段的宽松解码（老数据 / agent 手写 payload）

    func testMergeStateDecodesMissingFields() throws {
        let a = try JSONDecoder().decode(MergeState.self, from: Data("{}".utf8))
        XCTAssertTrue(a.tasks.isEmpty)

        let b = try JSONDecoder().decode(
            MergeState.self, from: Data(#"{"tasks":[]}"#.utf8)
        )
        XCTAssertTrue(b.deleted.isEmpty)

        let c = try JSONDecoder().decode(
            MergeState.self, from: Data(#"{"tasks":[],"meta":{"tz":"Asia/Tokyo"}}"#.utf8)
        )
        XCTAssertEqual(c.meta["tz"], "Asia/Tokyo")
    }

    // MARK: - 辅助

    private static func task(
        id: String,
        title: String = "示例任务",
        parentId: String = "",
        updatedAt: Double = 1700000000000
    ) -> PlannerTask {
        let json = """
        {"id":"\(id)","title":"\(title)","note":"","date":"2026-01-01","time":"","important":false,
         "urgent":false,"done":false,"dropped":false,"createdAt":1700000000000,"doneAt":null,
         "repeat":"","doneDates":[],"skipDates":[],"remind":null,"parentId":"\(parentId)",
         "updatedAt":\(updatedAt)}
        """
        return try! JSONDecoder().decode(PlannerTask.self, from: Data(json.utf8))
    }
}
