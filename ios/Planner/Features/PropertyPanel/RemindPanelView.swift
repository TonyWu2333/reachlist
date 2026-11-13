import SwiftUI

// MARK: - M-15 提醒面板（RemindPanel.vue）
//
// 选项值来自 notify.js:REMIND_OPTIONS = [0, 5, 15, 30, 60]；3 列网格 + 不提醒。
// 英文布局特例（F-16.6）："15 min before" 在三列里偏挤，字号缩小一档。

struct RemindPanelView: View {
    @Binding var value: Int?
    var onPick: (Int?) -> Void

    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    private var isEnglish: Bool { lang == "en" }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(PanelCatalog.remindOptions, id: \.self) { minutes in
                let on = value == minutes
                Button { onPick(minutes) } label: {
                    Text(PanelCatalog.remindShort(minutes, isEnglish: isEnglish))
                        .font(isEnglish ? .footnote : .subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .padding(.horizontal, 2)
                        .background(on
                            ? DesignTokens.color("--accent-soft", scheme: scheme)
                            : DesignTokens.color("--surface", scheme: scheme))
                        .foregroundStyle(on
                            ? DesignTokens.color("--accent", scheme: scheme)
                            : DesignTokens.color("--text-2", scheme: scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            Button { onPick(nil) } label: {
                HStack(spacing: 4) {
                    ReachIcon(name: .ban, size: 15)
                    Text(AppStrings.t("不提醒", lang: lang))
                        .font(isEnglish ? .footnote : .subheadline)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(value == nil
                    ? DesignTokens.color("--accent-soft", scheme: scheme)
                    : DesignTokens.color("--surface", scheme: scheme))
                .foregroundStyle(value == nil
                    ? DesignTokens.color("--accent", scheme: scheme)
                    : DesignTokens.color("--text-2", scheme: scheme))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}
