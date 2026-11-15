import XCTest
import Foundation
import SwiftUI
import UIKit
@testable import Planner

// T-18 接线集成测试：UI 适配层（CalendarDataStore）→ 真实 TaskStore → 本地临时 server。
//
// T-10 的端到端用例直接构造 TaskStore + SyncClient，验证的是协议层；本文件验证 T-18 新增的
// 「6 个页面共用的 UI 数据源」这条链路：UI 操作是否真的落盘 / 生成墓碑 / 撤销复活、
// 远端合并后 UI 快照是否刷新、另一端写入后 iOS 是否可见。
//
// server 按 OPEN-13=A：本机 `PLANNER_TOKEN=exampletoken0123456789
// DATA_FILE=/tmp/t19_server_state.json PORT=18787 node server/server.js`，不碰真实数据。
// 未启动时 XCTSkip 并如实说明，不伪造通过。

@MainActor
final class T18IntegrationTests: XCTestCase {

    private let base = "http://127.0.0.1:18787"
    private let token = "exampletoken0123456789"

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> (Int, Data) {
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

    /// A-03 / A-04 / A-07：UI 操作经 TaskStore 落盘，250ms 防抖、墓碑、撤销复活。
    func testUIAdapterPersistsThroughTaskStore() async throws {
        let storage = InMemoryPlannerDataStorage()
        let store = CalendarDataStore(settingsStorage: storage)
        XCTAssertTrue(store.tasks.isEmpty, "真实 App 首次启动为空数据（不再注入内存样例）")

        let t = store.add(fields: ["title": "T-18 落盘链路", "date": "2026-11-14", "time": "09:00"])
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertNil(storage.values["planner-data"], "250ms 防抖内不应落盘")

        try await Task.sleep(nanoseconds: 400_000_000)
        let raw = storage.values["planner-data"] ?? ""
        let obj = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
        XCTAssertEqual(obj["version"] as? Int, 1)
        XCTAssertEqual((obj["tasks"] as? [Any])?.count, 1)
        XCTAssertFalse(raw.contains("\"lang\""), "lang 只存 planner-settings（A-45）")

        store.settings.lang = .en
        let settingsRaw = storage.values["planner-settings"] ?? ""
        XCTAssertTrue(settingsRaw.contains("\"lang\":\"en\""))
        XCTAssertTrue(settingsRaw.contains("\"syncCode\""))

        let undo = store.remove(id: t.id)
        XCTAssertTrue(store.tasks.isEmpty)
        try await Task.sleep(nanoseconds: 400_000_000)
        let deletedRaw = storage.values["planner-data"] ?? ""
        let dObj = try JSONSerialization.jsonObject(with: Data(deletedRaw.utf8)) as! [String: Any]
        XCTAssertNotNil((dObj["deleted"] as? [String: Any])?[t.id], "删除应生成墓碑")

        undo()
        XCTAssertEqual(store.tasks.count, 1)
        try await Task.sleep(nanoseconds: 400_000_000)
        let revivedRaw = storage.values["planner-data"] ?? ""
        let rObj = try JSONSerialization.jsonObject(with: Data(revivedRaw.utf8)) as! [String: Any]
        XCTAssertNil((rObj["deleted"] as? [String: Any])?[t.id], "撤销应清除墓碑")
    }

    /// A-40：另一端写入 → iOS 拉取；iOS UI 写入 → 服务器可见。
    func testUIAdapterTwoWaySyncWithLocalServer() async throws {
        do {
            let (code, _) = try await request("/health")
            XCTAssertEqual(code, 200)
        } catch {
            throw XCTSkip("本地临时 server 未启动（OPEN-13=A）：\(error)")
        }

        let prefix = "t18-" + UUID().uuidString.prefix(8).lowercased()
        let webId = prefix + "-web"
        let webTask: [String: Any] = [
            "id": webId, "title": "T-18 Web 写入", "note": "", "date": "2026-11-14", "time": "",
            "important": false, "urgent": false, "done": false, "dropped": false,
            "createdAt": 1_700_000_000_000, "doneAt": NSNull(), "repeat": "",
            "doneDates": [], "skipDates": [], "remind": NSNull(), "parentId": "",
            "updatedAt": 1_700_000_000_000,
        ]
        let postBody = try JSONSerialization.data(withJSONObject: [
            "tasks": [webTask], "deleted": [:], "meta": ["tz": "Asia/Shanghai"],
        ])
        let (postCode, _) = try await request("/api/sync", method: "POST", body: postBody)
        XCTAssertEqual(postCode, 200)

        let storage = InMemoryPlannerDataStorage()
        let store = CalendarDataStore(settingsStorage: storage)
        store.settings.syncOn = true
        store.settings.syncCode = "\(base)#\(token)"
        let client = SyncClient(store: store.taskStore, transport: URLSessionSyncTransport(),
                                timeZone: { "Asia/Shanghai" })
        client.setActive(false)   // 只测一次同步，不启动长轮询

        await client.syncNow()
        store.refreshFromStore()
        XCTAssertTrue(store.tasks.contains { $0.id == webId }, "另一端写入的任务应出现在 UI 快照")

        let local = store.add(fields: ["title": "T-18 iOS 写入", "date": "2026-11-14"])
        await client.syncNow()
        let (code, data) = try await request("/api/state")
        XCTAssertEqual(code, 200)
        let state = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let tasks = state["tasks"] as? [[String: Any]] ?? []
        XCTAssertTrue(tasks.contains { ($0["id"] as? String) == local.id }, "iOS 写入应同步到服务器")
        XCTAssertTrue(tasks.contains { ($0["title"] as? String) == "T-18 iOS 写入" })
        XCTAssertNil(state["lang"], "同步载荷不含语言偏好")
    }

    // MARK: sheet 环境注入回归（真机崩溃报告 2026-11-14 19:00 / 19:09 / 19:27）
    //
    // 崩溃栈：_assertionFailure → EnvironmentObject.error() → wrappedValue.getter
    //        → SearchSheetView.results / QuickAddSheet.submit，即 sheet 内容读
    //        @EnvironmentObject 时找不到 CalendarDataStore，SwiftUI 直接 SIGTRAP。
    // 之前 ZZVisualProbe 是「直接渲染 sheet 视图并手动注入环境」，绕过了系统呈现路径，
    // 所以 6 张 PNG 全过但真机一点就崩。这里改用 .sheet(isPresented: .constant(true))
    // 让系统真正呈现，并断言 presentedViewController 非 nil，避免「根本没呈现」的假通过。

    /// 与 AppRootView 结构一致：environmentObject 挂在 TabView 链上，sheet 内容单独注入。
    @MainActor
    private struct SheetHost<Sheet: View>: View {
        @StateObject private var store = CalendarDataStore(
            settingsStorage: InMemoryPlannerDataStorage(), seedSample: true)
        @StateObject private var toast = ToastCenter()
        let language: String
        let sheet: (CalendarDataStore, ToastCenter) -> Sheet

        var body: some View {
            TabView {
                Text("host").tabItem { Text("host") }
            }
            .environmentObject(store)
            .environmentObject(toast)
            .environment(\.appLanguage, language)
            .sheet(isPresented: .constant(true)) {
                sheet(store, toast)
                    .environmentObject(store)
                    .environmentObject(toast)
                    .environment(\.appLanguage, language)
            }
        }
    }

    private func assertSheetPresents<Sheet: View>(
        _ host: SheetHost<Sheet>, label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let controller = UIHostingController(rootView: host)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.presentedViewController,
                        "\(label)：sheet 未被系统呈现，无法证明其内容 body 已求值",
                        file: file, line: line)
        print("SHEET-PRESENTED \(label) \(type(of: controller.presentedViewController))")
        // 再跑一次 runloop：若 sheet 内容里 @EnvironmentObject 解析失败，会在 body 求值时 SIGTRAP。
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(true, "\(label)：sheet 呈现后内容求值完成，未触发 EnvironmentObject.error()")
    }

    func testQuickAddSheetPresentsWithoutEnvironmentCrash() throws {
        try assertSheetPresents(
            SheetHost(language: "en") { _, _ in QuickAddSheet(defaults: .empty) },
            label: "quickAdd")
    }

    func testSearchSheetPresentsWithoutEnvironmentCrash() throws {
        try assertSheetPresents(
            SheetHost(language: "en") { _, _ in SearchSheetView() },
            label: "search")
    }

    func testDetailSheetPresentsWithoutEnvironmentCrash() throws {
        try assertSheetPresents(
            SheetHost(language: "zh") { store, _ in
                TaskDetailSheet(route: DetailRoute(id: store.tasks.first?.id ?? "s-open-am"))
            },
            label: "detail")
    }
}
