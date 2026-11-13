import SwiftUI

// MARK: - F-03 日程列表（CalendarView.vue:228-299, 365-459）
//
// 未完成/已完成分组、逾期分组（仅今天、全部移到今天带撤销）、进度环（排除 dropped）、
// 分组头文案、空态、任务行滑动操作与撤销 toast。任务行复用 T-14 的 M-19。

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
        List {
            Section {
                // 上游 .agenda 有 padding-top: 30px：把手条浮在列表之上（zIndex 2 > 1），
                // 顶部不留白会把「今天」标题的上半截盖住。
                agendaHeader
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 30, leading: 1, bottom: 14, trailing: 1))
            }

            if !overdue.isEmpty {
                Section {
                    ForEach(overdue, id: \.id) { t in
                        taskRow(RepeatInstance(task: t, occ: ""), showDate: true)
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
                    ForEach(split.open, id: \.task.id) { inst in
                        taskRow(inst, showDate: false)
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
                        ForEach(split.done, id: \.task.id) { inst in
                            taskRow(inst, showDate: false)
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
        .scrollContentBackground(.hidden)
        .background(DesignTokens.color("--bg", scheme: scheme))
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
    private func taskRow(_ inst: RepeatInstance, showDate: Bool) -> some View {
        let m = model(inst)
        TaskRow(model: m, showDate: showDate,
                onToggle: { toggle(inst) },
                onOpen: { onOpen(inst.task.id, inst.occ) })
            .taskRowSwipeActions(
                model: m, lang: lang,
                onComplete: { toggle(inst) },
                onPostpone: { postpone(inst) },
                onDrop: { drop(inst) },
                onDelete: { delete(inst) }
            )
            .listRowInsets(EdgeInsets(top: 3, leading: 1, bottom: 3, trailing: 1))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func toggle(_ inst: RepeatInstance) {
        store.toggleDone(id: inst.task.id, occ: inst.occ)
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
