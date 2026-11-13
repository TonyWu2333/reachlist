import SwiftUI

// MARK: - 属性行容器（TaskDetail.vue:td-group / .prop）
//
// 一行 = 图标 + 标签 + 值 + 展开箭头；点开后内嵌对应面板。
// 面板本身不做模态（§5.0：bottom sheet 是唯一模态面；属性面板是行内展开）。

struct PropertyRow<Content: View>: View {
    let icon: ReachIconName
    let label: String
    let value: String
    var valueIsSet = false
    var valueIsOverdue = false
    var enabled = true
    var isExpanded: Bool
    var onTap: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    ReachIcon(name: icon, size: 18)
                        .foregroundStyle(DesignTokens.color("--text-2", scheme: scheme))
                        .frame(width: 24)
                    Text(label)
                        .font(.body)
                        .foregroundStyle(DesignTokens.color("--text", scheme: scheme))
                    Spacer(minLength: 8)
                    Text(value)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                    ReachIcon(name: .chevronRight, size: 16)
                        .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.55)

            if isExpanded {
                content()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var valueColor: Color {
        if valueIsOverdue { return DesignTokens.color("--danger", scheme: scheme) }
        if valueIsSet { return DesignTokens.color("--accent", scheme: scheme) }
        return DesignTokens.color("--text-3", scheme: scheme)
    }
}

/// 属性面板集的外框（对应 TaskDetail.vue:.td-group）。
///
/// `fill` 默认 `--surface-2`：T-17 把详情页放进白色 sheet 时，灰面板压在白底上才分得出来。
/// 预览页（`TaskRowGallery`）在 `--bg` 灰底上，传 `--surface` 让它自己就是那张卡片，
/// 不再出现「白卡片 + 灰面板」两层叠着、四周留白还不一样宽的问题。
struct PropertyGroup<Content: View>: View {
    var fill: String = "--surface-2"
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(DesignTokens.color(fill, scheme: scheme))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerMedium))
    }
}
