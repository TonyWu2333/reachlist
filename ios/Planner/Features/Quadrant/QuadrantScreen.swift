import SwiftUI

// MARK: - M-11 四象限界面（T-16 / F-04 全量）
//
// §5.0 / OPEN-18：范围筛选交给系统 Picker(.segmented)，卡片用系统材质不逐张加玻璃
// （官方性能警告，§5.1 第 3 条）。功能语义完整保留：2×2、成员排除、范围内筛选、
// 显示已完成、象限内新建（带 q + 今天默认值）、340ms 长按拖拽 + 抬起卡片 + 落区高亮 +
// 撤销 toast + 300ms 点击守卫、底部提示文案、搜索入口。
//
// 长按反馈参考 iOS 主屏长按图标，分四段、由同一张抬起卡片连续完成（CardPhase）：
//   ① pressing  按住即在原行位置缓慢放大（1.0→1.04，0.30s easeOut，略短于 340ms 阈值），
//               阴影随卡片渐显——参考删除 App 前 App 先缓慢变大的状态；
//   ② dragging  340ms 到点：一次中等触感提示「现在可以拖了」，卡片 spring 到抬起
//               尺寸（1.05）开始跟手。角度始终为 0（用户 2026-11-16 要求不倾斜）；
//   ③ snapping  跨象限松手：抬起卡片不立刻消失，spring 飞到新象限的目标行位置
//               （吸附）并缩回原尺寸。飞行期间目标象限的真实行被 rowOpacity 完全
//               隐藏——否则动画一开始目标行就出现在那里，与飞行中的卡片重影
//               （2026-11-16 真机反馈）；
//   ④ settling  落定后交叉淡变：真实行淡入（0.18s）、抬起卡片淡出（0.15s）合并。
// 四段共用一张卡（QuadrantDragCard），不存在两套卡片交接导致的阴影闪烁；卡片画在
// 网格级 overlay 上，投影可以越过象限卡边界，不被 ScrollView / 象限卡圆角裁掉。
// 吸附目标位置来自 onGeometryChange 记下的行 frame：LazyVStack 只给可见行回调，
// 目标行不可见（被筛掉 / 折在屏幕外）时轮询超时，直接收起不做无目标飞行。

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
    /// 抬起卡片所处的阶段（见文件头三段式说明）。按下即进入 pressing——
    /// 只能从 `DragGesture(minimumDistance: 0)` 的 onChanged 拿到按下时刻，
    /// `LongPressGesture` 只在 340ms 到点回调，无法表现按住过程。
    @State private var phase: CardPhase = .idle
    /// 当前抬起卡片对应的任务 id。snapping 段 `DragState` 已被 `end()` 复位，
    /// 不能再从 drag.pressedID / draggingID 取，故单独持有。
    @State private var liftID: String?
    /// 抬起卡片当前的中心（named space 坐标）。拖拽时 = 起手位置 + 手指位移。
    @State private var ghostPoint: CGPoint = .zero
    /// 按下那一刻任务行的中心（named space 坐标）。抬起卡片从这里起手，
    /// 不再跳到网格中央——之前直接取 gridSize/2，长按瞬间卡片会蹦到屏幕正中。
    @State private var dragOrigin: CGPoint = .zero
    /// 行位置缓存用引用类型：滚动时每行每帧都会回调，若写进 @State 字典会每帧
    /// 让整个页面重算一遍，滚动直接卡住。
    @State private var rowFrames = QuadrantRowFrames()
    /// 当前手指距按下点的位移。`onLongPressGesture(maximumDistance:)` 与并行的
    /// `DragGesture(minimumDistance: 0)` 并存时，位移限制不可靠（真机实测：手指已
    /// 移出 8pt 仍会到点触发），导致没长按到位就能拖拽、卡片先淡出又淡入地闪一下。
    /// 用它自己把关：超过容差就不进拖拽。
    @State private var pressDistance: Double = 0
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
                    // 抬起卡片画在网格级 overlay（象限卡之上）：投影可以越过象限卡
                    // 边界，不被 ScrollView / 象限卡圆角裁掉。pressing 段就在原行
                    // 位置入场，dragging 段开始跟手，snapping 段吸附到新象限目标行
                    // ——同一张卡走完三段，无交接闪烁。
                    if phase != .idle,
                       let id = liftID,
                       let t = store.find(id) {
                        QuadrantDragCard(
                            model: Self.model(t, today: today, isEnglish: lang == "en"),
                            width: (width - 34) / 2,
                            phase: phase
                        )
                        .position(ghostPoint)
                        .allowsHitTesting(false)
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
        // 原行在抬起卡片各阶段的可见度（按 liftID 判定，不再看 drag.pressedID：
        // snapping 段 DragState 已被 end() 复位，pressedID 会变 nil）。
        let rowOpacity = Self.rowOpacity(phase: phase, liftID: liftID, taskID: t.id)
        return TaskRow(
            model: Self.model(t, today: today, isEnglish: lang == "en"),
            compact: true, showDate: true,
            onToggle: { store.toggleDone(id: t.id, occ: "") },
            onOpen: {
                guard !clickGuard.shouldIgnoreTap(), phase == .idle, !drag.isDragging else { return }
                onOpen(t.id, "")
            }
        )
            .opacity(rowOpacity)
            .animation(.easeOut(duration: 0.18), value: rowOpacity)
            .contentShape(Rectangle())
            // 记录每行在网格坐标系里的真实位置：按下瞬间抬起卡片就从这里起手，
            // 不依赖手势是否已经回调过 location（长按到点那一刻往往还没回调）。
            // snapping 段也用它定位新象限里的目标行。
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("quadrantGrid"))
            } action: { rect in
                rowFrames[t.id] = rect
            }
            .onLongPressGesture(minimumDuration: 0.34, maximumDistance: 8) {
                // 兜底把关：maximumDistance 与 simultaneous DragGesture 并存时不可靠，
                // 手指已移出容差就取消长按、不进拖拽——否则没长按到位也能拖走卡片，
                // 且卡片会先淡出（取消抬起）再淡入（长按又重新抬起）地闪一下。
                guard pressDistance <= QuadrantContract.pressCancelDistance else {
                    phase = .idle
                    liftID = nil
                    return
                }
                // 340ms 到点 = 卡片进入可拖拽状态：抬起卡片 spring 到抬起尺寸，
                // 并给一次中等触感，让用户知道「现在可以拖了」。
                phase = .dragging
                liftID = t.id
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
                    // 抬起卡片跟着手指平移，起手位置就是它原本所在的行中心。
                    ghostPoint = CGPoint(x: dragOrigin.x + value.translation.width,
                                         y: dragOrigin.y + value.translation.height)
                    let q = quadrant(at: value.location)
                    if drag.updateDrop(q), q > 0 { HapticFeedback.play(.select) }
                } else {
                    let distance = hypot(value.translation.width, value.translation.height)
                    pressDistance = distance
                    if drag.draggingID == nil,
                       distance <= QuadrantContract.pressCancelDistance {
                        // 触摸按下（minimumDistance 0 的首个回调）：抬起卡片在原行位置
                        // 入场，开始缓慢放大 + 阴影渐显（三段式的第①段）。
                        if phase == .idle {
                            phase = .pressing
                            liftID = t.id
                            drag.pressedID = t.id
                            dragOrigin = QuadrantContract.ghostOrigin(rowFrame: rowFrames[t.id],
                                                                     grid: gridSize)
                            ghostPoint = dragOrigin
                        }
                    } else if drag.pressedID == t.id {
                        // 位移超过长按容差（或已进入拖拽）：取消抬起卡片。
                        phase = .idle
                        liftID = nil
                    }
                    drag.moved(distance: distance)
                }
            }
            .onEnded { _ in
                pressDistance = 0
                // 不在这里统一置 idle：endDrag 可能进入 snapping 段（吸附动画），
                // 提前置 idle 会把抬起卡片直接撤掉，任务又变成「闪」过去。
                endDrag()
            }
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
        guard let result else { phase = .idle; liftID = nil; return }
        clickGuard.block(milliseconds: QuadrantContract.dropGuardMilliseconds)
        guard let task = store.find(result.id),
              QuadrantContract.shouldMove(task, to: result.q) else {
            // 原地松手 / 落回原象限：直接收起抬起卡片。
            phase = .idle
            liftID = nil
            return
        }
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
        startSnapping(id: task.id)
    }

    /// 吸附动画（第三段）+ 落定交叉淡变（第四段）：跨象限松手后不立刻收起抬起卡片，
    /// 先 spring 飞到新象限的目标行中心，落定后与真实行交叉淡变合并——避免任务直接
    /// 「闪」过去，也避免飞行刚开始目标行就已出现在那里。
    private func startSnapping(id: String) {
        phase = .snapping
        // 清掉旧象限的残留 frame：任务已换组，旧位置会让卡片飞回原象限。
        rowFrames[id] = nil
        Task { @MainActor in
            // 轮询等新象限的行布局完成：LazyVStack 只给可见行回调 onGeometryChange，
            // 目标行不在可见区（被筛掉 / 折在屏幕外）时永远等不到，超时即直接收起。
            // 期间真实行被 rowOpacity 完全隐藏，用户只看到飞行中的抬起卡片。
            var target: CGPoint?
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(16))
                if let rect = rowFrames[id], rect.width > 0, rect.height > 0 {
                    target = CGPoint(x: rect.midX, y: rect.midY)
                    break
                }
            }
            guard let target else {
                phase = .idle
                liftID = nil
                return
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                ghostPoint = target
            }
            // spring 收敛后交叉淡变：真实行淡入（0.18s）、抬起卡片淡出（0.15s），
            // 两者位置尺寸一致，合并无缝；卡片先让位、行后接管。
            try? await Task.sleep(for: .milliseconds(430))
            if phase == .snapping { phase = .settling }
            try? await Task.sleep(for: .milliseconds(180))
            if phase == .settling {
                phase = .idle
                liftID = nil
            }
        }
    }

    /// 原行在抬起卡片各阶段的可见度。
    ///
    /// pressing / dragging 淡到 0.35 让位（避免与抬起卡片重影）；**snapping 段必须
    /// 完全隐藏（0）**：此时任务已写回新象限、真实行立刻出现在目标位置，若可见，
    /// 吸附动画一开始用户就会看到目标象限的卡片「闪」出来，与飞行中的抬起卡片重影
    /// （2026-11-16 真机反馈）。settling 段恢复 1，与淡出的抬起卡片交叉合并。
    static func rowOpacity(phase: CardPhase, liftID: String?, taskID: String) -> Double {
        guard liftID == taskID else { return 1 }
        switch phase {
        case .idle, .settling: return 1
        case .pressing, .dragging: return 0.35
        case .snapping: return 0
        }
    }

    static func model(_ t: PlannerTask, today: String, isEnglish: Bool) -> TaskRowModel {
        TaskRowModel(task: t, today: today, isEnglish: isEnglish)
    }
}

