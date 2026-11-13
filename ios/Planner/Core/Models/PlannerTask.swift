import Foundation

// MARK: - 任意 JSON 值
//
// 用途：把原始任务 JSON 解成动态值，交给 normalize(_:) 复现 JS 的类型强制转换。
// 这样 PlannerTask 保持 Codable（OPEN-04=A），且只有「一份」规范化逻辑，
// 避免 RISK-01 提到的「三端逻辑分叉」。

indirect enum PlannerJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([PlannerJSONValue])
    case object([String: PlannerJSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([PlannerJSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: PlannerJSONValue].self) { self = .object(v); return }
        throw DecodingError.typeMismatch(
            PlannerJSONValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
        )
    }

    var raw: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let a): return a.map { $0.raw }
        case .object(let o): return o.mapValues { $0.raw }
        }
    }
}

// MARK: - JS 语义助手（store.js:normalizeTask 依赖的动态类型规则）

enum JSBridge {
    /// 区分「key 不存在」与「值为 null」——remind 规则需要这个区分。
    static func isUndefinedOrNull(_ v: Any?) -> Bool {
        guard let v else { return true }
        return v is NSNull
    }

    /// JS `!!v`
    static func truthy(_ v: Any?) -> Bool {
        guard let v, !(v is NSNull) else { return false }
        if let b = v as? Bool { return b }
        if let n = v as? Double { return n != 0 && !n.isNaN }
        if let n = v as? Int { return n != 0 }
        if let s = v as? String { return !s.isEmpty }
        return true // 数组 / 对象在 JS 里恒为 truthy（含空数组、空对象）
    }

    /// JS `Number(v)`：undefined → NaN，null → 0，字符串按数值解析
    static func number(_ v: Any?) -> Double {
        guard let v else { return .nan }
        if v is NSNull { return 0 }
        if let n = v as? Double { return n }
        if let n = v as? Int { return Double(n) }
        if let b = v as? Bool { return b ? 1 : 0 }
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return 0 }
            return Double(t) ?? .nan
        }
        if let a = v as? [Any] {
            if a.isEmpty { return 0 }
            if a.count == 1 { return number(a[0]) }
            return .nan
        }
        return .nan
    }

    /// JS `Number(v) || fallback`（0、NaN、-0 都走 fallback）
    static func numberOr(_ v: Any?, fallback: Double) -> Double {
        let n = number(v)
        return (!n.isNaN && n != 0) ? n : fallback
    }

    /// JS `String(v ?? '')`。数组/对象走 String(describing:)——仅脏数据会触发，
    /// §2.5.1 的类型约束下 title/note/id/parentId 均为字符串。
    static func string(_ v: Any?) -> String {
        guard let v, !(v is NSNull) else { return "" }
        if let s = v as? String { return s }
        if let b = v as? Bool { return b ? "true" : "false" }
        if let n = v as? Double {
            if n.isNaN { return "NaN" }
            if n.isInfinite { return n > 0 ? "Infinity" : "-Infinity" }
            if n == n.rounded() && abs(n) < 1e15 { return String(Int64(n)) }
            return String(n)
        }
        if let n = v as? Int { return String(n) }
        return String(describing: v)
    }
}

// MARK: - PlannerTask
//
// M-01 / A-01。与 src/lib/store.js:normalizeTask 逐字等价。
//
// 【硬约束：属性声明顺序】
// shared/merge.js:taskSig = JSON.stringify(除 updatedAt 外所有字段)，
// 键序敏感，平局时用来做确定性裁决（§2.6.1 / VERIFY-01）。
// 因此下面的 17 个属性顺序必须等同于 JS normalizeTask 返回对象的键序：
//   id, title, note, date, time, important, urgent, done, dropped,
//   createdAt, doneAt, repeat, doneDates, skipDates, remind, parentId, updatedAt
// 不得重排、不得插入新字段。Swift 的 `repeat` 是关键字，故属性名 repeatRule
// 经 CodingKeys 映射回 JSON 键 "repeat"。

