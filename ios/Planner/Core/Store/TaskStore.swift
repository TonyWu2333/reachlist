import Foundation
import Observation

// MARK: - M-02 UI 包装（OPEN-04=A：@MainActor Observable）
//
// `TaskStoreCore` 是纯逻辑状态机（可脱离 Xcode 做跨端夹具对比）；本类是 App 侧的
// 唯一入口：`@MainActor @Observable`，负责 250ms 防抖落盘（`store.js:143-146`）与
// 快照刷新。所有写操作都经这里转发并刷新，撤销闭包也在这里重新包装，保证
// 「任何改动 250ms 后整份写回、连续改动不重复写」（A-03）。
//
// 本任务**不改动 T-15 的界面文件**：T-15 仍用内存样例 `CalendarDataStore`，
// 按 §12 v0.18 的约定，真实数据源注入留 T-18 统一接入（调用点签名不变）。

@MainActor
@Observable
final class TaskStore {

    private(set) var tasks: [PlannerTask] = []
    private(set) var deleted: [String: Double] = [:]
    private(set) var settings: PlannerSettings = .defaults
    private(set) var ready = false

    /// 供 T-10 的同步客户端直接取载荷 / 应用远端结果。
    let core: TaskStoreCore

    private var flushTask: Task<Void, Never>?

    init(storage: PlannerDataStorage = FilePlannerDataStorage.appDefault) {
        self.core = TaskStoreCore(storage: storage)
        core.start()
        refresh()
    }

    /// 测试 / 联调用：注入时钟与 ID，保证夹具确定性。
    init(
        storage: PlannerDataStorage,
        now: @escaping () -> Double,
        makeID: @escaping () -> String
    ) {
        self.core = TaskStoreCore(storage: storage, now: now, makeID: makeID)
        core.start()
        refresh()
    }

    // MARK: 快照与防抖

    private func refresh() {
        tasks = core.tasks
        deleted = core.deleted
        settings = core.settings
        ready = core.ready
    }

    /// `watch(state.tasks, ...)` → `setTimeout(flush, 250)`：连续改动只保留最后一次。
    private func didMutate() {
        refresh()
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            self.core.flush()
            self.refresh()
        }
    }

    /// 退到后台 / 退出前立即落盘（F-12.3 的 flush 时机）。
    func flushNow() {
        flushTask?.cancel()
        flushTask = nil
        core.flush()
        refresh()
    }

    private func afterCoreWrite() {
        // applyRemote / flush 已自行落盘；这里只刷新快照并清掉排队的防抖写。
        flushTask?.cancel()
        flushTask = nil
        refresh()
    }

    // MARK: 操作门面

    @discardableResult
    func addTask(_ fields: [String: Any]) -> PlannerTask {
        let t = core.addTask(fields)
        didMutate()
        return t
    }

    func updateTask(_ id: String, patch: [String: Any]) {
        core.updateTask(id, patch: patch)
        didMutate()
    }

    func dropTask(_ id: String) -> () -> Void {
        let undo = core.dropTask(id)
        didMutate()
        return { [weak self] in
            undo()
            self?.didMutate()
        }
    }

    func toggleDone(_ id: String, occ: String = "") {
        core.toggleDone(id, occ: occ)
        didMutate()
    }

    func skipOccurrence(_ id: String, occ: String) -> () -> Void {
        let undo = core.skipOccurrence(id, occ: occ)
        didMutate()
        return { [weak self] in
            undo()
            self?.didMutate()
        }
    }

    func removeTask(_ id: String) -> () -> Void {
        let undo = core.removeTask(id)
        didMutate()
        return { [weak self] in
            undo()
            self?.didMutate()
        }
    }

    func replaceAll(_ rawTasks: [[String: Any]]) {
        core.replaceAll(rawTasks)
        didMutate()
    }

    @discardableResult
    func addSubtask(parentId: String, fields: [String: Any]) -> PlannerTask? {
        let t = core.addSubtask(parentId: parentId, fields: fields)
        didMutate()
        return t
    }

    func toggleSubtask(parentId: String, childId: String, occ: String) -> Bool {
        let all = core.toggleSubtask(parentId: parentId, childId: childId, occ: occ)
        didMutate()
        return all
    }

    func updateSettings(_ patch: [String: Any]) {
        core.updateSettings(patch)
        refresh()
    }

    // MARK: 同步接口（T-10）

    func syncPayload() -> MergeState {
        let payload = core.syncPayload()
        refresh()                       // stamp 改了 updatedAt
        return payload
    }

    func applyRemote(_ remote: MergeState) {
        core.applyRemote(remote)
        afterCoreWrite()
    }

    /// 本地真有改动时通知同步模块（store.js:101）。回调已切回 MainActor。
    func onLocalChange(_ fn: @escaping @MainActor () -> Void) {
        core.onLocalChange {
            Task { @MainActor in fn() }
        }
    }
}
