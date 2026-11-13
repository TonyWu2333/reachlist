import SwiftUI

// MARK: - T-14 组件预览（不是业务界面）
//
// 放在「日程」tab，用于真机核对 A-26 / A-30 / A-37 / A-38：
// 任务行的元信息分支、compact 变体、右滑完成、左滑推迟/放弃/删除、勾选 380ms 动画；
// 5 个属性面板与联动规则。真实日历与任务详情由 T-15 / T-17 接入，本页届时移除。

struct TaskRowGallery: View {
    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var toastCenter: ToastCenter

    @State private var rows: [TaskRowModel]
    @State private var demo: PlannerTask
    @State private var openPanel: PropertyPanel?
    @State private var defaultRemind = 15

    private var today: String { DateText.today() }
    private var isEnglish: Bool { lang == "en" }

    init() {
        let today = DateText.today()
        let sample = TaskRowGallery.task(
            id: "demo", title: "整理下周的会议材料", note: "带上打印稿",
            date: today, time: "18:00", important: true, urgent: true, remind: 15
        )
        _demo = State(initialValue: sample)
        _rows = State(initialValue: [
            TaskRowModel(
                task: sample, subDone: 1, subTotal: 3,
                parentTitle: "", streak: 0, today: today
            ),
            TaskRowModel(
                task: TaskRowGallery.task(
                    id: "repeat", title: "每天喝水 8 杯", date: today, time: "08:00",
                    repeatRule: "d1", remind: 0
                ),
                subDone: 0, subTotal: 0, streak: 3, streakUnit: "天", today: today
            ),
            TaskRowModel(
                task: TaskRowGallery.task(
                    id: "done", title: "回复客户邮件", date: today, time: "10:00", done: true, doneAt: 1_700_000_100_000
                ),
                today: today
            ),
            TaskRowModel(
                task: TaskRowGallery.task(
                    id: "dropped", title: "整理旧备份", date: today, dropped: true
                ),
                today: today
            ),
            TaskRowModel(
                task: TaskRowGallery.task(
                    id: "child", title: "买牛奶", date: today, time: "19:00",
                    remind: 5, parentId: "demo"
                ),
                parentTitle: "整理下周的会议材料", today: today
            ),
        ])
    }

    var body: some View {
        List {
            Section {
                Text(AppStrings.t("滑动试试：右滑完成，左滑推迟/放弃/删除", lang: lang))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .reachCardRow()
                ForEach(rows.indices, id: \.self) { index in
                    TaskRow(
                        model: withLanguage(rows[index]),
                        showDate: true,
                        onToggle: { toggle(index) },
                        onOpen: { openDetail(rows[index]) }
                    )
                    .taskRowSwipeActions(
                        model: withLanguage(rows[index]),
                        lang: lang,
                        onComplete: { toggle(index) },
                        onPostpone: { postpone(index) },
                        onDrop: { drop(index) },
                        onDelete: { delete(index) }
                    )
                    .reachCardRow()
                }
            } header: {
                Text(AppStrings.t("任务行预览", lang: lang))
            } footer: {
                Text(AppStrings.t("T-14 组件预览，真实日历由 T-15 接入", lang: lang))
            }

            Section {
                TaskRow(
                    model: TaskRowModel(
                        task: TaskRowGallery.task(id: "compact", title: "紧凑变体：标题最多两行，无卡片底", date: today, time: "20:00"),
                        today: today
                    ),
                    compact: true
                )
                .reachCardRow()
            } header: {
                Text("compact")
            }

            Section {
                PropertyGroup(fill: "--surface") {
                    propertyDate
                    panelDivider
                    propertyTime
                    panelDivider
                    propertyRemind
                    panelDivider
                    propertyRepeat
                }
                .reachPanelRow()

                quadrantSection
                    .reachPanelRow()
            } header: {
                Text(AppStrings.t("属性面板", lang: lang))
            }
        }
        .listStyle(.insetGrouped)
        // 页面底色用 --bg、卡片用 --surface：任务行只有「卡片」这一层，
        // 不再有「分组白底 + 卡片描边」两层叠在一起，也就不需要任何行间线。
        .scrollContentBackground(.hidden)
        .background(DesignTokens.color("--bg", scheme: scheme))
        .navigationTitle(Text(AppStrings.t("组件预览", lang: lang)))
    }