struct PlannerTask: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var note: String
    var date: String
    var time: String
    var important: Bool
    var urgent: Bool
    var done: Bool
    var dropped: Bool
    var createdAt: Double
    var doneAt: Double?
    var repeatRule: String
    var doneDates: [String]
    var skipDates: [String]
    var remind: Int?
    var parentId: String
    var updatedAt: Double

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, note, date, time, important, urgent, done, dropped
        case createdAt, doneAt
        case repeatRule = "repeat"
        case doneDates, skipDates, remind, parentId, updatedAt
    }

    /// JSON 键序的唯一真源，供单测断言与未来 VERIFY-01 的 taskSig 序列化复用。
    static let jsonKeyOrder: [String] = [
        "id", "title", "note", "date", "time", "important", "urgent", "done", "dropped",
        "createdAt", "doneAt", "repeat", "doneDates", "skipDates", "remind", "parentId", "updatedAt"
    ]

    // Codable 编码：用于 Swift 侧通用编解码场景。
    // 【更正 v1】这里显式写出全部键，只能保证「doneAt / remind 为 nil 时输出 null、不省略键」
    //（合成的 Encodable 会用 encodeIfPresent 省略），**保证不了键序**：
    // VERIFY-01 实测 Apple 平台的 JSONEncoder 按内部哈希顺序输出，
    // 与 encode(_:forKey:) 的调用顺序无关。契约输出必须走 jsJSONString()。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(note, forKey: .note)
        try c.encode(date, forKey: .date)
        try c.encode(time, forKey: .time)
        try c.encode(important, forKey: .important)
        try c.encode(urgent, forKey: .urgent)
        try c.encode(done, forKey: .done)
        try c.encode(dropped, forKey: .dropped)
        try c.encode(createdAt, forKey: .createdAt)
        if let doneAt { try c.encode(doneAt, forKey: .doneAt) }
        else { try c.encodeNil(forKey: .doneAt) }
        try c.encode(repeatRule, forKey: .repeatRule)
        try c.encode(doneDates, forKey: .doneDates)
        try c.encode(skipDates, forKey: .skipDates)
        if let remind { try c.encode(remind, forKey: .remind) }
        else { try c.encodeNil(forKey: .remind) }
        try c.encode(parentId, forKey: .parentId)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    // MARK: 规范化

    static func isValidYMD(_ s: String) -> Bool {
        let p = s.split(separator: "-", omittingEmptySubsequences: false)
        return p.count == 3
            && p[0].count == 4 && p[1].count == 2 && p[2].count == 2
            && p.allSatisfy { part in part.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }
    }

    static func isValidHM(_ s: String) -> Bool {
        guard s.count == 5 else { return false }
        let chars = Array(s.utf8)
        return [chars[0], chars[1], chars[3], chars[4]].allSatisfy { $0 >= 48 && $0 <= 57 }
            && chars[2] == 58 // ':'
    }

    /// store.js:dateList —— 只保留符合 ^\d{4}-\d{2}-\d{2}$ 的字符串
    static func dateList(_ v: Any?) -> [String] {
        guard let a = v as? [Any] else { return [] }
        return a.compactMap { $0 as? String }.filter(isValidYMD)
    }

    /// store.js:normalizeTask。now 可注入以便与 JS oracle 做确定性对比。
    static func normalize(
        _ raw: [String: Any],
        now: Double = Date().timeIntervalSince1970 * 1000,
        makeID: () -> String = { UUID().uuidString.lowercased() } // 对齐 JS crypto.randomUUID()
    ) -> PlannerTask {
        // id: String(t.id ?? uid())
        // T-09：makeID 可注入，让缺 id 的旧数据 / 子任务在夹具里也是确定性的
        // （JS 侧的 uid() 由 crypto.randomUUID 提供，T-09 生成器固定为 t09-N）。
        let id: String
        if JSBridge.isUndefinedOrNull(raw["id"]) {
            id = makeID()
        } else {
            id = JSBridge.string(raw["id"])
        }

        let title = JSBridge.string(raw["title"])
            .trimmingCharacters(in: .whitespacesAndNewlines) // String(...).trim()
        let note = JSBridge.string(raw["note"])

        // 注意：date/time 的校验针对「原始值」；repeat 也接收「原始 date」，不是规范化后的值。
        let rawDate = raw["date"] as? String ?? ""
        let rawTime = raw["time"] as? String ?? ""
        let date = isValidYMD(rawDate) ? rawDate : ""
        let time = isValidHM(rawTime) ? rawTime : ""

        let important = JSBridge.truthy(raw["important"])
        let urgent = JSBridge.truthy(raw["urgent"])
        let dropped = JSBridge.truthy(raw["dropped"])
        let done = JSBridge.truthy(raw["done"]) || dropped

        let createdAt = JSBridge.numberOr(raw["createdAt"], fallback: now)

        // doneAt: t.doneAt ?? null。按 §2.5.1 类型约束收敛为 Number|null；
        // 脏值（字符串/布尔）按 null 处理，这是唯一一处有意窄化。
        let doneAt: Double? = {
            guard let v = raw["doneAt"], !(v is NSNull) else { return nil }
            let n = JSBridge.number(v)
            return (n.isNaN || n.isInfinite) ? nil : n
        }()

        let repeatRule = RepeatNormalization.normalize(raw["repeat"], date: raw["date"])
        let doneDates = dateList(raw["doneDates"])
        let skipDates = dateList(raw["skipDates"])

        // remind: Number.isInteger(t.remind) && >=0 ? t.remind
        //         : t.remind === undefined && t.time ? 0 : null
        // 必须区分「key 缺失」与「显式 null」。
        let remind: Int? = {
            if let v = raw["remind"] {
                if v is NSNull { return nil }
                // JSON 解析得到 NSNumber / Double；手写字典也可能直接给 Swift Int。
                // 只接受数值类型：字符串、布尔都不算 Number.isInteger。
                if let n = v as? Double {
                    guard n.isFinite, n >= 0, n == n.rounded(), n <= Double(Int.max) else {
                        return nil
                    }
                    return Int(n)
                }
                if let n = v as? Int, n >= 0 { return n }
                return nil // 字符串 / 负数 / 小数 / 布尔都不算 Number.isInteger
            }
            return JSBridge.truthy(raw["time"]) ? 0 : nil
        }()

        // parentId: t.parentId ? String(...) : ''
        let parentId: String = {
            guard let v = raw["parentId"] else { return "" }
            return JSBridge.truthy(v) ? JSBridge.string(v) : ""
        }()

        // Number(t.updatedAt) || Number(t.createdAt) || Date.now()
        let updatedAt = JSBridge.numberOr(
            raw["updatedAt"],
            fallback: JSBridge.numberOr(raw["createdAt"], fallback: now)
        )

        return PlannerTask(
            id: id, title: title, note: note, date: date, time: time,
            important: important, urgent: urgent, done: done, dropped: dropped,
            createdAt: createdAt, doneAt: doneAt, repeatRule: repeatRule,
            doneDates: doneDates, skipDates: skipDates, remind: remind,
            parentId: parentId, updatedAt: updatedAt
        )
    }

    /// 从 planner-data 风格 JSON 读取任务数组（迁移 + 规范化）。
    static func normalizedTasks(
        from data: Data,
        now: Double = Date().timeIntervalSince1970 * 1000,
        makeID: () -> String = { UUID().uuidString.lowercased() }
    ) throws -> [PlannerTask] {
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let root = obj as? [String: Any], let arr = root["tasks"] as? [Any] else {
            return []
        }
        return LegacyMigration.migrate(arr, now: now).map { normalize($0, now: now, makeID: makeID) }
    }

    /// 17 个键的 `(key, value 片段)` 序列，顺序即契约顺序。
    ///
    /// 【VERIFY-01 结论，2026-11-13 实测】Apple 平台 JSONEncoder 不保证键序：
    /// 即使 encode(to:) 按固定顺序调用，15 条 fixture 仍得到 15 种不同的键顺序；
    /// 而 shared/merge.js:taskSig 依赖 JSON.stringify 的插入顺序做平局裁决（§2.6.1）。
    /// 因此 planner-data JSON 写入与 taskSig 必须走这里的有序拼接。
    /// 单值片段仍交给 JSONEncoder，保证字符串转义、布尔、整数值 Double 的表示与 JS 一致。
    ///
    /// T-05 起，本方法是「唯一」的序列化片段源：`jsJSONString()`（持久化）与
    /// `MergeEngine.taskSig`（合并平局裁决）都从这里派生，避免出现第二套序列化。
    func jsJSONParts() -> [(key: String, value: String)] {
        func frag<T: Encodable>(_ v: T) -> String {
            // T-09 实测：JSONEncoder 默认把 "/" 转义成 "\/"，而 JS JSON.stringify 不转义。
            // 含 URL 的 title / note / 连接码会因此与 Web/Android 逐字不一致（A-40）。
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            return String(data: try! encoder.encode(v), encoding: .utf8)!
        }
        let parts: [(key: String, value: String)] = [
            ("id", frag(id)),
            ("title", frag(title)),
            ("note", frag(note)),
            ("date", frag(date)),
            ("time", frag(time)),
            ("important", frag(important)),
            ("urgent", frag(urgent)),
            ("done", frag(done)),
            ("dropped", frag(dropped)),
            ("createdAt", frag(createdAt)),
            ("doneAt", doneAt.map { frag($0) } ?? "null"),
            ("repeat", frag(repeatRule)),
            ("doneDates", frag(doneDates)),
            ("skipDates", frag(skipDates)),
            ("remind", remind.map { frag($0) } ?? "null"),
            ("parentId", frag(parentId)),
            ("updatedAt", frag(updatedAt))
        ]
        assert(parts.count == PlannerTask.jsonKeyOrder.count)
        assert(parts.map(\.key) == PlannerTask.jsonKeyOrder)
        return parts
    }

    /// JS `JSON.stringify(task)` 的逐字等价输出（含键序）。
    func jsJSONString() -> String {
        "{" + jsJSONParts().map { "\"\($0.key)\":" + $0.value }.joined(separator: ",") + "}"
    }

    /// 契约输出（持久化 / taskSig / 跨端对比）的唯一出口。
    /// 只依赖 Foundation，可在 macOS 侧用 swiftc 做跨端对比。
    func jsonData() throws -> Data {
        Data(jsJSONString().utf8)
    }
}

// MARK: - Decodable
//
// 解码初始化器放在 extension 里，才能让编译器继续合成成员逐一初始化器
// （自定义 init 写在 struct 主体内会抑制 memberwise init 的合成）。
// 解码走同一份 normalize，不写第二套规则。
extension PlannerTask {
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        var dict: [String: Any] = [:]
        for key in c.allKeys {
            dict[key.stringValue] = try c.decode(PlannerJSONValue.self, forKey: key).raw
        }
        self = PlannerTask.normalize(dict)
    }
}
