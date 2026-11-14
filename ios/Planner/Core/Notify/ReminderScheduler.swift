import Foundation
import UserNotifications

// MARK: - M-07 UNUserNotificationCenter 适配层（T-11）
//
// 对齐 src/lib/notify.js:69-115 的 sync / ensurePermission / scheduleSync / initReminders：
// · 数据变化 → 600ms 防抖 → 取消全部待发 → 按最新数据全量重排；
// · 「第一次真正需要排提醒时才申请权限」：plan 为空直接返回，不调用 requestAuthorization；
// · 总开关 remindOn 关闭时清空全部待发通知；
// · channelId 'reminders'（Android）→ iOS 的 threadIdentifier；channel 名/描述由
//   ReminderPlanner.channelName / channelDescription 提供给 UI 权限引导（F-11.4）；
// · 点击通知的 extra { id, occ } → userInfo，由 ReminderPlanner.route 解析（F-11.3）。
//
// §2.11 / RISK-04：iOS 无精确闹钟 API，UNTimeIntervalNotificationTrigger 可能被系统或专注模式
// 延迟；VERIFY-02 实测待发上限 64 条、JS 的 MAX=60 全部可排上，故 30 天窗口无需缩短。

@MainActor
final class ReminderScheduler {

    /// 'granted' | 'denied' | 'prompt' | 'web'（对齐 notifyState.permission 的字符串值）。
    private(set) var permission: String = "prompt"
    private(set) var scheduled: Int = 0

    private let center: UNUserNotificationCenter
    private var debounceTask: Task<Void, Never>?
    private var chain: Task<Void, Never> = Task {}

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    // MARK: 请求构造（无副作用，可供 XCTest 逐字段核对）

    func makeRequest(_ n: ReminderNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.body = n.body
        content.sound = .default
        content.threadIdentifier = n.channelId
        content.userInfo = ["id": n.extraId, "occ": n.extraOcc]
        // JS 的 schedule.at 是绝对毫秒时刻；用相对当前的时间间隔表达同一个绝对触发点。
        let interval = max(1, n.at.timeIntervalSinceNow)
        return UNNotificationRequest(
            identifier: String(n.id), content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
    }

    // MARK: 权限（notify.js:ensurePermission）

    private func ensurePermission() async -> Bool {
        let settings = await withCheckedContinuation { c in
            center.getNotificationSettings { c.resume(returning: $0.authorizationStatus.rawValue) }
        }
        // UNAuthorizationStatus: 0 notDetermined / 1 denied / 2 authorized / 3 provisional / 4 ephemeral
        if settings == 0 {
            let granted = await withCheckedContinuation { c in
                center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                    c.resume(returning: ok)
                }
            }
            permission = granted ? "granted" : "denied"
        } else {
            permission = settings == 1 ? "denied" : "granted"
        }
        return permission == "granted"
    }

    // MARK: sync（notify.js:80-89）

    /// 全量重排。`remindOn = false` 时清空全部待发，且不申请权限。
    func sync(tasks: [PlannerTask], remindOn: Bool, isEnglish: Bool,
              now: Date = Date(), timeZone: TimeZone = .current) async {
        let plan = ReminderPlanner.makeNotifications(
            tasks, remindOn: remindOn, isEnglish: isEnglish, now: now, timeZone: timeZone)
        center.removeAllPendingNotificationRequests()
        scheduled = 0
        guard !plan.isEmpty else { return }
        guard await ensurePermission() else { return }
        for n in plan {
            do { try await center.add(makeRequest(n)) } catch { /* 单条失败不阻断其余 */ }
        }
        let pending = await withCheckedContinuation { c in
            center.getPendingNotificationRequests { c.resume(returning: $0.count) }
        }
        scheduled = pending
    }

    // MARK: 600ms 防抖 + 串行化（notify.js:scheduleSync）

    /// `watch(() => [state.tasks, state.settings.remindOn], scheduleSync, { deep: true })`
    /// 在 Swift 侧由调用方（T-18 生命周期接线）于数据变更后调用本方法。
    func scheduleSync(tasks: [PlannerTask], remindOn: Bool, isEnglish: Bool,
                      timeZone: TimeZone = .current) {
        debounceTask?.cancel()
        let previous = chain
        chain = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            _ = await previous.value
            await self?.sync(tasks: tasks, remindOn: remindOn, isEnglish: isEnglish,
                             timeZone: timeZone)
        }
        debounceTask = chain
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    // MARK: 点击通知（notify.js:109-112）

    func route(from userInfo: [AnyHashable: Any]) -> (id: String, occ: String)? {
        ReminderPlanner.route(from: userInfo)
    }
}
