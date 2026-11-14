import SwiftUI

// MARK: - M-11 四象限界面（T-16 / F-04 全量）
//
// §5.0 / OPEN-18：范围筛选交给系统 Picker(.segmented)，卡片用系统材质不逐张加玻璃
// （官方性能警告，§5.1 第 3 条）。功能语义完整保留：2×2、成员排除、范围内筛选、
// 显示已完成、象限内新建（带 q + 今天默认值）、340ms 长按拖拽 + ghost + 落区高亮 +
// 撤销 toast + 300ms 点击守卫、底部提示文案、搜索入口。

struct QuadrantScreen: View {
    @EnvironmentObject private var store: CalendarDataStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    var onOpen: (String, String) -> Void = { _, _ in }
    var onAdd: (QuickAddDefaults) -> Void = { _ in }
    var onSearch: () -> Void = {}

    @State private var range: QuadrantRange = .all
    @State private var showDone = false
    @State private var drag = QuadrantContract.DragState()
    @State private var ghostPoint: CGPoint = .zero
    /// 长按那一刻任务行的中心（named space 坐标）。ghost 从这里开始跟手，
    /// 不再跳到网格中央——之前直接取 gridSize/2，长按瞬间卡片会蹦到屏幕正中。
    @State private var dragOrigin: CGPoint = .zero
    /// 行位置缓存用引用类型：滚动时每行每帧都会回调，若写进 @State 字典会每帧
    /// 让整个页面重算一遍，滚动直接卡住。
    @State private var rowFrames = QuadrantRowFrames()
    @State private var gridSize: CGSize = .zero
    @State private var clickGuard = ClickGuard()

