import Foundation

// MARK: - M-02 存储层（T-09）
//
// 逐字对齐 baseline_commit 97a7c4c 的：
// · src/lib/storage.js（38 行）：planner-data / planner-settings 两个键、损坏原文另存
// · src/lib/store.js:23（7 项 settings 默认值）、:135-148（initStore 的加载与迁移）
// · §2.5.2 持久化结构：{ version: 1, tasks: Task[], deleted: { [id]: ms } }
//
// 硬约束（OPEN-04=A / VERIFY-01）：planner-data 的 JSON **必须逐字等价** JS 的
// JSON.stringify({version:1,tasks,deleted})，尤其 Task 的 17 键顺序。JSONEncoder
// 不保证键序，故这里用 PlannerTask.jsJSONString() 显式拼接，不交给 Codable。
// `deleted` 是对象，键序不影响任何解析方（JS Object.entries 只用于逐 id 比较），
// Swift 字典无序，故按 key 排序输出以保证确定性；这是唯一一处有意的键序差异。

// MARK: settings（store.js:23 / storage.js:27-38）

struct PlannerSettings: Equatable, Sendable {
    var lang: String
    var showLunar: Bool
    var showHoliday: Bool
    var remindOn: Bool
    var defaultRemind: Int
    var syncOn: Bool
    var syncCode: String

    /// store.js:23 的 7 个字段与默认值。`lang` 是 0.12.0 新增字段。
    static let defaults = PlannerSettings(
        lang: "auto", showLunar: true, showHoliday: true, remindOn: true,
        defaultRemind: 0, syncOn: false, syncCode: ""
    )

    /// `Object.assign(state.settings, settings)`：缺字段保留默认（尤其旧设置缺 `lang` → 'auto'）。
    /// 只接受类型正确的值；脏值（字符串塞进 Bool 等）按「无此字段」处理，与
    /// PlannerTask.normalize 的「有意窄化」一致，不属功能语义删减。
    static func merged(from raw: [String: Any]) -> PlannerSettings {
        var s = defaults
        if let v = raw["lang"] as? String { s.lang = v }
        if let v = boolValue(raw["showLunar"]) { s.showLunar = v }
        if let v = boolValue(raw["showHoliday"]) { s.showHoliday = v }
        if let v = boolValue(raw["remindOn"]) { s.remindOn = v }
        if let v = intValue(raw["defaultRemind"]) { s.defaultRemind = v }
        if let v = boolValue(raw["syncOn"]) { s.syncOn = v }
        if let v = raw["syncCode"] as? String { s.syncCode = v }
        return s
    }

    /// 固定键序输出（settings 是对象，键序无语义，但便于夹具逐字对比）。
    var jsJSONString: String {
        let frag = { (v: Encodable) in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            return String(data: try! encoder.encode(v), encoding: .utf8)!
        }
        return "{\"lang\":\(frag(lang)),\"showLunar\":\(frag(showLunar)),"
            + "\"showHoliday\":\(frag(showHoliday)),\"remindOn\":\(frag(remindOn)),"
            + "\"defaultRemind\":\(frag(defaultRemind)),\"syncOn\":\(frag(syncOn)),"
            + "\"syncCode\":\(frag(syncCode))}"
    }

    private static func boolValue(_ v: Any?) -> Bool? {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        return nil
    }

    private static func intValue(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        return nil
    }
}

// MARK: 存储后端（storage.js）

/// 唯一与「存在哪」打交道的抽象。文件实现用于 App，内存实现用于夹具 / XCTest。
protocol PlannerDataStorage: AnyObject {
    func read(key: String) -> String?
    func write(key: String, value: String)
    /// `storage.js:17` 数据损坏时先另存原文，避免被下一次保存覆盖。
    func archiveCorrupt(_ rawValue: String, now: Double)
}

final class FilePlannerDataStorage: PlannerDataStorage {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// App 默认落点：Application Support/Planner/，不进 iCloud、不进 UserDefaults。
    static var appDefault: FilePlannerDataStorage {
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return FilePlannerDataStorage(directory: base.appendingPathComponent("Planner", isDirectory: true))
    }

