import Foundation

// MARK: - M-22 设计系统：事实层
//
// 数值逐字取自 baseline_commit 97a7c4c 的 src/style.css（§2.13 指定它为唯一数值来源）。
// 本文件只依赖 Foundation，可在 macOS 侧用 swiftc 与 JS oracle 做逐字对比。
// 渲染用 API 见 DesignTokens.swift：字号 / 网格 / 动效按 OPEN-18 与 §5.1 第 7/8 条
// 交给 iOS 系统字体与系统弹簧，下面的 CSS 数值只作事实登记，不用于硬编码渲染。

enum DesignContract {

    struct Token: Equatable, Sendable {
        let cssName: String
        let light: String
        /// nil = 暗色 media 里未重定义，按 CSS 语义继承亮色值。
        let dark: String?
    }

    /// 顺序与 src/style.css :root 中声明顺序一致。
    static let tokens: [Token] = [
        .init(cssName: "--bg", light: "#f3f4f6", dark: "#0c0d10"),
        .init(cssName: "--surface", light: "#ffffff", dark: "#18191d"),
        .init(cssName: "--surface-2", light: "#f6f7f9", dark: "#202126"),
        .init(cssName: "--fill", light: "rgba(116, 122, 138, 0.1)", dark: "rgba(150, 156, 170, 0.14)"),
        .init(cssName: "--fill-2", light: "rgba(116, 122, 138, 0.17)", dark: "rgba(150, 156, 170, 0.22)"),
        .init(cssName: "--text", light: "#16171a", dark: "#eceef1"),
        .init(cssName: "--text-2", light: "#5d626c", dark: "#a3a8b2"),
        .init(cssName: "--text-3", light: "#a0a5ae", dark: "#676c76"),
        .init(cssName: "--sep", light: "rgba(20, 24, 32, 0.07)", dark: "rgba(255, 255, 255, 0.07)"),
        .init(cssName: "--accent", light: "#4b5cf0", dark: "#7584ff"),
        .init(cssName: "--accent-soft", light: "rgba(75, 92, 240, 0.1)", dark: "rgba(117, 132, 255, 0.16)"),
        .init(cssName: "--on-accent", light: "#fff", dark: nil),
        .init(cssName: "--danger", light: "#ef4444", dark: "#f87171"),
        .init(cssName: "--success", light: "#16a34a", dark: "#4ade80"),
        .init(cssName: "--warn", light: "#f59e0b", dark: nil),
        // --reach 是系列品牌色，§5.1 第 5 条：禁止用于按钮、链接、警告、状态。
        .init(cssName: "--reach", light: "#ffb23e", dark: "#ffbe5c"),
        .init(cssName: "--q1", light: "#ef4444", dark: "#f87171"),
        .init(cssName: "--q2", light: "#f59e0b", dark: "#fbbf24"),
        .init(cssName: "--q3", light: "#0ea5e9", dark: "#38bdf8"),
        .init(cssName: "--q4", light: "#10b981", dark: "#34d399"),
    ]

    /// 解析后的色板；scheme 只接受 "light" / "dark"。
    static func resolvedColors(scheme: String) -> [String: String] {
        var out: [String: String] = [:]
        for t in tokens {
            if scheme == "dark" {
                out[t.cssName] = t.dark ?? t.light
            } else {
                out[t.cssName] = t.light
            }
        }
        return out
    }

