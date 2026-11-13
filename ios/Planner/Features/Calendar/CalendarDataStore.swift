import Foundation
import SwiftUI

// MARK: - T-18 真实数据源 UI 适配层
//
// T-15 ~ T-17 期间本类是内存样例数据源（不持久化、不 stamp、不防抖、不联网）；
// v0.26 明确「真实 TaskStore 注入留 T-18」，用户 2026-11-14 决议采用「保留 UI 适配层」：
// 6 个页面 + 3 个 sheet 的调用点（tasks / settings / 操作函数 / 撤销闭包）签名不变，
// 底层统一转发给 M-02 `TaskStore`（@MainActor @Observable），由它负责
// 250ms 防抖落盘、stamp / updatedAt、墓碑、MergeEngine 合并与同步载荷。
//
// 本类只做两件事：① 把 TaskStore 的快照镜像成 @Published 供 SwiftUI 读取；
// ② 把 CalendarView.vue 的组合操作（推迟、批量移到今天）翻译成 TaskStore 的原语。
// Swift 侧不再有第二份任务状态机。

/// 7 项 settings + 通知权限状态。数值与 `PlannerSettings.defaults` 一致；
/// `lang` 只存在于本地，**不进入任何同步载荷**（A-45）。
struct UISettings: Equatable, Sendable {
    var lang: AppLanguagePref = .auto
    var showLunar = true
    var showHoliday = true
    var remindOn = true
    var defaultRemind = 0
    var syncOn = false
    var syncCode = ""
    /// `notify.js:notifyState.permission` 的 UI 侧镜像：notDetermined / authorized / denied / provisional。
    var notifyPermission = "notDetermined"
}

private extension UISettings {
    /// `Object.assign(state.settings, settings)` 的 UI 侧：旧设置缺 lang 时回退 'auto'（A-05）。
    init(_ p: PlannerSettings) {
        self.init(
            lang: AppLanguagePref(rawValue: p.lang) ?? .auto,
            showLunar: p.showLunar,
            showHoliday: p.showHoliday,
            remindOn: p.remindOn,
            defaultRemind: p.defaultRemind,
            syncOn: p.syncOn,
            syncCode: p.syncCode
        )
    }
}

/// 7 字段整份 patch（settings 无防抖，对齐 store.js:147）。
private func settingsPatch(_ ui: UISettings) -> [String: Any] {
    [
        "lang": ui.lang.rawValue, "showLunar": ui.showLunar,
        "showHoliday": ui.showHoliday, "remindOn": ui.remindOn,
        "defaultRemind": ui.defaultRemind, "syncOn": ui.syncOn,
        "syncCode": ui.syncCode,
    ]
}

@MainActor
final class CalendarDataStore: ObservableObject {

    /// 真实数据源（T-09 / M-02）。所有写操作都经它，落盘与合并语义单一来源。
    let taskStore: TaskStore
    /// 与 taskStore 共用的存储后端，供 XCTest 直接断言 planner-data / planner-settings。
    let settingsStorage: PlannerDataStorage

    @Published private(set) var tasks: [PlannerTask] = []
    @Published var settings: UISettings {
        didSet {
            guard !refreshing else { return }
            taskStore.updateSettings(settingsPatch(settings))
        }
    }
    /// T-10 的同步状态，由 AppRootView 通过 SyncClient.onStateChange 写入。
    @Published var syncState = SyncState()

    private var refreshing = false

    var today: String { PlannerCalendar.today() }

    /// `seedSample` 只给 DEV 视觉探针 / 自检页使用：真实 App 首次启动为空数据（与 Web 端一致）。
    init(settingsStorage: PlannerDataStorage = FilePlannerDataStorage.appDefault,
         seedSample: Bool = false) {
        let store = TaskStore(storage: settingsStorage)
        self.taskStore = store
        self.settingsStorage = settingsStorage
        self.settings = UISettings(store.settings)
        if seedSample && store.tasks.isEmpty {
            store.replaceAll(Self.rawSample(today: PlannerCalendar.today()))
        }
        tasks = store.tasks
    }

