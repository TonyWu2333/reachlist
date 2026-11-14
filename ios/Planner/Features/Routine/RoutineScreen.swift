import SwiftUI

// MARK: - M-12 打卡界面（T-16 / F-05 全量）
//
// 6 个规则分组（空组不显示）、未来实例标 later / 已结束、今日概览进度环、
// 连续次数与中英单位（TaskRow 元信息）、跳过 / 删除与撤销、空态与 FAB 默认值 {repeat:'d1'}。
// 呈现层按 §5.0 / OPEN-18：系统 List + 系统 swipeActions，不加自定义玻璃。

struct RoutineScreen: View {
    @EnvironmentObject private var store: CalendarDataStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    var onOpen: (String, String) -> Void = { _, _ in }
    var onAdd: (QuickAddDefaults) -> Void = { _ in }
    var onSearch: () -> Void = {}

    private var today: String { PlannerCalendar.today() }
    private var routines: [PlannerTask] { RoutineContract.routines(store.tasks) }
    private var groups: [RoutineGroup] { RoutineContract.groups(store.tasks, today: today) }
    private var summary: (headline: String, detail: String) {
        RoutineContract.summary(store.tasks, today: today, lang: lang)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // 页头放在 List 外面：insetGrouped 的 List 会给首行再叠一层内容缩进与
                // 分区间距，标题会比「四象限」「我的」更靠下、更靠里。放在外面才能让
                // 四个 tab 的标题位置完全对齐。
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                List {
                    if routines.isEmpty {
                        Section { emptyState }
                    } else {
                        Section {
                            summaryCard
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                        }
                        ForEach(groups, id: \.key) { group in
                            Section {
                                ForEach(group.items, id: \.task.id) { item in
                                    row(item, hideRepeat: group.key == "daily")
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets(top: 3, leading: 1, bottom: 3, trailing: 1))
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Text(AppStrings.t(group.labelKey, lang: lang))
                                    Text("\(group.items.count)").monospacedDigit()
                                        .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                        Section {
                            Color.clear.frame(height: 90)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                // 页头已经挪到 List 外面，这里去掉 List 自带的顶部内边距，
                // 否则标题和今日概览之间会多出一条约 40pt 的空档。
                .contentMargins(.top, 0, for: .scrollContent)
                .background(DesignTokens.color("--bg", scheme: scheme))
            }
            .background(DesignTokens.color("--bg", scheme: scheme))

            Button {
                onAdd(.routine())
            } label: {
                ReachIcon(name: .plus, size: 28)
                    .foregroundStyle(DesignTokens.color("--on-accent", scheme: scheme))
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 20)
                        .fill(DesignTokens.color("--accent", scheme: scheme)))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20).padding(.bottom, 22)
            .accessibilityLabel(AppStrings.t("新建打卡", lang: lang))
        }
    }

    // MARK: 页头 / 今日概览 / 空态

    private var header: some View {
        HStack(spacing: 10) {
            Text(AppStrings.t("打卡", lang: lang))
                .font(DesignTokens.font(.title))
            Spacer(minLength: 0)
            Button(action: onSearch) {
                ReachIcon(name: .search, size: 17)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DesignTokens.color("--fill", scheme: scheme)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.t("搜索", lang: lang))
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(DesignTokens.color("--fill-2", scheme: scheme), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: RoutineContract.progress(store.tasks, today: today))
                    .stroke(DesignTokens.color("--accent", scheme: scheme),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.headline).font(.body.weight(.semibold))
                Text(summary.detail).font(.caption)
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(DesignTokens.color("--surface", scheme: scheme))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerLarge))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ReachIcon(name: .`repeat`, size: 46)
                .foregroundStyle(DesignTokens.color("--accent", scheme: scheme).opacity(0.65))
            Text(AppStrings.t("还没有打卡任务", lang: lang)).font(.headline)
            VStack(spacing: 2) {
                Text(AppStrings.t("每天、每周都要做的事放在这里打卡", lang: lang))
                Text(AppStrings.t("试试输入「每天 跑步」或「每周五晚上8点 周会」", lang: lang))
            }
            .font(.caption)
            .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
            .multilineTextAlignment(.center)
            Button {
                onAdd(.routine())
            } label: {
                HStack(spacing: 6) {
                    ReachIcon(name: .plus, size: 16)
                    Text(AppStrings.t("添加打卡", lang: lang))
                }
                .padding(.horizontal, 16).frame(height: 38)
                .background(Capsule().fill(DesignTokens.color("--accent", scheme: scheme)))
                .foregroundStyle(DesignTokens.color("--on-accent", scheme: scheme))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: 任务行

    private func row(_ item: RoutineItem, hideRepeat: Bool) -> some View {
        var model = TaskRowModel(task: item.task, occ: item.occ,
                                 streak: item.streak, streakUnit: item.unit,
                                 today: today, isEnglish: lang == "en")
        let parentTitle = item.task.parentId.isEmpty
            ? "" : (store.find(item.task.parentId)?.title ?? "")
        model.parentTitle = parentTitle
        return TaskRow(
            model: model, showDate: !item.isToday && !item.occ.isEmpty,
            hideRepeat: hideRepeat,
            onToggle: { store.toggleDone(id: item.task.id, occ: item.occ) },
            onOpen: { onOpen(item.task.id, item.occ) }
        )
            .background(DesignTokens.color("--surface", scheme: scheme))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerMedium))
            .opacity(item.isToday ? 1 : 0.75)
            .taskRowSwipeActions(
                model: model, lang: lang,
                onComplete: { store.toggleDone(id: item.task.id, occ: item.occ) },
                onPostpone: { skip(item) },
                onDrop: {},
                onDelete: { delete(item) }
            )
    }

    private func skip(_ item: RoutineItem) {
        guard !item.occ.isEmpty else { return }
        let undo = store.skip(id: item.task.id, occ: item.occ)
        toastCenter.show(text: RoutineContract.skipText(occ: item.occ, today: today, lang: lang),
                         action: undo, actionText: AppStrings.t("撤销", lang: lang))
    }

    private func delete(_ item: RoutineItem) {
        let kids = store.childrenOf(item.task.id).count
        let undo = store.remove(id: item.task.id)
        toastCenter.show(text: RoutineContract.deleteText(title: item.task.title, kids: kids, lang: lang),
                         action: undo, actionText: AppStrings.t("撤销", lang: lang))
    }
}
