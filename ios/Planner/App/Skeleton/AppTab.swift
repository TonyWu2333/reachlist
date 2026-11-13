import SwiftUI

// MARK: - M-20：4 个 tab（src/App.vue:TABS，F-14.1）
//
// key / 中文标签 / 英文标签 / 图标名都来自 DesignContract（跨端对比夹具），
// 选中时用对应的 -fill 变体并触发 select 档触感。

enum AppTab: String, CaseIterable, Hashable, Sendable {
    case calendar, quadrant, routine, me
}

extension AppTab {
    var contract: DesignContract.TabContract {
        DesignContract.tabs.first { $0.key == rawValue } ?? DesignContract.tabs[0]
    }

    func title(lang: String) -> String {
        lang == "en" ? contract.labelEN : contract.labelZH
    }

    var outlineAsset: String { DesignContract.assetName(contract.icon) }
    var fillAsset: String { DesignContract.assetName(contract.icon + "-fill") }

    func asset(selected: Bool) -> String { selected ? fillAsset : outlineAsset }
}
