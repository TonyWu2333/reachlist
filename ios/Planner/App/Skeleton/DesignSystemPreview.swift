import SwiftUI

// MARK: - T-13 骨架自检页（不是业务界面）
//
// 放在「我的」tab，用于真机核对 A-42 / A-44 的可观察项：4 tab 图标、明暗两套令牌、
// 45 个自定义图标、Toast 2s/4s、四档触感、系统 .sheet 玻璃与下滑关闭、语言即时刷新。
// 业务视图由 T-14 ~ T-17 替换本页，届时本页可整体移除。

struct DesignSystemPreview: View {
    @Binding var langPref: AppLanguagePref
    let dayChangeCount: Int

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appLanguage) private var lang
    @EnvironmentObject private var toastCenter: ToastCenter

    @State private var sheetOpen = false
    @State private var showPrototype = false
    @State private var showT02 = false
    @State private var showT14 = false

    private var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
    private var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    paletteSection
                    iconsSection
                    feedbackSection
                    footer
                }
                .padding(DesignTokens.gutter)
            }
            .navigationTitle(Text(AppStrings.t("设计系统自检", lang: lang)))
            .reachSheet(isPresented: $sheetOpen) {
                VStack(spacing: 16) {
                    Text(AppStrings.t("系统弹窗", lang: lang))
                        .font(DesignTokens.font(.h2))
                    Text(AppStrings.t("系统弹窗由 SwiftUI .sheet 提供下滑关闭", lang: lang))
                        .font(DesignTokens.font(.sub))
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .fullScreenCover(isPresented: $showPrototype) {
                prototypeCover
            }
            .fullScreenCover(isPresented: $showT02) {
                t02Cover
            }
            .fullScreenCover(isPresented: $showT14) {
                t14Cover
            }
        }
    }

    // MARK: 区块

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.t("当前主题", lang: lang) + "：" + (scheme == .dark ? AppStrings.t("深色", lang: lang) : AppStrings.t("浅色", lang: lang)))
                .font(DesignTokens.font(.h3))
            Picker(AppStrings.t("语言", lang: lang), selection: $langPref) {
                ForEach(AppLanguagePref.allCases, id: \.self) { pref in
                    Text(pref.label).tag(pref)
                }
            }
            .pickerStyle(.segmented)
            Text("iOS 系统风格 / Liquid Glass · " + AppStrings.t("系统材质与玻璃", lang: lang))
                .font(DesignTokens.font(.cap))
                .foregroundStyle(.secondary)
            Text(DesignTokens.glassPolicyNote)
                .font(DesignTokens.font(.cap))
                .foregroundStyle(.secondary)
        }
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.t("色板", lang: lang))
                .font(DesignTokens.font(.h2))
            ForEach(DesignContract.tokens, id: \.cssName) { token in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignTokens.color(token.cssName, scheme: scheme))
                        .frame(width: 36, height: 24)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5)
                        }
                    Text(token.cssName)
                        .font(DesignTokens.font(.cap).monospaced())
                        .frame(width: 100, alignment: .leading)
                    Text((scheme == .dark ? token.dark ?? token.light : token.light))
                        .font(DesignTokens.font(.cap).monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var iconsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.t("自定义图标", lang: lang) + " · \(ReachIconName.allCases.count) " + AppStrings.t("个图标", lang: lang))
                .font(DesignTokens.font(.h2))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 12)], spacing: 14) {
                ForEach(ReachIconName.allCases, id: \.self) { name in
                    VStack(spacing: 4) {
                        ReachIcon(name: name, size: 24)
                            .foregroundStyle(DesignTokens.color("--text", scheme: scheme))
                        Text(name.rawValue)
                            .font(DesignTokens.font(.mini))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.t("反馈层", lang: lang))
                .font(DesignTokens.font(.h2))

            HStack {
                Button(AppStrings.t("普通提示", lang: lang)) {
                    toastCenter.show(text: AppStrings.t("已删除一条任务", lang: lang))
                }
                .buttonStyle(.bordered)

                Button(AppStrings.t("带撤销提示", lang: lang)) {
                    toastCenter.show(
                        text: AppStrings.t("已删除一条任务", lang: lang),
                        action: {
                            HapticFeedback.play(.success)
                            toastCenter.show(text: AppStrings.t("已撤销", lang: lang))
                        },
                        actionText: AppStrings.t("撤销", lang: lang)
                    )
                }
                .buttonStyle(.borderedProminent)
            }

            Button(AppStrings.t("系统弹窗", lang: lang)) { sheetOpen = true }
                .buttonStyle(.bordered)

            HStack {
                ForEach(FeedbackContract.Haptic.allCases, id: \.self) { kind in
                    Button(kind.rawValue) { HapticFeedback.play(kind) }
                        .buttonStyle(.bordered)
                        .font(DesignTokens.font(.cap))
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.t("版本", lang: lang) + " v\(marketingVersion) (\(buildVersion))")
                .font(DesignTokens.font(.foot).monospacedDigit())
                .foregroundStyle(.secondary)
            Text("dayChangeHook = \(dayChangeCount)")
                .font(DesignTokens.font(.cap).monospaced())
                .foregroundStyle(.tertiary)
            Button(AppStrings.t("查看 T-03 原型", lang: lang)) { showPrototype = true }
                .font(DesignTokens.font(.foot))
            Button(AppStrings.t("查看 T-02 占位页", lang: lang)) { showT02 = true }
                .font(DesignTokens.font(.foot))
            Button(AppStrings.t("查看 T-14 组件预览", lang: lang)) { showT14 = true }
                .font(DesignTokens.font(.foot))
        }
    }

    private var prototypeCover: some View {
        NavigationStack {
            PrototypeRootView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(AppStrings.t("关闭", lang: lang)) { showPrototype = false }
                    }
                }
        }
    }

    private var t02Cover: some View {
        NavigationStack {
            T02PlaceholderView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(AppStrings.t("关闭", lang: lang)) { showT02 = false }
                    }
                }
        }
    }

    /// T-15 把「日程」tab 换成真实日历后，组件预览保留在这里供 A-26 / A-30 / A-37 / A-38 观察。
    private var t14Cover: some View {
        NavigationStack {
            // 嵌套 fullScreenCover 同样不继承本页的 @EnvironmentObject（AppRootView 三张 sheet 的同一坑）。
            TaskRowGallery()
                .environmentObject(toastCenter)
                .environment(\.appLanguage, lang)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(AppStrings.t("关闭", lang: lang)) { showT14 = false }
                    }
                }
        }
    }
}
