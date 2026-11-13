import Foundation
import SwiftUI

// T-03 原型 / VERIFY-09：验证「以中文原文为键 + {placeholder} + 复数函数 +
// 缺失回退中文 + auto 跟随系统 + App 内切换即时刷新」在 Swift 侧能否等价实现。
//
// 这是**技术原型**，不是 M-23 LocalizationService 的实现：
// 词条表只收录验证 fixture 用到的 8 个键（复制自 baseline_commit 97a7c4c 的
// src/lib/i18n-en.js），全量 340 行词条与 String Catalog 方案留给 T-19。
// 契约来源：src/lib/i18n.js:t/fill/plural/applyLang/systemLang，src/lib/i18n-en.js。

enum LangPref: String, CaseIterable {
    case auto, zh, en

    var label: String {
        switch self {
        case .auto: return "跟随系统"
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    var next: LangPref {
        let all = LangPref.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

@MainActor
final class LocalizationProbe: ObservableObject {
    @Published var pref: LangPref = .auto {
        didSet { apply() }
    }
    @Published private(set) var effective: String = "zh"
    @Published private(set) var missingCount = 0
    private(set) var missingKeys: [String] = []

    init() { apply() }

    /// 对齐 i18n.js:systemLang 的 /^zh\b/i 边界判定，单独暴露以便断言。
    static func isZhLanguage(_ raw: String) -> Bool {
        raw.range(of: #"^zh\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// 对齐 i18n.js:systemLang —— /^zh\b/i.test(navigator.language || 'zh')
    static func systemLang() -> String {
        isZhLanguage(Locale.preferredLanguages.first ?? "zh") ? "zh" : "en"
    }

    /// 对齐 i18n.js:applyLang
    func apply() {
        effective = pref == .auto ? Self.systemLang() : pref.rawValue
    }

    /// 对齐 i18n.js:plural(n, one, many = one + 's')
    static func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) \(n == 1 ? one : (many ?? one + "s"))"
    }

    /// 对齐 i18n.js:fill —— 只替换参数里存在的 {key}，缺失的占位符原样保留。
    static func fill(_ s: String, _ p: [String: String]) -> String {
        guard !p.isEmpty else { return s }
        let re = try! NSRegularExpression(pattern: #"\{(\w+)\}"#)
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }
        var out = ""
        var cursor = 0
        for m in matches {
            let r = m.range
            out += ns.substring(with: NSRange(location: cursor, length: r.location - cursor))
            let key = ns.substring(with: m.range(at: 1))
            out += p[key] ?? ns.substring(with: r)
            cursor = r.location + r.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    /// 英文词典：值可以是字符串，也可以是 (params) -> String（复数/函数值）。
    /// 「共 {n} 项」故意不收录，用于验证缺失回退中文。
    static let en: [String: ([String: String]) -> String] = [
        "可及清单": { _ in "Reach List" },
        "四象限": { _ in "Matrix" },
        "撤销": { _ in "Undo" },
        "不提醒": { _ in "No reminder" },
        "提前 {n} 小时": { p in
            "\(plural(Int(p["n"] ?? "0") ?? 0, "hour")) before"
        },
        "服务器返回 {code}": { _ in "Server returned {code}" },
        "已恢复 {n} 条任务": { p in
            "Restored \(plural(Int(p["n"] ?? "0") ?? 0, "task"))"
        },
        "用备份里的 {a} 条任务替换当前的 {b} 条？": { p in
            let a = Int(p["a"] ?? "0") ?? 0
            let b = Int(p["b"] ?? "0") ?? 0
            return "Replace your \(plural(b, "task")) with the \(plural(a, "task")) in the backup?"
        },
    ]

    /// 对齐 i18n.js:t(zh, p)。非 en 直接 fill 中文；en 查表，缺失则回退中文并计数。
    func t(_ zh: String, _ p: [String: String] = [:]) -> String {
        if effective != "en" { return Self.fill(zh, p) }
        guard let entry = Self.en[zh] else {
            missingCount += 1
            missingKeys.append(zh)
            return Self.fill(zh, p)
        }
        return Self.fill(entry(p), p)
    }
}
