import XCTest
@testable import Planner

// T-12 / M-18 备份导出导入契约测试。
// 与 ios/PlannerTests/Fixtures/backup_fixtures.json 逐字一致（oracle = 真实 src/lib/backup.js）。
// 生成命令：node ios/PlannerTests/Fixtures/generate_backup_fixtures.mjs

final class T12BackupServiceTests: XCTestCase {

    private func fixture() throws -> [String: Any] {
        guard let url = Bundle(for: T12BackupServiceTests.self)
            .url(forResource: "backup_fixtures", withExtension: "json") else {
            XCTFail("backup_fixtures.json 未随测试 target 打包")
            return [:]
        }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    private func str(_ v: Any?) -> String {
        guard let v, !(v is NSNull) else { return "<nil>" }
        if let s = v as? String { return s }
        if let b = v as? Bool { return b ? "true" : "false" }
        return "\(v)"
    }

    private func numStr(_ v: Any?) -> String {
        guard let v, !(v is NSNull) else { return "<nil>" }
        if let n = v as? NSNumber { return n.stringValue }
        return "\(v)"
    }

    private func num(_ v: Any?) -> Double? {
        guard let v, !(v is NSNull) else { return nil }
        return (v as? NSNumber)?.doubleValue
    }

    private func task(_ raw: [String: Any]) -> PlannerTask {
        PlannerTask.normalize(raw, now: 1_700_000_000_000)
    }

    /// 全量夹具逐项对比（8 组导出 × 中英 + 18 组导入 × 中英）。
    func testFullFixtureContrast() throws {
        let f = try fixture()
        let meta = f["meta"] as! [String: Any]
        XCTAssertEqual(meta["baseline"] as? String, "97a7c4c17602327a42d30110806a6a1e6fa0e798")
        XCTAssertEqual(meta["exportCases"] as? Int, 8)
        XCTAssertEqual(meta["importCases"] as? Int, 18)

        var checked = 0
        var failures: [String] = []
        func eq(_ label: String, _ e: String, _ a: String) {
            checked += 1
            if e != a { failures.append("\(label): expected=<<<\(e)>>> actual=<<<\(a)>>>") }
        }

        for raw in f["exportCases"] as! [[String: Any]] {
            let isEn = str(raw["lang"]) == "en"
            let tz = TimeZone(identifier: str(raw["tz"]))!
            let now = Date(timeIntervalSince1970: num(raw["fixedMs"])! / 1000)
            let tasks = (raw["tasks"] as! [[String: Any]]).map(task(_:))
            let e = raw["expected"] as! [String: Any]
            let tag = "export \(str(raw["lang"])) \(str(raw["name"]))"
            eq(tag + " fileName", str(e["fileName"]),
               BackupService.fileName(now: now, timeZone: tz))
            eq(tag + " text", str(e["text"]), BackupService.exportText(tasks, now: now))
            eq(tag + " shareTitle", str(e["shareTitle"]),
               BackupService.shareTitle(isEnglish: isEn))
            eq(tag + " directory", str(e["directory"]), "CACHE")
            eq(tag + " encoding", str(e["encoding"]), "utf8")
        }

        for raw in f["importCases"] as! [[String: Any]] {
            let isEn = str(raw["lang"]) == "en"
            let text = str(raw["fileText"])
            let current = Int(num(raw["currentCount"])!)
            let confirmed = raw["confirm"] as! Bool
            let e = raw["expected"] as! [String: Any]
            let tag = "import \(str(raw["lang"])) \(str(raw["name"]))"

            var replaced: Int?
            let result = BackupService.importBackup(
                text: text, currentCount: current, isEnglish: isEn, confirmed: confirmed,
                replaceAll: { replaced = $0.count })
            eq(tag + " ok", str(e["ok"]), result.ok ? "true" : "false")
            eq(tag + " message", str(e["message"]), result.message ?? "<nil>")
            eq(tag + " count", str(e["count"]), result.count.map(String.init) ?? "<nil>")
            eq(tag + " replacedCount", numStr(e["replacedCount"]),
               replaced.map(String.init) ?? "<nil>")

            let parsed = BackupService.parseBackup(text: text)
            let confirmText: String? = parsed.map {
                BackupService.confirmText(backupCount: $0.count, currentCount: current,
                                          isEnglish: isEn)
            }
            eq(tag + " confirmText", str(e["confirmText"]), confirmText ?? "<nil>")
        }

        XCTAssertTrue(failures.isEmpty, "\(failures.count) 项不一致，前 3 条：\(failures.prefix(3))")
        XCTAssertEqual(checked, 130, "夹具断言总数应与独立 harness 一致")
    }

    /// 导出载荷真的写到 Cache 目录，内容 == 分享文本，文件名带当天日期。
    func testSharePayloadWritesCacheFile() throws {
        let now = Date(timeIntervalSince1970: 1_794_640_646.123) // 2026-11-14T07:17:26.123Z
        let payload = try BackupService.makeSharePayload(
            [task(["id": "a1", "title": "开会"])], now: now,
            timeZone: TimeZone(identifier: "Asia/Shanghai")!, isEnglish: true)
        XCTAssertEqual(payload.fileName, "planner-backup-20261114.json")
        XCTAssertEqual(payload.title, "Reach List backup")
        XCTAssertNotNil(payload.cacheURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: payload.cacheURL!.path))
        XCTAssertEqual(try String(contentsOf: payload.cacheURL!, encoding: .utf8), payload.text)
        XCTAssertTrue(payload.text.contains("\"exportedAt\": \"2026-11-14T07:17:26.123Z\""))
        try? FileManager.default.removeItem(at: payload.cacheURL!)
    }