    /// 解析 #rgb / #rrggbb / rgba(r, g, b, a) 为 0...1 分量。失败返回 nil。
    static func rgba(_ raw: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            func pair(_ from: Int) -> Double? {
                guard hex.count >= from + 2 else { return nil }
                let start = hex.index(hex.startIndex, offsetBy: from)
                let end = hex.index(start, offsetBy: 2)
                guard let v = Int(hex[start..<end], radix: 16) else { return nil }
                return Double(v) / 255.0
            }
            if hex.count == 3 {
                let chars = Array(hex)
                func one(_ c: Character) -> Double? {
                    guard let v = Int(String(c), radix: 16) else { return nil }
                    return Double(v * 17) / 255.0
                }
                guard let r = one(chars[0]), let g = one(chars[1]), let b = one(chars[2]) else { return nil }
                return (r, g, b, 1)
            }
            if hex.count == 6 {
                guard let r = pair(0), let g = pair(2), let b = pair(4) else { return nil }
                return (r, g, b, 1)
            }
            return nil
        }
        guard s.hasPrefix("rgba("), s.hasSuffix(")") else { return nil }
        let inner = s.dropFirst(5).dropLast()
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4,
              let r = Double(parts[0]), let g = Double(parts[1]),
              let b = Double(parts[2]), let a = Double(parts[3]) else { return nil }
        return (r / 255.0, g / 255.0, b / 255.0, a)
    }

    /// OPEN-03=B：45 个自定义 SVG 图标全部保留，不替换为 SF Symbols。
    /// 顺序与 src/components/Icon.vue:ICONS 一致；资产名前缀 "icon-"。
    static let iconNames: [String] = [
        "calendar", "calendar-fill", "grid", "grid-fill", "user", "user-fill",
        "plus", "check", "clock", "flag", "repeat", "repeat-fill",
        "cloud", "flame", "skip", "bell", "search", "checklist", "note", "trash",
        "chevron-right", "chevron-left", "chevron-down", "arrow-up", "arrow-right",
        "x", "sun", "sunrise", "week", "ban", "sparkle", "download", "upload",
        "eye", "eye-off", "moon", "lunar", "holiday", "shield", "info", "alert",
        "bolt", "star", "fire", "coffee",
    ]

    static func assetName(_ icon: String) -> String { "icon-\(icon)" }

    struct TabContract: Equatable, Sendable {
        let key: String
        let labelZH: String
        let labelEN: String
        let icon: String
    }

    /// src/App.vue:TABS + src/lib/i18n-en.js:core。4 个 tab 与标签文案属功能语义（F-14.1）。
    static let tabs: [TabContract] = [
        .init(key: "calendar", labelZH: "日程", labelEN: "Calendar", icon: "calendar"),
        .init(key: "quadrant", labelZH: "四象限", labelEN: "Matrix", icon: "grid"),
        .init(key: "routine", labelZH: "打卡", labelEN: "Routines", icon: "repeat"),
        .init(key: "me", labelZH: "我的", labelEN: "Me", icon: "user"),
    ]

    /// CSS 事实登记：仅参考，不硬编码渲染（§5.1 第 8 条 / OPEN-18）。
    static let cssFontScale: [String: String] = [
        "--fs-title": "30px/750", "--fs-h2": "20px/650", "--fs-h3": "17px/600",
        "--fs-body": "16px/400", "--fs-sub": "14px", "--fs-foot": "13px",
        "--fs-cap": "12px", "--fs-mini": "11px",
    ]

    static let cssLayout: [String: String] = [
        "--gutter": "20px", "--tabbar-h": "58px",
        "--r-sm": "10px", "--r-md": "14px", "--r-lg": "20px", "--r-xl": "26px",
        "--head-top": "max(32px, calc(var(--sat) + 20px))",
    ]

    /// §5.1 第 3 条：明确禁止逐个加 glassEffect 的位置（官方性能建议）。
    static let glassForbidden: [String] = ["日历日期格子", "任务行", "四象限卡片"]

    /// §5.1 第 2 条：允许自定义玻璃的少数浮动元素。
    /// 注：sheet 顶栏的两个圆钮按用户 2026-11-14 的要求也用了系统 Liquid Glass，
    /// 属用户指定的呈现层追加，登记在计划书 §5.3 第 37 条，本白名单仍按 §5.1 原文保留。
    static let glassAllowed: [String] = ["快速添加 chip 组", "FAB", "撤销 Toast", "日历折叠把手"]
}
