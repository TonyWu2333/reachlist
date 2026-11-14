import Foundation

// MARK: - 同步状态三元组
//
// 对应 shared/merge.js 注释里的 state shape：`{ tasks, deleted, meta }`。
// 服务器自己的 `rev` 是 server.js 的内部计数字段，不进入合并输入/输出，
// 因此不属于本类型（`rev` 由 T-10 的 SyncClient 单独处理）。
//
// `meta` 在服务器侧只承载 `{ tz }`（§2.5.2），故用 [String: String]。
// 非字符串的 meta 值在解码时被丢弃——这是唯一一处有意窄化，写入注释以便复核。

struct MergeState: Equatable, Sendable {
    var tasks: [PlannerTask] = []
    var deleted: [String: Double] = [:]
    var meta: [String: String] = [:]

    init(tasks: [PlannerTask] = [], deleted: [String: Double] = [:], meta: [String: String] = [:]) {
        self.tasks = tasks
        self.deleted = deleted
        self.meta = meta
    }
}

extension MergeState: Codable {
    enum CodingKeys: String, CodingKey {
        case tasks, deleted, meta
    }

    /// 宽松解码：JS 侧 `a.tasks || []`、`a.deleted || {}`、`a.meta || {}`
    /// 允许缺字段，Swift 侧同样不因缺字段失败（老数据 / agent 手写 payload）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tasks = (try? c.decode([PlannerTask].self, forKey: .tasks)) ?? []
        let deleted = (try? c.decode([String: Double].self, forKey: .deleted)) ?? [:]
        let rawMeta = (try? c.decode([String: PlannerJSONValue].self, forKey: .meta)) ?? [:]
        self.init(
            tasks: tasks,
            deleted: deleted,
            meta: rawMeta.compactMapValues { value in
                if case .string(let s) = value { return s }
                return nil
            }
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tasks, forKey: .tasks)
        try c.encode(deleted, forKey: .deleted)
        // JS 侧 meta 恒为对象（可能为空），这里同样始终输出，不省略键。
        try c.encode(meta, forKey: .meta)
    }
}

// MARK: - M-05 MergeEngine（shared/merge.js，48 行，逐字等价）
//
// 契约来源：docs/ios-native-plan.md §2.6.1，逐条对应关系如下。
//
// 【1】taskSig = JSON.stringify(除 updatedAt 外的全部字段) —— 键序敏感
// 【2】newer(x, y)：先比 updatedAt，相等时用 taskSig 字符串比较做确定性裁决
// 【3】deleted 逐 id 取较晚时间戳
// 【4】任务按 [a.tasks, b.tasks] 首次出现顺序排列，同 id 保留 newer 的版本
// 【5】deleted[id] >= updatedAt 丢弃任务；updatedAt > deleted[id] 则复活并清墓碑
// 【6】父任务被丢弃时子任务一并丢弃
// 【7】墓碑超过 90 天自动清理
// 【8】meta 浅合并（b 覆盖 a）
//
// 本文件是纯函数，无 UI、无持久化、无网络；T-09（TaskStore）与 T-10（SyncClient）
// 只调用它，不再各写一套合并逻辑（RISK-01：禁止出现第四份合并实现）。

enum MergeEngine {

    /// shared/merge.js:9 `const TOMBSTONE_TTL = 90 * 864e5;`
    static let tombstoneTTL: Double = 90 * 864e5

    // MARK: 【1】taskSig

    /// `shared/merge.js:taskSig` 的逐字等价输出：任务 JSON 去掉 `updatedAt` 键。
    ///
    /// 片段来自 `PlannerTask.jsJSONParts()` —— 与持久化输出共用同一份序列化源，
    /// 因此键序与数值/转义表示天然一致（VERIFY-01 的结论在此复用）。
    static func taskSig(_ t: PlannerTask) -> String {
        "{" + t.jsJSONParts()
            .filter { $0.key != "updatedAt" }
            .map { "\"\($0.key)\":" + $0.value }
            .joined(separator: ",") + "}"
    }

    // MARK: 【2】newer

