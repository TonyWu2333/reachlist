import Foundation

// MARK: - M-21 反馈层：事实层
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/lib/ui.js 与 src/components/TaskRow.vue。
// 纯数据 + 纯函数，不依赖 SwiftUI / UIKit，可在 macOS 侧做跨端对比。

enum FeedbackContract {

    /// ui.js:toast —— 带撤销 4 秒，普通 2 秒。
    static let toastDefaultMilliseconds = 2000
    static let toastUndoMilliseconds = 4000
    /// ui.js 默认 actionText = t('撤销')；中文原文为键，英文由 AppStrings 解析为 Undo。
    static let toastDefaultActionText = "撤销"

    /// TaskRow.vue:99 —— 滑动/拖拽结束后吞掉 250ms 内的误触 click。
    static let clickGuardMilliseconds = 250

    /// ui.js:haptic —— light / medium / select / success 四档，仅原生平台生效。
    enum Haptic: String, CaseIterable, Sendable {
        case light, medium, select, success
    }

    /// ui.js:toastState —— 全局只有一份状态，新 toast 覆盖旧的（同一时间只显示一条）。
    struct ToastState: Equatable, Sendable {
        let id: Int
        let text: String
        let hasAction: Bool
        let actionText: String
        let durationMilliseconds: Int
    }

    /// 对齐 ui.js:toast 的默认值展开；duration 显式传入时优先。
    static func makeToast(
        id: Int,
        text: String,
        hasAction: Bool = false,
        actionText: String? = nil,
        durationMilliseconds: Int? = nil
    ) -> ToastState {
        ToastState(
            id: id,
            text: text,
            hasAction: hasAction,
            actionText: actionText ?? toastDefaultActionText,
            durationMilliseconds: durationMilliseconds ?? (hasAction ? toastUndoMilliseconds : toastDefaultMilliseconds)
        )
    }

    /// TaskRow.vue:113 —— `Date.now() < clickGuard.until` 时忽略点击。
    static func shouldIgnoreTap(now: Int64, until: Int64) -> Bool { now < until }
}
