import SwiftUI

// MARK: - M-21：底部弹窗包装（§5.0 裁决 / OPEN-09=A）
//
// 用 SwiftUI 系统 `.sheet` + `.presentationDetents`，由系统提供玻璃材质与下滑关闭。
// 明确不做的（§5.0「不得为复刻 F-14.2 的拖拽阈值而自建模态容器」）：
// · 不复刻 >110pt / 速度 >0.5 且 >20pt 的自定义拖拽阈值；
// · 不自定义把手、不做逐帧键盘跟随（与上游的体感差异登记在 VERIFY-05，待真机录屏对比）；
// · 安卓返回键栈改为 NavigationStack 系统返回，弹窗关闭仍交给系统手势。
//
// 功能语义未删减：bottom sheet 仍是唯一模态面，关闭时失焦由系统负责。

extension View {
    /// `detents` 只是「这一张 sheet 需要多高」的声明，不是自建模态容器：
    /// T-16 的搜索（88dvh）与 T-17 的任务详情（92dvh）按上游用大档，
    /// 快速添加沿用默认 medium/large。系统玻璃材质与下滑关闭始终由系统提供。
    func reachSheet<Content: View>(
        isPresented: Binding<Bool>,
        detents: Set<PresentationDetent> = [.medium, .large],
        topInset: CGFloat = 20,
        surfaceToken: String = "--surface",
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented) {
            ReachSheetSurface(detents: detents, topInset: topInset,
                              surfaceToken: surfaceToken, content: content)
        }
    }

    /// 带载荷的呈现：内容由 item 驱动，呈现时才把该 item 传给内容闭包。
    /// 任务详情用这条路径：`isPresented + 外部 route` 的组合下，sheet 内容可能复用
    /// 启动期就建好的旧实例，首次打开会拿到占位空 id。
    func reachSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        detents: Set<PresentationDetent> = [.medium, .large],
        topInset: CGFloat = 20,
        surfaceToken: String = "--surface",
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item) { value in
            ReachSheetSurface(detents: detents, topInset: topInset,
                              surfaceToken: surfaceToken) { content(value) }
        }
    }
}

/// 所有系统 sheet 的统一内容容器。
///
/// 系统 sheet 的顶边由系统贴着灵动岛下方给出，内容若从 sheet 顶部 0~8pt 开始，
/// 视觉上会与灵动岛 / 系统把手挤在一起。这里统一让出 20pt：
/// 与页面标题的 `--head-top: sat + 20px` 节奏一致，也参考了系统「新建提醒事项」
/// 弹窗里标题行与卡片顶边的留白。
///
/// 顶部留白画在容器背景上（而不是只给内容加 padding），避免 sheet 顶边出现一条
/// 与 `--surface` 不一致的系统默认底色。
private struct ReachSheetSurface<Content: View>: View {
    @Environment(\.colorScheme) private var scheme

    let detents: Set<PresentationDetent>
    let content: Content

    /// sheet 内容距 sheet 顶边的留白（不含系统把手与灵动岛本身）。
    /// 自带工具条的 sheet 传小值，让 44pt 工具条自己承担呼吸区；无工具条的沿用 20pt。
    private let topInset: CGFloat
    /// sheet 底色 token：默认白 `--surface`；快速添加按参考图用分组灰 `--bg`，
    /// 上面再放白色卡片（§5.1 的色板，不引入新颜色）。
    private let surfaceToken: String

    init(detents: Set<PresentationDetent>, topInset: CGFloat, surfaceToken: String,
         @ViewBuilder content: () -> Content) {
        self.detents = detents
        self.topInset = topInset
        self.surfaceToken = surfaceToken
        self.content = content()
    }

    var body: some View {
        content
            .padding(.top, topInset)
            .background(DesignTokens.color(surfaceToken, scheme: scheme).ignoresSafeArea())
            .presentationDetents(detents)
            // 自带顶部工具条的 sheet（topInset 小）用 X 关闭，隐藏系统把手以免与工具条挤在一起；
            // 无工具条的 sheet（任务详情）仍保留系统把手。下滑关闭手势两者都由系统保留。
            .presentationDragIndicator(topInset < 10 ? .hidden : .visible)
    }
}