    // MARK: 属性行

    private var propertyDate: some View {
        PropertyRow(
            icon: .calendar,
            label: AppStrings.t(demo.repeatRule.isEmpty ? "日期" : "开始日期", lang: lang),
            value: demo.date.isEmpty ? AppStrings.t("无", lang: lang) : DateText.label(demo.date, today: today, isEnglish: isEnglish),
            valueIsSet: !demo.date.isEmpty,
            valueIsOverdue: DateText.isOverdue(date: demo.date, repeatRule: demo.repeatRule, done: demo.done, today: today),
            isExpanded: openPanel == .date,
            onTap: { togglePanel(.date) }
        ) {
            DatePanelView(
                value: .constant(demo.date),
                quick: PanelCatalog.dateOptions(today: today),
                onPick: { apply(PanelLinkage.setDate($0)); openPanel = nil }
            )
        }
    }

    private var propertyTime: some View {
        PropertyRow(
            icon: .clock,
            label: AppStrings.t("时间", lang: lang),
            value: demo.time.isEmpty ? AppStrings.t("无", lang: lang) : demo.time,
            valueIsSet: !demo.time.isEmpty,
            isExpanded: openPanel == .time,
            onTap: { togglePanel(.time) }
        ) {
            TimePanelView(
                value: .constant(demo.time),
                onPick: {
                    apply(PanelLinkage.setTime(
                        $0, taskDate: demo.date, taskTime: demo.time,
                        remind: demo.remind, defaultRemind: defaultRemind, today: today
                    ))
                    openPanel = nil
                }
            )
        }
    }

    private var propertyRemind: some View {
        PropertyRow(
            icon: .bell,
            label: AppStrings.t("提醒", lang: lang),
            value: demo.time.isEmpty
                ? AppStrings.t("先设时间", lang: lang)
                : PanelCatalog.remindLabel(demo.remind, isEnglish: isEnglish),
            valueIsSet: !demo.time.isEmpty && demo.remind != nil,
            isExpanded: openPanel == .remind,
            onTap: {
                HapticFeedback.play(.select)
                openPanel = PanelLinkage.panelToOpen(.remind, hasTime: !demo.time.isEmpty)
            }
        ) {
            RemindPanelView(
                value: .constant(demo.remind),
                onPick: { apply(PanelLinkage.setRemind($0)); openPanel = nil }
            )
        }
    }

    private var propertyRepeat: some View {
        PropertyRow(
            icon: .`repeat`,
            label: AppStrings.t("重复", lang: lang),
            value: PanelCatalog.repeatSummary(demo.repeatRule, date: demo.date, isEnglish: isEnglish),
            valueIsSet: !demo.repeatRule.isEmpty,
            isExpanded: openPanel == .`repeat`,
            onTap: { togglePanel(.`repeat`) }
        ) {
            RepeatPanelView(
                value: .constant(demo.repeatRule),
                date: demo.date.isEmpty ? today : demo.date,
                onPick: { rule, done in
                    apply(PanelLinkage.setRepeat(rule, taskDate: demo.date, today: today))
                    if done { openPanel = nil }
                }
            )
        }
    }

    /// 属性行之间的分隔线：跟着行内容左右各缩进 14pt，
    /// 不让线顶到卡片圆角上（整宽的话圆角处会切出毛边）。
    private var panelDivider: some View {
        Divider()
            .overlay(DesignTokens.color("--sep", scheme: scheme))
            .padding(.horizontal, 14)
    }

