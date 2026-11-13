import Foundation

// MARK: - 旧格式迁移（M-01 / A-02）
//
// 来源：src/lib/store.js:55-71 migrate、:135-148 initStore
//
// 旧格式里子任务嵌在父任务的 subtasks: [{id,title,done,doneDates}] 数组里。
// 读入时拆成独立 Task，继承父任务象限，createdAt = parent.createdAt + i + 1。
// initStore 检测到旧格式后立即 flush() 落盘（由 T-09 的 TaskStore 调用）。

enum LegacyMigration {
    /// initStore:142 —— data.tasks.some(t => Array.isArray(t.subtasks))
    static func containsLegacySubtasks(_ rawTasks: [Any]) -> Bool {
        rawTasks.contains { item in
            (item as? [String: Any])?["subtasks"] as? [Any] != nil
        }
    }

    /// 返回「未规范化」的原始字典数组，顺序与 JS 的 flatMap 一致：
    /// 每个父任务紧跟着它那组（过滤后）子任务。
    static func migrate(
        _ rawTasks: [Any],
        now: Double = Date().timeIntervalSince1970 * 1000
    ) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for case let parent as [String: Any] in rawTasks {
            out.append(parent)
            guard let subs = parent["subtasks"] as? [Any] else { continue }

            // (Number(t.createdAt) || Date.now()) + i + 1
            let parentCreated = JSBridge.numberOr(parent["createdAt"], fallback: now)

            // JS 是 .filter(...).map((x, i) => ...)：i 是「过滤后」的索引。
            var index = 0
            for case let x as [String: Any] in subs {
                let title = JSBridge.string(x["title"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }

                var child: [String: Any] = [:]
                // JS 对象里 x.id 若为 undefined，normalizeTask 会生成新 id；
                // 因此这里同样「不写入该键」，而不是塞 null。
                if let v = x["id"] { child["id"] = v }
                if let v = x["title"] { child["title"] = v }
                if let v = x["done"] { child["done"] = v }
                if let v = x["doneDates"] { child["doneDates"] = v }
                if let v = parent["id"] { child["parentId"] = v }
                if let v = parent["important"] { child["important"] = v }
                if let v = parent["urgent"] { child["urgent"] = v }
                child["createdAt"] = parentCreated + Double(index) + 1

                out.append(child)
                index += 1
            }
        }
        return out
    }

    /// initStore:137 / replaceAll:245 的等价入口：migrate → normalize
    static func normalizedTasks(
        _ rawTasks: [Any],
        now: Double = Date().timeIntervalSince1970 * 1000,
        makeID: () -> String = { UUID().uuidString.lowercased() }
    ) -> [PlannerTask] {
        migrate(rawTasks, now: now).map { PlannerTask.normalize($0, now: now, makeID: makeID) }
    }
}