    private var today: String { PlannerCalendar.today() }
    private var groups: [Int: [PlannerTask]] {
        QuadrantContract.groups(store.tasks, range: range, showDone: showDone, today: today)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $range) {
                ForEach(QuadrantContract.ranges, id: \.key) { item in
                    Text(AppStrings.t(item.label, lang: lang)).tag(item.key)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .onChange(of: range) { _, _ in HapticFeedback.play(.select) }

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(1...4, id: \.self) { q in
                        quadrantCard(q)
                            .frame(height: max(120, (height - 10) / 2))
                    }
                }
                .padding(.horizontal, 12)
                .frame(width: width, height: height)
                .coordinateSpace(name: "quadrantGrid")
                .onAppear { gridSize = geo.size }
                .onChange(of: geo.size) { _, new in gridSize = new }
                .overlay(alignment: .topLeading) {
                    if drag.isDragging, let id = drag.draggingID, let t = store.find(id) {
                        QuadrantDragGhost(
                            model: Self.model(t, today: today, isEnglish: lang == "en"),
                            width: (width - 34) / 2
                        )
                        .position(ghostPoint)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }
            }

            Text(AppStrings.t("长按任务拖到其他象限 · 点击查看详情", lang: lang))
                .font(.caption2)
                .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                .padding(.vertical, 10)
        }
        .background(DesignTokens.color("--bg", scheme: scheme))
    }

    // MARK: 页头（F-04.1 / F-04.6 / F-08 入口）

    private var header: some View {
        HStack(spacing: 10) {
            Text(AppStrings.t("四象限", lang: lang))
                .font(DesignTokens.font(.title))
                .foregroundStyle(DesignTokens.color("--text", scheme: scheme))
            Spacer(minLength: 0)
            Button(action: onSearch) {
                ReachIcon(name: .search, size: 17)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DesignTokens.color("--fill", scheme: scheme)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.t("搜索", lang: lang))
            Button {
                HapticFeedback.play(.select)
                showDone.toggle()
            } label: {
                HStack(spacing: 5) {
                    ReachIcon(name: showDone ? .eye : .eyeOff, size: 15)
                    Text(AppStrings.t("已完成", lang: lang)).font(.subheadline)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Capsule().fill(showDone
                    ? DesignTokens.color("--accent-soft", scheme: scheme)
                    : DesignTokens.color("--fill", scheme: scheme)))
                .foregroundStyle(showDone
                    ? DesignTokens.color("--accent", scheme: scheme)
                    : DesignTokens.color("--text-2", scheme: scheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: 象限卡

    private func quadrantCard(_ q: Int) -> some View {
        let item = PanelCatalog.quadrants[q - 1]
        let color = DesignTokens.color(item.colorToken, scheme: scheme)
        let list = groups[q] ?? []
        let count = QuadrantContract.openCount(list)
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(AppStrings.t(item.nameKey, lang: lang))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(lang == "en" ? 2 : 1)
                    .minimumScaleFactor(0.8)
                if count > 0 {
                    Text("\(count)").font(.caption2.weight(.bold)).monospacedDigit()
                        .padding(.horizontal, 5).frame(height: 18)
                        .background(Capsule().fill(color.opacity(0.14)))
                        .foregroundStyle(color)
                }
                Spacer(minLength: 0)
                Button {
                    HapticFeedback.play(.select)
                    onAdd(.inQuadrant(q, date: today))
                } label: {
                    ReachIcon(name: .plus, size: 18)
                        .frame(width: 28, height: 28)
                        .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(FeatureStrings.t("在{name}里新建", lang: lang,
                                                     ["name": AppStrings.t(item.nameKey, lang: lang)]))
            }
            .padding(.leading, 12).padding(.trailing, 4)
            .padding(.top, 10).padding(.bottom, 6)
            .frame(minHeight: lang == "en" ? 52 : 32)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(list, id: \.id) { t in
                        taskRow(t)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 10)
            }
            .overlay {
                if list.isEmpty { emptyHint(item, color: color) }
            }
        }
        .background(DesignTokens.color("--surface", scheme: scheme))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerLarge))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.cornerLarge)
                .strokeBorder(drag.isDragging && drag.dropQ == q ? color : .clear, lineWidth: 2)
        }
        .scaleEffect(drag.isDragging && drag.dropQ == q ? 1.025 : 1)
        .opacity(drag.isDragging && drag.dropQ != q && drag.dropQ != 0 ? 0.92 : 1)
    }

    private func emptyHint(_ item: PanelCatalog.Quadrant, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(AppStrings.t(item.hintKey, lang: lang))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color.opacity(0.7))
            if let key = QuadrantContract.emptyText[item.index] {
                Text(AppStrings.t(key, lang: lang))
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
            }
        }
        .multilineTextAlignment(.center)
        .padding(8)
    }

    private func taskRow(_ t: PlannerTask) -> some View {
        let isDragging = drag.draggingID == t.id
        return TaskRow(
            model: Self.model(t, today: today, isEnglish: lang == "en"),
            compact: true, showDate: true,
            onToggle: { store.toggleDone(id: t.id, occ: "") },
            onOpen: {
                guard !clickGuard.shouldIgnoreTap(), !drag.isDragging else { return }
                onOpen(t.id, "")
            }
        )
            .opacity(isDragging ? 0.35 : 1)
            .contentShape(Rectangle())
            // 记录每行在网格坐标系里的真实位置：长按瞬间 ghost 就从这里起手，
            // 不依赖手势是否已经回调过 location（长按到点那一刻往往还没回调）。
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("quadrantGrid"))
            } action: { rect in
                rowFrames[t.id] = rect
            }
            .onLongPressGesture(minimumDuration: 0.34, maximumDistance: 8) {
                drag.pressedID = t.id
                drag.longPressFired(id: t.id)
                dragOrigin = QuadrantContract.ghostOrigin(rowFrame: rowFrames[t.id], grid: gridSize)
                ghostPoint = dragOrigin
                HapticFeedback.play(.medium)
            }
            .simultaneousGesture(dragGesture(t))
    }

    private func dragGesture(_ t: PlannerTask) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("quadrantGrid"))
            .onChanged { value in
                if drag.isDragging, drag.draggingID == t.id {
                    // 卡片跟着手指平移，起手位置就是它原本所在的行中心。
                    ghostPoint = CGPoint(x: dragOrigin.x + value.translation.width,
                                         y: dragOrigin.y + value.translation.height)
                    let q = quadrant(at: value.location)
                    if drag.updateDrop(q), q > 0 { HapticFeedback.play(.select) }
                } else if drag.pressedID == t.id {
                    drag.moved(distance: hypot(value.translation.width, value.translation.height))
                }
            }
            .onEnded { _ in endDrag() }
    }

    /// 2×2 网格：q = 行 × 2 + 列 + 1，与 QuadrantView.vue:v-for [1,2,3,4] 一致。
    private func quadrant(at point: CGPoint) -> Int {
        guard gridSize.width > 0, gridSize.height > 0 else { return 0 }
        let col = point.x < gridSize.width / 2 ? 0 : 1
        let row = point.y < gridSize.height / 2 ? 0 : 1
        return row * 2 + col + 1
    }

    private func endDrag() {
        let result = drag.end()
        guard let result else { return }
        clickGuard.block(milliseconds: QuadrantContract.dropGuardMilliseconds)
        guard let task = store.find(result.id),
              QuadrantContract.shouldMove(task, to: result.q) else { return }
        let before = CalendarContract.quadrantOf(task)
        let beforeFlags = QuadrantContract.flags(before)
        let afterFlags = QuadrantContract.flags(result.q)
        store.update(id: task.id, patch: ["important": afterFlags.important, "urgent": afterFlags.urgent])
        HapticFeedback.play(.success)
        toastCenter.show(
            text: QuadrantContract.movedText(result.q, lang: lang),
            action: {
                store.update(id: task.id, patch: ["important": beforeFlags.important,
                                                   "urgent": beforeFlags.urgent])
            },
            actionText: AppStrings.t("撤销", lang: lang)
        )
    }

    static func model(_ t: PlannerTask, today: String, isEnglish: Bool) -> TaskRowModel {
        TaskRowModel(task: t, today: today, isEnglish: isEnglish)
    }
}

// MARK: - 拖拽中的卡片（ghost）
//
// 象限卡与页面底色都是白的，拖起来的卡片必须自带投影才分得清层次；
// 单独抽出来也是为了能在真机上单独取图核对投影浓淡。
struct QuadrantDragGhost: View {
    let model: TaskRowModel
    let width: CGFloat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TaskRow(model: model, compact: true, showDate: true)
            .frame(width: width)
            .padding(6)
            .background(DesignTokens.color("--surface", scheme: scheme))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(DesignTokens.color("--text", scheme: scheme).opacity(0.10),
                                  lineWidth: 1)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.22), radius: 14, x: 0, y: 8)
            .scaleEffect(1.05)
            .rotationEffect(.degrees(1.5))
    }
}

/// 任务行在网格坐标系里的位置缓存。
///
/// 用引用类型而不是 `@State` 字典：滚动时每行每帧都会回调 `onGeometryChange`，
/// 走 SwiftUI 状态更新会让整页每帧重算一次。这里只被长按那一刻读一次。
final class QuadrantRowFrames {
    private var frames: [String: CGRect] = [:]

    subscript(id: String) -> CGRect? {
        get { frames[id] }
        set { frames[id] = newValue }
    }
}
