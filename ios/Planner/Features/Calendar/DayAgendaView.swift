import SwiftUI

// MARK: - F-03 日程列表（CalendarView.vue:228-299, 365-459）
//
// 未完成/已完成分组、逾期分组（仅今天、全部移到今天带撤销）、进度环（排除 dropped）、
// 分组头文案、空态、任务行滑动操作与撤销 toast。任务行复用 T-14 的 M-19。

/// 只比数据输入：闭包每次父 body 都重建、lunar 静态、store 恒为同一实例。
/// 收拢拖动让父视图逐帧更新时，数据未变就跳过 List body 重算（§7.2）。
/// store 的 @ObservedObject 与环境失效不走 ==，任务变更/深浅色仍正常刷新。
/// View 是 @MainActor，conformance 必须同隔离域。
extension DayAgendaView: @MainActor Equatable {
    static func == (lhs: DayAgendaView, rhs: DayAgendaView) -> Bool {
        lhs.selected == rhs.selected && lhs.today == rhs.today
            && lhs.isEnglish == rhs.isEnglish && lhs.store === rhs.store
    }
}

struct DayAgendaView: View {
    let selected: String
    let today: String
    let isEnglish: Bool
    let lunar: LunarData?
    let onOpen: (String, String) -> Void
    let onAdd: (String) -> Void

    @ObservedObject var store: CalendarDataStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme
    @State private var showDone = true
    /// 左滑展开中的任务 id：整行底色随之变灰（颜色与分割线一致）。
    @State private var swipedTaskID: String?
    /// 日程列表可用宽度，供长按预览卡片按比例取宽。
    @State private var agendaWidth: CGFloat = 0

    private var instances: [RepeatInstance] {
        CalendarContract.dayTasks(store.tasks, selected: selected)
    }
    private var overdue: [PlannerTask] {
        CalendarContract.overdue(store.tasks, selected: selected, today: today)
    }
    private var split: (open: [RepeatInstance], done: [RepeatInstance]) {
        CalendarContract.split(instances)
    }
    private var progress: CalendarContract.Progress {
        CalendarContract.progress(instances)
    }
    private var heading: CalendarHeading {
        CalendarContract.heading(selected: selected, today: today, isEnglish: isEnglish, lunar: lunar)
    }
    private var dayInfo: PlannerDayInfo? { lunar?.dayInfo(selected) }

