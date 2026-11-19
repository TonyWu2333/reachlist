import SwiftUI

// MARK: - M-13 任务详情 sheet（T-17 / F-06 全量）
//
// 系统 .sheet + NavigationStack（§5.2 / OPEN-09=A）：点子任务从右推入，
// 从日历直达子任务时左上「‹ 父任务」返回父任务（F-06.2 的功能语义，不可删）。
// 实时编辑无保存按钮、5 个属性面板与联动、重复任务按 occ 打勾、子任务与进度、
// 放弃/恢复/删除与撤销、页脚信息。面板全部复用 T-14 的 M-15，文案走 FeatureStrings。

struct TaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let route: DetailRoute
    var onClose: () -> Void = {}

    /// 根页默认就是 route.id；只有从日历直达子任务、点「‹ 父任务」后才改写成父任务。
    /// 早期把 route.id 拷进 `@State nav`：sheet 内容首次呈现可能复用启动期以占位
    /// route（空 id）建好的实例，而 `@State` 初值只取一次，详情页会一直停在「—」。
    @State private var parentRoot: String? = nil
    @State private var path: [String] = []

    private var rootId: String { parentRoot ?? route.id }

    var body: some View {
        NavigationStack(path: $path) {
            page(id: rootId)
                .navigationDestination(for: String.self) { childId in
                    page(id: childId)
                }
        }
        .onChange(of: route.id) { _, _ in
            parentRoot = nil
            path = []
        }
    }

    private func page(id: String) -> some View {
        TaskDetailPage(
            id: id, route: route,
            onPushSub: { path.append($0) },
            onBack: { parentId in
                if !path.isEmpty { path.removeLast() }
                else if let parentId, !parentId.isEmpty { parentRoot = parentId }
            },
            onClose: close
        )
    }

    private func close() {
        dismiss()
        onClose()
    }
}

// MARK: - 单条任务的详情页（每个 id 一个实例，草稿状态互不串台）

private struct TaskDetailPage: View {
    @EnvironmentObject private var store: CalendarDataStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    let id: String
    let route: DetailRoute
    let onPushSub: (String) -> Void
    let onBack: (String?) -> Void
    let onClose: () -> Void

    @State private var panel: PropertyPanel? = nil
    @State private var draftTitle = ""
    @State private var draftNote = ""
    @State private var titleBefore = ""
    @State private var newSub = ""
    @FocusState private var titleFocused: Bool

    private var task: PlannerTask? { store.find(id) }
    private var parent: PlannerTask? {
        guard let task, !task.parentId.isEmpty else { return nil }
        return store.find(task.parentId)
    }
    private var today: String { PlannerCalendar.today() }
    private var occDay: String {
        TaskDetailContract.occOf(task, rootId: route.id, rootOcc: route.occ, today: today)
    }
    private var parentOcc: String {
        TaskDetailContract.occOf(parent, rootId: route.id, rootOcc: route.occ, today: today)
    }
    private var done: Bool {
        guard let task else { return false }
        return TaskDetailContract.isDone(task, parent: parent, occDay: occDay, parentOcc: parentOcc)
    }
    private var canDrop: Bool {
        guard let task else { return false }
        return TaskDetailContract.canDrop(task, parent: parent)
    }
    private var children: [PlannerTask] {
        TaskDetailContract.children(store.tasks, parentId: id)
    }
    private var progress: (done: Int, total: Int) {
        guard let task else { return (0, 0) }
        return TaskDetailContract.subProgress(store.tasks, parent: task, occ: occDay)
    }

