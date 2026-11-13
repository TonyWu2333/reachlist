import XCTest
import SwiftUI
@testable import Planner

// T-13 骨架 / M-20 + M-21 + M-22 契约黄金测试。
// 跨端 oracle：node /tmp/planner_t13_oracle.mjs（输出 /tmp/planner_t13_oracle.json），
// Swift harness：swiftc /tmp/planner_t13_harness/main.swift + 三个 Foundation-only 契约文件。
// 本文件内的期望值均取自 baseline_commit 97a7c4c 的 src/ 源码。

@MainActor
final class T13DesignSystemTests: XCTestCase {

    // MARK: M-22 图标（OPEN-03=B）

    func testReachIconEnumCoversAll45CustomSVGs() {
        XCTAssertEqual(ReachIconName.allCases.count, 45)
        XCTAssertEqual(ReachIconName.allCases.map(\.rawValue), DesignContract.iconNames)
        XCTAssertEqual(Set(DesignContract.iconNames).count, 45, "图标名不得重复")
        for name in ReachIconName.allCases {
            XCTAssertEqual(DesignContract.assetName(name.rawValue), "icon-\(name.rawValue)")
        }
    }

    func testFourTabsHaveFillVariants() {
        for tab in AppTab.allCases {
            let fill = tab.contract.icon + "-fill"
            XCTAssertTrue(DesignContract.iconNames.contains(tab.contract.icon))
            XCTAssertTrue(DesignContract.iconNames.contains(fill), "\(tab.rawValue) 缺 -fill 变体")
            XCTAssertEqual(tab.fillAsset, "icon-\(fill)")
        }
    }

    #if canImport(UIKit)
    func testAll45IconAssetsLoadFromAssetCatalog() {
        // 真机侧强证据：actool 产物里的 45 个 template 矢量图都能被 UIImage 加载。
        var missing: [String] = []
        for name in DesignContract.iconNames {
            if UIImage(named: DesignContract.assetName(name)) == nil { missing.append(name) }
        }
        XCTAssertTrue(missing.isEmpty, "缺失图标资产: \(missing.joined(separator: ", "))")
    }
    #endif

    // MARK: M-22 色板与令牌

    func testPaletteMatchesStyleCSSKeyValues() {
        let light = DesignContract.resolvedColors(scheme: "light")
        let dark = DesignContract.resolvedColors(scheme: "dark")
        XCTAssertEqual(light.count, 20)
        XCTAssertEqual(dark.count, 20)
        XCTAssertEqual(light["--accent"], "#4b5cf0")
        XCTAssertEqual(dark["--accent"], "#7584ff")
        XCTAssertEqual(light["--reach"], "#ffb23e")
        XCTAssertEqual(dark["--reach"], "#ffbe5c")
        XCTAssertEqual(light["--q1"], "#ef4444")
        XCTAssertEqual(dark["--q1"], "#f87171")
        XCTAssertEqual(light["--q2"], "#f59e0b")
        XCTAssertEqual(dark["--q2"], "#fbbf24")
        XCTAssertEqual(light["--q3"], "#0ea5e9")
        XCTAssertEqual(dark["--q3"], "#38bdf8")
        XCTAssertEqual(light["--q4"], "#10b981")
        XCTAssertEqual(dark["--q4"], "#34d399")
        // 暗色 media 未重定义的令牌按 CSS 语义继承亮色
        XCTAssertEqual(dark["--on-accent"], light["--on-accent"])
        XCTAssertEqual(dark["--warn"], light["--warn"])
    }

    func testRGBAParserHandlesHex3Hex6AndRGBA() {
        let white = DesignContract.rgba("#fff")
        XCTAssertEqual(white?.r, 1.0); XCTAssertEqual(white?.a, 1.0)
        let accent = DesignContract.rgba("#4b5cf0")!
        XCTAssertEqual(accent.r, 75.0 / 255.0, accuracy: 1e-9)
        XCTAssertEqual(accent.g, 92.0 / 255.0, accuracy: 1e-9)
        let fill = DesignContract.rgba("rgba(116, 122, 138, 0.1)")!
        XCTAssertEqual(fill.a, 0.1, accuracy: 1e-9)
        XCTAssertNil(DesignContract.rgba("not-a-color"))
    }

    func testCSSFactsAreRegisteredButNotUsedForFontSizes() {
        XCTAssertEqual(DesignContract.cssFontScale.count, 8)
        XCTAssertEqual(DesignContract.cssLayout.count, 7)
        XCTAssertEqual(DesignContract.cssLayout["--gutter"], "20px")
        // 渲染层用 Dynamic Type；这里只确认系统字体 API 可用且布局参考值合理
        _ = DesignTokens.font(.title)
        _ = DesignTokens.font(.mini)
        XCTAssertEqual(DesignTokens.gutter, 20)
        XCTAssertEqual(DesignTokens.tabIconSize, 25)
        XCTAssertGreaterThanOrEqual(DesignTokens.touchTarget, 40)
    }

