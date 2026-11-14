import XCTest
import Foundation
@testable import Planner

// T-10 / M-08 + M-09 同步客户端契约测试。
// 期望值取自 baseline_commit 97a7c4c 的 src/lib/sync.js / src/lib/i18n.js / i18n-en.js，
// 与 ios/PlannerTests/Fixtures/sync_fixtures.json 逐字一致。
// 生成命令：node ios/PlannerTests/Fixtures/generate_sync_fixtures.mjs

@MainActor
final class T10SyncClientTests: XCTestCase {

    private let code = "http://127.0.0.1:18787#abcdefghijklmnop"

    private func makeStore(lang: String = "zh", syncOn: Bool = true) -> (TaskStore, InMemoryPlannerDataStorage) {
        let storage = InMemoryPlannerDataStorage()
        let store = TaskStore(storage: storage, now: { 1794542400000 }, makeID: { "t10-1" })
        store.updateSettings([
            "lang": lang, "syncOn": syncOn, "syncCode": code,
        ])
        return (store, storage)
    }

    private func serverBody(tasks: String = "[]", rev: Int = 1) -> Data {
        "{\"tasks\":\(tasks),\"deleted\":{},\"meta\":{},\"rev\":\(rev)}".data(using: .utf8)!
    }

    private func makeClient(
        _ store: TaskStore, _ transport: MockSyncTransport
    ) -> SyncClient {
        SyncClient(store: store, transport: transport, now: { 1794542400000 },
                   timeZone: { "Asia/Shanghai" })
    }

    // MARK: 全量黄金夹具（parseCode / 文案 / 载荷编码）

    func testFullFixtureContrast() throws {
        guard let url = Bundle(for: T10SyncClientTests.self)
            .url(forResource: "sync_fixtures", withExtension: "json") else {
            XCTFail("sync_fixtures.json 未随测试 target 打包")
            return
        }
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let meta = root["meta"] as! [String: Any]
        XCTAssertEqual(meta["oracle_changed_lines"] as? Int, 3)

        var checked = 0
        var failures: [String] = []

        for c in root["parseCode"] as! [[String: Any]] {
            checked += 1
            let text = c["code"] as? String
            let got = SyncCode.parse(text)
            let e = c["expected"] as? [String: Any]
            let expected = e.map { ConnectionCode(url: $0["url"] as! String, token: $0["token"] as! String) }
            if got != expected { failures.append("parseCode \(text ?? "nil"): \(String(describing: got)) != \(String(describing: expected))") }
        }

        for s in root["strings"] as! [[String: Any]] {
            let key = s["key"] as! String
            for lang in ["zh", "en"] {
                checked += 1
                let expected = s[lang] as! String
                let got = resolve(key, isEnglish: lang == "en")
                if got != expected { failures.append("string \(key)/\(lang): \(got) != \(expected)") }
            }
        }

        for p in root["payloads"] as! [[String: Any]] {
            checked += 1
            let tasks = try JSONDecoder().decode([PlannerTask].self,
                                                 from: try JSONSerialization.data(withJSONObject: p["tasks"]!))
            let deleted = p["deleted"] as! [String: Double]
            let data = SyncPayloadCodec.encode(MergeState(tasks: tasks, deleted: deleted),
                                              tz: p["tz"] as! String)
            let got = String(data: data, encoding: .utf8)!
            let expected = p["expected"] as! String
            if got != expected { failures.append("payload: \(got) != \(expected)") }
        }

        XCTAssertTrue(failures.isEmpty,
                      "\(failures.count)/\(checked) 项不一致：\n" + failures.prefix(8).joined(separator: "\n"))
    }

    private func resolve(_ key: String, isEnglish: Bool) -> String {
        switch key {
        case "令牌不对": return SyncStrings.wrongToken(isEnglish: isEnglish)
        case "服务器返回 {code}": return SyncStrings.serverReturned(500, isEnglish: isEnglish)
        case "连不上服务器": return SyncStrings.cannotReach(isEnglish: isEnglish)
        case "连接码格式不对：应该是 地址#令牌": return SyncStrings.invalidCode(isEnglish: isEnglish)
        case "正在同步…": return SyncStrings.syncing(isEnglish: isEnglish)
        case "还没同步过": return SyncStrings.neverSynced(isEnglish: isEnglish)
        case "同步完成": return SyncStrings.syncComplete(isEnglish: isEnglish)
        default: return ""
        }
    }

    // MARK: 默认纯本地（§4.1.1 / F-12）

