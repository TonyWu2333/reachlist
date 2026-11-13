import SwiftUI

// MARK: - M-15 重复面板（RepeatPanel.vue）
//
// 预设 5 个 + 不重复；自定义「每 N 天/周/个月/年」、周几多选、结束日期。
// 英文布局特例（F-16.6）：单位按钮 days / months 一行放不下，挪到数字下面单独一行；
// 预设只写 Monthly / Yearly（完整规则看底部摘要）。

struct RepeatPanelView: View {
    @Binding var value: String
    let date: String
    /// (规则串, 是否收起面板)：点预设收起；自定义还在调，不收起。
    var onPick: (String, Bool) -> Void

    @State private var untilOpen = false
    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    private let freqs: [(String, String, String)] = [
        ("d", "天", "day"), ("w", "周", "week"), ("m", "个月", "month"), ("y", "年", "year"),
    ]
    private let weekOrder = [1, 2, 3, 4, 5, 6, 0]
    private var isEnglish: Bool { lang == "en" }
    private var today: String { DateText.today() }
    private var startDate: String { date.isEmpty ? today : date }
    private var rule: RepeatRule.Rule? { RepeatRule.parse(value) }
    private var cur: RepeatRule.Rule { PanelCatalog.customBase(value) }
    private var dow: Int { DateText.weekdayIndex(startDate) }
    private var base: String {
        guard let r = rule else { return "" }
        return RepeatRule.format(RepeatRule.Rule(freq: r.freq, n: r.n, days: r.days, until: ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            presets

            Rectangle()
                .fill(DesignTokens.color("--sep", scheme: scheme))
                .frame(height: 0.5)

            custom

            untilRow
            if untilOpen, rule != nil {
                DatePanelView(
                    value: Binding(get: { rule?.until ?? "" }, set: { setUntil($0) }),
                    quick: PanelCatalog.repeatEndQuickOptions(startDate: startDate, today: today),
                    onPick: { setUntil($0); untilOpen = false }
                )
            }

            HStack(spacing: 5) {
                ReachIcon(name: .`repeat`, size: 13)
                    .foregroundStyle(DesignTokens.color("--accent", scheme: scheme))
                Text(PanelCatalog.repeatSummary(value, date: startDate, isEnglish: isEnglish))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.color("--text-2", scheme: scheme))
            }
        }
    }

    // MARK: 预设