    private var quadrantSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.t("象限", lang: lang))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            QuadrantPanelView(
                value: .constant(PanelCatalog.quadrantOf(important: demo.important, urgent: demo.urgent)),
                onPick: { q in
                    let flags = PanelLinkage.setQuadrant(q)
                    demo.important = flags.important
                    demo.urgent = flags.urgent
                }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cornerMedium)
                .fill(DesignTokens.color("--surface", scheme: scheme))
        )
    }

    // MARK: 动作

    private func withLanguage(_ model: TaskRowModel) -> TaskRowModel {
        var m = model
        m.isEnglish = isEnglish
        m.today = today
        return m
    }

    private func togglePanel(_ panel: PropertyPanel) {
        HapticFeedback.play(.select)
        openPanel = (openPanel == panel) ? nil : panel
    }

    private func apply(_ patch: TaskPatch) {
        demo = patch.apply(to: demo)
    }

    private func toggle(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        var t = rows[index].task
        if !t.repeatRule.isEmpty {
            // 重复任务：按实例日期写入 doneDates
            let occ = rows[index].occ.isEmpty ? t.date : rows[index].occ
            if t.doneDates.contains(occ) {
                t.doneDates.removeAll { $0 == occ }
            } else {
                t.doneDates.append(occ)
            }
        } else {
            t.done.toggle()
            t.doneAt = t.done ? 1_700_000_100_000 : nil
        }
        rows[index].task = t
        HapticFeedback.play(.success)
    }

    private func postpone(_ index: Int) {
        var t = rows[index].task
        if t.repeatRule.isEmpty {
            t.date = DateText.addDays(max(t.date, today), 1)
        } else {
            let occ = rows[index].occ.isEmpty ? t.date : rows[index].occ
            t.skipDates.append(occ)
        }
        rows[index].task = t
        toastCenter.show(text: AppStrings.t(t.repeatRule.isEmpty ? "推迟" : "跳过", lang: lang))
    }

    private func drop(_ index: Int) {
        rows[index].task.dropped = true
        toastCenter.show(
            text: AppStrings.t("已放弃", lang: lang),
            action: { rows[index].task.dropped = false },
            actionText: AppStrings.t("撤销", lang: lang)
        )
    }

    private func delete(_ index: Int) {
        let removed = rows.remove(at: index)
        toastCenter.show(
            text: AppStrings.t("删除", lang: lang),
            action: { rows.insert(removed, at: min(index, rows.count)) },
            actionText: AppStrings.t("撤销", lang: lang)
        )
    }

    private func openDetail(_ model: TaskRowModel) {
        toastCenter.show(text: model.task.title)
    }

    // MARK: 示例数据

    static func task(
        id: String,
        title: String,
        note: String = "",
        date: String = "",
        time: String = "",
        important: Bool = false,
        urgent: Bool = false,
        done: Bool = false,
        doneAt: Double? = nil,
        dropped: Bool = false,
        repeatRule: String = "",
        remind: Int? = nil,
        parentId: String = ""
    ) -> PlannerTask {
        PlannerTask(
            id: id, title: title, note: note, date: date, time: time,
            important: important, urgent: urgent, done: done, dropped: dropped,
            createdAt: 1_700_000_000_000, doneAt: doneAt,
            repeatRule: repeatRule, doneDates: [], skipDates: [],
            remind: remind, parentId: parentId, updatedAt: 1_700_000_000_000
        )
    }
}

// MARK: - 列表行样式（卡片宽度、行距、分隔线）
//
// 卡片本身就是每行唯一的视觉层，行与行靠「--bg 底色 + 6pt 行距」分开，不画线：
// · 隐藏系统行分隔线 —— insetGrouped 的默认分隔线左端跟着内容缩进、右端贴分组边缘，
//   左右不对称，压在两张卡片中间很难看（真机实测左缩进 86pt / 右缩进 20.5pt）；
// · 行距 3+3=6pt，替代系统默认的上下各约 15pt（两张卡片之间原本空出 30pt）；
// · 行背景透明，让 --bg 露出来，卡片因此有自己的边界，不需要描边或阴影；
// · 左右留白 1pt：insetGrouped 的分组页边距是 20pt，再加 1pt = 21pt，
//   与真机 Tab Bar 玻璃胶囊的实际边界（x = 21..409 @430pt 宽）完全对齐。
private extension View {
    func reachCardRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 3, leading: 1, bottom: 3, trailing: 1))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// 面板类行（属性面板 / 象限）：卡片由内容自己画。
    /// 不能用 `.listRowBackground` 画卡片 —— 它会铺满整行、不受 `listRowInsets` 约束，
    /// 结果是卡片比内容四周各宽出一圈（真机实测左右 16pt、上下 6pt），两张相邻卡片还会贴在一起。
    func reachPanelRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 16, leading: 1, bottom: 16, trailing: 1))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
