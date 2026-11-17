import SwiftUI

// MARK: - M-19 TaskRow（可复用行）
//
// 结构逐条对齐 TaskRow.vue：勾选圈（象限色）+ 标题（完成划线）+ 元信息行 + 右侧时间。
// 数据与动作全部由调用方注入（TaskRowModel + 闭包），不直接依赖 TaskStore（T-09）。
// 滑动由系统 List 的 swipeActions 提供，见 TaskRowSwipe.swift。

struct TaskRow: View {
    let model: TaskRowModel
    var compact = false
    var showDate = false
    var hideRepeat = false
    var hideParent = false
    /// 分组卡片（如日程页）由外层统一画整组底色，行本身不再单独画卡片。
    var showsCardBackground = true

    var onToggle: () -> Void = {}
    /// 勾选触点按下的瞬间回调（参数 = 目标完成态），供调用方做乐观更新；
    /// 数据仍按 TaskRowContract.toggleDelayMilliseconds 延迟到 onToggle 提交。
    var onToggleIntent: (Bool) -> Void = { _ in }
    var onOpen: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appLanguage) private var lang
    @State private var pending = false
    @State private var guardUntil: Int64 = 0

    private var isEnglish: Bool { lang == "en" }
    private var quadrantColor: Color {
        DesignTokens.color(PanelCatalog.quadrants[model.quadrant - 1].colorToken, scheme: scheme)
    }
    private var done: Bool { TaskRowContract.visualDone(taskDone: model.isDone, pending: pending) }

    private var flags: TaskRowContract.MetaFlags {
        TaskRowContract.metaFlags(
            showDate: showDate,
            compact: compact,
            hideRepeat: hideRepeat,
            hideParent: hideParent,
            date: model.task.date,
            time: model.task.time,
            note: model.task.note,
            repeatRule: model.task.repeatRule,
            streak: model.streak,
            subTotal: model.subTotal,
            parentTitle: model.parentTitle,
            dropped: model.task.dropped
        )
    }

    var body: some View {
        HStack(alignment: compact ? .top : .center,
               spacing: compact ? 8 : TaskRowContract.rowSpacing) {
            checkButton
            VStack(alignment: .leading, spacing: 2) {
                titleView
                if flags.any { metaRow }
            }
            if !compact && !model.task.time.isEmpty { timeView }
        }
        .padding(.horizontal, compact ? 6 : TaskRowContract.rowHorizontalInset)
        .padding(.vertical, compact ? 7 : 8)
        .frame(minHeight: compact ? nil : DesignTokens.rowMinHeight, alignment: .leading)
        // 卡片是这一行唯一的视觉层：不描边、不加阴影。
        // 行与行之间靠 --bg 底色 + 3pt 行间距分开，不再画线（见 TaskRowGallery.reachCardRow）。
        .background {
            if !compact && showsCardBackground {
                RoundedRectangle(cornerRadius: DesignTokens.cornerMedium)
                    .fill(DesignTokens.color("--surface", scheme: scheme))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: handleTap)
        .opacity(pending ? 0.92 : 1)
    }

    // MARK: 勾选

    private var checkButton: some View {
        Button(action: toggle) {
            ZStack {
                Circle()
                    .fill(done ? quadrantColor : quadrantColor.opacity(0.12))
                Circle()
                    .strokeBorder(done ? quadrantColor : quadrantColor, lineWidth: compact ? 1.6 : 2)
                if model.task.dropped && !pending {
                    CrossMark()
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                        .padding(compact ? 4 : 5)
                } else if done {
                    CheckMark()
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .padding(compact ? 4 : 5)
                }
            }
            .frame(width: compact ? 18 : 24, height: compact ? 18 : 24)
        }
        .buttonStyle(.plain)
        .frame(minWidth: DesignTokens.touchTarget, minHeight: DesignTokens.touchTarget, alignment: .leading)
        .accessibilityLabel(accessibilityCheckLabel)
    }

    private var accessibilityCheckLabel: String {
        if model.task.dropped && !pending { return AppStrings.t("恢复", lang: lang) }
        if done { return AppStrings.t("标记为未完成", lang: lang) }
        return AppStrings.t("标记为完成", lang: lang)
    }

    /// TaskRow.vue:toggle —— 先播 380ms，再提交；期间 pending 防止重复触发。
    /// onToggleIntent 在按下瞬间同步触发，调用方可据此做乐观更新（如打卡页进度环）。
    private func toggle() {
        guard !pending else { return }
        pending = true
        onToggleIntent(!model.isDone)
        guardUntil = Int64((Date().timeIntervalSince1970 * 1000).rounded())
            + Int64(FeedbackContract.clickGuardMilliseconds)
        if !model.isDone { HapticFeedback.play(.light) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(TaskRowContract.toggleDelayMilliseconds) * 1_000_000)
            onToggle()
            pending = false
        }
    }

    /// TaskRow.vue:onClick —— 守卫窗口内的点击吞掉，不打开详情。
    private func handleTap() {
        let now = Int64((Date().timeIntervalSince1970 * 1000).rounded())
        if FeedbackContract.shouldIgnoreTap(now: now, until: guardUntil) { return }
        if pending { return }
        onOpen()
    }

    // MARK: 标题

    private var titleView: some View {
        Text(model.task.title)
            .font(compact ? .subheadline : .body)
            .foregroundStyle(titleColor)
            .strikethrough(done && !model.task.dropped, color: titleColor)
            .lineLimit(compact ? 2 : 1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleColor: Color {
        if model.task.dropped { return DesignTokens.color("--text-3", scheme: scheme) }
        return done
            ? DesignTokens.color("--text-3", scheme: scheme)
            : DesignTokens.color("--text", scheme: scheme)
    }

    // MARK: 元信息（TaskRow.vue:trow-meta）

    private var metaRow: some View {
        HStack(spacing: compact ? 6 : 8) {
            if flags.dropped {
                Text(AppStrings.t("已放弃", lang: lang))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(DesignTokens.color("--fill", scheme: scheme))
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if flags.date {
                Text(model.dateText)
                    .foregroundStyle(model.isOverdue
                        ? DesignTokens.color("--danger", scheme: scheme)
                        : DesignTokens.color("--text-3", scheme: scheme))
                    .fontWeight(model.isOverdue ? .semibold : .regular)
            }
            if flags.streak {
                HStack(spacing: 2) {
                    ReachIcon(name: .flame, size: 12)
                    Text(model.streakText)
                }
                .foregroundStyle(DesignTokens.color("--q2", scheme: scheme))
                .fontWeight(.semibold)
            }
            if flags.repeatRule {
                HStack(spacing: 3) {
                    ReachIcon(name: .`repeat`, size: 12)
                    if !compact { Text(model.repeatText) }
                }
                .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
            }
            if flags.compactTime {
                HStack(spacing: 2) {
                    if model.task.remind != nil { ReachIcon(name: .bell, size: 11) }
                    Text(model.task.time).monospacedDigit()
                }
                .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
            }
            if flags.subProgress {
                HStack(spacing: 3) {
                    ReachIcon(name: .checklist, size: 12)
                    Text("\(model.subDone)/\(model.subTotal)").monospacedDigit()
                }
                .foregroundStyle(model.subDone == model.subTotal
                    ? DesignTokens.color("--success", scheme: scheme)
                    : DesignTokens.color("--text-3", scheme: scheme))
            }
            if flags.note {
                ReachIcon(name: .note, size: 13)
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
            }
            if flags.parent {
                Text("↳ " + model.parentTitle)
                    .lineLimit(1)
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
            }
        }
        .font(compact ? .caption2 : .caption)
        .lineLimit(1)
    }

    // MARK: 右侧时间

    private var timeView: some View {
        HStack(spacing: 3) {
            if model.task.remind != nil && !done {
                ReachIcon(name: .bell, size: 13)
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
            }
            Text(model.task.time)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(done
                    ? DesignTokens.color("--text-3", scheme: scheme)
                    : DesignTokens.color("--text-2", scheme: scheme))
        }
        .fixedSize()
    }
}

// 勾选标记用 Path 绘制（TaskRow.vue 的内联 SVG），不引入 SF Symbols（OPEN-03=B 的精神）。

private struct CheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 6.5 * s, y: 12.5 * s))
        p.addLine(to: CGPoint(x: 10.1 * s, y: 16.1 * s))
        p.addLine(to: CGPoint(x: 17.5 * s, y: 7.6 * s))
        return p
    }
}

private struct CrossMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 8 * s, y: 8 * s))
        p.addLine(to: CGPoint(x: 16 * s, y: 16 * s))
        p.move(to: CGPoint(x: 16 * s, y: 8 * s))
        p.addLine(to: CGPoint(x: 8 * s, y: 16 * s))
        return p
    }
}
