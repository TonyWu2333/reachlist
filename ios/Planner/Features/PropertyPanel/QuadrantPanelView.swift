import SwiftUI

// MARK: - M-15 象限面板（QuadPanel.vue）
//
// 4 项，2×2；象限色属功能识别色，按 §5.1 第 5 条保留（--q1~--q4 亮暗两套）。

struct QuadrantPanelView: View {
    @Binding var value: Int
    var onPick: (Int) -> Void

    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(PanelCatalog.quadrants, id: \.index) { q in
                let on = value == q.index
                let color = DesignTokens.color(q.colorToken, scheme: scheme)
                Button { onPick(q.index) } label: {
                    HStack(spacing: 10) {
                        ReachIcon(name: ReachIconName(rawValue: q.icon) ?? .star, size: 18)
                            .frame(width: 32, height: 32)
                            .background(on ? color : color.opacity(0.12))
                            .foregroundStyle(on ? .white : color)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(AppStrings.t(q.nameKey, lang: lang))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(DesignTokens.color("--text", scheme: scheme))
                                // T-19 / A-43：英文象限名比中文长（"Important, not urgent"），
                                // 单行 + 0.75 缩放仍会被省略号截断；允许两行后中英都完整。
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                            Text(AppStrings.t(q.hintKey, lang: lang))
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(on ? color.opacity(0.12) : DesignTokens.color("--surface", scheme: scheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.cornerMedium)
                            .strokeBorder(on ? color : .clear, lineWidth: 1.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerMedium))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