    var body: some View {
        VStack(spacing: 0) {
            // 标题块固定在 List 之外：列表滚动／顶部裁切不再切到标题、进度环与节假日标签。
            // 顶部 38pt 让标题避开浮在列表之上的把手条（把手命中区盖住本视图顶部约 26pt）。
            agendaHeader
                // 21pt = insetGrouped 的 20pt 分组页边距 + 1pt 行边距，标题与卡片左缘对齐。
                .padding(.horizontal, 21)
                .padding(.top, 38)
                .padding(.bottom, 24)

            List {
                if !overdue.isEmpty {
                    Section {
                        ForEach(Array(overdue.enumerated()), id: \.element.id) { index, t in
                            taskRow(RepeatInstance(task: t, occ: ""), showDate: true,
                                    edge: rowEdge(index, overdue.count),
                                    hideSeparator: hideBottomSeparator(
                                        id: t.id,
                                        nextID: index + 1 < overdue.count ? overdue[index + 1].id : nil))
                        }
                    } header: {
                        HStack {
                            Text(AppStrings.t("已过期 · {n}", lang: lang, ["n": String(overdue.count)]))
                                .foregroundStyle(DesignTokens.color("--danger", scheme: scheme))
                            Spacer()
                            Button(AppStrings.t("全部移到今天", lang: lang)) { moveOverdue() }
                                .foregroundStyle(DesignTokens.color("--accent", scheme: scheme))
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }

                if !split.open.isEmpty {
                    Section {
                        ForEach(Array(split.open.enumerated()), id: \.element.task.id) { index, inst in
                            taskRow(inst, showDate: false, edge: rowEdge(index, split.open.count),
                                    hideSeparator: hideBottomSeparator(
                                        id: inst.task.id,
                                        nextID: index + 1 < split.open.count
                                            ? split.open[index + 1].task.id : nil))
                        }
                    } header: {
                        if !overdue.isEmpty {
                            Text(heading.title).font(.subheadline.weight(.semibold))
                        }
                    }
                }

                if !split.done.isEmpty {
                    Section {
                        if showDone {
                            ForEach(Array(split.done.enumerated()), id: \.element.task.id) { index, inst in
                                taskRow(inst, showDate: false, edge: rowEdge(index, split.done.count),
                                        hideSeparator: hideBottomSeparator(
                                            id: inst.task.id,
                                            nextID: index + 1 < split.done.count
                                                ? split.done[index + 1].task.id : nil))
                            }
                        }
                    } header: {
                        Button {
                            showDone.toggle()
                        } label: {
                            HStack {
                                Text(doneHead).font(.subheadline.weight(.semibold))
                                ReachIcon(name: .chevronDown, size: 16)
                                    .rotationEffect(.degrees(showDone ? 0 : -90))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                if instances.isEmpty && overdue.isEmpty {
                    Section {
                        emptyState
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1))
                    }
                }

                Section {
                    Color.clear.frame(height: 110)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1))
                }
            }
            // T-14 的卡片列表做法：insetGrouped 自带 20pt 分组页边距，
            // 每行左右再各留 1pt = 21pt，与真机 Tab Bar 玻璃胶囊边界对齐。
            // plain 没有这层页边距，任务卡片会直接贴着屏幕边缘。
            .listStyle(.insetGrouped)
            // 交给系统协调各行左滑的互斥、滚动/点击外部收起，状态回调更可靠。
            .modifier(SwipeActionsContainerModifier())
            // 标题块已移到 List 外，这里去掉 List 自带的顶部内容内边距，
            // 否则标题与第一张卡片之间会多出约 34pt 空档。
            .contentMargins(.top, 0, for: .scrollContent)
            // 组与组之间保持紧凑而清晰的层次。
            .listSectionSpacing(20)
            .scrollContentBackground(.hidden)
        }
        .background(DesignTokens.color("--bg", scheme: scheme))
        // 预览卡片宽度随可用宽度自适应（各机型 / iPad 分栏都成立），不写死某一机型。
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { agendaWidth = $0 }
    }

    /// 预览卡片宽度：与任务卡片左右边界（21pt）对齐，上限 372、下限 280。
    private var previewWidth: CGFloat {
        agendaWidth > 0 ? min(372, max(280, agendaWidth - 42)) : 320
    }

    // MARK: 头部 / 进度环

    private var agendaHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(heading.title).font(.title2.weight(.bold))
                    if let info = dayInfo {
                        if !info.holidayName.isEmpty {
                            tag(info.holidayName, work: false)
                        } else if info.holiday == "班" {
                            tag(AppStrings.t("调休上班", lang: lang), work: true)
                        }
                    }
                }
                Text(heading.sub).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if progress.total > 0 { ring.padding(.trailing, 4) }
        }
        .padding(.horizontal, 4)
    }

    private func tag(_ text: String, work: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(work
                ? DesignTokens.color("--fill", scheme: scheme)
                : DesignTokens.color("--danger", scheme: scheme).opacity(0.12)))
            .foregroundStyle(work
                ? DesignTokens.color("--text-2", scheme: scheme)
                : DesignTokens.color("--danger", scheme: scheme))
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(DesignTokens.color("--fill-2", scheme: scheme), lineWidth: 3.2)
            Circle()
                .trim(from: 0, to: progress.ratio)
                .stroke(DesignTokens.color("--accent", scheme: scheme),
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(progress.done)/\(progress.total)")
                .font(.caption2.weight(.semibold)).monospacedDigit()
        }
        .frame(width: 44, height: 44)
    }

    private var doneHead: String {
        let s = CalendarContract.doneSummary(instances)
        var parts: [String] = []
        if s.done > 0 { parts.append(AppStrings.t("已完成 {n}", lang: lang, ["n": String(s.done)])) }
        if s.dropped > 0 { parts.append(AppStrings.t("已放弃 {n}", lang: lang, ["n": String(s.dropped)])) }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            ReachIcon(name: .sparkle, size: 44).foregroundStyle(.secondary)
            Text(AppStrings.t(selected == today ? "今天还没有安排" : "这天还没有安排", lang: lang))
                .font(.headline)
            Text(AppStrings.t("试试输入「明天下午3点开会」，自动识别时间", lang: lang))
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onAdd(selected)
            } label: {
                HStack(spacing: 6) {
                    ReachIcon(name: .plus, size: 18)
                    Text(AppStrings.t("添加任务", lang: lang)).font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18).frame(height: 40)
                .background(Capsule().fill(DesignTokens.color("--accent-soft", scheme: scheme)))
                .foregroundStyle(DesignTokens.color("--accent", scheme: scheme))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: 任务行与操作

    private func model(_ inst: RepeatInstance) -> TaskRowModel {
        let kids = CalendarContract.childrenOf(inst.task.id, store.tasks)
        let subDone = kids.filter { child in
            !inst.task.repeatRule.isEmpty && !inst.occ.isEmpty
                ? child.doneDates.contains(inst.occ)
                : child.done
        }.count
        return TaskRowModel(
            task: inst.task, occ: inst.occ,
            subDone: subDone, subTotal: kids.count,
            parentTitle: "", streak: 0, streakUnit: "天",
            today: today, isEnglish: isEnglish
        )
    }

    @ViewBuilder
    private func taskRow(_ inst: RepeatInstance, showDate: Bool, edge: GroupRowEdge,
                         hideSeparator: Bool = false) -> some View {
        let m = model(inst)
        let dimmed = isRowDimmed(inst.task.id)
        TaskRow(model: m, showDate: showDate, showsCardBackground: false,
                onToggle: { toggle(inst) },
                onOpen: {
                    // 打开详情会收起左滑，灰底同步恢复。
                    swipedTaskID = nil
                    onOpen(inst.task.id, inst.occ)
                })
            // 整组共用一张卡片：每行只负责自己那一段底色，首/尾行带圆角，
            // 中间行之间靠一条内缩的分割线区分（参照「备忘录」分组列表）。
            .background {
                ZStack {
                    GroupCardShape(edge: edge)
                        .fill(DesignTokens.color("--surface", scheme: scheme))
                    // 左滑展开中：与分割线同色（--fill-2 叠在 surface 上，正好等于分隔线的实测色）。
                    GroupCardShape(edge: edge)
                        .fill(DesignTokens.color("--fill-2", scheme: scheme))
                        .opacity(dimmed ? 1 : 0)
                        .animation(.easeOut(duration: 0.22), value: dimmed)
                }
            }
            .overlay(alignment: .bottom) {
                // 常驻绘制、用 opacity 控制显隐：下方行被勾选移除后本行成为组尾，
                // 分割线要随让位动画淡出而不是瞬间消失（条件移除做不到）。
                let showsSeparator = edge.hasSeparator && !hideSeparator
                // 不透明分隔线：先铺 surface 再叠 --fill-2，等价于「白底上的分隔灰」。
                // 这样即使压在左滑变灰的行上，也不会二次变深。
                Rectangle()
                    .fill(DesignTokens.color("--surface", scheme: scheme))
                    .overlay {
                        Rectangle()
                            .fill(DesignTokens.color("--fill-2", scheme: scheme))
                    }
                    .frame(height: 1)
                    // 起始位置对齐标题文字：行内边距 + 勾选触点 + 图标文字间距。
                    .padding(.leading, TaskRowContract.separatorInset)
                    .padding(.trailing, TaskRowContract.rowHorizontalInset)
                    .opacity(showsSeparator ? 1 : 0)
                    .animation(.easeOut(duration: 0.22), value: showsSeparator)
            }
            .taskRowSwipeActions(
                model: m, lang: lang,
                onSwipePresentation: { _, presented in
                    swipedTaskID = presented ? inst.task.id : nil
                },
                onComplete: { toggle(inst) },
                onPostpone: { postpone(inst) },
                onDrop: { drop(inst) },
                onDelete: { delete(inst) }
            )
            // 长按快速预览（F-03 增补）：预览卡片与菜单面板全部交给系统
            // contextMenu，抬起动画、背景压暗与 iOS 26 的 Liquid Glass 菜单都由系统提供。
            // 抬起形状必须与行本身的组卡片形状一致：直接用 40/60 的圆角会让 52pt 高的行
            // 两端瞬间变成半圆（胶囊），所以这里复用 GroupCardShape（首/尾 14、中间 0）。
            .contentShape(.contextMenuPreview, GroupCardShape(edge: edge))
            .contextMenu {
                ShareLink(item: shareText(inst))
                Button(role: .destructive) {
                    delete(inst)
                } label: {
                    Label {
                        Text(AppStrings.t("删除", lang: lang))
                    } icon: {
                        Image("icon-trash").renderingMode(.template)
                    }
                }
            } preview: {
                TaskPreviewCard(task: inst.task, occ: inst.occ, width: previewWidth,
                                store: store)
            }
            // 组内行紧贴，形成一整块；组与组之间由 Section 自带间距分开。
            .listRowInsets(EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func rowEdge(_ index: Int, _ count: Int) -> GroupRowEdge {
        if count <= 1 { return .single }
        if index == 0 { return .first }
        if index == count - 1 { return .last }
        return .middle
    }

    /// 左滑展开的行会整体左移、变窄，行内画的分割线会随之错位并叠在灰底上变深；
    /// 因此隐藏该行自身的下边线，以及它上一行的下边线（即它上方那条）。
    private func hideBottomSeparator(id: String, nextID: String?) -> Bool {
        isRowDimmed(id) || (nextID.map(isRowDimmed) ?? false)
    }

    /// 行是否显示灰底：系统认为该行已展开。
    private func isRowDimmed(_ id: String) -> Bool {
        swipedTaskID == id
    }

    private func toggle(_ inst: RepeatInstance) {
        // 让位动画：与四象限跨象限写回同一条 spring（0.42 / 0.72，见
        // QuadrantScreen.snapFlightSeconds）。勾选行移出后，上下其余行弹性补位；
        // 取消勾选（行插回）与左滑「完成」同走这里，共用同一曲线。
        // 日程列表是纯 SwiftUI List，withAnimation 直接驱动行增删与布局，
        // 不需要四象限那套 UIKit 桥接动画。
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            store.toggleDone(id: inst.task.id, occ: inst.occ)
        }
        HapticFeedback.play(.success)
    }

    private func delete(_ inst: RepeatInstance) {
        let t = inst.task
        let kids = CalendarContract.childrenOf(t.id, store.tasks).count
        let undo = store.remove(id: t.id)
        toastCenter.show(
            text: CalendarStrings.deleted(title: t.title, kids: kids,
                                          isRepeat: !t.repeatRule.isEmpty, lang: lang),
            action: undo, actionText: AppStrings.t("撤销", lang: lang)
        )
    }

    /// 长按预览的「共享」载荷：标题、日期时间、子任务勾选状态、备注。
    /// 复用既有「子任务」「备注」词条，不新增本地化 key。
    private func shareText(_ inst: RepeatInstance) -> String {
        let t = inst.task
        var lines: [String] = [t.title]
        let day = inst.occ.isEmpty ? (t.date.isEmpty ? selected : t.date) : inst.occ
        let when = [day, t.time].filter { !$0.isEmpty }.joined(separator: " ")
        if !when.isEmpty { lines.append(when) }

        let kids = CalendarContract.childrenOf(t.id, store.tasks).filter { !$0.dropped }
        if !kids.isEmpty {
            lines.append("")
            lines.append(AppStrings.t("子任务", lang: lang))
            for kid in kids {
                lines.append((store.subDone(t, kid, occ: inst.occ) ? "☑ " : "☐ ") + kid.title)
            }
        }

        let note = t.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            lines.append("")
            lines.append(AppStrings.t("备注", lang: lang))
            lines.append(note)
        }
        return lines.joined(separator: "\n")
    }

    private func drop(_ inst: RepeatInstance) {
        let undo = store.drop(id: inst.task.id)
        toastCenter.show(
            text: AppStrings.t("已放弃「{title}」", lang: lang, ["title": inst.task.title]),
            action: undo, actionText: AppStrings.t("撤销", lang: lang)
        )
    }

    private func postpone(_ inst: RepeatInstance) {
        let result = store.postpone(id: inst.task.id, occ: inst.occ)
        let text: String
        if inst.task.repeatRule.isEmpty {
            let label = PlannerCalendar.dateLabel(result.nextDate, today: store.today, isEnglish: isEnglish)
            text = CalendarStrings.postponed(label, lang: lang)
        } else {
            text = AppStrings.t("已跳过这一次", lang: lang)
        }
        toastCenter.show(text: text, action: result.undo, actionText: AppStrings.t("撤销", lang: lang))
    }

    private func moveOverdue() {
        let result = store.moveOverdueToToday()
        HapticFeedback.play(.success)
        toastCenter.show(
            text: CalendarStrings.movedAll(result.count, lang: lang),
            action: result.undo, actionText: AppStrings.t("撤销", lang: lang)
        )
    }
}

