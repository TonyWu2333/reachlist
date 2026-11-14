import Foundation

// MARK: - M-02 TaskStore 核心状态机（T-09）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/lib/store.js（246 行）。
// 本文件是**纯 Foundation 逻辑**：不依赖 SwiftUI / Observation / 网络，
// 因而可以脱离 Xcode 工程用独立 swiftc harness 与真实 JS oracle 逐项对比。
// UI 侧的 `@MainActor @Observable` 包装与 250ms 防抖见同目录 TaskStore.swift。
//
// 与 JS 的三处「实现层对齐」（不改功能语义，均已在计划书 §5.3 / 落地说明登记）：
// 1. JS 的 `watch(state.tasks, {deep:true})` 等价为「每个 mutating 操作末尾通知 onMutation」；
//    core 不持有 Timer，由 UI 包装层实现 250ms 防抖。JS 在 stamp 修改 updatedAt 后
//    会因 deep watch 多触发一次冗余 flush，Swift 侧不做这次冗余写（净状态完全一致）。
// 2. `applyRemote` 的「尽量原地更新、不换对象引用」：PlannerTask 是值类型 struct，
//    UI 按 id 驱动、不依赖对象身份；Swift 侧用「sig 与 updatedAt 都相同则复用旧值」
//    表达同一语义，其余情况用合并后的新值替换（等价 Object.assign(cur, t)）。
// 3. `Object.assign(t, patch)` 不做 normalize；这里按 17 字段做类型安全的直接赋值，
//    脏值（把数字塞进 title 等）按「忽略该字段」处理，与 PlannerTask.normalize 的
//    既有窄化策略一致。契约内所有调用方传入的都是正确类型。

final class TaskStoreCore {

    // MARK: 状态（store.js:16-24）

    private(set) var tasks: [PlannerTask] = []
    private(set) var deleted: [String: Double] = [:]
    private(set) var settings: PlannerSettings = .defaults
    private(set) var ready = false

    // MARK: 注入

    let storage: PlannerDataStorage
    private let clock: () -> Double
    private let idFactory: () -> String

    /// `clearTimeout(timer)` 的钩子，由 UI 包装层注入；core 自身不持有定时器。
    var clearScheduledFlush: (() -> Void)?

    private var saved: [String: String] = [:]          // id → 上次保存时的 taskSig
    private var localChangeListeners: [() -> Void] = []
    private var mutationListeners: [() -> Void] = []

    init(
        storage: PlannerDataStorage,
        now: @escaping () -> Double = { Date().timeIntervalSince1970 * 1000 },
        makeID: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.storage = storage
        self.clock = now
        self.idFactory = makeID
    }

    func now() -> Double { clock() }

    // MARK: 监听（store.js:79-81 / 143-147）

    /// 本地真的改了东西（不是同步拉下来的）时通知；T-10 用它触发上传。
    func onLocalChange(_ fn: @escaping () -> Void) { localChangeListeners.append(fn) }

    /// 任何状态改动时通知；UI 包装层用它刷新快照并排 250ms 防抖落盘。
    func onMutation(_ fn: @escaping () -> Void) { mutationListeners.append(fn) }

    private func notifyMutation() { mutationListeners.forEach { $0() } }

    // MARK: 戳记与落盘（store.js:77-133）

    /// `stamp()`：改过的任务更新 updatedAt，消失的任务记墓碑，撤销删除时清墓碑。
    private func stamp() {
        let nowMs = now()
        var alive = Set<String>()
        var changed = false
        for i in tasks.indices {
            let t = tasks[i]
            alive.insert(t.id)
            let sig = MergeEngine.taskSig(t)      // 不含 updatedAt，故更新戳记不会改 sig
            if saved[t.id] == sig { continue }
            let previous = t.updatedAt.isNaN ? 0 : t.updatedAt
            tasks[i].updatedAt = max(nowMs, previous + 1)
            saved[t.id] = sig
            deleted.removeValue(forKey: t.id)
            changed = true
        }
        for id in Array(saved.keys) {
            if alive.contains(id) { continue }
            saved.removeValue(forKey: id)
            deleted[id] = nowMs
            changed = true
        }
        if changed { localChangeListeners.forEach { $0() } }
    }

    private func remember() {
        saved.removeAll()
        for t in tasks { saved[t.id] = MergeEngine.taskSig(t) }
    }

    /// `flush()`：清定时器 → stamp → 整份写回。
    func flush() {
        clearScheduledFlush?()
        stamp()
        PlannerDataFile.save(tasks: tasks, deleted: deleted, to: storage)
    }

    /// `syncPayload()`：先 stamp，返回给同步客户端的载荷（meta.tz 由 T-10 补）。
    func syncPayload() -> MergeState {
        stamp()
        return MergeState(tasks: tasks, deleted: deleted)
    }

