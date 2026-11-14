import SwiftUI
import UIKit

// MARK: - M-14 快速添加 sheet（T-17 / F-07 全量）
//
// 默认值注入（date / q / repeat）、打开即聚焦、输入即识别（只识别中文，F-07.7）、
// 提示拆成 [前, 加粗 when, 后] 三段以适配英文语序、撤销识别、三个 manual 覆盖标志、
// 4 个面板 + 备注、面板联动（补今天 / 清时间 / 自定义不收起）、空标题不可提交、
// 提交后 toast（本地化）与象限色提示。面板全部复用 T-14 的 M-15，不写第二份。
//
// 呈现层：系统 .sheet + 系统键盘避让（§5.0 裁决，VERIFY-05 体感仍留真机录屏对比）。

struct QuickAddSheet: View {
    @EnvironmentObject private var store: CalendarDataStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    let defaults: QuickAddDefaults
    /// DEV-ONLY 取图用：直接以某个面板展开态渲染，供视觉探针核对月历是否被裁切。
    var initialPanel: QuickAddPanel? = nil
    var onClose: () -> Void = {}

    @State private var state = QuickAddState()
    @State private var now = Date()
    @FocusState private var focused: Bool

    private var today: String { PlannerCalendar.today(now) }
    private var parsed: ParsedInput { QuickAddContract.parsed(state, now: now) }
    private var effDate: String { QuickAddContract.effDate(state, now: now) }
    private var effTime: String { QuickAddContract.effTime(state, now: now) }
    private var effRepeat: String { QuickAddContract.effRepeat(state, now: now) }
    private var recognized: Bool { QuickAddContract.recognized(state, now: now) }
    private var canSend: Bool { QuickAddContract.canSend(state) }
    private var whenLabel: String {
        QuickAddContract.whenLabel(state, now: now, lang: lang, today: today)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetTopBar(title: AppStrings.t("新建任务", lang: lang), onClose: close) {
                Button(action: submit) {
                    ReachIcon(name: .check, size: SheetTopBarMetrics.iconBox)
                        .foregroundStyle(canSend
                            ? DesignTokens.color("--accent", scheme: scheme)
                            : DesignTokens.color("--text-3", scheme: scheme))
                        .frame(width: SheetTopBarMetrics.control,
                               height: SheetTopBarMetrics.control)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(!canSend)
                .accessibilityLabel(AppStrings.t("添加", lang: lang))
            }

            // 内容放进可滚动容器：月历比 .medium 档高得多，早前用固定 VStack 会
            // 把顶栏与输入行挤出裁剪区（用户 2026-11-15 的第二张截图）。
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    inputCard
                    if recognized { parseBanner }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { chips }
                    }
                    if let panel = state.panel {
                        panelView(panel)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                DesignTokens.color("--surface", scheme: scheme),
                                in: RoundedRectangle(cornerRadius: 18)
                            )
                    }
                }
                // 20pt：与四象限卡片、Tab Bar 玻璃胶囊（实测 21..409 @430pt）同一条边线。
                .padding(.horizontal, DesignTokens.gutter)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(DesignTokens.color("--bg", scheme: scheme))
        // 键盘只覆盖在内容之上，不改变 sheet 的内容高度：
        // 否则键盘收放会让固定 .large 档的 sheet 再发生一次垂直位移。
        .ignoresSafeArea(.keyboard)
        .onAppear {
            now = Date()
            state = .opened(defaults, today: PlannerCalendar.today(now))
            if let initialPanel {
                state.panel = initialPanel
                focused = false
            } else {
                focused = true
            }
        }
        .onChange(of: defaults) { _, new in
            now = Date()
            state = .opened(new, today: PlannerCalendar.today(now))
            if let initialPanel {
                state.panel = initialPanel
                focused = false
            } else {
                focused = true
            }
        }
    }

    /// 白色卡片承载标题与备注，放在浅灰 sheet 底色之上（参考图「标题 / 备注与 URL」卡片）。
    private var inputCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(quadrantColor, lineWidth: 2)
                    .background(Circle().fill(quadrantColor.opacity(0.12)))
                    .frame(width: 22, height: 22)
                TextField(AppStrings.t("准备做点什么？", lang: lang), text: $state.text)
                    .font(.title3)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .onChange(of: state.text) { _, _ in
                        if state.panel != nil { state.panel = nil }   // @focus 时收起面板
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if state.showNote {
                Divider().padding(.leading, 16)
                TextField(AppStrings.t("添加备注…", lang: lang), text: $state.note)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(
            DesignTokens.color("--surface", scheme: scheme),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    // MARK: 识别提示

    private var parseBanner: some View {
        let msg = QuickAddContract.parseMsg(parsed, lang: lang)
        return HStack(spacing: 6) {
            ReachIcon(name: .sparkle, size: 16)
                .foregroundStyle(DesignTokens.color("--accent", scheme: scheme))
            Text(msg.before)
                + Text(QuickAddContract.recognizedWhen(state, now: now, lang: lang, today: today))
                    .fontWeight(.bold)
                    .foregroundColor(DesignTokens.color("--accent", scheme: scheme))
                + Text(msg.after)
            Spacer(minLength: 0)
            Button(AppStrings.t("撤销识别", lang: lang)) {
                state.useParse = false
                HapticFeedback.play(.select)
            }
            .font(.caption)
            .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
        }
        .font(.footnote)
        .lineLimit(1)
        .padding(8).padding(.horizontal, 4)
        .background(DesignTokens.color("--accent-soft", scheme: scheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: chips

    @ViewBuilder private var chips: some View {
        chip(icon: .calendar, label: effDate.isEmpty
             ? AppStrings.t("日期", lang: lang)
             : PlannerCalendar.dateLabel(effDate, today: today, isEnglish: lang == "en"),
             on: !effDate.isEmpty, active: state.panel == .date) { toggle(.date) }
        chip(icon: .clock, label: effTime.isEmpty ? AppStrings.t("时间", lang: lang) : effTime,
             on: !effTime.isEmpty, active: state.panel == .time) { toggle(.time) }
        chip(icon: .`repeat`, label: effRepeat.isEmpty
             ? AppStrings.t("重复", lang: lang)
             : RepeatEngine.repeatLabel(effRepeat, date: effDate, isEnglish: lang == "en"),
             on: !effRepeat.isEmpty, active: state.panel == .repeat) { toggle(.repeat) }
        chip(icon: .flag, label: AppStrings.t(PanelCatalog.quadrants[state.quadrant - 1].shortKey, lang: lang),
             on: true, active: state.panel == .quad) { toggle(.quad) }
        chip(icon: .note, label: nil, on: state.showNote, active: false) {
            state.showNote.toggle()
            HapticFeedback.play(.select)
        }
    }

    private func chip(icon: ReachIconName, label: String?, on: Bool, active: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ReachIcon(name: icon, size: 15)
                if let label {
                    Text(label).font(.caption).lineLimit(1)
                }
            }
            .padding(.horizontal, label == nil ? 9 : 10)
            .frame(height: 32)
            .background(Capsule().fill(on
                ? DesignTokens.color("--accent-soft", scheme: scheme)
                : DesignTokens.color("--fill", scheme: scheme)))
            .overlay {
                Capsule().strokeBorder(active ? quadrantColor : .clear, lineWidth: 1.5)
            }
            .foregroundStyle(on
                ? DesignTokens.color("--accent", scheme: scheme)
                : DesignTokens.color("--text-2", scheme: scheme))
        }
        .buttonStyle(.plain)
    }

    private var quadrantColor: Color {
        DesignTokens.color(PanelCatalog.quadrants[state.quadrant - 1].colorToken, scheme: scheme)
    }

    // MARK: 面板

    private func toggle(_ p: QuickAddPanel) {
        HapticFeedback.play(.select)
        // 面板出现/消失不做隐式布局动画，避免 ScrollView 内容高度变化时整页上下弹动。
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state.panel = state.panel == p ? nil : p
            // 展开面板时收起键盘；收起面板时**不**自动重新唤起。
            // 早前 focused = (panel == nil) 会让键盘在每次点 chip 时上下滑动一次。
            if state.panel != nil { focused = false }
        }
    }

    @ViewBuilder
    private func panelView(_ p: QuickAddPanel) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.vertical, 12)
            switch p {
            case .date:
                DatePanelView(
                    value: Binding(get: { effDate }, set: { state.setDate($0) }),
                    quick: PanelCatalog.dateOptions(today: today),
                    onPick: { state.setDate($0) }
                )
            case .time:
                TimePanelView(
                    value: Binding(get: { effTime }, set: { state.setTime($0, now: now, today: today) }),
                    onPick: { state.setTime($0, now: now, today: today) }
                )
            case .repeat:
                RepeatPanelView(
                    value: Binding(get: { effRepeat }, set: { state.setRepeat($0, done: true, now: now, today: today) }),
                    date: effDate.isEmpty ? today : effDate,
                    onPick: { rule, done in
                        state.setRepeat(rule, done: done, now: now, today: today)
                    }
                )
            case .quad:
                QuadrantPanelView(
                    value: Binding(get: { state.quadrant }, set: { state.setQuadrant($0) }),
                    onPick: { state.setQuadrant($0) }
                )
            }
        }
    }

    /// 关 sheet 前必须让当前第一响应者真正交出键盘：
    /// 只把 @FocusState 置 false 就立刻 dismiss，系统会在键盘动画途中拆掉 sheet，
    /// 键盘就留在了上一个页面上（用户 2026-11-15 反馈）。
    private func finish() {
        focused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        // 等键盘交出第一响应者后的下一个主actor任务再关 sheet。
        Task { @MainActor in
            dismiss()
            onClose()
        }
    }

    private func close() {
        finish()
    }

    // MARK: 提交

    private func submit() {
        guard canSend else { return }
        let fields = QuickAddContract.submitFields(state, now: now)
        let message = QuickAddContract.toastMessage(state, now: now, lang: lang, today: today)
        _ = store.add(fields: fields)
        HapticFeedback.play(.success)
        toastCenter.show(text: message)
        finish()
    }
}