    private func url(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    func read(key: String) -> String? {
        try? String(contentsOf: url(key), encoding: .utf8)
    }

    func write(key: String, value: String) {
        try? value.write(to: url(key), atomically: true, encoding: .utf8)
    }

    func archiveCorrupt(_ rawValue: String, now: Double) {
        let key = "planner-data-corrupt-\(Int(now))"
        write(key: key, value: rawValue)
    }
}

/// DEV / 测试用：不落盘，保留写入历史便于断言防抖与「损坏原文另存」。
final class InMemoryPlannerDataStorage: PlannerDataStorage {
    private(set) var values: [String: String] = [:]
    private(set) var writes: [(key: String, value: String)] = []
    private(set) var corrupt: [String] = []

    /// 预置的原始数据（模拟首次启动 / 恢复）。
    init(data: String? = nil, settings: String? = nil) {
        if let data { values["planner-data"] = data }
        if let settings { values["planner-settings"] = settings }
    }

    func read(key: String) -> String? { values[key] }

    func write(key: String, value: String) {
        values[key] = value
        writes.append((key, value))
    }

    func archiveCorrupt(_ rawValue: String, now: Double) {
        corrupt.append(rawValue)
        write(key: "planner-data-corrupt-\(Int(now))", value: rawValue)
    }
}

// MARK: planner-data 读写（storage.js:8-25 / store.js:135-142）

enum PlannerDataFile {
    static let dataKey = "planner-data"
    static let settingsKey = "planner-settings"

    struct Loaded {
        var tasks: [PlannerTask]
        var deleted: [String: Double]
        /// `initStore:142`：检测到旧格式 `subtasks[]` 后要立即 flush 落盘。
        var hadLegacy: Bool
        /// `storage.js:15-20`：解析失败时已另存原文并回退空数据。
        var wasCorrupt: Bool
    }

    static func load(
        from storage: PlannerDataStorage,
        now: Double = Date().timeIntervalSince1970 * 1000,
        makeID: () -> String = { UUID().uuidString.lowercased() }
    ) -> Loaded {
        guard let raw = storage.read(key: dataKey) else {
            return Loaded(tasks: [], deleted: [:], hadLegacy: false, wasCorrupt: false)
        }
        guard let bytes = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: bytes),
              let root = obj as? [String: Any],
              let rawTasks = root["tasks"] as? [Any] else {
            storage.archiveCorrupt(raw, now: now)
            return Loaded(tasks: [], deleted: [:], hadLegacy: false, wasCorrupt: true)
        }

        var deleted: [String: Double] = [:]
        if let d = root["deleted"] as? [String: Any] {
            for (k, v) in d {
                if let n = v as? NSNumber { deleted[k] = n.doubleValue }
                else if let n = v as? Double { deleted[k] = n }
            }
        }

        return Loaded(
            tasks: LegacyMigration.normalizedTasks(rawTasks, now: now, makeID: makeID),
            deleted: deleted,
            hadLegacy: LegacyMigration.containsLegacySubtasks(rawTasks),
            wasCorrupt: false
        )
    }

    /// `save({ version: 1, tasks, deleted })` 的逐字等价输出。
    static func save(tasks: [PlannerTask], deleted: [String: Double], to storage: PlannerDataStorage) {
        let frag = { (v: Encodable) in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            return String(data: try! encoder.encode(v), encoding: .utf8)!
        }
        let tasksJSON = tasks.map { $0.jsJSONString() }.joined(separator: ",")
        let deletedJSON = "{" + deleted.keys.sorted().map { key in
            "\(frag(key)):\(frag(deleted[key]!))"
        }.joined(separator: ",") + "}"
        let out = "{\"version\":1,\"tasks\":[\(tasksJSON)],\"deleted\":\(deletedJSON)}"
        storage.write(key: dataKey, value: out)
    }

    static func loadSettings(from storage: PlannerDataStorage) -> PlannerSettings {
        guard let raw = storage.read(key: settingsKey),
              let bytes = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: bytes),
              let dict = obj as? [String: Any] else { return .defaults }
        return PlannerSettings.merged(from: dict)
    }

    static func saveSettings(_ settings: PlannerSettings, to storage: PlannerDataStorage) {
        storage.write(key: settingsKey, value: settings.jsJSONString)
    }
}
