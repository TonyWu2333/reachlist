import SwiftUI

// MARK: - M-10 CalendarScreen（T-15）
//
// F-02 日历 + F-03 日程列表全量：
// · 月/周双模式只做位移不改高度（A-10）、三页常驻跟手轨道（A-11）、上下手势折叠；
// · 7 列周一起始、相邻月、今天/选中/周末、今天列高亮（A-12）；
// · 农历/节气/节日/休班（A-13）、象限彩点（A-14）、年月选择（A-15）、跨天钩子由 AppRoot 提供（A-16）；
// · 分组、逾期、进度环、空态、FAB（A-17~A-19）。
//
// 呈现层按 §5.0 / OPEN-18 用系统组件；手势与三页轨道属功能语义，保留自定义实现。
// 数据源是 T-15 的内存样例（T-09 注入 M-02 后替换）；搜索 / 快速添加 / 任务详情
// 分别由 T-16 / T-17 接入，本页只留触发口。

struct CalendarScreen: View {
    /// T-16：共享界面数据源由 AppRootView 注入，4 个 tab 与 3 个 sheet 看到同一份任务。
    @EnvironmentObject private var store: CalendarDataStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    var onOpenDetail: (String, String) -> Void = { _, _ in }
    var onAddTask: (QuickAddDefaults) -> Void = { _ in }
    var onSearch: () -> Void = {}

    @State private var selected = PlannerCalendar.today()
    @State private var mode: CalendarMode = .month
    @State private var pickerOpen = false
    @State private var dragX: CGFloat = 0
    @State private var sliding = false
    @State private var isHorizontalDrag: Bool? = nil
    @State private var gestureStart: Date? = nil
    @State private var overridePane: Int? = nil
    @State private var overrideDate = ""
    @State private var viewportWidth: CGFloat = 390
    @State private var clickGuard = ClickGuard()

    private var isEnglish: Bool { lang == "en" }
    private var today: String { PlannerCalendar.today() }
    private var lunar: LunarData? { LunarData.bundled }
    private var rowHeight: CGFloat { store.settings.showLunar ? 54 : 46 }
    private let headerHeight: CGFloat = 72
    private let weekdayHeight: CGFloat = 28

    private var panes: [MonthGeometry] {
        CalendarContract.panes(
            selected: selected, mode: mode, today: today,
            override: overridePane.map { (n: $0, date: overrideDate) }
        )
    }
    private var slots: [CalendarPaneSlot] { CalendarContract.slots(panes, mode: mode) }
    private var currentGeom: MonthGeometry { panes[1] }
    private var drop: CGFloat {
        CalendarContract.drop(rows: currentGeom.rows, rowHeight: Double(rowHeight), mode: mode)
    }
    private var dots: [String: [CalendarDot]] {
        CalendarContract.dots(tasks: store.tasks, panes: panes)
    }
    private var todayCol: Int {
        CalendarContract.todayColumn(selected: selected, mode: mode, today: today)
    }
    private var baseTop: CGFloat { headerHeight + weekdayHeight + rowHeight }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(DesignTokens.color("--surface", scheme: scheme))
                    .ignoresSafeArea()

                // 只占标题区本身的高度：早期版本让这个容器铺满全屏并加不透明背景，
                // 又给了 zIndex(4)，结果把 zIndex(3) 的月网格和 zIndex(1) 的日程列表整层盖住。
                // 标题栏需要在网格之上（遮住周视图上移后多出的行），但除它之外的区域必须透明。
                VStack(spacing: 0) {
                    header
                        .frame(height: headerHeight)
                    weekdayHeader
                        .frame(height: weekdayHeight)
                }
                .frame(width: width)
                .background(DesignTokens.color("--surface", scheme: scheme))
                .zIndex(4)

                DayAgendaView(
                    selected: selected, today: today, isEnglish: isEnglish,
                    lunar: lunar,
                    onOpen: { id, occ in onOpenDetail(id, occ) },
                    onAdd: { date in onAddTask(.onDate(date)) },
                    store: store
                )
                .frame(width: width, height: max(120, geo.size.height - baseTop))
                .offset(y: baseTop + drop)
                .zIndex(1)

                handle
                    .frame(width: width)
                    .offset(y: baseTop + drop - 8)
                    .zIndex(2)

