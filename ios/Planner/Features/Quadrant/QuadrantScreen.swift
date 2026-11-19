import SwiftUI
import UIKit

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
//               （吸附）并缩回原尺寸。飞行期间目标象限的真实行必须完全不可见——
//               SwiftUI 的 rowOpacity 跨 UIHostingController 桥更新且带 0.18s
//               渐隐，事务分离时目标行会先以 0.35 入场再淡出；现在由
//               QuadrantTaskScroll.hiddenTaskID 在 UIView 层无动画硬隐藏，
//               SwiftUI 侧同时禁用 snapping 的 opacity 动画，双保险保证
//               「吸附动画完成前终点位置没有卡片」（2026-11-18 真机反馈）；
//   ④ settling  落定后交叉淡变：真实行淡入（0.18s）、抬起卡片淡出（0.15s）合并。
// 四段共用一张卡（QuadrantDragCard），不存在两套卡片交接导致的阴影闪烁；卡片画在
// 网格级 overlay 上，投影可以越过象限卡边界，不被 ScrollView / 象限卡圆角裁掉。
// 吸附目标位置来自 UIKit 桥接上报的行 frame（named 坐标空间跨不过 UIKit 桥，
// 行内 onGeometryChange 拿不到网格坐标——2026-11-18 真机实测卡片瞬移的根因）：
// 只上报可见行，目标行不可见（被筛掉 / 折在屏幕外）时轮询超时，直接收起不做无目标飞行。
//
// 手势结构（2026-11-18 第三轮，UIKit 桥接）：
//   SwiftUI 手势修饰器与 ScrollView 的滚动仲裁不可靠——simultaneous / sequenced /
//   普通优先级 DragGesture 三轮真机迭代均失败（抢滚动或拖不动，工程手册 §7.2
//   第 17 条）。滚动 + 长按拖拽是系统级成熟场景（UITableView / UICollectionView
//   交互式重排同款）：UIScrollView 的 pan 与 UILongPressGestureRecognizer
//   （minimumPressDuration 0.34 / allowableMovement 8）由 UIKit 自动仲裁——
//   位移超差长按失败、滚动接管；按住到点长按识别，此时 isScrollEnabled = false
//   锁定滚动、手指由长按识别器继续跟踪。象限列表因此包进 QuadrantTaskScroll
//   （UIViewRepresentable + UIHostingConfiguration，行渲染仍是 SwiftUI TaskRow），
//   四段式抬起卡片 / 吸附 / 让位动画全部不变。
//
// 跨象限写回（endDrag / 撤销）包在 withAnimation 里：原象限与目标象限的其他行
// 用与吸附飞行同一条 spring（0.42 / 0.72）平滑让位，不再闪现移动。

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
    /// 抬起卡片所处的阶段（见文件头四段式说明）。按下即进入 pressing——
    /// 按下时刻由 UIKit 桥接的 touchesBegan 回调提供（长按识别器本身只在
    /// 340ms 到点才回调 .began，无法表现按住过程）。
    @State private var phase: CardPhase = .idle
    /// 当前抬起卡片对应的任务 id。snapping 段 `DragState` 已被 `end()` 复位，
    /// 不能再从 drag.pressedID / draggingID 取，故单独持有。
    @State private var liftID: String?
    /// 抬起卡片当前的中心（named space 坐标）。拖拽时 = 起手位置 + 手指位移。
    @State private var ghostPoint: CGPoint = .zero
    /// 按下那一刻任务行的中心（named space 坐标）。抬起卡片从这里起手，
    /// 不再跳到网格中央——之前直接取 gridSize/2，长按瞬间卡片会蹦到屏幕正中。
    @State private var dragOrigin: CGPoint = .zero
    /// 行位置缓存（网格坐标）由 UIKit 桥接在布局 / 滚动时上报。用引用类型：
    /// 滚动时每行每帧都会回调，若写进 @State 字典会让整个页面每帧重算，滚动卡住。
    @State private var rowFrames = QuadrantRowFrames()
    @State private var gridSize: CGSize = .zero
    /// 各象限滚动列表在网格坐标系里的 frame：把 UIKit 手势的列表内坐标换算成
    /// 网格坐标（落区判定 / 抬起卡片跟手都用网格坐标）。
    @State private var scrollFrames: [Int: CGRect] = [:]
    @State private var clickGuard = ClickGuard()
    /// 按压代际：兜底定时器只收自己那一代 pressing，不误杀同的下一次按压。
    @State private var pressGeneration = 0

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

            QuadrantTaskScroll(
                tasks: list,
                isScrollEnabled: !drag.isDragging,
                // 吸附飞行期间把「这张任务的真实行」在 UIView 层硬隐藏：
                // 目标象限一写回就插入该行，光靠 SwiftUI 的 opacity 跨桥更新
                // 会有一帧（甚至 0.18s 渐隐期）露出第二张卡。
                hiddenTaskID: phase == .snapping ? liftID : nil,
                rowToken: "\(phase)|\(liftID ?? "")|\(lang)|\(scheme)",
                gridOrigin: CGPoint(x: scrollFrames[q]?.minX ?? 0, y: scrollFrames[q]?.minY ?? 0),
                row: { t in taskRow(t) },
                onRowFrames: { rowFrames.merge($0) },
                onPressDown: { id, p in pressDown(id: id, location: gridPoint(q, p)) },
                onLongPressFired: { id in longPressFired(id: id) },
                onPressCancelled: { pressCancelled() },
                onDragMoved: { p in dragMoved(to: gridPoint(q, p)) },
                onDragEnded: { endDrag() }
            )
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("quadrantGrid"))
            } action: { rect in
                scrollFrames[q] = rect
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
            // snapping 进入瞬间必须「无动画」地隐藏：0.35 → 0 若走 0.18s 渐隐，
            // 吸附飞行前 0.18s 终点位置仍能看到真实行与飞行卡片重影。
            .animation(phase == .snapping ? nil : .easeOut(duration: 0.18), value: rowOpacity)
            .contentShape(Rectangle())
    }

    // MARK: 手势回调（UIKit 桥接 → 四段式卡片；坐标均已换算到网格空间）

    /// 触摸按下：抬起卡片在原行位置入场，缓慢放大 + 阴影渐显（第①段）。
    private func pressDown(id: String?, location: CGPoint) {
        guard let id, phase == .idle else { return }
        phase = .pressing
        liftID = id
        drag.pressedID = id
        dragOrigin = QuadrantContract.ghostOrigin(rowFrame: rowFrames[id], grid: gridSize)
        ghostPoint = dragOrigin
        // 兜底：正常流程 340ms 到点进 dragging、或松手 / 滚动即取消；若识别器
        // 的失败回调在真机上没送达（勾选快 tap / 滚动接管曾卡住卡片），600ms 后
        // 仍停在 pressing 就强制收起，抬起卡片不会留在页面上。
        pressGeneration += 1
        let gen = pressGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            if pressGeneration == gen, phase == .pressing, liftID == id { pressCancelled() }
        }
    }

    /// 340ms 到点：卡片进入可拖拽状态（第②段），medium 触感提示「现在可以拖了」。
    /// 位移把关由 UIKit allowableMovement(8pt) 完成，超差长按识别器根本不会成立。
    private func longPressFired(id: String) {
        guard phase == .pressing, liftID == id else { return }
        phase = .dragging
        drag.longPressFired(id: id)
        dragOrigin = QuadrantContract.ghostOrigin(rowFrame: rowFrames[id], grid: gridSize)
        ghostPoint = dragOrigin
        HapticFeedback.play(.medium)
    }

    /// 长按失败 / 被滚动取消 / 到点前松手：收起按住卡片；拖拽中被取消则直接收起
    /// 不写回（系统取消语义，与松手落区不同）。
    private func pressCancelled() {
        if phase == .pressing {
            phase = .idle
            liftID = nil
            drag.pressedID = nil
        } else if phase == .dragging {
            _ = drag.end()
            phase = .idle
            liftID = nil
        }
    }

    /// 拖拽跟手：抬起卡片中心跟随手指，落区变化给 select 触感。
    private func dragMoved(to point: CGPoint) {
        guard drag.isDragging else { return }
        ghostPoint = point
        let q = quadrant(at: point)
        if drag.updateDrop(q), q > 0 { HapticFeedback.play(.select) }
    }

    /// 列表可视 frame 内坐标 → 网格坐标系（加列表 frame 原点）。
    private func gridPoint(_ q: Int, _ p: CGPoint) -> CGPoint {
        guard let f = scrollFrames[q] else { return p }
        return CGPoint(x: f.minX + p.x, y: f.minY + p.y)
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
        guard let result else {
            // 重复收尾时 drag 已复位：只收 pressing / dragging，不能打断
            // snapping / settling 的吸附飞行（v0.73 真机回归根因之一）。
            if phase == .pressing || phase == .dragging { phase = .idle; liftID = nil }
            return
        }
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
        // 先切到 snapping 再写回：写回会让目标象限同步插入真实行，若此时 phase
        // 还停在 dragging，新行的 rootView 会以 0.35 透明度入场，等下一个事务才
        // 淡到 0——吸附刚起手终点就出现第二张卡。phase 先到位，新行从创建起
        // 就是隐藏态（SwiftUI opacity 0 + UIKit alpha 0）。
        // 注意：只提前「切阶段」，`rowFrames` 的清理仍留在 startSnapping（写回后），
        // 否则旧象限布局回调会把旧 frame 重新写回缓存，卡片又飞回原象限。
        phase = .snapping
        // 写回包在与吸附飞行同一条 spring 里（SwiftUI 侧）；行布局在 UIKit 桥接内，
        // 由 updateUIView 用同曲线 UIView spring 动画让位（withAnimation 跨不过桥）。
        withAnimation(.spring(response: Self.snapFlightSeconds, dampingFraction: 0.72)) {
            store.update(id: task.id, patch: ["important": afterFlags.important, "urgent": afterFlags.urgent])
        }
        HapticFeedback.play(.success)
        toastCenter.show(
            text: QuadrantContract.movedText(result.q, lang: lang),
            action: {
                withAnimation(.spring(response: Self.snapFlightSeconds, dampingFraction: 0.72)) {
                    store.update(id: task.id, patch: ["important": beforeFlags.important,
                                                       "urgent": beforeFlags.urgent])
                }
            },
            actionText: AppStrings.t("撤销", lang: lang)
        )
        // 写回完成后再清旧 frame / 启动吸附飞行（清 frame 必须在写回之后）。
        startSnapping(id: task.id)
    }

    /// 吸附飞行时长，与 ghostPoint 的 spring response / 让位 UIView.animate 同源；
    /// 也是「飞行最短时长」守卫的基准（见 `settleSnapping`）。
    private static let snapFlightSeconds: Double = 0.42

    /// 吸附动画（第三段）+ 落定交叉淡变（第四段）：跨象限松手后不立刻收起抬起卡片，
    /// 先 spring 飞到新象限的目标行中心，落定后与真实行交叉淡变合并。
    /// 飞行期间真实行由 `hiddenTaskID` 在 UIView 层硬隐藏，终点位置不会先出现卡片。
    private func startSnapping(id: String) {
        // endDrag 已在写回前置位（保证新行从创建起就是隐藏态），这里幂等兜底。
        phase = .snapping
        // 清掉旧象限的残留 frame：任务已换组，旧位置会让卡片飞回原象限。
        rowFrames[id] = nil
        Task { @MainActor in
            // 轮询等新象限的行布局完成：UIKit 桥接只上报可见行，目标行不在可见区
            //（被筛掉 / 折在屏幕外）时永远等不到，超时即直接收起。
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
            let flightStart = Date()
            // 落定判定用系统动画完成回调而不是固定 430ms：spring 真正收敛前
            // 就让真实行淡入，会看到目标行提前显形 + 飞行卡片残影（v0.74 真机反馈）。
            withAnimation(.spring(response: Self.snapFlightSeconds, dampingFraction: 0.72),
                          completionCriteria: .removed) {
                ghostPoint = target
            } completion: {
                self.settleSnapping(id: id, flightStart: flightStart)
            }
            // 兜底：完成回调理论上必达（含被打断），极端情况下 1.2s 仍停在
            // snapping 就强制走落定流程，抬起卡片不会留在页面上。
            try? await Task.sleep(for: .milliseconds(1200))
            self.settleSnapping(id: id, flightStart: flightStart)
        }
    }

    /// 显形门控：系统动画完成回调 + 飞行最短时长同时满足才让真实行淡入。
    /// completion 若因动画被替换 / 打断而提前送达，补足剩余飞行时间，
    /// 避免「吸附还没做完、终点位置就已经有卡片」。
    private func settleSnapping(id: String, flightStart: Date) {
        guard phase == .snapping, liftID == id else { return }
        let remaining = Self.snapFlightSeconds - Date().timeIntervalSince(flightStart)
        guard remaining > 0.01 else {
            enterSettling(id: id)
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
            self.enterSettling(id: id)
        }
    }

    /// 进入落定交叉淡变：真实行淡入（UIKit alpha 0.18s + SwiftUI opacity 0.18s）、
    /// 抬起卡片淡出（0.15s）。phase 守卫天然防重入（completion 与 1.2s 兜底都会调）。
    private func enterSettling(id: String) {
        guard phase == .snapping, liftID == id else { return }
        phase = .settling
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(QuadrantContract.dropAnimationMilliseconds))
            if phase == .settling, liftID == id {
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
    /// （2026-11-16 真机反馈）。跨 UIKit 桥的更新可能晚一拍，故另有
    /// `hiddenTaskID` 在 UIView 层把该行 alpha 直接置 0（双保险）。
    /// settling 段恢复 1，与淡出的抬起卡片交叉合并。
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

/// 任务行在网格坐标系里的位置缓存（UIKit 桥接按象限上报可见行，合并写入）。
///
/// 用引用类型而不是 `@State` 字典：滚动时每行每帧都会上报，走 SwiftUI 状态更新
/// 会让整页每帧重算一次。这里只被按下那一刻与吸附轮询读取。
final class QuadrantRowFrames {
    private var frames: [String: CGRect] = [:]

    subscript(id: String) -> CGRect? {
        get { frames[id] }
        set { frames[id] = newValue }
    }

    func merge(_ incoming: [String: CGRect]) {
        for (id, rect) in incoming { frames[id] = rect }
    }
}

/// 布局 / 滚动（bounds 变化）后上报名：行 frame 只能在 UIKit 侧测——
/// SwiftUI 的 named 坐标空间跨不过 UIViewRepresentable 桥。
private final class ReportingScrollView: UIScrollView {
    var onLayout: () -> Void = {}

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout()
    }
}

