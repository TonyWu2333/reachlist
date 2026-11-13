import Foundation

// MARK: - M-21：点击守卫（src/lib/ui.js:clickGuard + TaskRow.vue:99/113）
//
// 滑动/拖拽结束后 250ms 内的误触 click 要吞掉。SwiftUI 没有 DOM click 事件，
// 这里提供服务化 API，供 T-14 的 TaskRow 在手势结束与点击处理处调用；
// 时间窗口与大小比较逻辑逐字对齐上游，纯逻辑可单测。

@MainActor
final class ClickGuard {
    private var until: Int64 = 0
    private let now: @Sendable () -> Int64

    init(now: @escaping @Sendable () -> Int64 = {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }) {
        self.now = now
    }

    func block(milliseconds: Int = FeedbackContract.clickGuardMilliseconds) {
        until = now() + Int64(milliseconds)
    }

    func shouldIgnoreTap() -> Bool {
        FeedbackContract.shouldIgnoreTap(now: now(), until: until)
    }

    /// 测试/调试用：当前截止时间（毫秒时间戳）。
    var untilMillis: Int64 { until }
}
