import SwiftUI

// MARK: - F-02.7 年月选择器（MonthPicker.vue）
//
// 上/下年、12 个月网格、干支生肖年、当月/选中月标记、回到今天；
// 英文月份用 PlannerCalendar.monthName（Jan/Feb/…），年份文案走 '{y}年' 词条。

struct MonthPickerView: View {
    let year: Int
    let month0: Int
    let today: String
    let isEnglish: Bool
    let lunar: LunarData?
    let onPick: (Int, Int) -> Void
    let onToday: () -> Void

    @State private var shownYear: Int
    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    init(year: Int, month0: Int, today: String, isEnglish: Bool, lunar: LunarData?,
         onPick: @escaping (Int, Int) -> Void, onToday: @escaping () -> Void) {
        self.year = year
        self.month0 = month0
        self.today = today
        self.isEnglish = isEnglish
        self.lunar = lunar
        self.onPick = onPick
        self.onToday = onToday
        _shownYear = State(initialValue: year)
    }

    private var todayYear: Int { Int(today.prefix(4)) ?? year }
    private var todayMonth0: Int {
        let m = today.dropFirst(5).prefix(2)
        return (Int(m) ?? 1) - 1
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button {
                    HapticFeedback.play(.select)
                    shownYear -= 1
                } label: {
                    ReachIcon(name: .chevronLeft, size: 20)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(DesignTokens.color("--fill", scheme: scheme)))
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(AppStrings.t("{y}年", lang: lang, ["y": String(shownYear)]))
                        .font(.system(size: 20, weight: .bold)).monospacedDigit()
                    if let label = lunar?.lunarYearLabel(shownYear) {
                        Text(label)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    HapticFeedback.play(.select)
                    shownYear += 1
                } label: {
                    ReachIcon(name: .chevronRight, size: 20)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(DesignTokens.color("--fill", scheme: scheme)))
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(0..<12, id: \.self) { m in
                    let isSelected = shownYear == year && m == month0
                    let isNow = shownYear == todayYear && m == todayMonth0
                    Button {
                        HapticFeedback.play(.select)
                        onPick(shownYear, m)
                    } label: {
                        Text(monthLabel(m))
                            .font(.system(size: isEnglish ? 14 : 18, weight: isEnglish ? .regular : .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(isSelected
                                ? DesignTokens.color("--on-accent", scheme: scheme)
                                : isNow
                                    ? DesignTokens.color("--accent", scheme: scheme)
                                    : DesignTokens.color("--text-2", scheme: scheme))
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.cornerMedium)
                                    .fill(isSelected
                                        ? DesignTokens.color("--accent", scheme: scheme)
                                        : DesignTokens.color("--surface-2", scheme: scheme))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                HapticFeedback.play(.select)
                onToday()
            } label: {
                HStack(spacing: 6) {
                    ReachIcon(name: .calendar, size: 18)
                    Text(AppStrings.t("回到今天", lang: lang))
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(DesignTokens.color("--accent", scheme: scheme))
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.cornerMedium)
                        .fill(DesignTokens.color("--accent-soft", scheme: scheme))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .onChange(of: year) { _, new in shownYear = new }
    }

    private func monthLabel(_ m0: Int) -> String {
        isEnglish ? PlannerCalendar.monthName(m0, isEnglish: true) : "\(m0 + 1)月"
    }
}