// MARK: - UIKit 桥接：象限任务列表（滚动 + 长按拖拽的系统级仲裁）
//
// SwiftUI 手势修饰器与 ScrollView 的滚动仲裁不可靠（simultaneous / sequenced /
// 普通优先级三轮真机迭代均失败，工程手册 §7.2 第 17 条）。滚动 + 长按拖拽是
// UIKit 的成熟系统场景——UITableView / UICollectionView 交互式重排同款机制：
// UIScrollView 的 pan 与 UILongPressGestureRecognizer 自动仲裁，位移超过
// allowableMovement 长按失败、滚动接管；按住到点长按识别，拖拽期
// isScrollEnabled = false 锁滚动，手指由长按识别器持续跟踪（可拖出本象限）。
// 行渲染仍是 SwiftUI（UIHostingConfiguration），四段式抬起卡片画在网格级
// overlay 上，本组件只上报手势事件与坐标（列表可视 frame 内坐标，调用方加
// frame 原点换算到网格）。

struct QuadrantTaskScroll<Row: View>: UIViewRepresentable {
    let tasks: [PlannerTask]
    var isScrollEnabled = true
    /// 吸附飞行期间必须隐藏的真实行 id（抬起卡片正在飞向它）。
    /// SwiftUI 行的 `opacity` 要跨 UIHostingController 桥更新、且带 0.18s 渐隐，
    /// 写回与 phase 切换事务分离时目标行会先显形再淡出；这里在 UIView 层
    /// 无动画硬隐藏，与 SwiftUI 的 rowOpacity 互为双保险，保证吸附完成前
    /// 终点位置不会出现第二张卡片。
    var hiddenTaskID: String? = nil
    /// 行渲染依赖的页面状态指纹（phase / liftID / 语言 / 深浅色）：
    /// 与任务内容指纹一起决定是否需要重设行的 rootView——拖拽每帧只动
    /// ghostPoint，不触发整列重渲染。
    var rowToken = ""
    /// 本列表在网格坐标系里的原点（SwiftUI 侧 onGeometryChange 测得）：
    /// UIKit 上报行 frame 时换算到网格空间用。
    var gridOrigin: CGPoint = .zero
    @ViewBuilder let row: (PlannerTask) -> Row
    /// 可见行在网格坐标系里的 frame（布局 / 滚动时上报）：抬起卡片起手位置
    /// 与吸附目标都从这里取——named 坐标空间跨不过 UIKit 桥，不能在行内用
    /// onGeometryChange 测。
    var onRowFrames: ([String: CGRect]) -> Void = { _ in }
    /// 触摸按下（早于 340ms 阈值）：id = 按中的行；location 为列表可视 frame 内坐标。
    var onPressDown: (String?, CGPoint) -> Void = { _, _ in }
    /// 长按 340ms 到点（位移未超 8pt）。
    var onLongPressFired: (String) -> Void = { _ in }
    /// 长按失败 / 被取消 / 到点前松手。
    var onPressCancelled: () -> Void = {}
    /// 长按成立后的手指移动（列表可视 frame 内坐标）。
    var onDragMoved: (CGPoint) -> Void = { _ in }
    /// 长按成立后松手。
    var onDragEnded: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = ReportingScrollView()
        scroll.onLayout = { context.coordinator.reportRowFrames() }
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 1
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 10, right: 5)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        context.coordinator.stack = stack

        let press = PressTrackingLongPress()
        press.minimumPressDuration = TimeInterval(QuadrantContract.pressMilliseconds) / 1000
        press.allowableMovement = QuadrantContract.pressCancelDistance
        press.delegate = context.coordinator
        press.onTouchDown = { [weak scroll] point in
            guard let scroll else { return }
            context.coordinator.handleTouchDown(at: point, in: scroll)
        }
        press.onTouchUp = { context.coordinator.handleTouchUp() }
        press.addTarget(context.coordinator, action: #selector(Coordinator.handlePress(_:)))
        scroll.delegate = context.coordinator
        scroll.addGestureRecognizer(press)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let c = context.coordinator
        c.tasks = tasks
        c.gridOrigin = gridOrigin
        c.hiddenTaskID = hiddenTaskID
        c.onRowFrames = onRowFrames
        c.row = { AnyView(row($0)) }
        c.onPressDown = onPressDown
        c.onLongPressFired = onLongPressFired
        c.onPressCancelled = onPressCancelled
        c.onDragMoved = onDragMoved
        c.onDragEnded = onDragEnded
        scroll.isScrollEnabled = isScrollEnabled
        let contentToken = tasks.map { "\($0.id):\($0.updatedAt)" }.joined(separator: "|")
        let contentChanged = contentToken != c.lastContentToken
        if contentChanged || rowToken != c.lastRowToken {
            c.lastContentToken = contentToken
            c.lastRowToken = rowToken
            if contentChanged && c.hasLoaded {
                // 让位动画：行布局在 UIKit 侧，withAnimation 跨不过桥——用与吸附
                // 飞行同参数的 UIKit spring（0.42 / 0.72）包住行增删与布局。
                UIView.animate(withDuration: 0.42, delay: 0,
                               usingSpringWithDamping: 0.72, initialSpringVelocity: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState]) {
                    let inserted = c.syncRows()
                    scroll.layoutIfNeeded()
                    c.freezeInsertedRows(inserted)
                }
            } else {
                c.syncRows()
                scroll.layoutIfNeeded()
                c.hasLoaded = true
            }
        }
        c.reportRowFrames()
        // 必须在 syncRows 之后：新插入的目标行要在首次渲染前就 alpha 0，
        // 否则飞行刚开始会露出一帧真实卡片。
        c.applyHiddenState()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UIScrollViewDelegate {
        weak var stack: UIStackView?
        var tasks: [PlannerTask] = []
        var row: (PlannerTask) -> AnyView = { _ in AnyView(EmptyView()) }
        var onPressDown: (String?, CGPoint) -> Void = { _, _ in }
        var onLongPressFired: (String) -> Void = { _ in }
        var onPressCancelled: () -> Void = {}
        var onDragMoved: (CGPoint) -> Void = { _ in }
        var onDragEnded: () -> Void = {}
        /// 按 id 复用 hosting controller：刷新只换 rootView，不重建整列，
        /// 滚动位置与行内 SwiftUI 状态（勾选 pending 等）不受影响。
        private var controllers: [String: UIHostingController<AnyView>] = [:]
        private var pressedID: String?
        /// 本次触摸是否已到点（.began）/ 是否已被状态机回调收尾。
        /// touch-up 冗余收尾只补状态机漏掉的回调，不重复提交。
        private var pressDidBegin = false
        private var pressDidResolve = false
        fileprivate var lastContentToken = ""
        fileprivate var lastRowToken = ""
        fileprivate var hasLoaded = false
        var gridOrigin: CGPoint = .zero
        var onRowFrames: ([String: CGRect]) -> Void = { _ in }
        /// 本轮被硬隐藏的行 id：只在集合变化时做显形淡入，拖拽每帧
        /// updateUIView 不会重复触发动画。
        var hiddenTaskID: String? = nil
        private var hiddenIDs: Set<String> = []

        /// 吸附期硬隐藏 / 落定淡入：只改 `UIView.alpha`，不改 SwiftUI rootView，
        /// 绕开跨桥 opacity 更新时序与 0.18s 渐隐窗口。alpha 与 SwiftUI
        /// `.opacity` 叠加，两者在 snapping 同为 0、settling 后同为 1，不冲突。
        func applyHiddenState() {
            let target: Set<String> = hiddenTaskID.map { [$0] } ?? []
            for id in hiddenIDs where !target.contains(id) {
                guard let view = controllers[id]?.view else { continue }
                UIView.animate(withDuration: 0.18, delay: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState]) {
                    view.alpha = 1
                }
            }
            for id in target {
                guard let view = controllers[id]?.view else { continue }
                if view.alpha != 0 {
                    UIView.performWithoutAnimation { view.alpha = 0 }
                }
            }
            hiddenIDs = target
        }

        /// 可见行 frame → 网格坐标上报。stack.convert 得到的是含 contentOffset
        /// 的 scroll bounds 坐标，减 contentOffset 再加列表网格原点即网格坐标。
        /// layoutSubviews 里拿到的是模型层最终值（动画中也是终值），吸附定位不偏。
        func reportRowFrames() {
            guard let stack, let scroll = stack.superview as? UIScrollView,
                  scroll.bounds.width > 0 else { return }
            let visible = CGRect(origin: gridOrigin, size: scroll.bounds.size)
            var out: [String: CGRect] = [:]
            for (index, view) in stack.arrangedSubviews.enumerated() where index < tasks.count {
                let rect = stack.convert(view.frame, to: scroll)
                    .offsetBy(dx: gridOrigin.x - scroll.contentOffset.x,
                              dy: gridOrigin.y - scroll.contentOffset.y)
                if rect.intersects(visible) { out[tasks[index].id] = rect }
            }
            onRowFrames(out)
        }

        /// 返回本轮新插入的行 id：调用方在让位动画里冻结它们的帧动画——
        /// 新行从初始 frame 滑入槽位的「残影」不该被看到（吸附期它 opacity 0，
        /// 淡入时必须已静止在终值）。
        func syncRows() -> [String] {
            guard let stack else { return [] }
            var inserted: [String] = []
            let ids = Set(tasks.map(\.id))
            for (id, hc) in controllers where !ids.contains(id) {
                stack.removeArrangedSubview(hc.view)
                hc.view.removeFromSuperview()
                controllers[id] = nil
            }
            for (index, t) in tasks.enumerated() {
                let hc: UIHostingController<AnyView>
                if let existing = controllers[t.id] {
                    hc = existing
                } else {
                    hc = UIHostingController(rootView: row(t))
                    hc.sizingOptions = .intrinsicContentSize
                    hc.view.backgroundColor = .clear
                    controllers[t.id] = hc
                    inserted.append(t.id)
                }
                hc.rootView = row(t)
                let current = stack.arrangedSubviews.firstIndex(of: hc.view) ?? -1
                if current != index {
                    stack.insertArrangedSubview(hc.view, at: index)
                }
            }
            return inserted
        }

        /// 新插入行直接落终值：移除让位动画给它们自身加的帧动画，
        /// 其余行的让位动画不受影响。
        func freezeInsertedRows(_ ids: [String]) {
            for id in ids { controllers[id]?.view.layer.removeAllAnimations() }
        }

        func handleTouchDown(at point: CGPoint, in scroll: UIScrollView) {
            pressDidBegin = false
            pressDidResolve = false
            pressedID = taskID(at: point, in: scroll)
            onPressDown(pressedID, visualPoint(point, in: scroll))
        }

        /// 触摸结束 / 被取消的冗余收尾：真机上勾选快 tap、滚动接管时
        /// .failed / .cancelled 的动作回调曾不送达，卡片卡在 pressing。
        /// 状态机已收尾（pressDidResolve）则跳过，避免 endDrag 双提交把
        /// 吸附动画打断。
        func handleTouchUp() {
            guard !pressDidResolve else { return }
            pressDidResolve = true
            if pressDidBegin { onDragEnded() } else { onPressCancelled() }
        }

        /// 手势坐标（含 contentOffset 的 bounds 坐标）→ 列表可视 frame 内坐标：
        /// 调用方加上列表在网格里的 frame 原点即得网格坐标，滚动过也不偏。
        private func visualPoint(_ p: CGPoint, in scroll: UIScrollView) -> CGPoint {
            CGPoint(x: p.x - scroll.contentOffset.x, y: p.y - scroll.contentOffset.y)
        }

        /// 列表坐标 → 行 id：换算到 stack 坐标后逐行 hit-test。
        private func taskID(at point: CGPoint, in scroll: UIScrollView) -> String? {
            guard let stack else { return nil }
            let p = scroll.convert(point, to: stack)
            for (index, view) in stack.arrangedSubviews.enumerated()
                where view.frame.contains(p) && index < tasks.count {
                return tasks[index].id
            }
            return nil
        }

        @objc func handlePress(_ g: UILongPressGestureRecognizer) {
            guard let scroll = g.view as? UIScrollView else { return }
            let point = g.location(in: scroll)
            switch g.state {
            case .began:
                pressDidBegin = true
                if let id = pressedID { onLongPressFired(id) }
            case .changed:
                onDragMoved(visualPoint(point, in: scroll))
            case .ended:
                // 与 handleTouchUp 互为守卫：真机上动作回调与 touchesEnded
                // override 先后不定，谁先到谁收尾，后到者跳过——否则 endDrag
                // 双提交，第二次 nil 分支会把吸附飞行直接打断。
                if !pressDidResolve {
                    pressDidResolve = true
                    onDragEnded()
                }
            case .cancelled, .failed:
                if !pressDidResolve {
                    pressDidResolve = true
                    onPressCancelled()
                }
            default:
                break
            }
        }

        /// 滚动一旦开始，长按必然已失败： pressing 卡片立即收起（冗余信号，
        /// 不依赖识别器的 .failed 回调送达）。拖拽期滚动被锁，不会误触。
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            onPressCancelled()
        }

        /// 与 UIScrollView 的 pan 并行仲裁：位移超差长按失败、滚动接管，
        /// 正是系统交互式重排的手感，不需要自定义失败依赖。
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// 补上「触摸按下」时刻：UILongPressGestureRecognizer 只在阈值到点才回调 .began，
/// 按住段的缓慢放大需要从按下就开始（TouchesBegan 转发不影响长按识别本身）。
fileprivate final class PressTrackingLongPress: UILongPressGestureRecognizer {
    var onTouchDown: (CGPoint) -> Void = { _ in }
    var onTouchUp: () -> Void = {}

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if let touch = touches.first, let view {
            onTouchDown(touch.location(in: view))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        onTouchUp()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        onTouchUp()
    }
}
