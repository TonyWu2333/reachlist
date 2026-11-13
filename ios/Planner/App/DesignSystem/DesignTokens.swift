import SwiftUI

// MARK: - M-22 设计系统：渲染层
//
// 色值来自 DesignContract（逐字取自 src/style.css），按 colorScheme 取亮/暗两套。
// 字号 / 动效 / 网格按 OPEN-18 与 §5.1 第 7/8 条交给系统：
// · 字号用 Dynamic Type，不硬编码 CSS 的 11~30px 阶梯与半像素字重；
// · 动效用 SwiftUI 系统弹簧，不复刻 --ease / --spring 的 cubic-bezier 数值；
// · 安全区交给系统组件（TabView / NavigationStack / .safeAreaInset），不移植 --sat / --sab。

enum DesignTokens {

    static func color(_ cssName: String, scheme: ColorScheme) -> Color {
        let raw = DesignContract.resolvedColors(scheme: scheme == .dark ? "dark" : "light")[cssName]
        guard let raw, let c = DesignContract.rgba(raw) else { return .primary }
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }

    /// 与 src/style.css 的 --fs-* 一一对应，但用系统文本样式（Dynamic Type）。
    enum TextRole: CaseIterable {
        case title, h2, h3, body, sub, foot, cap, mini
    }

    static func font(_ role: TextRole) -> Font {
        switch role {
        case .title: return .system(.largeTitle, weight: .bold)
        case .h2: return .system(.title2, weight: .semibold)
        case .h3: return .system(.headline)
        case .body: return .body
        case .sub: return .subheadline
        case .foot: return .footnote
        case .cap: return .caption
        case .mini: return .caption2
        }
    }

    /// 布局参考值（4px 网格仅作参考，§5.1 第 8 条）：整数 pt，不含字号硬编码。
    static let gutter: CGFloat = 20
    static let rowMinHeight: CGFloat = 52
    static let touchTarget: CGFloat = 40
    static let cornerSmall: CGFloat = 10
    static let cornerMedium: CGFloat = 14
    static let cornerLarge: CGFloat = 20
    static let cornerXLarge: CGFloat = 26
    static let tabIconSize: CGFloat = 25

    /// §5.1 第 2 条：同屏最多一个 GlassEffectContainer，且只用于少数浮动元素。
    /// 第 3 条：日历格子 / 任务行 / 象限卡片禁止逐个加玻璃。
    /// 这里不做全局封装，避免后续模块无意中给列表元素套玻璃；
    /// 需要玻璃的浮动元素（Toast / FAB / chip 组）由各自视图显式调用 .glassEffect。
    static let glassPolicyNote =
        "只允许：\(DesignContract.glassAllowed.joined(separator: "、"))；禁止：\(DesignContract.glassForbidden.joined(separator: "、"))"

    /// --reach #FFB23E 是系列品牌色，§5.1 第 5 条：禁止用于按钮、链接、警告、状态。
    /// 这里不提供任何 UI 便捷构造器，防止误用；仅有事实登记 DesignContract.tokens。
}