    var body: some View {
        ScrollView {
                if let task {
                    VStack(alignment: .leading, spacing: 0) {
                        if let parent {
                            Button { onBack(parent.id) } label: {
                                HStack(spacing: 2) {
                                    ReachIcon(name: .chevronLeft, size: 22)
                                    Text(parent.title).lineLimit(1)
                                }
                                .font(.body.weight(.medium))
                                .foregroundStyle(DesignTokens.color("--accent", scheme: scheme))
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 6)
                        }

                        titleRow(task)
                        if task.dropped { droppedBanner(task) }
                        propertyGroup(task)
                        if task.parentId.isEmpty { subtaskSection(task) }
                        quadrantSection(task)
                        noteSection(task)
                        footer(task)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                } else {
                    Text("—")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                }
        }
        .background(DesignTokens.color("--surface", scheme: scheme))
        .onAppear {
            draftTitle = task?.title ?? ""
            draftNote = task?.note ?? ""
        }
    }

    // MARK: 标题 / 放弃 / 恢复

    private func titleRow(_ t: PlannerTask) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: check) {
                ZStack {
                    Circle().fill(done ? quadrantColor(t) : quadrantColor(t).opacity(0.12))
                    Circle().strokeBorder(quadrantColor(t), lineWidth: 2)
                    if t.dropped {
                        Text("×").font(.headline.weight(.bold)).foregroundStyle(.white)
                    } else if done {
                        ReachIcon(name: .check, size: 16).foregroundStyle(.white)
                    }
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .frame(minWidth: DesignTokens.touchTarget, minHeight: DesignTokens.touchTarget)
            .accessibilityLabel(t.dropped ? AppStrings.t("恢复", lang: lang)
                                : done ? AppStrings.t("标记为未完成", lang: lang)
                                : AppStrings.t("标记为完成", lang: lang))

            TextField(AppStrings.t("任务标题", lang: lang), text: $draftTitle, axis: .vertical)
                .font(.title3.weight(.semibold))
                .focused($titleFocused)
                .submitLabel(.done)
                .strikethrough(done && !t.dropped)
                .foregroundStyle(done ? .secondary : .primary)
                .onChange(of: draftTitle) { _, new in
                    store.update(id: id, patch: ["title": new.replacingOccurrences(of: "\n", with: "")])
                }
                .onChange(of: titleFocused) { _, focused in
                    if focused { titleBefore = t.title }
                    else if SearchContract.trimmed(t.title).isEmpty {
                        store.update(id: id, patch: ["title": titleBefore.isEmpty
                                                     ? AppStrings.t("未命名任务", lang: lang)
                                                     : titleBefore])
                        draftTitle = titleBefore.isEmpty
                            ? AppStrings.t("未命名任务", lang: lang) : titleBefore
                    }
                }
                .onSubmit { titleFocused = false }
        }
        .padding(.vertical, 10)
    }

    private func quadrantColor(_ t: PlannerTask) -> Color {
        let q = CalendarContract.quadrantOf(t)
        return DesignTokens.color(PanelCatalog.quadrants[q - 1].colorToken, scheme: scheme)
    }

