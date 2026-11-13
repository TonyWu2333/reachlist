import Foundation

// MARK: - T-16 / T-17 词条入口（T-19 起转发 M-23）
//
// T-16 时上游 19 条函数值词条无法用 [String: String] 承载，这里曾按上游函数体手写桥接。
// T-19 已由 Localization/LocalizationFunctions.swift 全量实现并以 JS oracle 逐字校验，
// 本文件保留 t / s / plural 三个签名，41 处调用点零改动。

enum FeatureStrings {

    static func plural(_ n: Int, _ one: String) -> String {
        LocalizationService.plural(n, one)
    }

    /// 与 i18n.js:t(zh, params) 等价。
    static func t(_ key: String, lang: String, _ params: [String: String] = [:]) -> String {
        LocalizationService.t(key, lang: lang, params)
    }

    /// 一句话提示的别名，历史上与 t 同义。
    static func s(_ key: String, _ lang: String, _ params: [String: String] = [:]) -> String {
        LocalizationService.t(key, lang: lang, params)
    }
}
