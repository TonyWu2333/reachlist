import XCTest
import Foundation
@testable import Planner

// T-10 真机端到端联调（OPEN-13=A / A-40 / VERIFY-03）。
//
// 服务器：本机 `PLANNER_TOKEN=exampletoken0123456789 DATA_FILE=/tmp/t10_server_state.json
//          PORT=18787 node server/server.js`（临时实例，不碰真实数据，server.js 零改动）。
// 裸 IP 明文 HTTP 在 iOS 27.3 beta 上不受 ATS -1022 拦截（§7.2.2 v0.7 实测），
// 故端到端不需要 ATS 例外；ATS 例外的最小键名由 testATSMinimalExceptionKey 单独验证。
//
// 这些用例属于「跨端联调」而非纯单元测试：server 未启动时会 XCTSkip 并如实说明，
// 不伪造通过结果。

@MainActor
final class T10EndToEndTests: XCTestCase {

    private let base = "http://127.0.0.1:18787"
    private let token = "exampletoken0123456789"

    private final class Clock {
        private var t: Double = 1794542400000
        func now() -> Double { t += 1000; return t }   // 递进时钟：墓碑必须晚于任务戳记
    }

    private final class IDBox {
        /// 每次运行唯一前缀：本地 server 是临时实例但可能连续跑多轮，
        /// 固定 id 会让上一轮残留数据参与合并，影响墓碑 / updatedAt 裁决。
        let prefix = "e2e-" + UUID().uuidString.prefix(8).lowercased()
        private var n = 0
        func next() -> String { n += 1; return "\(prefix)-ios-\(n)" }
        var webId: String { "\(prefix)-web" }
    }

