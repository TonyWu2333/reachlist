import SwiftUI

// MARK: - M-15 时间面板（TimePanel.vue）
//
// 10 个预设（08:00 ~ 22:00）+ 自定义（系统 DatePicker 时分）+ 不设时间。

struct TimePanelView: View {
    @Binding var value: String
    var onPick: (String) -> Void

    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(PanelCatalog.timePresets, id: \.self) { preset in
                    Button { onPick(preset) } label: {
                        Text(preset)
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                value == preset
                                    ? DesignTokens.color("--accent", scheme: scheme)
                                    : DesignTokens.color("--surface", scheme: scheme)
                            )
                            .foregroundStyle(
                                value == preset
                                    ? DesignTokens.color("--on-accent", scheme: scheme)
                                    : DesignTokens.color("--text-2", scheme: scheme)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                // 自定义：系统 DatePicker 只取时分，外观贴合「一行按钮」
                HStack(spacing: 6) {
                    ReachIcon(name: .clock, size: 18)
                    DatePicker(
                        "",
                        selection: customBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: lang == "en" ? "en_US" : "zh_CN"))
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    !value.isEmpty && !PanelCatalog.timePresets.contains(value)
                        ? DesignTokens.color("--accent-soft", scheme: scheme)
                        : DesignTokens.color("--surface", scheme: scheme)
                )
                .foregroundStyle(
                    !value.isEmpty && !PanelCatalog.timePresets.contains(value)
                        ? DesignTokens.color("--accent", scheme: scheme)
                        : DesignTokens.color("--text-2", scheme: scheme)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button { onPick("") } label: {
                    HStack(spacing: 6) {
                        ReachIcon(name: .ban, size: 18)
                        Text(AppStrings.t("不设时间", lang: lang))
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(value.isEmpty
                        ? DesignTokens.color("--accent-soft", scheme: scheme)
                        : DesignTokens.color("--surface", scheme: scheme))
                    .foregroundStyle(value.isEmpty
                        ? DesignTokens.color("--accent", scheme: scheme)
                        : DesignTokens.color("--text-2", scheme: scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customBinding: Binding<Date> {
        Binding(
            get: {
                let parts = value.split(separator: ":").compactMap { Int($0) }
                var c = DateComponents()
                c.hour = parts.count == 2 ? parts[0] : 9
                c.minute = parts.count == 2 ? parts[1] : 0
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                onPick("\(DateText.pad(c.hour ?? 0)):\(DateText.pad(c.minute ?? 0))")
            }
        )
    }
}