    private var presets: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(PanelCatalog.repeatPresets(date: startDate), id: \.self) { preset in
                Button { pickPreset(preset) } label: {
                    Text(PanelCatalog.repeatPresetLabel(preset, date: startDate, isEnglish: isEnglish))
                        .font(.footnote)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .padding(.horizontal, 2)
                        .background(base == preset
                            ? DesignTokens.color("--accent-soft", scheme: scheme)
                            : DesignTokens.color("--surface", scheme: scheme))
                        .foregroundStyle(base == preset
                            ? DesignTokens.color("--accent", scheme: scheme)
                            : DesignTokens.color("--text-2", scheme: scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            Button { emit(nil, done: true) } label: {
                HStack(spacing: 4) {
                    ReachIcon(name: .ban, size: 15)
                    Text(AppStrings.t("不重复", lang: lang)).font(.footnote)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(value.isEmpty
                    ? DesignTokens.color("--accent-soft", scheme: scheme)
                    : DesignTokens.color("--surface", scheme: scheme))
                .foregroundStyle(value.isEmpty
                    ? DesignTokens.color("--accent", scheme: scheme)
                    : DesignTokens.color("--text-2", scheme: scheme))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 自定义「每 N 天/周/个月/年」

    private var custom: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEnglish {
                HStack(spacing: 10) {
                    everyLabel
                    stepper
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) { unitButtons }
                    .padding(.leading, 50)
            } else {
                HStack(spacing: 10) {
                    everyLabel
                    stepper
                    unitButtons
                }
            }

            if cur.freq == "w" {
                HStack(spacing: 6) {
                    ForEach(weekOrder, id: \.self) { day in
                        let on = cur.days.contains(day)
                        Button { toggleDay(day) } label: {
                            Text(DateText.weekdayName(day, short: true, isEnglish: isEnglish))
                                .font(.footnote)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(on
                                    ? DesignTokens.color("--accent", scheme: scheme)
                                    : DesignTokens.color("--surface", scheme: scheme))
                                .foregroundStyle(on
                                    ? DesignTokens.color("--on-accent", scheme: scheme)
                                    : DesignTokens.color("--text-2", scheme: scheme))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, isEnglish ? 50 : 40)
            } else if cur.freq == "m" || cur.freq == "y" {
                Text(
                    AppStrings.t(
                        cur.freq == "m" ? "按开始日期 {date} 的几号重复" : "按开始日期 {date} 的月和日重复",
                        lang: lang,
                        ["date": DateText.label(startDate, today: today, isEnglish: isEnglish)]
                    )
                )
                .font(.caption2)
                .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                .padding(.leading, isEnglish ? 50 : 40)
            }
        }
        .opacity(rule == nil ? 0.6 : 1)
    }

    private var everyLabel: some View {
        Text(AppStrings.t("每", lang: lang))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DesignTokens.color("--text-2", scheme: scheme))
            .frame(width: isEnglish ? 40 : 30, alignment: .leading)
    }

    private var stepper: some View {
        HStack(spacing: 4) {
            Button { step(-1) } label: {
                Text("−")
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .background(DesignTokens.color("--surface", scheme: scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(cur.n <= 1)

            Text("\(cur.n)")
                .font(.headline)
                .monospacedDigit()
                .frame(minWidth: 26)

            Button { step(1) } label: {
                Text("+")
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .background(DesignTokens.color("--surface", scheme: scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(DesignTokens.color("--text-2", scheme: scheme))
    }

    private var unitButtons: some View {
        ForEach(freqs, id: \.0) { item in
            let on = rule != nil && cur.freq == item.0
            Button { setFreq(item.0) } label: {
                Text(freqLabel(item.1, item.2))
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(on
                        ? DesignTokens.color("--accent-soft", scheme: scheme)
                        : DesignTokens.color("--surface", scheme: scheme))
                    .foregroundStyle(on
                        ? DesignTokens.color("--accent", scheme: scheme)
                        : DesignTokens.color("--text-2", scheme: scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 结束日期

    private var untilRow: some View {
        Button { untilOpen.toggle() } label: {
            HStack(spacing: 10) {
                Text(AppStrings.t("结束", lang: lang))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.color("--text-2", scheme: scheme))
                    .frame(width: isEnglish ? 40 : 30, alignment: .leading)
                Text(rule?.until.isEmpty == false
                    ? AppStrings.t("到 {date}", lang: lang, ["date": DateText.label(rule?.until ?? "", today: today, isEnglish: isEnglish)])
                    : AppStrings.t("永不结束", lang: lang))
                    .font(.subheadline)
                    .foregroundStyle(rule?.until.isEmpty == false
                        ? DesignTokens.color("--accent", scheme: scheme)
                        : DesignTokens.color("--text-3", scheme: scheme))
                Spacer(minLength: 0)
                ReachIcon(name: .chevronRight, size: 16)
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                    .rotationEffect(.degrees(untilOpen ? 90 : 0))
            }
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(rule == nil)
        .opacity(rule == nil ? 0.45 : 1)
    }

    // MARK: 动作

    private func freqLabel(_ zh: String, _ en: String) -> String {
        isEnglish ? (cur.n == 1 ? en : en + "s") : zh
    }

    private func pickPreset(_ preset: String) {
        guard let parsed = RepeatRule.parse(preset) else { return }
        let merged = RepeatRule.Rule(freq: parsed.freq, n: parsed.n, days: parsed.days, until: rule?.until ?? "")
        emit(merged, done: true)
    }

    private func emit(_ next: RepeatRule.Rule?, done: Bool) {
        HapticFeedback.play(.select)
        onPick(next.map(RepeatRule.format) ?? "", done)
    }

    private func setFreq(_ freq: String) {
        if rule != nil && freq == cur.freq { return }
        let days = PanelCatalog.daysWhenSwitching(freq: freq, current: cur.days, dow: dow)
        emit(RepeatRule.Rule(freq: freq, n: cur.n, days: days, until: cur.until), done: false)
    }

    private func step(_ delta: Int) {
        let n = PanelCatalog.steppedCount(cur.n, delta: delta)
        if rule != nil && n == cur.n { return }
        emit(RepeatRule.Rule(freq: cur.freq, n: n, days: cur.days, until: cur.until), done: false)
    }

    private func toggleDay(_ day: Int) {
        let days = PanelCatalog.toggledDays(cur.days, day)
        emit(RepeatRule.Rule(freq: "w", n: cur.n, days: days, until: cur.until), done: false)
    }

    private func setUntil(_ until: String) {
        let clamped = PanelCatalog.clampUntil(until, startDate: startDate)
        emit(RepeatRule.Rule(freq: cur.freq, n: cur.n, days: cur.days, until: clamped), done: false)
    }
}