    /// `applyRemote()`：合并服务器结果，尽量原地更新，立即落盘。
    func applyRemote(_ remote: MergeState) {
        stamp()
        let merged = MergeEngine.mergeState(
            MergeState(tasks: tasks, deleted: deleted), remote, now: now())
        let next = merged.tasks.map { renormalize($0) }
        let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        tasks = next.map { t in
            guard let cur = byId[t.id] else { return t }
            if MergeEngine.taskSig(cur) == MergeEngine.taskSig(t) && cur.updatedAt == t.updatedAt {
                return cur                         // 完全没变：保持「原对象」
            }
            return t                               // 等价 Object.assign(cur, t)
        }
        deleted = merged.deleted
        remember()
        clearScheduledFlush?()
        PlannerDataFile.save(tasks: tasks, deleted: deleted, to: storage)
        notifyMutation()                          // JS 的 state.tasks = next 会触发 watch
    }

    /// `merged.tasks.map(normalizeTask)`：Swift 侧解码时已 normalize 过，这里再走一遍保证幂等。
    private func renormalize(_ t: PlannerTask) -> PlannerTask {
        guard let data = t.jsJSONString().data(using: .utf8),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return t }
        return PlannerTask.normalize(raw, now: now(), makeID: idFactory)
    }

    /// `initStore()` 的同步等价版。watch 注册由 UI 包装层完成，故这里不通知 mutation。
    func start() {
        let loaded = PlannerDataFile.load(from: storage, now: now(), makeID: idFactory)
        tasks = loaded.tasks
        deleted = loaded.deleted
        settings = PlannerDataFile.loadSettings(from: storage)
        remember()
        ready = true
        if loaded.hadLegacy { flush() }           // 旧格式迁移后立即落盘（A-02）
    }

    // MARK: 某日任务（store.js:151-152，纯函数版由 T-07 提供）

    func tasksOn(_ day: String) -> [RepeatInstance] {
        RepeatEngine.tasksOn(tasks, day: day)
    }

    // MARK: 操作集（store.js:155-246）

    func findTask(_ id: String) -> PlannerTask? { tasks.first { $0.id == id } }

    func addTask(_ fields: [String: Any]) -> PlannerTask {
        // remind 默认值：`fields.remind !== undefined ? ... : fields.time ? defaultRemind : null`
        var raw = fields
        if fields["remind"] == nil {
            raw["remind"] = JSBridge.truthy(fields["time"]) ? settings.defaultRemind : NSNull()
        }
        raw["id"] = idFactory()
        raw["createdAt"] = now()
        var task = PlannerTask.normalize(raw, now: now(), makeID: idFactory)
        if !task.repeatRule.isEmpty && task.date.isEmpty {
            task.date = PlannerCalendar.today(Date(timeIntervalSince1970: now() / 1000))
        }
        tasks.append(task)
        notifyMutation()
        return task
    }

    func updateTask(_ id: String, patch: [String: Any]) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        var t = tasks[i]
        if let doneValue = patch["done"] {
            let newDone = JSBridge.truthy(doneValue)
            if newDone != t.done { t.doneAt = newDone ? now() : nil }
        }
        var applied = patch
        // `patch.done === false` → 取消完成 = 也取消放弃
        if let b = patch["done"] as? Bool, b == false { applied["dropped"] = false }
        applyPatch(applied, to: &t)
        tasks[i] = t
        notifyMutation()
    }

    private func applyPatch(_ patch: [String: Any], to t: inout PlannerTask) {
        if let v = patch["id"] { t.id = JSBridge.string(v) }
        if let v = patch["title"] { t.title = JSBridge.string(v) }
        if let v = patch["note"] { t.note = JSBridge.string(v) }
        if let v = patch["date"] { t.date = JSBridge.string(v) }
        if let v = patch["time"] { t.time = JSBridge.string(v) }
        if let v = patch["important"] { t.important = JSBridge.truthy(v) }
        if let v = patch["urgent"] { t.urgent = JSBridge.truthy(v) }
        if let v = patch["done"] { t.done = JSBridge.truthy(v) }
        if let v = patch["dropped"] { t.dropped = JSBridge.truthy(v) }
        if let v = patch["createdAt"] { t.createdAt = JSBridge.number(v) }
        if let v = patch["doneAt"] {
            t.doneAt = v is NSNull ? nil : JSBridge.number(v)
        }
        if let v = patch["repeat"] { t.repeatRule = JSBridge.string(v) }
        if let v = patch["doneDates"] as? [String] { t.doneDates = v }
        if let v = patch["skipDates"] as? [String] { t.skipDates = v }
        if let v = patch["remind"] {
            if v is NSNull { t.remind = nil }
            else if let n = v as? Int { t.remind = n }
            else if let n = v as? NSNumber { t.remind = n.intValue }
        }
        if let v = patch["parentId"] { t.parentId = JSBridge.string(v) }
        if let v = patch["updatedAt"] { t.updatedAt = JSBridge.number(v) }
    }

    func dropTask(_ id: String) -> () -> Void {
        guard let i = tasks.firstIndex(where: { $0.id == id }), tasks[i].repeatRule.isEmpty else { return {} }
        let before = tasks[i]
        tasks[i].done = true
        tasks[i].dropped = true
        tasks[i].doneAt = now()
        notifyMutation()
        return { [weak self] in
            guard let self, let i = self.tasks.firstIndex(where: { $0.id == id }) else { return }
            self.tasks[i].done = before.done
            self.tasks[i].dropped = before.dropped
            self.tasks[i].doneAt = before.doneAt
            self.notifyMutation()
        }
    }

    func countsAsDone(_ t: PlannerTask) -> Bool { t.done && !t.dropped }

    func toggleDone(_ id: String, occ: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        if tasks[i].repeatRule.isEmpty || occ.isEmpty {
            updateTask(id, patch: ["done": !tasks[i].done])
            return
        }
        if let k = tasks[i].doneDates.firstIndex(of: occ) { tasks[i].doneDates.remove(at: k) }
        else { tasks[i].doneDates.append(occ) }
        notifyMutation()
    }

    func skipOccurrence(_ id: String, occ: String) -> () -> Void {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return {} }
        tasks[i].skipDates.append(occ)
        notifyMutation()
        return { [weak self] in
            guard let self, let i = self.tasks.firstIndex(where: { $0.id == id }),
                  let k = self.tasks[i].skipDates.firstIndex(of: occ) else { return }
            self.tasks[i].skipDates.remove(at: k)
            self.notifyMutation()
        }
    }

    // MARK: 子任务（store.js:205-232）

    func childrenOf(_ id: String) -> [PlannerTask] {
        tasks.enumerated()
            .filter { $0.element.parentId == id }
            .sorted { lhs, rhs in
                lhs.element.createdAt == rhs.element.createdAt
                    ? lhs.offset < rhs.offset          // JS V8 的 Array#sort 稳定
                    : lhs.element.createdAt < rhs.element.createdAt
            }
            .map(\.element)
    }

    private func perOcc(parent: PlannerTask, child: PlannerTask, occ: String) -> Bool {
        !parent.repeatRule.isEmpty && !occ.isEmpty && child.date.isEmpty
    }

    func subDone(parent: PlannerTask, child: PlannerTask, occ: String) -> Bool {
        perOcc(parent: parent, child: child, occ: occ)
            ? child.doneDates.contains(occ) : child.done
    }

    func subProgress(parent: PlannerTask, occ: String) -> (done: Int, total: Int) {
        let kids = childrenOf(parent.id).filter { !$0.dropped }
        return (kids.filter { subDone(parent: parent, child: $0, occ: occ) }.count, kids.count)
    }

    func addSubtask(parentId: String, fields: [String: Any]) -> PlannerTask? {
        guard let p = findTask(parentId),
              let title = fields["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var raw = fields
        raw["parentId"] = parentId
        raw["important"] = p.important
        raw["urgent"] = p.urgent
        return addTask(raw)
    }

    func toggleSubtask(parentId: String, childId: String, occ: String) -> Bool {
        guard let p = findTask(parentId), let c = findTask(childId) else { return false }
        if perOcc(parent: p, child: c, occ: occ) {
            guard let i = tasks.firstIndex(where: { $0.id == childId }) else { return false }
            if let k = tasks[i].doneDates.firstIndex(of: occ) { tasks[i].doneDates.remove(at: k) }
            else { tasks[i].doneDates.append(occ) }
            notifyMutation()
        } else {
            updateTask(childId, patch: ["done": !c.done])
        }
        let progress = subProgress(parent: p, occ: occ)
        return progress.done == progress.total
    }

    // MARK: 删除与替换（store.js:234-246）

    func removeTask(_ id: String) -> () -> Void {
        var removed: [(Int, PlannerTask)] = []
        for i in stride(from: tasks.count - 1, through: 0, by: -1) {
            if tasks[i].id == id || tasks[i].parentId == id {
                removed.insert((i, tasks[i]), at: 0)
                tasks.remove(at: i)
            }
        }
        if removed.isEmpty { return {} }
        notifyMutation()
        return { [weak self] in
            guard let self else { return }
            for (i, t) in removed { self.tasks.insert(t, at: min(i, self.tasks.count)) }
            self.notifyMutation()
        }
    }

    func replaceAll(_ rawTasks: [[String: Any]]) {
        tasks = LegacyMigration.normalizedTasks(rawTasks, now: now(), makeID: idFactory)
        notifyMutation()
    }

    // MARK: settings（store.js:147 watch(settings, saveSettings)）

    private func settingsDict() -> [String: Any] {
        [
            "lang": settings.lang, "showLunar": settings.showLunar,
            "showHoliday": settings.showHoliday, "remindOn": settings.remindOn,
            "defaultRemind": settings.defaultRemind, "syncOn": settings.syncOn,
            "syncCode": settings.syncCode,
        ]
    }

    /// 变化即存（无防抖），对齐 `watch(state.settings, s => saveSettings(s), {deep:true})`。
    func updateSettings(_ patch: [String: Any]) {
        var raw = settingsDict()
        for (k, v) in patch { raw[k] = v }
        settings = PlannerSettings.merged(from: raw)
        PlannerDataFile.saveSettings(settings, to: storage)
    }
}
