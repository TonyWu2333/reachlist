import Foundation

// MARK: - M-20 语言偏好 + M-23 兼容入口
//
// T-19 起，全部词条与翻译逻辑由 Localization/LocalizationService.swift 单一收口：
// 上游 211 个词条（含 19 条函数值）由 generate_t19_fixtures.mjs 从 baseline 97a7c4c
// 的 i18n-en*.js 逐字产出，自检页 / 原型页的 30 条 DEV 词条单独存放。
// 本文件只保留语言偏好枚举与旧调用签名，178 处 AppStrings.t 调用点零改动。

enum AppLanguagePref: String, CaseIterable, Sendable {
    case auto, zh, en

    var label: String {
        switch self {
        case .auto: return "跟随系统"
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

enum AppStrings {

    /// 对齐 i18n.js:systemLang 的 /^zh\b/i。
    static func isZhLanguage(_ raw: String) -> Bool {
        LocalizationService.isZhLanguage(raw)
    }

    static func systemLang(_ preferred: String) -> String {
        LocalizationService.systemLang(preferred)
    }

    /// 对齐 i18n.js:applyLang —— auto 走系统语言，其余直接用偏好值。
    static func effectiveLang(_ pref: AppLanguagePref, system: String) -> String {
        LocalizationService.effectiveLang(pref, system: system)
    }

    /// 对齐 i18n.js:fill —— 只替换传入的 {key}，未知占位符原样保留。
    static func fill(_ template: String, _ params: [String: String]) -> String {
        LocalizationService.fill(template, params)
    }

    /// 对齐 i18n.js:t —— 中文原文为键；英文缺失时回退中文（DEV 下打印 missing）。
    static func t(_ zh: String, lang: String, _ params: [String: String] = [:]) -> String {
        LocalizationService.t(zh, lang: lang, params)
    }

    /// 对齐 i18n.js:plural(n, one, many = one + 's')
    static func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        LocalizationService.plural(n, one, many)
    }
}