// MARK: - 分组卡片形状

/// iOS 27 起系统提供 swipeActionsContainer：在一个容器内协调各行左滑的互斥与收起。
/// 低版本没有该能力，退回系统默认行为。
private struct SwipeActionsContainerModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content.swipeActionsContainer()
        } else {
            content
        }
    }
}

/// 行在组内的位置：只有首/尾行带圆角，组内行用分割线衔接。
private enum GroupRowEdge {
    case single, first, middle, last

    var hasSeparator: Bool {
        switch self {
        case .single, .last: return false
        case .first, .middle: return true
        }
    }

    var topRadius: CGFloat {
        switch self {
        case .single, .first: return DesignTokens.cornerMedium
        case .middle, .last: return 0
        }
    }

    var bottomRadius: CGFloat {
        switch self {
        case .single, .last: return DesignTokens.cornerMedium
        case .first, .middle: return 0
        }
    }
}

private struct GroupCardShape: Shape {
    // 存圆角值而不是 edge 枚举：首/尾行被勾选移除后，新首/尾行的圆角要从 0
    // 平滑长到 14（让位动画的一部分），animatableData 才能逐帧插值；
    // 枚举切换只能跳变，会让滑动中的卡片边角「咔」地变圆。
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    init(edge: GroupRowEdge) {
        topRadius = edge.topRadius
        bottomRadius = edge.bottomRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        )
        .path(in: rect)
    }
}

