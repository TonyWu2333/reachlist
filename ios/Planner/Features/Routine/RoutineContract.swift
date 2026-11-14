import Foundation

// MARK: - M-12 打卡：事实层（T-16）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/views/RoutineView.vue:16-78：
// 数据源、6 个分组、未来实例 / 已结束、组内排序、今日概览、连续次数单位、
// 跳过与删除的文案分支。重复规则计算只调 M-03 RepeatEngine，不写第二份逻辑。

struct RoutineItem: Equatable, Sendable {
    var task: PlannerTask
    var occ: String
    var isToday: Bool
    var streak: Int
    /// 中文单位：天 / 周 / 个月 / 年 / 次（TaskRow 会把整句翻成英文）
    var unit: String
}

struct RoutineGroup: Equatable, Sendable {
    var key: String
    var labelKey: String
    var items: [RoutineItem]
}

enum RoutineContract {

    /// RoutineView.vue:GROUPS，空组不显示。
    static let groupsDefinition: [(key: String, label: String)] = [
        ("daily", "每天"), ("interval", "每隔几天"), ("weekly", "每周"),
        ("monthly", "每月"), ("yearly", "每年"), ("ended", "已结束"),
    ]

    /// unitOf：每天→天，每周只有一天→周，每月/每年 n=1→个月/年，其余→次。
    static func unitOf(_ t: PlannerTask) -> String {
        let r = RepeatEngine.parse(t.repeatRule)
        var unit = "次"
        if RepeatEngine.repeatGroup(t.repeatRule) == "daily" { unit = "天" }
        else if r?.freq == "w" && r?.n == 1 && r?.days.count == 1 { unit = "周" }
        else if r?.freq == "m" && r?.n == 1 { unit = "个月" }
        else if r?.freq == "y" && r?.n == 1 { unit = "年" }
        return unit
    }

    static func routines(_ tasks: [PlannerTask]) -> [PlannerTask] {
        tasks.filter { !$0.repeatRule.isEmpty && $0.parentId.isEmpty }
    }

    static func todayList(_ tasks: [PlannerTask], today: String) -> [PlannerTask] {
        routines(tasks).filter { RepeatEngine.occursOn($0, today) }
    }

    static func doneToday(_ tasks: [PlannerTask], today: String) -> Int {
        todayList(tasks, today: today).filter { $0.doneDates.contains(today) }.count
    }

    static func progress(_ tasks: [PlannerTask], today: String) -> Double {
        let list = todayList(tasks, today: today)
        return list.isEmpty ? 0 : Double(doneToday(tasks, today: today)) / Double(list.count)
    }

    /// 今日概览三分支（RoutineView.vue:98-101）。
    static func summary(_ tasks: [PlannerTask], today: String, lang: String) -> (headline: String, detail: String) {
        let list = todayList(tasks, today: today)
        let done = doneToday(tasks, today: today)
        let headline: String
        if list.isEmpty {
            headline = FeatureStrings.t("今天没有要打卡的", lang: lang)
        } else if done == list.count {
            headline = FeatureStrings.t("今天的卡都打完了", lang: lang)
        } else {
            headline = FeatureStrings.t("今天还剩 {n} 项", lang: lang, ["n": String(list.count - done)])
        }
        let detail = FeatureStrings.t(
            "今天 {done}/{total} · 共 {n} 项打卡", lang: lang,
            ["done": String(done), "total": String(list.count), "n": String(routines(tasks).count)]
        )
        return (headline, detail)
    }

    /// groups：occ 不存在 → 已结束；组内含今天优先 → 时间 → createdAt，空组过滤。
    /// JS Array.sort 稳定，这里显式带原序做 tie-break。
    static func groups(_ tasks: [PlannerTask], today: String) -> [RoutineGroup] {
        let all = routines(tasks).enumerated().map { index, t -> (order: Int, item: RoutineItem, group: String) in
            let occ = RepeatEngine.occursOn(t, today) ? today : RepeatEngine.nextOccurrence(t, from: today)
            // 上游已结束分支是 `{ ...t, occ: '' }`（保留原 date / done），
            // 不是 instanceOf(t, '')，后者会把 date 清空、done 置 false。
            let inst: RepeatInstance = occ.isEmpty
                ? RepeatInstance(task: t, occ: "")
                : RepeatEngine.instanceOf(t, occ)
            return (
                order: index,
                item: RoutineItem(
                    task: inst.task,
                    occ: inst.occ,
                    isToday: occ == today,
                    streak: RepeatEngine.streakOf(t, today),
                    unit: unitOf(t)
                ),
                group: occ.isEmpty ? "ended" : RepeatEngine.repeatGroup(t.repeatRule)
            )
        }
        return groupsDefinition.compactMap { def in
            let items = all.filter { $0.group == def.key }.sorted { a, b in
                if a.item.isToday != b.item.isToday { return a.item.isToday }
                let ta = a.item.task.time.isEmpty ? "99" : a.item.task.time
                let tb = b.item.task.time.isEmpty ? "99" : b.item.task.time
                if ta != tb { return ta < tb }
                if a.item.task.createdAt != b.item.task.createdAt {
                    return a.item.task.createdAt < b.item.task.createdAt
                }
                return a.order < b.order
            }.map(\.item)
            return items.isEmpty ? nil : RoutineGroup(key: def.key, labelKey: def.label, items: items)
        }
    }

    /// onSkip 的 toast（RoutineView.vue:77）。
    static func skipText(occ: String, today: String, lang: String) -> String {
        FeatureStrings.t(occ == today ? "今天这次已跳过" : "下一次已跳过", lang: lang)
    }

    /// onDelete 的 toast，带孩子数量分支（RoutineView.vue:72）。
    static func deleteText(title: String, kids: Int, lang: String) -> String {
        kids > 0
            ? FeatureStrings.t("已删除「{title}」及 {n} 个子任务", lang: lang,
                               ["title": title, "n": String(kids)])
            : FeatureStrings.t("已删除「{title}」", lang: lang, ["title": title])
    }
}
