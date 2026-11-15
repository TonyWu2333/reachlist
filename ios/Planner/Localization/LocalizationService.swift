import Foundation

// MARK: - M-23 本地化服务（T-19 正式实现）
//
// 单一收口，逐字对齐 baseline 97a7c4c 的 src/lib/i18n.js（35 行）与 i18n-en*.js（340 行）：
// · 中文原文为键；英文值可为字符串或函数（复数 / 分支 / 月份名 / 相对日期）；
// · fill() 只替换传入的 {placeholder}，未知占位符原样保留；
// · 缺失词条回退中文，DEV 下打印 [i18n] missing（对齐 console.warn）；
// · auto 跟随系统（/^zh\b/i，系统为空时按 'zh' 兜底），zh / en 强制，其它值一律跟随系统；
// · 切换即时刷新：调用方每次渲染都读 environment 的 lang，改 @State 即重算（VERIFY-09）。
//
// 词条来源：LocalizationDictionary.swift（生成器从上游词典产出，勿手改）
//          LocalizationFunctions.swift（19 条函数值，按上游函数体逐字组装）
// 旧入口 AppStrings.t / FeatureStrings.t 保留签名不变，全部转发到这里。

enum LocalizationService {

    // MARK: 词条查找

    /// i18n.js:t(zh, p)。函数值结果仍会经 fill —— 与 JS 的 `fill(e(p||{}), p)` 一致。
    static func t(_ key: String, lang: String, _ params: [String: String] = [:]) -> String {
        guard lang == "en" else { return fill(key, params) }
        if let template = LocalizationFunctions.evaluate(key, params) {
            return fill(template, params)
        }
        if let template = LocalizationDictionary.english[key] {
            return fill(template, params)
        }
        if let template = LocalizationDictionary.dev[key] {
            return fill(template, params)
        }
        #if DEBUG
        print("[i18n] missing: \(key)")
        #endif
        return fill(key, params)
    }

    /// 该 key 是否有登记词条（业务 / DEV / 函数值），供「全界面无缺失」断言。
    static func hasEntry(_ key: String) -> Bool {
        LocalizationDictionary.allKeys.contains(key)
            || LocalizationDictionary.dev[key] != nil
            || LocalizationFunctions.evaluate(key, [:]) != nil
    }

    static var businessKeyCount: Int { LocalizationDictionary.allKeys.count }
    static var devKeyCount: Int { LocalizationDictionary.dev.count }

    // MARK: 占位符

    /// i18n.js:fill —— `/\{(\w+)\}/g` 单次扫描；JS 的 \w 是 ASCII [A-Za-z0-9_]，
    /// 不用 ICU 的 \w（它会把 Unicode 字母也算进去）。替换值不会再被二次扫描。
    static func fill(_ template: String, _ params: [String: String]) -> String {
        guard template.contains("{"),
              let re = try? NSRegularExpression(pattern: #"\{([A-Za-z0-9_]+)\}"#) else {
            return template
        }
        let ns = template as NSString
        let matches = re.matches(in: template, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return template }
        var out = ""
        var cursor = 0
        for match in matches {
            let range = match.range
            if range.location > cursor {
                out += ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
            }
            let name = ns.substring(with: match.range(at: 1))
            out += params[name] ?? ns.substring(with: range)
            cursor = range.location + range.length
        }
        if cursor < ns.length { out += ns.substring(from: cursor) }
        return out
    }

    // MARK: 复数

    /// i18n.js:plural(n, one, many = one + 's') —— n === 1 用单数。
    static func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) \(n == 1 ? one : (many ?? one + "s"))"
    }

    // MARK: 语言判定

    /// i18n.js:systemLang 的 /^zh\b/i（T-03 原型 LocalizationProbe 已用同一写法对齐 22 条夹具）。
    static func isZhLanguage(_ raw: String) -> Bool {
        raw.range(of: #"^zh\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// JS 的 `navigator.language || 'zh'`：空串按中文兜底。
    static func systemLang(_ preferred: String) -> String {
        isZhLanguage(preferred.isEmpty ? "zh" : preferred) ? "zh" : "en"
    }

    /// i18n.js:applyLang(pref) —— 只有 'zh' / 'en' 是强制值，其余（含 auto、脏值）跟随系统。
    static func effectiveLang(_ pref: String, system: String) -> String {
        pref == "zh" || pref == "en" ? pref : systemLang(system)
    }

    static func effectiveLang(_ pref: AppLanguagePref, system: String) -> String {
        effectiveLang(pref.rawValue, system: system)
    }

    /// applyLang 同时设置 document.documentElement.lang。iOS 无 DOM，保留该映射供契约对齐，
    /// 界面实际刷新由 EnvironmentValues.appLanguage 驱动（ReachText.swift）。
    static func htmlLang(_ lang: String) -> String {
        lang == "en" ? "en" : "zh-CN"
    }
}
