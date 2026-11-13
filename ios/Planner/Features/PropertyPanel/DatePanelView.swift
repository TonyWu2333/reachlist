import SwiftUI

// MARK: - M-15 日期面板（DatePanel.vue）
//
// 保留 4 个快捷项（今天 / 明天 / 下周一 / 无日期，功能语义）；月历交给系统
// `DatePicker(.graphical)`（§5.2 组件映射表允许「DatePicker(.graphical) 或自定义月历」，
// §5.1 第 1 条优先系统组件）。

struct DatePanelView: View {
    @Binding var value: String
    var quick: [PanelCatalog.DateQuickOption]
    var onPick: (String) -> Void

    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(quick) { option in
                    Button { onPick(option.value) } label: {
                        VStack(spacing: 4) {
                            ReachIcon(name: ReachIconName(rawValue: option.icon) ?? .sun, size: 21)
                            Text(AppStrings.t(option.key, lang: lang))
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            value == option.value
                                ? DesignTokens.color("--accent-soft", scheme: scheme)
                                : DesignTokens.color("--surface-2", scheme: scheme)
                        )
                        .foregroundStyle(
                            value == option.value
                                ? DesignTokens.color("--accent", scheme: scheme)
                                : DesignTokens.color("--text-2", scheme: scheme)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerMedium))
                    }
                    .buttonStyle(.plain)
                }
            }

            DatePicker("", selection: dateBinding, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                // 放进 ScrollView 后系统月历会被压缩到不确定高度，固定取自身固有高度，
                // 避免下半个月份网格被裁掉（用户 2026-11-15 第二张截图）。
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.locale, Locale(identifier: lang == "en" ? "en_US" : "zh_CN"))
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { value.isEmpty ? DateText.parse(DateText.today()) : DateText.parse(value) },
            set: { onPick(DateText.today($0)) }
        )
    }
}
