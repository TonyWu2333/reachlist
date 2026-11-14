import XCTest
import Foundation
@testable import Planner

// T-09 / M-02 TaskStore 契约测试。
// 期望值取自 baseline_commit 97a7c4c 的 src/lib/store.js（真实源码 oracle），
// 与 ios/PlannerTests/Fixtures/store_fixtures.json 逐字一致。
//
// 两层验证：
// 1) 本文件的夹具测试：21 组操作序列 × 6 项状态 = 126 项，逐字对比 oracle。
//    生成器：node ios/PlannerTests/Fixtures/generate_store_fixtures.mjs
//    （/tmp 运行副本只替换 5 处环境依赖，store.js 的函数体逐字未改）
// 2) 独立 swiftc harness（不依赖真机）跑同一份夹具：/tmp/t09_harness/verify
//
// 另有 250ms 防抖、settings 七字段、损坏数据保护等 UI / 存储专项。

final class T09TaskStoreTests: XCTestCase {

    private var fixedNow: Double {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 11; dc.day = 13; dc.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: dc)!.timeIntervalSince1970 * 1000
    }

    private final class IDBox {
        var n = 0
        func next() -> String { n += 1; return "t09-\(n)" }
    }

    private func jsonData(_ v: Any) -> Data { try! JSONSerialization.data(withJSONObject: v) }
    private func jsonString(_ v: Any) -> String { String(data: jsonData(v), encoding: .utf8)! }

    private func fragments(_ v: Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(data: try! encoder.encode(v), encoding: .utf8)!
    }

    private func sortedDeleted(_ d: [String: Double]) -> String {
        "{" + d.keys.sorted().map { "\(fragments($0)):\(fragments(d[$0]!))" }.joined(separator: ",") + "}"
    }

    private func taskList(_ tasks: [PlannerTask]) -> String {
        "[" + tasks.map { $0.jsJSONString() }.joined(separator: ",") + "]"
    }

    /// 重演一组 ops，返回与生成器 expect 同构的快照。
    private func run(_ c: [String: Any]) -> [String: Any] {
        let setup = c["setup"] as! [String: Any]
        let dataValue: String? = {
            guard let v = setup["data"] else { return nil }
            return v as? String ?? jsonString(v)
        }()
        let settingsValue: String? = {
            guard let v = setup["settings"] else { return nil }
            return v as? String ?? jsonString(v)
        }()
        let storage = InMemoryPlannerDataStorage(data: dataValue, settings: settingsValue)
        let ids = IDBox()
        let now = fixedNow
        let core = TaskStoreCore(storage: storage, now: { now }, makeID: { ids.next() })
        core.start()

        var undos: [() -> Void] = []
        for op in c["ops"] as! [[String: Any]] {
            switch op["op"] as! String {
            case "add": core.addTask(op["fields"] as! [String: Any])
            case "update": core.updateTask(op["id"] as! String, patch: op["patch"] as! [String: Any])
            case "drop": undos.append(core.dropTask(op["id"] as! String))
            case "toggle": core.toggleDone(op["id"] as! String, occ: op["occ"] as! String)
            case "skip": undos.append(core.skipOccurrence(op["id"] as! String, occ: op["occ"] as! String))
            case "remove": undos.append(core.removeTask(op["id"] as! String))
            case "addSub":
                core.addSubtask(parentId: op["parentId"] as! String, fields: op["fields"] as! [String: Any])
            case "toggleSub":
                core.toggleSubtask(parentId: op["parentId"] as! String,
                                   childId: op["childId"] as! String, occ: op["occ"] as! String)
            case "replaceAll": core.replaceAll(op["tasks"] as! [[String: Any]])
            case "flush": core.flush()
            case "payload": _ = core.syncPayload()
            case "remote":
                let state = op["state"] as! [String: Any]
                core.applyRemote(try! JSONDecoder().decode(MergeState.self, from: jsonData(state)))
            case "settings": core.updateSettings(op["patch"] as! [String: Any])
            case "undo": undos.popLast()?()
            default: XCTFail("未知 op：\(op["op"] ?? "")")
            }
        }
        return [
            "tasks": taskList(core.tasks),
            "deleted": sortedDeleted(core.deleted),
            "settings": core.settings.jsJSONString,
            "savedData": storage.writes.last(where: { $0.key == "planner-data" })?.value ?? NSNull(),
            "savedSettings": storage.writes.last(where: { $0.key == "planner-settings" })?.value ?? NSNull(),
            "corruptCount": storage.corrupt.count,
        ]
    }

    private func normalize(_ v: Any) -> String {
        if v is NSNull { return "" }
        if let n = v as? Int { return String(n) }
        if let n = v as? NSNumber { return String(n.intValue) }
        if let s = v as? String { return s }
        return ""
    }

    // MARK: 全量黄金夹具

    func testFullFixtureContrast() throws {
        guard let url = Bundle(for: T09TaskStoreTests.self)
            .url(forResource: "store_fixtures", withExtension: "json") else {
            XCTFail("store_fixtures.json 未随测试 target 打包")
            return
        }
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let cases = root["cases"] as! [[String: Any]]
        let meta = root["meta"] as! [String: Any]
        XCTAssertEqual(meta["oracle_changed_lines"] as? Int, 5, "运行副本只改环境依赖")

        var checked = 0
        var failures: [String] = []
        for c in cases {
            let name = c["name"] as! String
            let expect = c["expect"] as! [String: Any]
            let actual = run(c)
            for key in ["tasks", "deleted", "settings", "savedData", "savedSettings", "corruptCount"] {
                checked += 1
                let e = normalize(expect[key] ?? NSNull()), a = normalize(actual[key] ?? NSNull())
                if e != a { failures.append("\(name)/\(key): expected=\(e.prefix(300)) actual=\(a.prefix(300))") }
            }
        }
        XCTAssertEqual(cases.count, 21)
        XCTAssertTrue(failures.isEmpty,
                      "\(failures.count)/\(checked) 项不一致：\n" + failures.prefix(8).joined(separator: "\n"))
    }

    // MARK: 状态机专项

    func testStampOnlyChangesWhenSigDiffers() {
        let storage = InMemoryPlannerDataStorage()
        let now = fixedNow
        let ids = IDBox()
        let core = TaskStoreCore(storage: storage, now: { now }, makeID: { ids.next() })
        core.start()
        _ = core.addTask(["title": "A"])
        core.flush()
        // JS 的 addTask 返回 state.tasks 里的对象引用，stamp 会改到它；
        // Swift 的 PlannerTask 是值类型，返回值是快照，故断言 core.tasks 里的当前值。
        XCTAssertEqual(core.tasks[0].updatedAt, now + 1, "首次 stamp：max(now, createdAt+1)")
        core.flush()
        XCTAssertEqual(core.tasks[0].updatedAt, now + 1, "sig 未变不重复更新 updatedAt")
        core.updateTask("t09-1", patch: ["title": "B"])
        core.flush()
        XCTAssertEqual(core.tasks[0].updatedAt, now + 2, "sig 变化才递增")
    }

    func testTombstoneAndUndoDelete() {
        let storage = InMemoryPlannerDataStorage()
        let now = fixedNow
        let ids = IDBox()
        let core = TaskStoreCore(storage: storage, now: { now }, makeID: { ids.next() })
        core.start()
        core.addTask(["title": "A"])
        core.flush()
        let undo = core.removeTask("t09-1")
        core.flush()
        XCTAssertEqual(core.deleted["t09-1"], now, "删除生成墓碑")
        undo()
        core.flush()
        XCTAssertNil(core.deleted["t09-1"], "撤销删除清除墓碑")
        XCTAssertEqual(core.tasks.count, 1)
    }

    func testSettingsSevenFieldsAndLangFallback() {
        let storage = InMemoryPlannerDataStorage(settings: "{\"showLunar\":false,\"defaultRemind\":30}")
        let core = TaskStoreCore(storage: storage, now: { self.fixedNow }, makeID: { "x" })
        core.start()
        XCTAssertEqual(core.settings.lang, "auto", "旧设置缺 lang 回退 auto（A-05）")
        XCTAssertFalse(core.settings.showLunar)
        XCTAssertEqual(core.settings.defaultRemind, 30)
        core.updateSettings(["lang": "en", "syncOn": true])
        XCTAssertEqual(core.settings.lang, "en")
        XCTAssertTrue(core.settings.syncOn)
        XCTAssertTrue(storage.writes.contains { $0.key == "planner-settings" }, "settings 变化即存")
    }

    func testCorruptDataIsArchivedNotOverwritten() {
        let storage = InMemoryPlannerDataStorage(data: "__NOT_JSON__")
        let core = TaskStoreCore(storage: storage, now: { self.fixedNow }, makeID: { "x" })
        core.start()
        XCTAssertEqual(storage.corrupt.count, 1, "损坏原文另存")
        XCTAssertEqual(storage.corrupt.first, "__NOT_JSON__")
        XCTAssertTrue(core.tasks.isEmpty, "回退空数据")
        // storage.js:17 只「另存」原文，不覆盖 planner-data 键；下一次 save 才覆盖。
        XCTAssertEqual(storage.read(key: "planner-data"), "__NOT_JSON__", "损坏原文未被覆盖")
        XCTAssertTrue(storage.writes.contains { $0.key.hasPrefix("planner-data-corrupt-") },
                      "原文已另存到带时间戳的键")
    }

    func testApplyRemoteMergesWithoutSecondMergeImplementation() {
        let storage = InMemoryPlannerDataStorage()
        let now = fixedNow
        let core = TaskStoreCore(storage: storage, now: { now }, makeID: { "x" })
        core.start()
        let remote = MergeState(
            tasks: [PlannerTask.normalize(["id": "r1", "title": "来自服务器", "updatedAt": 5000])],
            deleted: [:])
        core.applyRemote(remote)
        XCTAssertEqual(core.tasks.count, 1)
        XCTAssertEqual(core.tasks[0].title, "来自服务器")
        XCTAssertTrue(storage.writes.contains { $0.key == "planner-data" }, "applyRemote 立即落盘")
    }

    // MARK: UI 包装：250ms 防抖（A-03）

    @MainActor
    func testDebouncedFlushWritesOnceForConsecutiveChanges() async throws {
        let storage = InMemoryPlannerDataStorage()
        let now = fixedNow
        let ids = IDBox()
        let store = TaskStore(storage: storage, now: { now }, makeID: { ids.next() })
        store.addTask(["title": "A"])
        store.addTask(["title": "B"])
        store.addTask(["title": "C"])
        XCTAssertEqual(storage.writes.filter { $0.key == "planner-data" }.count, 0, "250ms 内不落盘")
        XCTAssertEqual(store.tasks.count, 3, "@Observable 快照即时刷新")
        try await Task.sleep(nanoseconds: 400_000_000)
        let writes = storage.writes.filter { $0.key == "planner-data" }
        XCTAssertEqual(writes.count, 1, "连续改动只写一次")
        XCTAssertTrue(writes.first?.value.contains("\"title\":\"C\"") == true)
        XCTAssertEqual(store.core.tasks.count, 3)
    }

    @MainActor
    func testFlushNowCancelsPendingDebounce() async throws {
        let storage = InMemoryPlannerDataStorage()
        let now = fixedNow
        let ids = IDBox()
        let store = TaskStore(storage: storage, now: { now }, makeID: { ids.next() })
        store.addTask(["title": "A"])
        store.flushNow()
        XCTAssertEqual(storage.writes.filter { $0.key == "planner-data" }.count, 1)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(storage.writes.filter { $0.key == "planner-data" }.count, 1,
                       "flushNow 后不再重复写")
    }
}