                gridLayer(width: width)
                    // frame 默认 .center 对齐会把 6 行网格垂直居中进 1 行容器，
                    // 顶部溢出约 2.5 行并被标题栏盖住；必须顶对齐，让内容从容器 y=0 开始。
                    .frame(width: width, height: rowHeight, alignment: .topLeading)
                    .clipShape(CalendarClipShape(width: width, height: rowHeight, extendBottom: drop + 6))
                    .offset(y: headerHeight + weekdayHeight)
                    .contentShape(Rectangle())
                    .highPriorityGesture(calendarGesture(width: width))
                    .zIndex(3)

                Button {
                    onAddTask(.onDate(selected))
                } label: {
                    ReachIcon(name: .plus, size: 28)
                        .foregroundStyle(DesignTokens.color("--on-accent", scheme: scheme))
                        .frame(width: 58, height: 58)
                        .background(RoundedRectangle(cornerRadius: 20)
                            .fill(DesignTokens.color("--accent", scheme: scheme)))
                }
                .buttonStyle(.plain)
                .position(x: width - 49, y: geo.size.height - 49)
                .zIndex(5)
            }
            .onAppear { viewportWidth = width }
            .onChange(of: width) { _, new in viewportWidth = new }
        }
        .background(DesignTokens.color("--bg", scheme: scheme))
        .reachSheet(isPresented: $pickerOpen) {
            MonthPickerView(
                year: currentGeom.year, month0: currentGeom.month0,
                today: today, isEnglish: isEnglish, lunar: lunar,
                onPick: pickMonth, onToday: { pickerOpen = false; goToday() }
            )
            .environment(\.appLanguage, lang)   // sheet 不继承 TabView 的环境值
        }
    }

    // MARK: 标题区（F-02.8）

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                HapticFeedback.play(.select)
                pickerOpen = true
            } label: {
                HStack(spacing: 8) {
                    Text(isEnglish
                        ? PlannerCalendar.monthName(currentGeom.month0, isEnglish: true)
                        : "\(currentGeom.month0 + 1)月")
                        .font(.system(size: 30, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(currentGeom.year)").font(.caption2.weight(.semibold)).monospacedDigit()
                        if let label = lunar?.lunarYearLabel(currentGeom.year) {
                            Text(label).font(.caption2)
                        }
                    }
                    .foregroundStyle(.secondary)
                    ReachIcon(name: .chevronDown, size: 16).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.color("--text", scheme: scheme))

            Spacer(minLength: 0)

            Button(action: onSearch) {
                ReachIcon(name: .search, size: 17)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DesignTokens.color("--fill", scheme: scheme)))
            }
            .buttonStyle(.plain)

            if selected != today {
                Button {
                    goToday()
                } label: {
                    Text(AppStrings.t("今", lang: lang))
                        .font(.caption.weight(.bold))
                        .frame(height: 32).padding(.horizontal, (isEnglish ? 11 : 0))
                        .frame(minWidth: 32)
                        .background(Capsule().fill(DesignTokens.color("--accent-soft", scheme: scheme)))
                        .foregroundStyle(DesignTokens.color("--accent", scheme: scheme))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                Button { shift(-1) } label: {
                    ReachIcon(name: .chevronLeft, size: 18).frame(width: 36, height: 32)
                }
                Divider().frame(height: 14)
                Button { shift(1) } label: {
                    ReachIcon(name: .chevronRight, size: 18).frame(width: 36, height: 32)
                }
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(DesignTokens.color("--fill", scheme: scheme)))
        }
        .padding(.horizontal, 16)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(CalendarContract.weekdayColumnOrder.enumerated()), id: \.offset) { col, d in
                Text(PlannerCalendar.weekdayName(d, short: true, isEnglish: isEnglish))
                    .font(.footnote.weight(col == todayCol ? .semibold : .regular))
                    .foregroundStyle(col == todayCol
                        ? DesignTokens.color("--accent", scheme: scheme)
                        : Color.secondary)
                    .opacity(col >= 5 && col != todayCol ? 0.7 : 1)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: 三页常驻轨道（F-02.2）

    private func gridLayer(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(slots, id: \.n) { slot in
                MonthGridView(
                    geometry: slot.geometry,
                    selected: slot.n == 0 ? selected : slot.geometry.date,
                    today: today, mode: mode,
                    showLunar: store.settings.showLunar, showHoliday: store.settings.showHoliday,
                    dots: dots, lunar: lunar,
                    onSelect: selectDay
                )
                .frame(width: width)
                .offset(
                    x: CGFloat(slot.n) * width + dragX,
                    y: CalendarContract.shiftOf(slot.geometry, mode: mode, rowHeight: Double(rowHeight))
                )
            }
        }
    }

    /// 左右裁掉相邻页、上下放出 drop（对应 Web 的 clipPath）。
    private struct CalendarClipShape: Shape {
        let width: CGFloat
        let height: CGFloat
        let extendBottom: CGFloat
        func path(in rect: CGRect) -> Path {
            Path(CGRect(x: 0, y: -2000, width: width, height: 2000 + height + extendBottom))
        }
    }

    // MARK: 把手（F-02.3）

    private var handle: some View {
        Button {
            setMode(mode == .month ? .week : .month)
        } label: {
            ZStack {
                Rectangle().fill(DesignTokens.color("--surface", scheme: scheme))
                Capsule()
                    .fill(DesignTokens.color("--fill-2", scheme: scheme))
                    .frame(width: mode == .month ? 34 : 22, height: 5)
            }
            .frame(height: 22)
        }
        .buttonStyle(.plain)
    }

    // MARK: 手势（CalendarView.vue:167-226）

    private func calendarGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard !sliding else { return }
                if isHorizontalDrag == nil {
                    isHorizontalDrag = abs(value.translation.width) > abs(value.translation.height)
                    gestureStart = Date()
                }
                if isHorizontalDrag == true { dragX = value.translation.width }
            }
            .onEnded { value in
                let horizontal = isHorizontalDrag
                isHorizontalDrag = nil
                guard !sliding else { return }
                if horizontal == true {
                    clickGuard.block()
                    let elapsed = max(0.001, Date().timeIntervalSince(gestureStart ?? Date()))
                    let velocity = abs(value.translation.width) / elapsed
                    let n = value.translation.width < 0 ? 1 : -1
                    if CalendarContract.shouldSlide(dx: value.translation.width, width: width, velocity: velocity) {
                        slide(to: n, width: width)
                    } else {
                        withAnimation(.easeOut(duration: 0.25)) { dragX = 0 }
                    }
                } else if horizontal == false && abs(value.translation.height) > CalendarContract.verticalSwitchDistance {
                    clickGuard.block()
                    setMode(value.translation.height < 0 ? .week : .month)
                }
                gestureStart = nil
            }
    }

    // MARK: 导航（CalendarView.vue:97-164）

    private func slide(to n: Int, width: CGFloat) {
        guard !sliding, panes.indices.contains(n + 1) else { return }
        sliding = true
        HapticFeedback.play(.select)
        let target = panes[n + 1].date
        withAnimation(.easeInOut(duration: Double(CalendarContract.slideMilliseconds) / 1000)) {
            dragX = -CGFloat(n) * width
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(CalendarContract.slideMilliseconds) * 1_000_000)
            selected = target
            overridePane = nil
            dragX = 0
            sliding = false
        }
    }

    private func shift(_ n: Int) { slide(to: n, width: viewportWidth) }

    private func go(_ date: String) {
        guard date != selected else { return }
        for n in [-1, 1] {
            let p = CalendarContract.geom(CalendarContract.neighbour(selected: selected, mode: mode, n: n, today: today))
            let same = mode == .week
                ? PlannerCalendar.mondayOf(p.date) == PlannerCalendar.mondayOf(date)
                : String(p.date.prefix(7)) == String(date.prefix(7))
            if same {
                overridePane = n
                overrideDate = date
                slide(to: n, width: viewportWidth)
                return
            }
        }
        HapticFeedback.play(.select)
        selected = date
    }

    private func selectDay(_ d: String) {
        guard !clickGuard.shouldIgnoreTap() else { return }
        if mode == .month && String(d.prefix(7)) != String(selected.prefix(7)) {
            go(d)
            return
        }
        HapticFeedback.play(.select)
        selected = d
    }

    private func setMode(_ next: CalendarMode) {
        guard mode != next else { return }
        HapticFeedback.play(.light)
        withAnimation(.easeInOut(duration: 0.42)) { mode = next }
    }

    private func goToday() {
        let t = today
        let visible = mode == .week
            ? PlannerCalendar.mondayOf(t) == PlannerCalendar.mondayOf(selected)
            : String(t.prefix(7)) == String(selected.prefix(7))
        if visible {
            HapticFeedback.play(.select)
            selected = t
        } else {
            go(t)
        }
    }

    private func pickMonth(_ y: Int, _ m0: Int) {
        pickerOpen = false
        let key = "\(y)-\(PlannerCalendar.pad(m0 + 1))"
        guard key != String(selected.prefix(7)) else { return }
        go(today.hasPrefix(key) ? today : "\(key)-01")
    }
}