// MARK: - 抬起卡片（按住 → 拖拽，同一张卡）
//
// 一张卡片贯穿四段式反馈（见文件头）：
//   ① pressing   按住即在原行位置缓慢放大（1.0→1.04）并渐显；
//   ② dragging   340ms 到点后 spring 到抬起尺寸（1.05）开始跟手；
//   ③ snapping   跨象限松手后 spring 飞到新象限目标位置吸附，缩回原尺寸；
//   ④ settling   落定后交叉淡变：真实行淡入、抬起卡片淡出，完成合并。
// 四段共用同一张卡，不存在「自绘卡片 → 系统 lift 快照」两套渲染源交接导致的
// 阴影闪烁；画在网格级 overlay 上，投影可以越过象限卡边界。
// 圆角底挂 `.background` 而不是 `ZStack { shape.fill }`——后者会接受任意提案尺寸，
// 被 overlay 以网格全尺寸提案时撑成竖长方形、带着投影闪现（2026-11-16 真机实测）。
// 阴影不直接补间 `.shadow` 的 radius/opacity（SwiftUI 补间不稳定），而是整卡
// `.opacity` 渐显，阴影随卡片一起渐显。
enum CardPhase: Equatable {
    case idle
    case pressing
    case dragging
    case snapping
    /// 已吸附落定、正在与真实行交叉淡变（行淡入 / 抬起卡淡出）。
    case settling
}