    private func rawRequest(_ path: String, method: String = "GET", body: Data? = nil) async throws -> (Int, Data) {
        var req = URLRequest(url: URL(string: base + path)!, timeoutInterval: 10)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = body
        }
        let (data, res) = try await URLSession.shared.data(for: req)
        return ((res as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    private func serverState() async throws -> [String: Any] {
        let (code, data) = try await rawRequest("/api/state")
        XCTAssertEqual(code, 200, "GET /api/state")
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func taskJSON(_ o: [String: Any]) -> [String: Any] {
        var t: [String: Any] = [
            "id": "x", "title": "x", "note": "", "date": "2026-11-13", "time": "",
            "important": false, "urgent": false, "done": false, "dropped": false,
            "createdAt": 1700000000000, "doneAt": NSNull(), "repeat": "",
            "doneDates": [], "skipDates": [], "remind": NSNull(),
            "parentId": "", "updatedAt": 1700000000000,
        ]
        for (k, v) in o { t[k] = v }
        return t
    }

    private func makeClient(_ clock: Clock, _ ids: IDBox) -> (TaskStore, SyncClient) {
        let storage = InMemoryPlannerDataStorage()
        // store.js:addTask 强制用 uid() 覆盖 fields.id，故 id 由 makeID 决定，测试取返回值。
        let store = TaskStore(storage: storage, now: { clock.now() }, makeID: { ids.next() })
        store.updateSettings(["syncOn": true, "syncCode": "\(base)#\(token)"])
        let now = clock.now()
        let client = SyncClient(store: store, transport: URLSessionSyncTransport(),
                                now: { now }, timeZone: { "Asia/Shanghai" })
        client.setActive(false)   // 端到端只测 HTTP 协议与合并；长轮询由 Mock 契约测试覆盖
        return (store, client)
    }

    /// 覆盖：iOS 写入→服务器可见；另一端写入→iOS 拉取；删除墓碑；撤销删除复活；
    /// 重复任务按天完成；父子任务连带删除。
    func testEndToEndWithLocalServer() async throws {
        let health = try? await rawRequest("/health")
        try XCTSkipUnless(health?.0 == 200,
                          "本地临时 server 未启动（OPEN-13=A，仅 T-10/T-18/A-40 验收用）")

        let clock = Clock()
        let ids = IDBox()
        let (store, client) = makeClient(clock, ids)
        defer { client.stop() }

        // 1) iOS 写入 → 服务器可见
        let iosTask = store.addTask(["title": "iOS 写入", "date": "2026-11-13"])
        let iosId = iosTask.id
        await client.syncNow()
        XCTAssertEqual(client.state.error, "", "首次同步无错误")
        var state = try await serverState()
        var tasks = state["tasks"] as? [[String: Any]] ?? []
        let serverIos = tasks.first { ($0["id"] as? String) == iosId }
        XCTAssertEqual(serverIos?["title"] as? String, "iOS 写入", "服务器收到 iOS 写入的任务")
        XCTAssertEqual(state["meta"] as? [String: String] ?? [:], ["tz": "Asia/Shanghai"],
                       "meta.tz 已上报")

        // 2) 另一端（Web / Agent CLI 等效）写入 → iOS 拉取
        let webId = ids.webId
        let webBody: [String: Any] = [
            "tasks": [taskJSON(["id": webId, "title": "Web 写入", "updatedAt": 1794542500000])],
            "deleted": [:],
        ]
        let webData = try JSONSerialization.data(withJSONObject: webBody)
        let (webStatus, _) = try await rawRequest("/api/sync", method: "POST", body: webData)
        XCTAssertEqual(webStatus, 200, "另一端写入")
        await client.syncNow()
        XCTAssertTrue(store.tasks.contains { $0.id == webId && $0.title == "Web 写入" },
                      "iOS 拉到另一端写入的任务（合并结果一致）")

        // 3) 删除 → 墓碑；撤销删除 → 复活并清墓碑
        let undo = store.removeTask(iosId)
        await client.syncNow()
        state = try await serverState()
        let deleted = state["deleted"] as? [String: Any] ?? [:]
        XCTAssertNotNil(deleted[iosId], "服务器记录了墓碑")
        undo()
        await client.syncNow()
        state = try await serverState()
        tasks = state["tasks"] as? [[String: Any]] ?? []
        XCTAssertTrue(tasks.contains { ($0["id"] as? String) == iosId }, "撤销删除后任务复活")
        XCTAssertNil((state["deleted"] as? [String: Any] ?? [:])[iosId], "墓碑已清除")

        // 4) 重复任务按天打勾
        let repTask = store.addTask(["title": "每天喝水", "date": "2026-11-01", "repeat": "d1"])
        store.toggleDone(repTask.id, occ: "2026-11-14")
        await client.syncNow()
        state = try await serverState()
        tasks = state["tasks"] as? [[String: Any]] ?? []
        let rep = tasks.first { ($0["id"] as? String) == repTask.id }
        XCTAssertTrue((rep?["doneDates"] as? [String] ?? []).contains("2026-11-14"),
                      "重复任务按天完成状态同步到服务器")

        // 5) 父子任务连带删除
        let parent = store.addTask(["title": "父任务"])
        _ = store.addSubtask(parentId: parent.id, fields: ["title": "子任务"])
        _ = store.removeTask(parent.id)
        await client.syncNow()
        state = try await serverState()
        tasks = state["tasks"] as? [[String: Any]] ?? []
        XCTAssertFalse(tasks.contains { ($0["parentId"] as? String) == parent.id },
                       "父任务删除时子任务一并丢弃")
    }

    /// VERIFY-03：确认 `NSExceptionDomains.<domain>.NSExceptionAllowsInsecureHTTPLoads = true`
    /// 是让域名明文 HTTP 放行的最小配置。对照基线：§7.2.2 v0.7 无例外时 `http://example.com`
    /// 返回 NSURLErrorDomain -1022。
    func testATSMinimalExceptionKey() async throws {
        let req = URLRequest(url: URL(string: "http://example.com")!, timeoutInterval: 10)
        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            let code = (res as? HTTPURLResponse)?.statusCode ?? 0
            XCTAssertNotEqual(code, 0)
            print("VERIFY-03: http://example.com -> HTTP \(code), \(data.count) bytes")
        } catch {
            let ns = error as NSError
            XCTFail("最小 ATS 例外未放行域名 HTTP：\(ns.domain) \(ns.code) \(ns.localizedDescription)")
        }
    }
}
