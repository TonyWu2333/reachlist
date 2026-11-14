import XCTest
import UserNotifications
@testable import Planner

// T-11 / M-07 提醒排程契约测试。
// 与 ios/PlannerTests/Fixtures/notify_fixtures.json 逐字一致（oracle = 真实 src/lib/notify.js）。
// 生成命令：node ios/PlannerTests/Fixtures/generate_notify_fixtures.mjs

final class T11ReminderPlannerTests: XCTestCase {

    private func fixture() throws -> [String: Any] {
        guard let url = Bundle(for: T11ReminderPlannerTests.self)
            .url(forResource: "notify_fixtures", withExtension: "json") else {
            XCTFail("notify_fixtures.json 未随测试 target 打包")
            return [:]
        }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    private func num(_ v: Any?) -> Double? {
        guard let v, !(v is NSNull) else { return nil }
        return (v as? NSNumber)?.doubleValue
    }

    private func string(_ v: Any?) -> String {
        guard let v, !(v is NSNull) else { return "<nil>" }
        return v as? String ?? "\(v)"
    }

    private func task(_ raw: [String: Any]) -> PlannerTask {
        PlannerTask.normalize(raw, now: 1_700_000_000_000)
    }

    /// 全量夹具逐项对比（5 时区 × 8 组排程 + 中英通知文案 + 哈希 + 提醒标签）。
    func testFullFixtureContrast() throws {
        let f = try fixture()
        let meta = f["meta"] as! [String: Any]
        XCTAssertEqual(meta["baseline"] as? String, "97a7c4c17602327a42d30110806a6a1e6fa0e798")
        XCTAssertEqual(meta["windowDays"] as? Int, 30)
        XCTAssertEqual(meta["max"] as? Int, 60)
        XCTAssertEqual((meta["timezones"] as? [String])?.count, 5)
        XCTAssertEqual(meta["planCases"] as? Int, 40)

        var checked = 0
        var failures: [String] = []
        func eq(_ label: String, _ e: String, _ a: String) {
            checked += 1
            if e != a { failures.append("\(label): expected=\(e) actual=\(a)") }
        }

        for raw in f["labels"] as! [[String: Any]] {
            let m = num(raw["m"]).map { Int($0) }
            let tag = "label \(m.map(String.init) ?? "nil")"
            eq(tag + " zhLabel", string(raw["zhLabel"]), ReminderPlanner.remindLabel(m, isEnglish: false))
            eq(tag + " enLabel", string(raw["enLabel"]), ReminderPlanner.remindLabel(m, isEnglish: true))
            eq(tag + " zhShort", string(raw["zhShort"]), ReminderPlanner.remindShort(m, isEnglish: false))
            eq(tag + " enShort", string(raw["enShort"]), ReminderPlanner.remindShort(m, isEnglish: true))
        }

        for raw in f["idOf"] as! [[String: Any]] {
            eq("idOf " + string(raw["key"]), String(Int(num(raw["expected"])!)),
               String(ReminderPlanner.idOf(string(raw["key"]))))
        }

        for raw in f["planCases"] as! [[String: Any]] {
            let name = string(raw["name"])
            let tz = TimeZone(identifier: string(raw["tz"]))!
            let now = Date(timeIntervalSince1970: num(raw["nowMs"])! / 1000)
            let tasks = (raw["tasks"] as! [[String: Any]]).map(task(_:))
            let got = ReminderPlanner.planReminders(tasks, now: now, timeZone: tz)
            let exp = raw["expected"] as! [[String: Any]]
            let tag = "plan \(name) \(string(raw["tz"]))"
            eq(tag + " count", String(exp.count), String(got.count))
            if got.count == exp.count {
                for (i, e) in exp.enumerated() {
                    eq("\(tag)[\(i)].at", String(Int64(num(e["at"])!)),
                       String(Int64(got[i].at)))
                    eq("\(tag)[\(i)].taskId", string(e["taskId"]), got[i].task.id)
                    eq("\(tag)[\(i)].date", string(e["date"]), got[i].date)
                }
            }
        }

        for raw in f["notificationCases"] as! [[String: Any]] {
            let isEn = string(raw["lang"]) == "en"
            let at = num(raw["at"])!
            let n = ReminderPlanner.makeNotification(
                ReminderPlan(at: at, task: task(raw["task"] as! [String: Any]),
                             date: string(raw["date"])), isEnglish: isEn)
            let e = raw["expected"] as! [String: Any]
            let tag = "noti \(string(raw["lang"])) \(string(raw["taskId"]))"
            eq(tag + " id", String(Int(num(e["id"])!) ), String(n.id))
            eq(tag + " title", string(e["title"]), n.title)
            eq(tag + " body", string(e["body"]), n.body)
            eq(tag + " channelId", string(e["channelId"]), n.channelId)
            eq(tag + " extraId", string(e["extraId"]), n.extraId)
            eq(tag + " extraOcc", string(e["extraOcc"]), n.extraOcc)
            eq(tag + " scheduleAt", String(Int64(at)), String(Int64(n.at.timeIntervalSince1970 * 1000)))
        }

        XCTAssertTrue(failures.isEmpty, "\(failures.count) 项不一致，前 5 条：\(failures.prefix(5))")
        XCTAssertEqual(checked, 2496, "夹具断言总数应与独立 harness 一致")
    }

    /// 30 天窗口 / 60 条上限：3 条每天任务 × 31 天 = 93 个候选，只保留最早的 60 个。
    func testWindowAndMaxClamp() {
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date(timeIntervalSince1970: 1_793_462_400) // 2026-11-01 00:00 +08
        let tasks = ["A", "B", "C"].enumerated().map { i, s in
            PlannerTask.normalize([
                "id": "cap-\(s)", "title": s, "date": "2026-11-01",
                "time": String(format: "%02d:00", 7 + i), "repeat": "d1", "remind": 0,
            ], now: 1_700_000_000_000)
        }
        let plan = ReminderPlanner.planReminders(tasks, now: now, timeZone: tz)
        XCTAssertEqual(plan.count, 60)
        XCTAssertEqual(plan.map(\.at), plan.map(\.at).sorted(), "按时间升序")
        XCTAssertEqual(ReminderPlanner.makeNotifications(tasks, remindOn: false,
                                                         isEnglish: false, now: now,
                                                         timeZone: tz).count, 0,
                       "总开关关闭 → 清空全部待发，不申请权限")
    }

    /// 上游 `remindShort(null)` 未特判，输出字面 "null"；逐字保留，不擅自修正。
    func testUpstreamNullRemindShortBehavior() {
        XCTAssertEqual(ReminderPlanner.remindShort(nil, isEnglish: false), "null 分钟前")
        XCTAssertEqual(ReminderPlanner.remindShort(nil, isEnglish: true), "null min before")
        XCTAssertEqual(ReminderPlanner.remindLabel(nil, isEnglish: false), "不提醒")
        XCTAssertEqual(ReminderPlanner.remindLabel(nil, isEnglish: true), "No reminder")
    }

    func testLocalizedLabelsAndChannel() {
        XCTAssertEqual(ReminderPlanner.remindLabel(5, isEnglish: false), "提前 5 分钟")
        XCTAssertEqual(ReminderPlanner.remindLabel(5, isEnglish: true), "5 minutes before")
        XCTAssertEqual(ReminderPlanner.remindLabel(60, isEnglish: false), "提前 1 小时")
        XCTAssertEqual(ReminderPlanner.remindLabel(60, isEnglish: true), "1 hour before")
        XCTAssertEqual(ReminderPlanner.remindShort(60, isEnglish: true), "1 hr before")
        XCTAssertEqual(ReminderPlanner.channelName(isEnglish: false), "任务提醒")
        XCTAssertEqual(ReminderPlanner.channelName(isEnglish: true), "Task reminders")
        XCTAssertEqual(ReminderPlanner.channelDescription(isEnglish: true),
                       "Reminders for tasks that have a time")
    }

    /// 点击通知的 extra 路由：一次性任务 occ 为空，重复任务带发生日期。
    func testNotificationRoute() {
        let one = ReminderPlanner.makeNotification(
            ReminderPlan(at: 1_795_143_600_000,
                         task: PlannerTask.normalize(["id": "x1", "title": "A"], now: 0),
                         date: "2026-11-16"), isEnglish: false)
        let rep = ReminderPlanner.makeNotification(
            ReminderPlan(at: 1_795_143_600_000,
                         task: PlannerTask.normalize(["id": "x2", "title": "B", "repeat": "d1"], now: 0),
                         date: "2026-11-16"), isEnglish: false)
        let r1 = ReminderPlanner.route(from: ["id": one.extraId, "occ": one.extraOcc])
        let r2 = ReminderPlanner.route(from: ["id": rep.extraId, "occ": rep.extraOcc])
        XCTAssertEqual(r1?.id, "x1")
        XCTAssertEqual(r1?.occ, "")
        XCTAssertEqual(r2?.id, "x2")
        XCTAssertEqual(r2?.occ, "2026-11-16")
        XCTAssertNil(ReminderPlanner.route(from: ["occ": "2026-11-16"]))
    }

    /// UNNotificationRequest 构造：id → identifier、channel → threadIdentifier、
    /// extra → userInfo、绝对时刻 → 未来 trigger（不申请权限、不写系统）。
    @MainActor
    func testUNRequestConstruction() {
        let n = ReminderNotification(id: 123, title: "开会", body: "09:00 · 不重要不紧急",
                                     channelId: "reminders", extraId: "a1", extraOcc: "2026-11-16",
                                     at: Date(timeIntervalSinceNow: 3600))
        let scheduler = ReminderScheduler()
        let request = scheduler.makeRequest(n)
        XCTAssertEqual(request.identifier, "123")
        XCTAssertEqual(request.content.title, "开会")
        XCTAssertEqual(request.content.body, "09:00 · 不重要不紧急")
        XCTAssertEqual(request.content.threadIdentifier, "reminders")
        XCTAssertEqual(request.content.userInfo["id"] as? String, "a1")
        XCTAssertEqual(request.content.userInfo["occ"] as? String, "2026-11-16")
        let trigger = request.trigger as? UNTimeIntervalNotificationTrigger
        XCTAssertNotNil(trigger)
        XCTAssertEqual(trigger?.repeats, false)
        XCTAssertTrue((trigger?.timeInterval ?? 0) > 3500)
        XCTAssertEqual(scheduler.route(from: request.content.userInfo)?.occ, "2026-11-16")
    }
}