struct QuadrantDragCard: View {
    let model: TaskRowModel
    let width: CGFloat
    let phase: CardPhase

    @Environment(\.colorScheme) private var scheme
    /// 入场进度：0 = 未入场（透明、原尺寸），1 = 按住段，2 = 拖拽段，3 = 吸附飞行，
    /// 4 = 落定交叉淡变（淡出让位给真实行）。单值驱动单个 `.animation(_:value:)`，
    /// 避免多个动画互相覆盖。
    @State private var stage = 0

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        TaskRow(model: model, compact: true, showDate: true)
            .padding(6)
            .frame(width: max(0, width))
            .background {
                shape.fill(DesignTokens.color("--surface", scheme: scheme))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.22),
                            radius: 14, x: 0, y: 8)
            }
            .overlay {
                shape.strokeBorder(DesignTokens.color("--text", scheme: scheme).opacity(0.10),
                                   lineWidth: 1)
            }
            // 整卡渐显：阴影随卡片一起渐显，不会突兀跳出。stage 4 落定后淡出，
            // 与正在淡入的真实行交叉合并。
            .opacity(stage == 0 || stage >= 4 ? 0 : 1)
            // ① 按住：1.0→1.04 缓慢放大（0.30s easeOut，略短于 340ms 阈值）；
            // ② 到点：spring 到 1.05。角度保持 0——拖拽中倾斜会让文字发虚，
            // 且用户反馈不需要角度变化（2026-11-16）；
            // ③ 吸附：缩回 1.0，和真实行尺寸一致，落定即「并」进行里。
            .scaleEffect(stage >= 3 ? 1 : (stage >= 2 ? 1.05 : (stage == 1 ? 1.04 : 1)))
            .animation(Self.cardAnimation(stage), value: stage)
            .onAppear { stage = 1 }
            .onChange(of: phase) { _, new in
                switch new {
                case .dragging: stage = 2
                case .snapping: stage = 3
                case .settling: stage = 4
                default: break
                }
            }
    }

    /// 卡片各阶段曲线：stage 单值驱动，避免多个 `.animation` 互相覆盖。
    /// ③ 吸附用 easeOut 而不是 spring——spring 的回弹会让缩回尺寸时过冲到 1.0 以下，
    /// 与正在飞行的位置叠加出「抖一下」的观感。
    /// ④ 落定淡出比真实行的淡入（0.18s）略短，保证卡片先让位、行后接管。
    private static func cardAnimation(_ stage: Int) -> Animation {
        switch stage {
        case 2: return .spring(response: 0.28, dampingFraction: 0.8)
        case 3: return .easeOut(duration: 0.22)
        case 4: return .easeOut(duration: 0.15)
        default: return .easeOut(duration: 0.30).delay(0.04)
        }
    }
}

/// 任务行在网格坐标系里的位置缓存。
///
/// 用引用类型而不是 `@State` 字典：滚动时每行每帧都会回调 `onGeometryChange`，
/// 走 SwiftUI 状态更新会让整页每帧重算一次。这里只被按下那一刻读一次。
final class QuadrantRowFrames {
    private var frames: [String: CGRect] = [:]

    subscript(id: String) -> CGRect? {
        get { frames[id] }
        set { frames[id] = newValue }
    }
}
