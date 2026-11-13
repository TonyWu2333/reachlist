import UIKit

// MARK: - M-21：四档触感（src/lib/ui.js:haptic）
//
// 上游用 Capacitor Haptics 的 impact(.light/.medium)、selectionChanged、notification(.success)；
// iOS 侧一一映射到系统生成器，档位语义不变。仅真机生效（模拟器无触感）。

@MainActor
enum HapticFeedback {
    static func play(_ kind: FeedbackContract.Haptic) {
        switch kind {
        case .light:
            let g = UIImpactFeedbackGenerator(style: .light)
            g.prepare()
            g.impactOccurred()
        case .medium:
            let g = UIImpactFeedbackGenerator(style: .medium)
            g.prepare()
            g.impactOccurred()
        case .select:
            let g = UISelectionFeedbackGenerator()
            g.prepare()
            g.selectionChanged()
        case .success:
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.success)
        }
    }
}
