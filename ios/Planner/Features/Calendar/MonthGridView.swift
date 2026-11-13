import SwiftUI

// MARK: - F-02.4 日期格子（MonthGrid.vue）
//
// 7 列、周一起始、相邻月置灰（周视图不置灰）、今天高亮、选中态、周末色、
// 农历/节气/节日小字、休/班角标、象限彩点最多 3 个、全完成灰点。
// 呈现层按 §5.0 / OPEN-18 用系统 Button + 语义色，不复刻 CSS 的阴影与固定字号阶梯。

struct MonthGridView: View {
    let geometry: MonthGeometry
    let selected: String
    let today: String
    let mode: CalendarMode
    let showLunar: Bool
    let showHoliday: Bool
    let dots: [String: [CalendarDot]]
    let lunar: LunarData?
    let onSelect: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    private var rowHeight: CGFloat { showLunar ? 54 : 46 }

    var body: some View {
        let grid = CalendarContract.monthGrid(year: geometry.year, month0: geometry.month0, today: today)
        VStack(spacing: 0) {
            ForEach(Array(grid.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(row) { cell in
                        cellView(cell)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: rowHeight)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ cell: CalendarDayCell) -> some View {
        let isSelected = cell.key == selected
        let info = (showLunar || showHoliday) ? lunar?.dayInfo(cell.key) : nil
        let cellDots = dots[cell.key] ?? []

        Button {
            onSelect(cell.key)
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 1) {
                    Text("\(cell.day)")
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(numberColor(cell: cell, isSelected: isSelected))
                    if showLunar, let info {
                        Text(info.text)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(lunarColor(kind: info.kind, isSelected: isSelected))
                    }
                    HStack(spacing: 2.5) {
                        ForEach(Array(cellDots.enumerated()), id: \.offset) { _, dot in
                            Circle()
                                .fill(dotColor(dot, isSelected: isSelected))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showHoliday, let holiday = info?.holiday, !holiday.isEmpty {
                    Text(holiday)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(holiday == "班"
                            ? DesignTokens.color("--text-3", scheme: scheme)
                            : DesignTokens.color("--danger", scheme: scheme))
                        .padding(.top, 2)
                        .padding(.trailing, 6)
                }
            }
            .frame(width: 42, height: rowHeight - 4)
            .background(background(cell: cell, isSelected: isSelected))
            .opacity(cell.isOut && mode == .month ? 0.28 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cell.key)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func background(cell: CalendarDayCell, isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: DesignTokens.cornerMedium)
            .fill(isSelected
                ? DesignTokens.color("--accent", scheme: scheme)
                : cell.isToday
                    ? DesignTokens.color("--accent-soft", scheme: scheme)
                    : Color.clear)
    }

    private func numberColor(cell: CalendarDayCell, isSelected: Bool) -> Color {
        if isSelected { return DesignTokens.color("--on-accent", scheme: scheme) }
        if cell.isToday { return DesignTokens.color("--accent", scheme: scheme) }
        if cell.isWeekend { return DesignTokens.color("--text-2", scheme: scheme) }
        return DesignTokens.color("--text", scheme: scheme)
    }

    private func lunarColor(kind: String, isSelected: Bool) -> Color {
        if isSelected { return DesignTokens.color("--on-accent", scheme: scheme) }
        switch kind {
        case "festival": return DesignTokens.color("--danger", scheme: scheme)
        case "term": return DesignTokens.color("--accent", scheme: scheme)
        default: return DesignTokens.color("--text-3", scheme: scheme)
        }
    }

    private func dotColor(_ dot: CalendarDot, isSelected: Bool) -> Color {
        if isSelected { return DesignTokens.color("--on-accent", scheme: scheme).opacity(0.85) }
        switch dot {
        case .done: return DesignTokens.color("--text-3", scheme: scheme).opacity(0.6)
        case .quadrant(let q): return DesignTokens.color("--q\(q)", scheme: scheme)
        }
    }
}