    private func droppedBanner(_ t: PlannerTask) -> some View {
        HStack(spacing: 8) {
            ReachIcon(name: .ban, size: 16)
            Text(TaskDetailContract.droppedText(t, lang: lang)).font(.footnote)
            Spacer(minLength: 0)
            Button(AppStrings.t("恢复", lang: lang)) { restore() }
                .font(.footnote.weight(.semibold))
        }
        .padding(10)
        .background(DesignTokens.color("--fill", scheme: scheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 12)
    }

    // MARK: 属性面板

    private func propertyGroup(_ t: PlannerTask) -> some View {
        PropertyGroup {
            PropertyRow(icon: .calendar,
                        label: AppStrings.t(t.repeatRule.isEmpty ? "日期" : "开始日期", lang: lang),
                        value: TaskDetailContract.dateText(t, lang: lang, today: today),
                        valueIsSet: !t.date.isEmpty,
                        valueIsOverdue: CalendarContract.isOverdue(t, today: today),
                        isExpanded: panel == .date,
                        onTap: { toggle(.date) }) {
                DatePanelView(value: .constant(t.date),
                              quick: PanelCatalog.dateOptions(today: today),
                              onPick: setDate)
            }
            PropertyRow(icon: .clock, label: AppStrings.t("时间", lang: lang),
                        value: t.time.isEmpty ? AppStrings.t("无", lang: lang) : t.time,
                        valueIsSet: !t.time.isEmpty,
                        isExpanded: panel == .time,
                        onTap: { toggle(.time) }) {
                TimePanelView(value: .constant(t.time), onPick: setTime)
            }
            PropertyRow(icon: .bell, label: AppStrings.t("提醒", lang: lang),
                        value: TaskDetailContract.remindValue(t, remindOn: store.settings.remindOn, lang: lang),
                        valueIsSet: !t.time.isEmpty && t.remind != nil,
                        isExpanded: panel == .remind,
                        onTap: { openRemind() }) {
                RemindPanelView(value: .constant(t.remind), onPick: setRemind)
            }
            if t.parentId.isEmpty {
                PropertyRow(icon: .`repeat`, label: AppStrings.t("重复", lang: lang),
                            value: TaskDetailContract.repeatValue(t, lang: lang),
                            valueIsSet: !t.repeatRule.isEmpty,
                            isExpanded: panel == .repeat,
                            onTap: { toggle(.repeat) }) {
                    RepeatPanelView(value: .constant(t.repeatRule),
                                    date: t.date.isEmpty ? today : t.date,
                                    onPick: { rule, done in setRepeat(rule, done: done) })
                }
            }
        }
    }

    private func toggle(_ p: PropertyPanel) {
        HapticFeedback.play(.select)
        panel = panel == p ? nil : p
    }

    private func openRemind() {
        HapticFeedback.play(.select)
        let target = PanelLinkage.panelToOpen(.remind, hasTime: !(task?.time.isEmpty ?? true))
        panel = panel == target ? nil : target
    }

    private func apply(_ patch: TaskPatch) {
        var raw: [String: Any] = [:]
        for (key, value) in patch.values { raw[key] = value }
        for key in patch.cleared {
            raw[key] = key == "remind" ? NSNull() : ""
        }
        store.update(id: id, patch: raw)
    }

    private func setDate(_ v: String) {
        apply(PanelLinkage.setDate(v))
        panel = nil
    }

    private func setTime(_ v: String) {
        guard let t = task else { return }
        apply(PanelLinkage.setTime(v, taskDate: t.date, taskTime: t.time, remind: t.remind,
                                   defaultRemind: store.settings.defaultRemind, today: today))
        panel = nil
    }

    private func setRemind(_ v: Int?) {
        apply(PanelLinkage.setRemind(v))
        panel = nil
    }

    private func setRepeat(_ v: String, done: Bool) {
        guard let t = task else { return }
        apply(PanelLinkage.setRepeat(v, taskDate: t.date, today: today))
        if done { panel = nil }
    }

    // MARK: 子任务 / 象限 / 备注 / 页脚

    private func subtaskSection(_ t: PlannerTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TaskDetailContract.subtasksLabel(progress, lang: lang))
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                .padding(.top, 18)
            VStack(spacing: 0) {
                ForEach(children, id: \.id) { c in
                    let view = TaskDetailContract.subView(c, parent: t, occ: occDay)
                    TaskRow(model: TaskRowModel(task: view, today: today, isEnglish: lang == "en"),
                            compact: true, showDate: true, hideParent: true,
                            onToggle: { toggleSub(c) },
                            onOpen: { onPushSub(c.id) })
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    Divider().padding(.leading, 14)
                }
                HStack(spacing: 10) {
                    ReachIcon(name: .plus, size: 19)
                        .foregroundStyle(DesignTokens.color("--accent", scheme: scheme))
                    TextField(AppStrings.t("添加子任务，可以写“明天下午3点 买菜”", lang: lang), text: $newSub)
                        .font(.subheadline)
                        .submitLabel(.next)
                        .onSubmit(addSub)
                    if !subHint.isEmpty {
                        Text(subHint).font(.caption2)
                            .foregroundStyle(DesignTokens.color("--accent", scheme: scheme))
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
            }
            .background(DesignTokens.color("--surface-2", scheme: scheme))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerMedium))
        }
    }

    private var subParsed: ParsedInput? {
        SearchContract.trimmed(newSub).isEmpty ? nil : NaturalLanguageParser.parseInput(newSub)
    }

    private var subHint: String {
        guard let p = subParsed, !p.hits.isEmpty else { return "" }
        return [p.date.isEmpty ? "" : PlannerCalendar.dateLabel(p.date, today: today, isEnglish: lang == "en"), p.time]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func addSub() {
        guard let p = subParsed else { return }
        _ = store.addSubtask(parentId: id, fields: ["title": p.title, "date": p.date, "time": p.time])
        newSub = ""
        HapticFeedback.play(.light)
    }

    private func toggleSub(_ c: PlannerTask) {
        let wasDone = TaskDetailContract.subDone(task, c, occ: occDay)
        let all = store.toggleSubtask(parentId: id, childId: c.id, occ: occDay)
        if !wasDone && all && !done {
            toastCenter.show(
                text: AppStrings.t("子任务都完成了", lang: lang),
                action: { store.toggleDone(id: id, occ: occDay) },
                actionText: AppStrings.t("完成任务", lang: lang)
            )
        }
    }

    private func quadrantSection(_ t: PlannerTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.t("象限", lang: lang))
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                .padding(.top, 18)
            QuadrantPanelView(
                value: .constant(CalendarContract.quadrantOf(t)),
                onPick: { n in
                    let f = PanelLinkage.setQuadrant(n)
                    store.update(id: id, patch: ["important": f.important, "urgent": f.urgent])
                }
            )
        }
    }

    private func noteSection(_ t: PlannerTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.t("备注", lang: lang))
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                .padding(.top, 18)
            TextEditor(text: $draftNote)
                .font(.body)
                // 去掉 TextEditor 自带的系统白底（长方形白框），只留外层 --surface-2 圆角灰框。
                // 与搜索 / 打卡 / 日程页的 TextEditor / List 同款处理（§7.2）。
                .scrollContentBackground(.hidden)
                .frame(minHeight: 84)
                .padding(8)
                .background(DesignTokens.color("--surface-2", scheme: scheme))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerMedium))
                .onChange(of: draftNote) { _, new in
                    store.update(id: id, patch: ["note": new])
                }
        }
    }

    private func footer(_ t: PlannerTask) -> some View {
        HStack(spacing: 10) {
            Text(TaskDetailContract.footer(t, lang: lang))
                .font(.caption2)
                .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            if canDrop {
                Button(AppStrings.t("放弃", lang: lang)) { dropTask(t) }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(Capsule().fill(DesignTokens.color("--fill", scheme: scheme)))
                    .foregroundStyle(DesignTokens.color("--text-2", scheme: scheme))
                    .buttonStyle(.plain)
            }
            Button(AppStrings.t("删除", lang: lang)) { deleteTask(t) }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).frame(height: 34)
                .background(Capsule().fill(DesignTokens.color("--danger", scheme: scheme).opacity(0.12)))
                .foregroundStyle(DesignTokens.color("--danger", scheme: scheme))
                .buttonStyle(.plain)
        }
        .padding(.top, 18)
    }

    // MARK: 操作

    private func check() {
        if !done { HapticFeedback.play(.light) }
        if let parent {
            _ = store.toggleSubtask(parentId: parent.id, childId: id, occ: parentOcc)
        } else {
            store.toggleDone(id: id, occ: occDay)
        }
    }

    private func restore() {
        HapticFeedback.play(.light)
        store.update(id: id, patch: ["done": false])
    }

    private func dropTask(_ t: PlannerTask) {
        let undo = store.drop(id: id)
        toastCenter.show(text: TaskDetailContract.dropMessage(title: t.title, lang: lang),
                         action: undo, actionText: AppStrings.t("撤销", lang: lang))
        dismiss()
        onClose()
    }

    private func deleteTask(_ t: PlannerTask) {
        let kids = children.count
        let isRepeat = !t.repeatRule.isEmpty
        let undo = store.remove(id: id)
        toastCenter.show(
            text: TaskDetailContract.deleteMessage(title: t.title, kids: kids,
                                                   isRepeat: isRepeat, lang: lang),
            action: undo, actionText: AppStrings.t("撤销", lang: lang)
        )
        dismiss()
        onClose()
    }
}
