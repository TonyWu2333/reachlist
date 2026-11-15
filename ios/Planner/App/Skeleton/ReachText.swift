import SwiftUI

// MARK: - M-20 / M-23 之间的最小桥梁
//
// 语言偏好由 AppRootView 持有，经 EnvironmentValues.appLanguage 下发；
// 修改 @State 即触发 body 重算，实现「切换即时刷新」（VERIFY-09 已验证的机制）。
// T-19 接入 M-23 全量词条后，只需替换 AppStrings 内部字典，调用方不变。

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: String = "zh"
}

extension EnvironmentValues {
    var appLanguage: String {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

struct ReachText: View {
    let key: String
    var params: [String: String] = [:]

    @Environment(\.appLanguage) private var lang

    var body: some View {
        Text(AppStrings.t(key, lang: lang, params))
    }
}
