import SwiftUI
import Combine

// MARK: - M-21：撤销 Toast（src/lib/ui.js:toast / Toast.vue）
//
// 保留功能语义：普通 2 秒、带撤销 4 秒、同一时间只显示一条、actionText 本地化、点击撤销后立即关闭。
// 呈现层按 §5.0 / OPEN-18 改为系统 Liquid Glass + 系统语义色，不移植固定深色 #23252b 与实体阴影
// （偏离项逐条登记见计划书 §5.3）。

@MainActor
final class ToastCenter: ObservableObject {
    @Published private(set) var current: FeedbackContract.ToastState?

    private var pendingAction: (() -> Void)?
    private var dismissTask: Task<Void, Never>?
    private var nextID = 0

    /// 对齐 ui.js:toast —— 新 toast 覆盖旧的（clearTimeout + id+1）。
    func show(
        text: String,
        action: (() -> Void)? = nil,
        actionText: String? = nil,
        durationMilliseconds: Int? = nil
    ) {
        dismissTask?.cancel()
        nextID += 1
        let state = FeedbackContract.makeToast(
            id: nextID,
            text: text,
            hasAction: action != nil,
            actionText: actionText,
            durationMilliseconds: durationMilliseconds
        )
        pendingAction = action
        current = state
        let duration = state.durationMilliseconds
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    /// 对齐 Toast.vue:runAction —— 先执行 undo，再立即 dismiss。
    func runAction() {
        let action = pendingAction
        clear()
        action?()
    }

    /// 对齐 ui.js:dismissToast。
    func dismiss() { clear() }

    private func clear() {
        dismissTask?.cancel()
        dismissTask = nil
        pendingAction = nil
        current = nil
    }
}

struct ToastOverlay: View {
    @ObservedObject var center: ToastCenter

    var body: some View {
        if let state = center.current {
            HStack(spacing: 12) {
                Text(state.text)
                    .font(DesignTokens.font(.sub))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if state.hasAction {
                    Button {
                        center.runAction()
                    } label: {
                        Text(state.actionText)
                            .font(DesignTokens.font(.sub).weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .frame(minHeight: DesignTokens.touchTarget - 6)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .foregroundStyle(.primary)
            .glassEffect(.regular, in: .rect(cornerRadius: DesignTokens.cornerMedium))
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }
}