    /// JSON pretty：非空数组逐元素换行、空数组仍为 []、字符串里的 "/" 不转义。
    func testJSONPrettyFragmentRules() {
        let t = task([
            "id": "a1", "title": "带/斜杠", "note": "http://x/y",
            "doneDates": ["2026-11-14", "2026-11-15"], "skipDates": [],
        ])
        let text = BackupService.exportText([t], now: Date(timeIntervalSince1970: 1_794_640_646))
        XCTAssertTrue(text.contains("\"title\": \"带/斜杠\""))
        XCTAssertTrue(text.contains("\"note\": \"http://x/y\""))
        XCTAssertTrue(text.contains("\"doneDates\": [\n        \"2026-11-14\",\n        \"2026-11-15\"\n      ]"))
        XCTAssertTrue(text.contains("\"skipDates\": []"))
    }

    /// 中英确认文案与结果文案的复数分支。
    func testLocalizedImportMessages() {
        XCTAssertEqual(BackupService.confirmText(backupCount: 3, currentCount: 5, isEnglish: false),
                       "用备份里的 3 条任务替换当前的 5 条？")
        XCTAssertEqual(BackupService.confirmText(backupCount: 1, currentCount: 1, isEnglish: true),
                       "Replace your 1 task with the 1 task in the backup?")
        XCTAssertEqual(BackupService.confirmText(backupCount: 0, currentCount: 7, isEnglish: true),
                       "Replace your 7 tasks with the 0 tasks in the backup?")
        XCTAssertEqual(BackupService.restoredMessage(1, isEnglish: true), "Restored 1 task")
        XCTAssertEqual(BackupService.restoredMessage(0, isEnglish: true), "Restored 0 tasks")
        XCTAssertEqual(BackupService.invalidMessage(isEnglish: true),
                       "This isn't a valid backup file")
    }

    /// 导入接真实 TaskStore.replaceAll：全量替换并走 migrate + normalize（17 字段补全）。
    @MainActor
    func testImportThroughTaskStore() {
        let storage = InMemoryPlannerDataStorage()
        let store = TaskStore(storage: storage, now: { 1_700_000_000_000 }, makeID: { "t12" })
        store.replaceAll([["id": "old1", "title": "旧任务"], ["id": "old2", "title": "旧任务2"]])
        XCTAssertEqual(store.tasks.count, 2)

        let text = """
        {"version":1,"tasks":[{"id":"new1","title":"新任务","date":"2026-11-14"}]}
        """
        var called = 0
        let result = BackupService.importBackup(
            text: text, currentCount: store.tasks.count, isEnglish: false, confirmed: true,
            replaceAll: { raw in called += 1; store.replaceAll(raw) })
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.message, "已恢复 1 条任务")
        XCTAssertEqual(called, 1)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.id, "new1")
        XCTAssertEqual(store.tasks.first?.time, "", "normalize 补齐了 17 字段")
        XCTAssertEqual(store.tasks.first?.remind, nil)
    }

    /// 无效备份 / 用户取消都不得改动 store。
    @MainActor
    func testInvalidOrCancelledImportDoesNotReplace() {
        let storage = InMemoryPlannerDataStorage()
        let store = TaskStore(storage: storage, now: { 1_700_000_000_000 }, makeID: { "t12" })
        store.replaceAll([["id": "keep", "title": "保留"]])
        for (text, confirmed) in [("{oops", true), ("{\"tasks\":[]}", false)] {
            let r = BackupService.importBackup(
                text: text, currentCount: 1, isEnglish: false, confirmed: confirmed,
                replaceAll: { store.replaceAll($0) })
            XCTAssertFalse(r.ok)
        }
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.id, "keep")
    }
}