// MARK: - 长按预览卡片
//
// `.contextMenu(...) preview:` 的自定义预览内容。抬起/收起动画、背景压暗与下方菜单的
// Liquid Glass 面板全部由系统提供；这里只负责卡片内部（事件名称 / 子任务 / 备注）。
// 宽度由调用方按可用宽度注入，避免写死某一机型。

/// 预览卡片与系统抬起/最终预览容器共用的圆角。
/// 参考截图的卡片圆角实测约 40pt，与系统 contextMenu 预览观感一致。
private let agendaPreviewCornerRadius: CGFloat = 40

private struct TaskPreviewCard: View {
    let task: PlannerTask
    let occ: String
    let width: CGFloat
    @ObservedObject var store: CalendarDataStore

    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    private var done: Bool {
        task.repeatRule.isEmpty ? task.done : task.doneDates.contains(occ.isEmpty ? task.date : occ)
    }
    private var subtasks: [PlannerTask] {
        CalendarContract.childrenOf(task.id, store.tasks).filter { !$0.dropped }
    }
    private var note: String {
        task.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// 子任务过多时只列前 5 条，余量用 +N 表示，避免预览被系统压缩。
    private var shownSubtasks: [PlannerTask] { Array(subtasks.prefix(5)) }
    private var hiddenSubtaskCount: Int { max(0, subtasks.count - shownSubtasks.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.title3.weight(.bold))
                    .strikethrough(done, color: DesignTokens.color("--text-3", scheme: scheme))
                    .foregroundStyle(done
                        ? DesignTokens.color("--text-3", scheme: scheme)
                        : DesignTokens.color("--text", scheme: scheme))
                    .lineLimit(3)
                if !task.time.isEmpty {
                    Text(task.time)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                }
            }

            if !subtasks.isEmpty { subtaskBlock }
            if !note.isEmpty { noteBlock }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: width, alignment: .topLeading)
        .frame(minHeight: 196, alignment: .topLeading)
        .background(DesignTokens.color("--surface", scheme: scheme))
        .clipShape(RoundedRectangle(cornerRadius: agendaPreviewCornerRadius, style: .continuous))
    }

    private var subtaskBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle(AppStrings.t("子任务", lang: lang))
            ForEach(shownSubtasks, id: \.id) { kid in
                let checked = store.subDone(task, kid, occ: occ)
                HStack(spacing: 8) {
                    checkDot(checked)
                    Text(kid.title)
                        .font(.subheadline)
                        .strikethrough(checked)
                        .foregroundStyle(checked
                            ? DesignTokens.color("--text-3", scheme: scheme)
                            : DesignTokens.color("--text-2", scheme: scheme))
                        .lineLimit(1)
                }
            }
            if hiddenSubtaskCount > 0 {
                Text("+\(hiddenSubtaskCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                    .padding(.leading, 24)
            }
        }
    }

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(AppStrings.t("备注", lang: lang))
            Text(note)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.color("--text-2", scheme: scheme))
                .lineLimit(6)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
    }

    private func checkDot(_ checked: Bool) -> some View {
        ZStack {
            Circle()
                .fill(checked ? DesignTokens.color("--accent", scheme: scheme) : Color.clear)
            Circle()
                .strokeBorder(checked
                    ? DesignTokens.color("--accent", scheme: scheme)
                    : DesignTokens.color("--text-3", scheme: scheme), lineWidth: 1.4)
            if checked {
                ReachIcon(name: .check, size: 9).foregroundStyle(.white)
            }
        }
        .frame(width: 16, height: 16)
    }
}
