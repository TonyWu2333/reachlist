import SwiftUI

// MARK: - M-22：45 个自定义 SVG 图标（OPEN-03=B）
//
// 全部保留 src/components/Icon.vue:ICONS 的原始路径，不替换为 SF Symbols。
// 资产生成：/tmp/gen_icons.py（从 Icon.vue 逐字导出，currentColor → #000000），
// 落在 Assets.xcassets/icon-<name>.imageset，template rendering + preserve vector。
// actool 已实测编译进 Assets.car，45 个 icon-* 条目齐全。

enum ReachIconName: String, CaseIterable, Sendable {
    case calendar, calendarFill = "calendar-fill"
    case grid, gridFill = "grid-fill"
    case user, userFill = "user-fill"
    case plus, check, clock, flag
    case `repeat`, repeatFill = "repeat-fill"
    case cloud, flame, skip, bell, search, checklist, note, trash
    case chevronRight = "chevron-right"
    case chevronLeft = "chevron-left"
    case chevronDown = "chevron-down"
    case arrowUp = "arrow-up"
    case arrowRight = "arrow-right"
    case x, sun, sunrise, week, ban, sparkle, download, upload
    case eye, eyeOff = "eye-off"
    case moon, lunar, holiday, shield, info, alert, bolt, star, fire, coffee
}

struct ReachIcon: View {
    let name: ReachIconName
    var size: CGFloat = 22

    var body: some View {
        Image(DesignContract.assetName(name.rawValue))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
