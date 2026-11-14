import Foundation

// MARK: - M-13 任务详情：事实层（T-17）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/components/TaskDetail.vue:28-219：
// 弹窗内导航栈（rootId / stack / goBack）、occ 取值、isDone / canDrop / 子任务按 occ 打勾、
// 日期与页脚文案（中英）、五个属性面板的值文案、放弃 / 恢复 / 删除的四种 toast 分支。
// 纯 Foundation，可在 Xcode 外用 swiftc + JS oracle 夹具逐字对比。

struct DetailNav: Equatable, Sendable {
    var rootId: String
    var stack: [String] = []

    init(rootId: String) { self.rootId = rootId }

    var currentId: String { stack.last ?? rootId }

    mutating func reset(rootId id: String) {
        rootId = id
        stack = []
    }

    mutating func pushSub(_ id: String) { stack.append(id) }

    /// 有子任务页先弹栈；底层就是子任务时，返回其父任务（保留左上「‹ 父任务」）。
    mutating func goBack(parentId: String?) -> Bool {
        if !stack.isEmpty { stack.removeLast(); return true }
        if let parentId, !parentId.isEmpty { rootId = parentId; return true }
        return false
    }
}

enum TaskDetailContract {

    // MARK: 导航与 occ

    /// occOf：从日历某一天点进来的重复任务用那一天，否则今天/下一次。
    static func occOf(_ task: PlannerTask?, rootId: String, rootOcc: String, today: String) -> String {
        guard let task, !task.repeatRule.isEmpty else { return "" }
        if task.id == rootId && !rootOcc.isEmpty { return rootOcc }
        return RepeatEngine.nextOccurrence(task, from: today)
    }

    /// 父任务是重复任务、子任务自己没日期时按父任务那一天打勾。
    static func isPerOcc(_ parent: PlannerTask?, _ child: PlannerTask, _ occ: String) -> Bool {
        guard let parent else { return false }
        return !parent.repeatRule.isEmpty && !occ.isEmpty && child.date.isEmpty
    }

    static func subDone(_ parent: PlannerTask?, _ child: PlannerTask, occ: String) -> Bool {
        isPerOcc(parent, child, occ) ? child.doneDates.contains(occ) : child.done
    }

    static func subView(_ child: PlannerTask, parent: PlannerTask?, occ: String) -> PlannerTask {
        var copy = child
        copy.done = subDone(parent, child, occ: occ)
        return copy
    }

    static func children(_ tasks: [PlannerTask], parentId: String) -> [PlannerTask] {
        CalendarContract.childrenOf(parentId, tasks)
    }

    /// 放弃的子任务不计入进度。
    static func subProgress(_ tasks: [PlannerTask], parent: PlannerTask, occ: String) -> (done: Int, total: Int) {
        let kids = children(tasks, parentId: parent.id).filter { !$0.dropped }
        return (kids.filter { subDone(parent, $0, occ: occ) }.count, kids.count)
    }

    static func isDone(_ task: PlannerTask, parent: PlannerTask?, occDay: String, parentOcc: String) -> Bool {
        if let parent { return subDone(parent, task, occ: parentOcc) }
        return task.repeatRule.isEmpty ? task.done : task.doneDates.contains(occDay)
    }

    /// 放弃：仅未完成的一次性任务；挂在重复任务下、按父任务 occ 打勾的子任务也不行。
    static func canDrop(_ task: PlannerTask, parent: PlannerTask?) -> Bool {
        if !task.repeatRule.isEmpty || task.done { return false }
        if let parent, !parent.repeatRule.isEmpty, task.date.isEmpty { return false }
        return true
    }

    // MARK: 值文案

