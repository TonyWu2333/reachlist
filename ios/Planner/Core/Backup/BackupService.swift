import Foundation

// MARK: - M-18 备份导出 / 导入（T-12）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/lib/backup.js（41 行）与 §2.5.2：
// · 导出：`{ version: 1, exportedAt: ISO, tasks: Task[] }`，`JSON.stringify(..., null, 2)`，
//   文件名 `planner-backup-YYYYMMDD.json`（改名后未改文件名），写到 Cache 目录并调系统分享；
// · 导入：校验 `tasks` 是数组 → 确认替换条数 → `replaceAll` 全量替换（走 migrate + normalize）
//   → 本地化结果文案；中英两套逐字取自 src/lib/i18n-en.js:core。
//
// 设计约束：
// · 只 import Foundation，可在 macOS 侧用 swiftc 与 JS 夹具逐字对比；
// · 任务序列化**唯一来源**仍是 `PlannerTask.jsJSONParts()`（T-05 起的约定）；
//   JSJSONPretty 只把紧凑片段按 JS pretty 规则重新排版，不另写一套字段序列化；
// · `now` / `timeZone` 注入使 `new Date().toISOString()` 与 `today()` 可复现；
// · 语言用 `isEnglish` 显式传入，T-19 落地后包一层即可，调用点不变；
// · 系统分享（UIActivityViewController）属 T-16 / M-17 的 UI 层，本模块只产出
//   `BackupSharePayload`（文件名 / 文本 / 标题 / Cache URL），不 import UIKit。

// MARK: - JS `JSON.stringify(value, null, 2)` 的等价排版

indirect enum JSJSONNode {
    case scalar(String)                     // 已是合法 JSON 片段（字符串含引号与转义）
    case array([JSJSONNode])
    case object([(String, JSJSONNode)])     // 保序，与 JS 对象键序一致
}

enum JSJSONPretty {