/// 顶部工具条的尺寸事实值，工具条与调用方（快速添加的 ✓）共用。
///
/// 数值来自参考图（系统「新建提醒事项」弹窗）逐像素实测：
/// 截图 1280×2774 对应 430pt 宽机型，比例 2.977 px/pt。
/// · 圆钮直径 132 px（横向 59…190 / 纵向 232…366）→ **44pt**（系统标准控件尺寸）；
/// · 圆钮左缘距 sheet 左边缘 59−12 px → **16pt**；
/// · 圆钮上缘距 sheet 顶边 232−177 px → **18.5pt**；
/// · 图标笔画 51×50 px → **17pt**。
enum SheetTopBarMetrics {
    /// 圆形控件的直径，左右两侧与标题避让边距共用，保证标题居中。
    static let control: CGFloat = 44
    /// 圆钮里的图标笔画目标尺寸（参考图实测 17pt）。
    /// `ReachIcon` 的 SVG 沿用上游 Icon.vue 的 24×24 视图框，内容只占框宽 ~53%
    /// （实测 @3x：框 15pt → 笔画 22px、框 17pt → 27px），所以 17pt 笔画要给 32pt 框。
    static let glyphStroke: CGFloat = 17
    static let iconBox: CGFloat = 32
    /// 工具条左右留白：参考图圆钮左缘距 sheet 边 16pt。
    static let sideInset: CGFloat = 16
    /// 工具条顶部留白：参考图圆钮上缘距 sheet 顶 18.5pt，减去 sheet 内容容器的 4pt 顶衬。
    static let topInset: CGFloat = 14
}

/// sheet 顶部工具条：左侧圆形关闭、居中标题、右侧可选确认。
///
/// 几何按参考图（系统「新建提醒事项」弹窗）实测对齐，全部取自 `SheetTopBarMetrics`：
/// 圆钮 44pt、图标 17pt、左右留白 16pt、圆钮上缘距 sheet 顶 18.5pt。
/// 工具条自身高度等于圆钮直径，标题与圆钮自然同轴居中。
///
/// 标题用 `ZStack` 叠在整行之上做**绝对居中**：只给左右按钮各留等宽的避让边距。
/// 早前用 `HStack + Spacer` 的实现，当右侧没有按钮（搜索 sheet）时标题会被左按钮挤偏。
///
/// 两个圆形按钮用系统 Liquid Glass（`.glassEffect(.regular.interactive(), in: .circle)`），
/// 与参考截图里 X / ✓ 的毛玻璃圆钮一致。
/// 不用 `.buttonStyle(.glass)` 是因为它会按标签自带内边距撑大控件，44pt 顶栏里容易溢出；
/// `.glassEffect` 只加材质、不改几何，圆钮直径就是 `SheetTopBarMetrics.control`。
/// 玻璃只加在这两个浮动控件上，不进入 sheet 内容区（§5.1 第 3 条的禁止清单不受影响）。
struct SheetTopBar<Trailing: View>: View {
    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    let title: String
    var onClose: (() -> Void)?
    let trailing: Trailing

    init(title: String, onClose: (() -> Void)? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.onClose = onClose
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(DesignTokens.color("--text", scheme: scheme))
                .lineLimit(1)
                // 左右各让出一个按钮宽度 + 间距，长标题也不会压到玻璃按钮上。
                .padding(.horizontal, SheetTopBarMetrics.control * 2 + 12 * 2)

            HStack(spacing: 12) {
                if let onClose {
                    Button(action: onClose) {
                        ReachIcon(name: .x, size: SheetTopBarMetrics.iconBox)
                            .foregroundStyle(DesignTokens.color("--text-2", scheme: scheme))
                            .frame(width: SheetTopBarMetrics.control, height: SheetTopBarMetrics.control)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(AppStrings.t("关闭", lang: lang))
                } else {
                    Color.clear.frame(width: SheetTopBarMetrics.control, height: SheetTopBarMetrics.control)
                }

                Spacer(minLength: 0)

                trailing.frame(width: SheetTopBarMetrics.control, height: SheetTopBarMetrics.control)
            }
        }
        // 先定高、再加外衬：反序会让「padding + frame」把内容在 44pt 里居中截断，
        // 实际顶衬被吃掉一半（14 → 7），且与下一行重叠 7pt。
        .frame(height: SheetTopBarMetrics.control)
        .padding(.top, SheetTopBarMetrics.topInset)
        .padding(.horizontal, SheetTopBarMetrics.sideInset)
    }
}

extension SheetTopBar where Trailing == EmptyView {
    init(title: String, onClose: (() -> Void)? = nil) {
        self.init(title: title, onClose: onClose) { EmptyView() }
    }
}