    /// dateText：dateLabel + 月日 + 星期，避免英文分支重复 "Fri"。
    static func dateText(_ task: PlannerTask, lang: String, today: String) -> String {
        guard !task.date.isEmpty else { return AppStrings.t("无日期", lang: lang) }
        let en = lang == "en"
        let rel = PlannerCalendar.dateLabel(task.date, today: today, isEnglish: en)
        let p = PlannerCalendar.parseYmd(task.date)
        let md = PlannerCalendar.monthDay(p, isEnglish: en)
        let wd = PlannerCalendar.weekdayName(PlannerCalendar.weekdayIndex(task.date), isEnglish: en)
        let full = en ? "\(wd), \(md)" : "\(md) \(wd)"
        return rel == md || (en && rel == wd) ? full : "\(rel) · \(full)"
    }

    /// fmt(ms)：`${monthDay(d)}${isEn()?',':''} ${pad(h)}:${pad(m)}`
    static func fmt(_ ms: Double, lang: String) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let en = lang == "en"
        let h = Calendar.current.component(.hour, from: d)
        let m = Calendar.current.component(.minute, from: d)
        return "\(PlannerCalendar.monthDay(d, isEnglish: en))\(en ? "," : "") \(PlannerCalendar.pad(h)):\(PlannerCalendar.pad(m))"
    }

    static func remindValue(_ task: PlannerTask, remindOn: Bool, lang: String) -> String {
        if task.time.isEmpty { return AppStrings.t("先设时间", lang: lang) }
        if !remindOn && task.remind != nil { return AppStrings.t("已关闭全部提醒", lang: lang) }
        return PanelCatalog.remindLabel(task.remind, isEnglish: lang == "en")
    }

    static func repeatValue(_ task: PlannerTask, lang: String) -> String {
        task.repeatRule.isEmpty
            ? AppStrings.t("不重复", lang: lang)
            : RepeatEngine.repeatLabel(task.repeatRule, date: task.date,
                                       isEnglish: lang == "en", withUntil: true)
    }

    static func droppedText(_ task: PlannerTask, lang: String) -> String {
        FeatureStrings.t("已放弃 · {time}", lang: lang,
                         ["time": fmt(task.doneAt ?? 0, lang: lang)])
    }

    /// 页脚：创建时间 + （重复：已完成 N 次 / 一次性：完成时间）。
    static func footer(_ task: PlannerTask, lang: String) -> String {
        var s = FeatureStrings.t("创建于 {time}", lang: lang, ["time": fmt(task.createdAt, lang: lang)])
        if !task.repeatRule.isEmpty {
            s += " · " + FeatureStrings.t("已完成 {n} 次", lang: lang,
                                          ["n": String(task.doneDates.count)])
        } else if let doneAt = task.doneAt, !task.dropped {
            s += " · " + FeatureStrings.t("完成于 {time}", lang: lang,
                                          ["time": fmt(doneAt, lang: lang)])
        }
        return s
    }

    static func subtasksLabel(_ progress: (done: Int, total: Int), lang: String) -> String {
        let title = AppStrings.t("子任务", lang: lang)
        return progress.total > 0 ? "\(title) · \(progress.done)/\(progress.total)" : title
    }

    /// onDelete 的四种 toast（sheets.js:40-43）。
    static func deleteMessage(title: String, kids: Int, isRepeat: Bool, lang: String) -> String {
        let params = ["title": title, "n": String(kids)]
        let key: String
        if isRepeat && kids > 0 { key = "已删除「{title}」及以后的重复和{n} 个子任务" }
        else if isRepeat { key = "已删除「{title}」及以后的重复" }
        else if kids > 0 { key = "已删除「{title}」及{n} 个子任务" }
        else { key = "已删除「{title}」" }
        return FeatureStrings.t(key, lang: lang, params)
    }

    static func dropMessage(title: String, lang: String) -> String {
        FeatureStrings.t("已放弃「{title}」", lang: lang, ["title": title])
    }

    static func deleteSubtaskMessage(title: String, lang: String) -> String {
        FeatureStrings.t("已删除子任务「{title}」", lang: lang, ["title": title])
    }
}
