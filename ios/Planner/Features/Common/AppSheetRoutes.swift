import Foundation

// MARK: - App.vue:quick / detail / searchOpen 的三个路由值（T-16 / T-17 共用）
//
// 纯值类型，供 AppRootView 持有、供各页面触发，也便于 XCTest 断言默认值注入。
// 与 src/App.vue:32-37 的 openQuick(defaults) / openDetail(id, occ) / openSearch() 一一对应。

/// QuickAdd 的 `defaults`：`{ date, q, repeat }`，三个键都可选（缺省行为见 QuickAdd.vue:watch(open)）。
struct QuickAddDefaults: Equatable, Sendable {
    var date: String? = nil
    var quadrant: Int? = nil
    var repeatRule: String? = nil

    static let empty = QuickAddDefaults()

    /// 日历 FAB / 空态：带当天日期。
    static func onDate(_ date: String) -> QuickAddDefaults {
        QuickAddDefaults(date: date)
    }

    /// 四象限卡片里的 +：带象限与今天。
    static func inQuadrant(_ q: Int, date: String) -> QuickAddDefaults {
        QuickAddDefaults(date: date, quadrant: q)
    }

    /// 打卡页 FAB / 空态：默认每天重复。
    static func routine() -> QuickAddDefaults {
        QuickAddDefaults(repeatRule: "d1")
    }
}

/// TaskDetail 的 `taskId + occ`；occ 是从日历某一天点进来的重复实例日期。
struct DetailRoute: Equatable, Sendable {
    var id: String
    var occ: String = ""
}