    func testSyncOffSendsNoRequest() async {
        let (store, _) = makeStore(syncOn: false)
        let transport = MockSyncTransport()
        let client = makeClient(store, transport)
        await client.syncNow()
        XCTAssertTrue(transport.requests.isEmpty, "syncOn=false 时一个网络请求都不发")
        XCTAssertNil(client.configuration())
    }

    // MARK: syncNow 主流程

    func testSyncNowHappyPath() async {
        let (store, _) = makeStore()
        let transport = MockSyncTransport(responses: [
            SyncResponse(status: 200, data: serverBody(rev: 7)),
        ])
        let client = makeClient(store, transport)
        await client.syncNow()

        XCTAssertEqual(transport.requests.count, 1)
        let req = transport.requests[0]
        XCTAssertEqual(req.url.absoluteString, "http://127.0.0.1:18787/api/sync")
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.token, "abcdefghijklmnop")
        XCTAssertEqual(req.timeout, 15)
        let body = String(data: req.body!, encoding: .utf8)!
        XCTAssertTrue(body.hasPrefix("{\"tasks\":["), "载荷键序 tasks 优先")
        XCTAssertTrue(body.contains("\"meta\":{\"tz\":\"Asia/Shanghai\"}"), "上报本机时区（A-41）")
        XCTAssertFalse(body.contains("\\/"), "斜杠不得转义（T-09 修复的 T-04 缺陷）")
        XCTAssertEqual(client.state.at, 1794542400000)
        XCTAssertEqual(client.state.error, "")
        XCTAssertFalse(client.state.busy)
    }

    func testErrorMappingChineseAndEnglish() async {
        for (status, zh, en) in [(401, "令牌不对", "Wrong token"), (500, "服务器返回 500", "Server returned 500")] {
            for (lang, expected) in [("zh", zh), ("en", en)] {
                let (store, _) = makeStore(lang: lang)
                let transport = MockSyncTransport(responses: [SyncResponse(status: status, data: Data())])
                let client = makeClient(store, transport)
                await client.syncNow()
                XCTAssertEqual(client.state.error, expected, "status=\(status) lang=\(lang)")
            }
        }
    }

    func testNetworkErrorMapping() async {
        for (lang, expected) in [("zh", "连不上服务器"), ("en", "Can't reach the server")] {
            let (store, _) = makeStore(lang: lang)
            let transport = MockSyncTransport(errors: [
                NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost),
            ])
            let client = makeClient(store, transport)
            await client.syncNow()
            XCTAssertEqual(client.state.error, expected)
        }
    }

    func testConsecutiveSyncNow() async {
        let (store, _) = makeStore()
        let transport = MockSyncTransport(responses: [
            SyncResponse(status: 200, data: serverBody(rev: 1)),
            SyncResponse(status: 200, data: serverBody(rev: 2)),
        ])
        let client = makeClient(store, transport)
        await client.syncNow()
        await client.syncNow()
        // 成功同步会启动长轮询（GET /api/wait），故总请求数含 GET；这里只数 POST。
        let posts = transport.requests.filter { $0.method == "POST" }
        XCTAssertEqual(posts.count, 2, "连续两次同步各发一个 POST")
        XCTAssertFalse(client.state.busy)
        XCTAssertEqual(client.state.error, "")
        client.stop()
    }

    func testLocalChangeDoesNotSyncImmediately() async {
        let (store, _) = makeStore()
        let transport = MockSyncTransport()
        let client = makeClient(store, transport)
        client.localChanged()
        XCTAssertTrue(transport.requests.isEmpty, "本地改动有 2 秒防抖")
        client.stop()
    }

    // MARK: 长轮询

    func testLongPollRevChangeTriggersSync() async {
        let (store, _) = makeStore()
        let waitBody = "{\"rev\":9}".data(using: .utf8)!
        let transport = MockSyncTransport(responses: [
            SyncResponse(status: 200, data: serverBody(rev: 1)),  // 首次 syncNow
            SyncResponse(status: 200, data: waitBody),             // /api/wait 返回新 rev
            SyncResponse(status: 200, data: serverBody(rev: 9)),  // 触发的第二次 syncNow
        ])
        let client = makeClient(store, transport)
        await client.syncNow()                                    // 内部启动 watch
        try? await Task.sleep(nanoseconds: 250_000_000)
        client.stop()
        XCTAssertTrue(transport.requests.contains { $0.url.absoluteString.contains("/api/wait?rev=1") },
                      "长轮询带 rev 参数")
        XCTAssertTrue(transport.requests.filter { $0.method == "POST" }.count >= 2,
                      "rev 变化触发再次同步")
    }
}