    /// 把 TaskStore 的快照镜像到 @Published；刷新期间抑制 settings 的反向写入。
    private func syncFromStore() {
        refreshing = true
        tasks = taskStore.tasks
        settings = UISettings(taskStore.settings)
        refreshing = false
    }

    /// 供 SyncClient.applyRemote / 备份导入等「底层自行写入」的路径刷新 UI。
    func refreshFromStore() { syncFromStore() }

    private func index(of id: String) -> Int? { tasks.firstIndex { $0.id == id } }

    func find(_ id: String) -> PlannerTask? {
        guard let i = index(of: id) else { return nil }
        return tasks[i]
    }

    // MARK: 操作（全部转发 M-02，撤销闭包执行后刷新快照）

    func toggleDone(id: String, occ: String) {
        taskStore.toggleDone(id, occ: occ)
        syncFromStore()
    }

    /// 删除任务连带子任务，返回撤销函数（store.js:removeTask）。
    func remove(id: String) -> () -> Void {
        let undo = taskStore.removeTask(id)
        syncFromStore()
        return { [weak self] in
            undo()
            self?.syncFromStore()
        }
    }

    /// 放弃仅对未完成的一次性任务有效（store.js:dropTask）。
    func drop(id: String) -> () -> Void {
        let undo = taskStore.dropTask(id)
        syncFromStore()
        return { [weak self] in
            undo()
            self?.syncFromStore()
        }
    }

    func skip(id: String, occ: String) -> () -> Void {
        let undo = taskStore.skipOccurrence(id, occ: occ)
        syncFromStore()
        return { [weak self] in
            undo()
            self?.syncFromStore()
        }
    }

    /// 推迟：重复任务加 skipDates；一次性任务把日期推到 max(原日期, 今天) + 1。
    /// 返回新日期（供 toast 文案）与撤销函数（CalendarView.vue:266-299）。
    func postpone(id: String, occ: String) -> (nextDate: String, undo: () -> Void) {
        guard let t = find(id) else { return ("", {}) }
        if !t.repeatRule.isEmpty {
            let undo = taskStore.skipOccurrence(id, occ: occ)
            syncFromStore()
            return (t.date, { [weak self] in
                undo()
                self?.syncFromStore()
            })
        }
        let prev = t.date
        let base = (!prev.isEmpty && prev > today) ? prev : today
        let next = PlannerCalendar.addDays(base, 1)
        taskStore.updateTask(id, patch: ["date": next])
        syncFromStore()
        return (next, { [weak self] in
            self?.taskStore.updateTask(id, patch: ["date": prev])
            self?.syncFromStore()
        })
    }

    func moveOverdueToToday() -> (count: Int, undo: () -> Void) {
        let ids = CalendarContract.overdue(tasks, selected: today, today: today).map(\.id)
        var previous: [String: String] = [:]
        for id in ids {
            guard let t = find(id) else { continue }
            previous[id] = t.date
        }
        for id in ids { taskStore.updateTask(id, patch: ["date": today]) }
        syncFromStore()
        return (ids.count, { [weak self] in
            for (id, date) in previous { self?.taskStore.updateTask(id, patch: ["date": date]) }
            self?.syncFromStore()
        })
    }

    // MARK: T-16 / T-17 新增（转发 M-02 / 只读计算）

    /// `tasksOn(d)`：一次性任务按 date 命中，重复任务按 occursOn 展开为实例。
    func tasksOn(_ day: String) -> [RepeatInstance] {
        RepeatEngine.tasksOn(tasks, day: day)
    }

    @discardableResult
    func add(fields: [String: Any]) -> PlannerTask {
        let t = taskStore.addTask(fields)
        syncFromStore()
        return t
    }

    func update(id: String, patch: [String: Any]) {
        taskStore.updateTask(id, patch: patch)
        syncFromStore()
    }

    func childrenOf(_ id: String) -> [PlannerTask] {
        CalendarContract.childrenOf(id, tasks)
    }

    /// 父任务重复且 occ 非空、子任务自己没日期时，按父任务那一天打勾。
    static func perOcc(_ parent: PlannerTask?, _ child: PlannerTask, _ occ: String) -> Bool {
        guard let parent else { return false }
        return !parent.repeatRule.isEmpty && !occ.isEmpty && child.date.isEmpty
    }