    static func encodeString(_ s: String) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]   // T-09：JS 不转义 "/"
        return String(data: try! e.encode(s), encoding: .utf8)!
    }

    /// 解析一个紧凑 JSON 片段（由 jsJSONParts 产生），保留原始标量文本。
    static func parse(_ text: String) -> JSJSONNode? {
        var i = text.startIndex
        return parseNode(text, &i)
    }

    private static func skipWS(_ s: String, _ i: inout String.Index) {
        while i < s.endIndex, s[i] == " " || s[i] == "\n" || s[i] == "\t" || s[i] == "\r" {
            i = s.index(after: i)
        }
    }

    private static func stringToken(_ s: String, _ i: inout String.Index) -> String? {
        guard i < s.endIndex, s[i] == "\"" else { return nil }
        let start = i
        i = s.index(after: i)
        while i < s.endIndex {
            if s[i] == "\\" {
                i = s.index(after: i)
                guard i < s.endIndex else { return nil }
                i = s.index(after: i)
            } else if s[i] == "\"" {
                i = s.index(after: i)
                return String(s[start..<i])
            } else {
                i = s.index(after: i)
            }
        }
        return nil
    }

    private static func parseNode(_ s: String, _ i: inout String.Index) -> JSJSONNode? {
        skipWS(s, &i)
        guard i < s.endIndex else { return nil }
        switch s[i] {
        case "{":
            i = s.index(after: i)
            var pairs: [(String, JSJSONNode)] = []
            skipWS(s, &i)
            if i < s.endIndex, s[i] == "}" {
                i = s.index(after: i)
                return .object([])
            }
            while i < s.endIndex {
                guard let keyToken = stringToken(s, &i) else { return nil }
                skipWS(s, &i)
                guard i < s.endIndex, s[i] == ":" else { return nil }
                i = s.index(after: i)
                guard let value = parseNode(s, &i) else { return nil }
                let key = String(keyToken.dropFirst().dropLast())
                pairs.append((key, value))
                skipWS(s, &i)
                if i < s.endIndex, s[i] == "," {
                    i = s.index(after: i)
                    continue
                }
                if i < s.endIndex, s[i] == "}" {
                    i = s.index(after: i)
                    return .object(pairs)
                }
                return nil
            }
            return nil
        case "[":
            i = s.index(after: i)
            var items: [JSJSONNode] = []
            skipWS(s, &i)
            if i < s.endIndex, s[i] == "]" {
                i = s.index(after: i)
                return .array([])
            }
            while i < s.endIndex {
                guard let value = parseNode(s, &i) else { return nil }
                items.append(value)
                skipWS(s, &i)
                if i < s.endIndex, s[i] == "," {
                    i = s.index(after: i)
                    continue
                }
                if i < s.endIndex, s[i] == "]" {
                    i = s.index(after: i)
                    return .array(items)
                }
                return nil
            }
            return nil
        case "\"":
            return stringToken(s, &i).map { .scalar($0) }
        default:
            let start = i
            while i < s.endIndex, s[i] != "," && s[i] != "]" && s[i] != "}" {
                i = s.index(after: i)
            }
            let raw = String(s[start..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? nil : .scalar(raw)
        }
    }

    /// JS pretty 规则：对象 / 数组每级 +2 空格，`": "` 带空格，空容器仍写 `{}` / `[]`。
    static func render(_ node: JSJSONNode, level: Int = 0) -> String {
        let pad = String(repeating: " ", count: level * 2)
        let inner = String(repeating: " ", count: (level + 1) * 2)
        switch node {
        case .scalar(let s):
            return s
        case .array(let items):
            if items.isEmpty { return "[]" }
            var lines: [String] = []
            for item in items {
                let rendered: String = render(item, level: level + 1)
                lines.append(inner + rendered)
            }
            let body: String = lines.joined(separator: ",\n")
            return "[\n" + body + "\n" + pad + "]"
        case .object(let pairs):
            if pairs.isEmpty { return "{}" }
            var lines: [String] = []
            for pair in pairs {
                let key: String = encodeString(pair.0)
                let rendered: String = render(pair.1, level: level + 1)
                lines.append(inner + key + ": " + rendered)
            }
            let body: String = lines.joined(separator: ",\n")
            return "{\n" + body + "\n" + pad + "}"
        }
    }
}

// MARK: - 备份服务

struct BackupSharePayload: Equatable, Sendable {
    let fileName: String
    let text: String
    let title: String
    let cacheURL: URL?
}

struct BackupImportResult: Equatable, Sendable {
    let ok: Bool
    /// 对齐 JS：校验失败有 message；用户取消时 `return { ok: false }` → message 为 nil；
    /// 成功时 `return { ok: true, message }` → **没有 count 字段**（尽管 backup.js 注释写了 count）。
    let message: String?
    let count: Int?
}

enum BackupService {

    static let version = 1

    // MARK: 本地化（i18n.js:t + i18n-en.js:core）

    private static func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) \(n == 1 ? one : (many ?? one + "s"))"
    }

    static func shareTitle(isEnglish: Bool) -> String {
        isEnglish ? "Reach List backup" : "可及清单备份"
    }

    static func invalidMessage(isEnglish: Bool) -> String {
        isEnglish ? "This isn't a valid backup file" : "这不是有效的备份文件"
    }

    static func confirmText(backupCount: Int, currentCount: Int, isEnglish: Bool) -> String {
        isEnglish
            ? "Replace your \(plural(currentCount, "task")) with the \(plural(backupCount, "task")) in the backup?"
            : "用备份里的 \(backupCount) 条任务替换当前的 \(currentCount) 条？"
    }

    static func restoredMessage(_ n: Int, isEnglish: Bool) -> String {
        isEnglish ? "Restored \(plural(n, "task"))" : "已恢复 \(n) 条任务"
    }

    // MARK: 日期（date.js:today + Date.prototype.toISOString）

    private static func localYmd(_ now: Date, _ tz: TimeZone) -> String {
        var c = PlannerCalendar.calendar
        c.timeZone = tz
        let p = c.dateComponents([.year, .month, .day], from: now)
        return "\(p.year ?? 0)-\(PlannerCalendar.pad(p.month ?? 1))-\(PlannerCalendar.pad(p.day ?? 1))"
    }

    static func fileName(now: Date, timeZone: TimeZone = .current) -> String {
        "planner-backup-" + localYmd(now, timeZone).replacingOccurrences(of: "-", with: "") + ".json"
    }

    /// `new Date().toISOString()`：UTC、毫秒固定三位、带 `Z`。
    static func exportedAt(_ now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return f.string(from: now)
    }

    // MARK: 导出（backup.js:exportBackup）

    /// `JSON.stringify({ version: 1, exportedAt, tasks }, null, 2)` 的逐字等价输出。
    static func exportText(_ tasks: [PlannerTask], now: Date) -> String {
        let taskNodes: [JSJSONNode] = tasks.map { t in
            .object(t.jsJSONParts().compactMap { part in
                JSJSONPretty.parse(part.value).map { (part.key, $0) }
            })
        }
        let root = JSJSONNode.object([
            ("version", .scalar("1")),
            ("exportedAt", .scalar(JSJSONPretty.encodeString(exportedAt(now)))),
            ("tasks", .array(taskNodes)),
        ])
        return JSJSONPretty.render(root)
    }

    /// 写到 Cache 目录并返回分享载荷。`UIActivityViewController` 由 UI 层（T-16）调起。
    static func makeSharePayload(
        _ tasks: [PlannerTask], now: Date = Date(),
        timeZone: TimeZone = .current, isEnglish: Bool = false,
        writeToCache: Bool = true
    ) throws -> BackupSharePayload {
        let name = fileName(now: now, timeZone: timeZone)
        let text = exportText(tasks, now: now)
        var url: URL?
        if writeToCache {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            url = base.appendingPathComponent(name)
            try text.write(to: url!, atomically: true, encoding: .utf8)
        }
        return BackupSharePayload(fileName: name, text: text,
                                  title: shareTitle(isEnglish: isEnglish), cacheURL: url)
    }

    // MARK: 导入（backup.js:importBackup）

    /// 校验 `tasks` 为数组；返回原始任务字典（交给 `TaskStore.replaceAll` 走 migrate + normalize）。
    static func parseBackup(text: String) -> [[String: Any]]? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let root = obj as? [String: Any],
              let arr = root["tasks"] as? [Any] else { return nil }
        // JS 只校验 Array.isArray(data.tasks)，元素类型交给 normalizeTask 兜底；
        // Swift 侧非对象元素按空字典进入 normalize，夹具未覆盖该输入（不改变有效备份行为）。
        return arr.map { ($0 as? [String: Any]) ?? [:] }
    }

    /// `confirmed` 对应 JS 的 `confirm(...)` 返回值；UI 先用 `confirmText` 弹确认框。
    static func importBackup(
        text: String, currentCount: Int, isEnglish: Bool, confirmed: Bool,
        replaceAll: ([[String: Any]]) -> Void
    ) -> BackupImportResult {
        guard let tasks = parseBackup(text: text) else {
            return BackupImportResult(ok: false, message: invalidMessage(isEnglish: isEnglish), count: nil)
        }
        guard confirmed else { return BackupImportResult(ok: false, message: nil, count: nil) }
        replaceAll(tasks)
        return BackupImportResult(ok: true, message: restoredMessage(tasks.count, isEnglish: isEnglish),
                                  count: nil)
    }
}