    func testGlassPolicyFollowsSection51() {
        XCTAssertEqual(DesignContract.glassForbidden, ["日历日期格子", "任务行", "四象限卡片"])
        XCTAssertEqual(DesignContract.glassAllowed, ["快速添加 chip 组", "FAB", "撤销 Toast", "日历折叠把手"])
    }

    // MARK: M-20 4 tab 与语言

    func testFourTabContract() {
        XCTAssertEqual(AppTab.allCases.map(\.rawValue), ["calendar", "quadrant", "routine", "me"])
        XCTAssertEqual(DesignContract.tabs.map(\.labelZH), ["日程", "四象限", "打卡", "我的"])
        XCTAssertEqual(DesignContract.tabs.map(\.labelEN), ["Calendar", "Matrix", "Routines", "Me"])
        XCTAssertEqual(DesignContract.tabs.map(\.icon), ["calendar", "grid", "repeat", "user"])
        XCTAssertEqual(AppTab.calendar.title(lang: "en"), "Calendar")
        XCTAssertEqual(AppTab.me.title(lang: "zh"), "我的")
    }

    func testAppStringsMechanismMatchesI18nJS() {
        XCTAssertEqual(AppStrings.t("撤销", lang: "en"), "Undo")
        XCTAssertEqual(AppStrings.t("撤销", lang: "zh"), "撤销")
        XCTAssertEqual(AppStrings.t("未收录词条", lang: "en"), "未收录词条", "缺失回退中文")
        XCTAssertEqual(AppStrings.fill("已删除「{title}」", ["title": "买菜"]), "已删除「买菜」")
        XCTAssertEqual(AppStrings.fill("{n} 项 / {other}", ["n": "3"]), "3 项 / {other}", "未知占位符保留")
        XCTAssertEqual(AppStrings.plural(1, "hour"), "1 hour")
        XCTAssertEqual(AppStrings.plural(3, "hour"), "3 hours")
        XCTAssertTrue(AppStrings.isZhLanguage("zh-Hans"))
        XCTAssertTrue(AppStrings.isZhLanguage("ZH"))
        XCTAssertFalse(AppStrings.isZhLanguage("en-US"))
        // T-03 原型 fixture 结论：zhHans（无连字符）不算 zh
        XCTAssertFalse(AppStrings.isZhLanguage("zhHans"))
        XCTAssertEqual(AppStrings.effectiveLang(.auto, system: "zh-CN"), "zh")
        XCTAssertEqual(AppStrings.effectiveLang(.auto, system: "en-US"), "en")
        XCTAssertEqual(AppStrings.effectiveLang(.en, system: "zh-CN"), "en")
    }

    // MARK: M-21 反馈层

    func testToastDurationAndDefaultActionText() {
        let plain = FeedbackContract.makeToast(id: 1, text: "x")
        XCTAssertEqual(plain.durationMilliseconds, 2000)
        XCTAssertFalse(plain.hasAction)
        let undo = FeedbackContract.makeToast(id: 2, text: "x", hasAction: true)
        XCTAssertEqual(undo.durationMilliseconds, 4000)
        XCTAssertEqual(undo.actionText, "撤销")
        let explicit = FeedbackContract.makeToast(id: 3, text: "x", hasAction: true, actionText: "完成任务", durationMilliseconds: 50)
        XCTAssertEqual(explicit.durationMilliseconds, 50)
        XCTAssertEqual(explicit.actionText, "完成任务")
    }

    func testToastCenterKeepsOnlyOneToastAndRunsUndo() {
        let center = ToastCenter()
        center.show(text: "第一条")
        XCTAssertEqual(center.current?.id, 1)
        center.show(text: "第二条", action: {}, actionText: "撤销")
        XCTAssertEqual(center.current?.id, 2, "新 toast 覆盖旧的，同一时间只显示一条")
        XCTAssertEqual(center.current?.durationMilliseconds, 4000)
        var ran = false
        center.show(text: "第三条", action: { ran = true })
        center.runAction()
        XCTAssertTrue(ran)
        XCTAssertNil(center.current, "撤销后立即关闭")
    }

    func testClickGuardWindowIs250ms() {
        final class Clock: @unchecked Sendable { var value: Int64 = 10_000 }
        let clock = Clock()
        let guardService = ClickGuard(now: { clock.value })
        XCTAssertFalse(guardService.shouldIgnoreTap())
        guardService.block()
        XCTAssertEqual(guardService.untilMillis, 10_250)
        XCTAssertTrue(guardService.shouldIgnoreTap())
        clock.value = 10_249
        XCTAssertTrue(guardService.shouldIgnoreTap())
        clock.value = 10_250
        XCTAssertFalse(guardService.shouldIgnoreTap(), "边界与上游 Date.now() < until 一致")
    }

    func testHapticContractHasFourLevels() {
        XCTAssertEqual(FeedbackContract.Haptic.allCases.map(\.rawValue), ["light", "medium", "select", "success"])
    }
}