    func subDone(_ parent: PlannerTask?, _ child: PlannerTask, occ: String) -> Bool {
        Self.perOcc(parent, child, occ) ? child.doneDates.contains(occ) : child.done
    }

    /// 放弃的子任务不计入进度（store.js:subProgress）。
    func subProgress(_ parent: PlannerTask, occ: String) -> (done: Int, total: Int) {
        let kids = childrenOf(parent.id).filter { !$0.dropped }
        return (kids.filter { subDone(parent, $0, occ: occ) }.count, kids.count)
    }

    /// 返回切换后是否「全部完成」，对齐 store.js:toggleSubtask。
    func toggleSubtask(parentId: String, childId: String, occ: String) -> Bool {
        let all = taskStore.toggleSubtask(parentId: parentId, childId: childId, occ: occ)
        syncFromStore()
        return all
    }

    @discardableResult
    func addSubtask(parentId: String, fields: [String: Any]) -> PlannerTask? {
        let t = taskStore.addSubtask(parentId: parentId, fields: fields)
        syncFromStore()
        return t
    }

    /// 备份导入的全量替换：走 migrate + normalize（backup.js → store.js:replaceAll）。
    func replaceAll(_ rawTasks: [[String: Any]]) {
        taskStore.replaceAll(rawTasks)
        syncFromStore()
    }

    // MARK: DEV 样例数据（仅视觉探针 / 组件预览，真实 App 不注入）

    static func task(
        id: String, title: String, date: String, time: String = "",
        important: Bool = false, urgent: Bool = false, done: Bool = false,
        dropped: Bool = false, repeatRule: String = "", parentId: String = ""
    ) -> PlannerTask {
        PlannerTask(
            id: id, title: title, note: "", date: date, time: time,
            important: important, urgent: urgent, done: done, dropped: dropped,
            createdAt: 1_700_000_000_000, doneAt: done ? 1_700_000_100_000 : nil,
            repeatRule: repeatRule, doneDates: [], skipDates: [],
            remind: nil, parentId: parentId, updatedAt: 1_700_000_000_000
        )
    }

    static func sample(today: String) -> [PlannerTask] {
        let d = { (n: Int) in PlannerCalendar.addDays(today, n) }
        return [
            task(id: "s-open-am", title: "晨会", date: today, time: "09:00", important: true, urgent: true),
            task(id: "s-open-no-time", title: "整理会议材料", date: today, important: true),
            task(id: "s-done", title: "回复客户邮件", date: today, time: "08:00", done: true),
            task(id: "s-dropped", title: "整理旧备份", date: today, done: true, dropped: true),
            task(id: "s-overdue-1", title: "交月度报表", date: d(-3), time: "08:00", urgent: true),
            task(id: "s-overdue-2", title: "预约体检", date: d(-5)),
            task(id: "s-future", title: "项目评审", date: d(2), time: "14:00", important: true),
            task(id: "s-tomorrow", title: "买咖啡豆", date: d(1), time: "10:00"),
            task(id: "s-daily", title: "每天喝水 8 杯", date: d(-10), time: "07:30", repeatRule: "d1"),
            task(id: "s-weekly", title: "周会", date: d(-14), time: "18:00", repeatRule: "w1:5"),
            task(id: "s-monthly", title: "月度复盘", date: d(-20), repeatRule: "m1"),
            task(id: "s-child", title: "打印资料", date: today, parentId: "s-open-am"),
        ]
    }

    /// 样例任务还原成 store.js:replaceAll 接受的 raw 数组，仍走 normalize / migrate。
    private static func rawSample(today: String) -> [[String: Any]] {
        sample(today: today).map { t in
            [
                "id": t.id, "title": t.title, "note": t.note, "date": t.date, "time": t.time,
                "important": t.important, "urgent": t.urgent, "done": t.done, "dropped": t.dropped,
                "createdAt": t.createdAt, "doneAt": t.doneAt as Any? ?? NSNull(),
                "repeat": t.repeatRule, "doneDates": t.doneDates, "skipDates": t.skipDates,
                "remind": t.remind as Any? ?? NSNull(), "parentId": t.parentId,
                "updatedAt": t.updatedAt,
            ]
        }
    }
}