    /// JS `const a = x.updatedAt || 0;` —— `NaN` 在 JS 里是 falsy，会被替换成 0。
    private static func rev(_ t: PlannerTask) -> Double {
        t.updatedAt.isNaN ? 0 : t.updatedAt
    }

    /// `shared/merge.js:newer`。
    static func newer(_ x: PlannerTask, _ y: PlannerTask) -> Bool {
        let a = rev(x)
        let b = rev(y)
        if a != b { return a > b }
        // 平局：`taskSig(x) > taskSig(y)`，JS 的字符串比较是 UTF-16 code unit 序。
        return jsStringGreater(taskSig(x), taskSig(y))
    }

    /// JS 字符串 `a > b` 的等价实现。
    ///
    /// 不能用 Swift 原生 `<`：Swift 按 Unicode 标量 / 规范等价比较，
    /// 而 JS 按 UTF-16 code unit 比较。二者在两类输入上会给出相反结果：
    /// · 非 BMP 字符（emoji 等代理对）与 BMP 高码位字符的先后；
    /// · 组合字符（`e` + U+0301）与预组合字符（U+00E9）—— Swift 视其「相等」，
    ///   而 JS 逐 code unit 比较能分出大小，平局裁决必须与 JS 一致。
    static func jsStringGreater(_ a: String, _ b: String) -> Bool {
        var i = a.utf16.makeIterator()
        var j = b.utf16.makeIterator()
        while true {
            let x = i.next()
            let y = j.next()
            switch (x, y) {
            case (nil, nil): return false          // 完全相同
            case (nil, _): return false            // a 是 b 的前缀 → a < b
            case (_, nil): return true             // b 是 a 的前缀 → a > b
            case let (lhs?, rhs?):
                if lhs != rhs { return lhs > rhs }
            }
        }
    }

    // MARK: 【3】~【8】mergeState

    /// `shared/merge.js:mergeState(a, b, now)`。
    /// `now` 可注入以便与 JS oracle 做确定性对比（墓碑 90 天清理用）。
    static func mergeState(
        _ a: MergeState,
        _ b: MergeState,
        now: Double = Date().timeIntervalSince1970 * 1000
    ) -> MergeState {
        // 【3】deleted 逐 id 取较晚的时间戳。
        // JS: `if (!(deleted[id] >= at)) deleted[id] = at;` —— 缺键时 undefined >= at 为 false。
        var deleted = a.deleted
        for (id, at) in b.deleted {
            if !((deleted[id] ?? -.infinity) >= at) { deleted[id] = at }
        }

        // 【4】首次出现顺序 + 同 id 取 newer。
        var byId: [String: PlannerTask] = [:]
        var order: [String] = []
        for t in a.tasks + b.tasks {
            let cur = byId[t.id]
            if cur == nil { order.append(t.id) }
            if cur == nil || newer(t, cur!) { byId[t.id] = t }
        }

        // 【5】墓碑裁决。
        // JS 的两处判断都以 `gone` 的真假为前提，`gone === 0` 是 falsy：
        // 任务保留、墓碑也不清除（只能等【7】按 90 天清理）。
        var tasks: [PlannerTask] = []
        tasks.reserveCapacity(order.count)
        for id in order {
            guard let t = byId[id] else { continue }
            if let gone = deleted[id], gone != 0 {
                if gone >= rev(t) { continue }      // 墓碑不早于任务 → 丢弃任务
                deleted[id] = nil                    // 任务在墓碑之后被编辑 → 复活并清墓碑
            }
            tasks.append(t)
        }

        // 【6】父任务被丢弃时，其子任务一并丢弃。
        let ids = Set(tasks.map(\.id))
        let kept = tasks.filter { $0.parentId.isEmpty || ids.contains($0.parentId) }

        // 【7】墓碑 90 天清理（顺序在【5】之后：本轮仍参与裁决）。
        var live: [String: Double] = [:]
        live.reserveCapacity(deleted.count)
        for (id, at) in deleted where !(now - at > tombstoneTTL) { live[id] = at }

        // 【8】meta 浅合并，b 覆盖 a。
        var meta = a.meta
        for (k, v) in b.meta { meta[k] = v }

        return MergeState(tasks: kept, deleted: live, meta: meta)
    }
}
