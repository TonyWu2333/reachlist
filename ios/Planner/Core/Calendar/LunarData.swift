import Foundation

// MARK: - OPEN-07=A 静态数据源（T-06 / M-06）
//
// `lunar-data.json` 不是"原始数据 + Swift 侧重写 dayInfo 选择逻辑"，而是
// src/lib/date.js:dayInfo 在 1900-01-01 .. 2100-12-31 共 73414 天上的**输出快照**。
// Swift 侧只做查表，因此农历/节气/节日/休班与 JS 逐字一致，且无运行时第三方依赖。
//
// 生成命令（仓库根目录）：
//   node ios/PlannerTests/Fixtures/generate_calendar_fixtures.mjs
// 调休数据年份与来源登记在 JSON 的 meta 里（lunar-javascript 内嵌 HolidayUtil，2001-2027）。
//
// T-14 替换映射（供 T-14 收尾时改自己的 Features/ 文件，本轮不动那些文件）：
//   DateText.today()            -> PlannerCalendar.today()
//   DateText.parse/addDays      -> PlannerCalendar.parseYmd / addDays
//   DateText.diffDays           -> PlannerCalendar.diffDays
//   DateText.mondayOf           -> PlannerCalendar.mondayOf
//   DateText.weekdayIndex       -> PlannerCalendar.weekdayIndex
//   DateText.weekdayName        -> PlannerCalendar.weekdayName(_:short:isEnglish:)
//   DateText.weekdayCharacter   -> PlannerCalendar.weekdayOf(_:)
//   DateText.monthDay/ordinal   -> PlannerCalendar.monthDay / ordinal
//   DateText.label              -> PlannerCalendar.dateLabel(_:today:isEnglish:)
// 调用点签名保持一致；`isEnglish` 目前由调用方传入，T-19 接入后可改为内部读取。

struct PlannerDayInfo: Equatable, Sendable {
    let text: String        // 日历格子里的那行小字
    let kind: String        // festival | term | lunar
    let holiday: String     // 休 | 班 | ""
    let holidayName: String
    let full: String        // 农历X月X日
}

struct LunarData: Sendable {

    let rangeStart: String
    let rangeEnd: String
    let days: Int
    let holidayDataYears: String

    private let years: [String: [String]]
    private let yearLabels: [String: String]

    private struct Raw: Decodable {
        struct Meta: Decodable {
            let range: [String]
            let days: Int
            let holidayDataYears: String
            enum CodingKeys: String, CodingKey {
                case range, days
                case holidayDataYears = "holiday_data_years"
            }
        }
        let meta: Meta
        let yearLabels: [String: String]
        let years: [String: [String]]
    }

    init(contentsOf url: URL) throws {
        let decoded = try JSONDecoder().decode(Raw.self, from: Data(contentsOf: url))
        years = decoded.years
        yearLabels = decoded.yearLabels
        rangeStart = decoded.meta.range.first ?? ""
        rangeEnd = decoded.meta.range.last ?? ""
        days = decoded.meta.days
        holidayDataYears = decoded.meta.holidayDataYears
    }

    /// 表覆盖范围外返回 nil（不猜测、不降级伪造）。JS 侧的农历表同样只在此范围有效。
    func dayInfo(_ ymd: String) -> PlannerDayInfo? {
        let parts = ymd.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let year = parts[0]
        guard let rows = years[String(year)] else { return nil }
        let date = PlannerCalendar.parseYmd(ymd)
        guard let ordinal = PlannerCalendar.calendar.ordinality(of: .day, in: .year, for: date),
              ordinal >= 1, ordinal <= rows.count else { return nil }
        let fields = rows[ordinal - 1].split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 5 else { return nil }
        return PlannerDayInfo(
            text: fields[0], kind: fields[1], holiday: fields[2],
            holidayName: fields[3], full: fields[4]
        )
    }

    func lunarYearLabel(_ year: Int) -> String? { yearLabels[String(year)] }

    /// App 内唯一入口。资源需随 target 打包；未登记进 Xcode 工程时返回 nil，
    /// 由调用方显式处理（不静默回退）。
    static let bundled: LunarData? = {
        guard let url = Bundle.main.url(forResource: "lunar-data", withExtension: "json") else { return nil }
        return try? LunarData(contentsOf: url)
    }()
}
