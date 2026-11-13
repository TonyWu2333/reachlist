import XCTest
import Foundation
@testable import Planner

// T-06 / M-06 契约测试。
// 期望值取自 baseline_commit 97a7c4c 的 src/lib/date.js（真实源码 oracle）。
// 全量逐字对比（372 条夹具 + 73414 天静态表自检）由独立 swiftc harness 执行：
//   node ios/PlannerTests/Fixtures/generate_calendar_fixtures.mjs
//   swiftc -O ios/Planner/Core/Calendar/PlannerCalendar.swift \
//             ios/Planner/Core/Calendar/LunarData.swift /tmp/t06_harness/main.swift \
//             -o /tmp/t06_harness/verify
//   /tmp/t06_harness/verify ios/PlannerTests/Fixtures/calendar_fixtures.json \
//                           ios/Planner/Resources/lunar-data.json

final class T06CalendarContractTests: XCTestCase {

    // MARK: 基础日期（date.js:4-17, 31）

    func testYmdRoundTripAndPad() {
        XCTAssertEqual(PlannerCalendar.pad(9), "09")
        XCTAssertEqual(PlannerCalendar.pad(10), "10")
        XCTAssertEqual(PlannerCalendar.ymd(PlannerCalendar.parseYmd("2026-11-13")), "2026-11-13")
        XCTAssertEqual(PlannerCalendar.ymd(PlannerCalendar.parseYmd("1900-01-01")), "1900-01-01")
    }

    func testAddDaysAcrossLeapYearAndYearBoundary() {
        XCTAssertEqual(PlannerCalendar.addDays("2024-02-28", 1), "2024-02-29")
        XCTAssertEqual(PlannerCalendar.addDays("2024-02-29", 1), "2024-03-01")
        XCTAssertEqual(PlannerCalendar.addDays("2026-12-31", 1), "2027-01-01")
        XCTAssertEqual(PlannerCalendar.addDays("2026-01-01", -1), "2025-12-31")
    }

    func testDiffDaysMatchesJSMillisecondRounding() {
        XCTAssertEqual(PlannerCalendar.diffDays("2026-11-13", "2026-11-13"), 0)
        XCTAssertEqual(PlannerCalendar.diffDays("2026-11-14", "2026-11-13"), 1)
        XCTAssertEqual(PlannerCalendar.diffDays("2026-11-13", "2026-11-14"), -1)
        XCTAssertEqual(PlannerCalendar.diffDays("2024-03-01", "2024-02-28"), 2)
    }

    func testMondayOfWeekAndWeekdayIndex() {
        // 2026-11-13 是周五：JS getDay() = 5
        XCTAssertEqual(PlannerCalendar.weekdayIndex("2026-11-13"), 5)
        XCTAssertEqual(PlannerCalendar.mondayOf("2026-11-13"), "2026-11-09")
        XCTAssertEqual(PlannerCalendar.mondayOf("2026-11-09"), "2026-11-09")
        XCTAssertEqual(PlannerCalendar.weekdayOf("2026-11-13"), "五")
    }

    // MARK: 中英文案（date.js:23-29）

    func testWeekdayNamesBothLanguages() {
        XCTAssertEqual(PlannerCalendar.weekdayName(0, isEnglish: false), "周日")
        XCTAssertEqual(PlannerCalendar.weekdayName(0, short: true, isEnglish: false), "日")
        XCTAssertEqual(PlannerCalendar.weekdayName(5, isEnglish: true), "Fri")
        XCTAssertEqual(PlannerCalendar.weekdayName(5, short: true, isEnglish: true), "F")
    }

    func testMonthNameMonthDayAndOrdinal() {
        XCTAssertEqual(PlannerCalendar.monthName(0, isEnglish: false), "1月")
        XCTAssertEqual(PlannerCalendar.monthName(10, isEnglish: true), "Nov")
        XCTAssertEqual(PlannerCalendar.monthDay("2026-11-20", isEnglish: false), "11月20日")
        XCTAssertEqual(PlannerCalendar.monthDay("2026-11-20", isEnglish: true), "Nov 20")
        XCTAssertEqual(PlannerCalendar.ordinal(1), "1st")
        XCTAssertEqual(PlannerCalendar.ordinal(2), "2nd")
        XCTAssertEqual(PlannerCalendar.ordinal(3), "3rd")
        XCTAssertEqual(PlannerCalendar.ordinal(11), "11th")
        XCTAssertEqual(PlannerCalendar.ordinal(13), "13th")
        XCTAssertEqual(PlannerCalendar.ordinal(21), "21st")
        XCTAssertEqual(PlannerCalendar.ordinal(113), "113th")
    }

    // MARK: dateLabel（date.js:33-52）

    func testDateLabelChineseBranches() {
        let today = "2026-11-13"
        XCTAssertEqual(PlannerCalendar.dateLabel("", today: today, isEnglish: false), "")
        XCTAssertEqual(PlannerCalendar.dateLabel("2026-11-13", today: today, isEnglish: false), "今天")
        XCTAssertEqual(PlannerCalendar.dateLabel("2026-11-14", today: today, isEnglish: false), "明天")
        XCTAssertEqual(PlannerCalendar.dateLabel("2026-11-15", today: today, isEnglish: false), "后天")
        XCTAssertEqual(PlannerCalendar.dateLabel("2026-11-12", today: today, isEnglish: false), "昨天")
        XCTAssertEqual(PlannerCalendar.dateLabel("2026-10-14", today: today, isEnglish: false), "10月14日")
        XCTAssertEqual(PlannerCalendar.dateLabel("2027-01-01", today: today, isEnglish: false), "2027年1月1日")
    }

    func testDateLabelEnglishBranches() {
        let today = "2026-11-13"
        XCTAssertEqual(PlannerCalendar.dateLabel("2026-11-13", today: today, isEnglish: true), "Today")
        XCTAssertEqual(PlannerCalendar.dateLabel("2026-11-14", today: today, isEnglish: true), "Tomorrow")
        XCTAssertEqual(PlannerCalendar.dateLabel("2026-11-12", today: today, isEnglish: true), "Yesterday")
        // 英文分支没有「大后天」等价词：n=2 落进 n>1 && n<7 的星期名分支。
        XCTAssertEqual(PlannerCalendar.dateLabel("2026-11-15", today: today, isEnglish: true), "Sun")
        XCTAssertEqual(PlannerCalendar.dateLabel("2027-01-01", today: today, isEnglish: true), "Jan 1, 2027")
    }

    // MARK: OPEN-07=A 静态表

    func testStaticTableMetadata() throws {
        guard let data = LunarData.bundled else {
            throw XCTSkip("lunar-data.json 未随 App target 打包，检查 Resources phase")
        }
        XCTAssertEqual(data.rangeStart, "1900-01-01")
        XCTAssertEqual(data.rangeEnd, "2100-12-31")
        XCTAssertEqual(data.days, 73414)
        XCTAssertEqual(data.holidayDataYears, "2001-2027")
        XCTAssertEqual(data.lunarYearLabel(2026), "丙午马年")
        XCTAssertEqual(data.lunarYearLabel(1900), "庚子鼠年")
    }

    func testDayInfoFestivalTermHolidayAndLunarFallback() throws {
        guard let data = LunarData.bundled else {
            throw XCTSkip("lunar-data.json 未随 App target 打包，检查 Resources phase")
        }
        // 公历节日 + 休
        let nationalDay = try XCTUnwrap(PlannerCalendar.dayInfo("2026-10-01", using: data))
        XCTAssertEqual(nationalDay.text, "国庆节")
        XCTAssertEqual(nationalDay.kind, "festival")
        XCTAssertEqual(nationalDay.holiday, "休")
        XCTAssertEqual(nationalDay.holidayName, "国庆节")
        XCTAssertEqual(nationalDay.full, "农历八月廿一")

        // 节气
        let qingming = try XCTUnwrap(PlannerCalendar.dayInfo("2026-04-05", using: data))
        XCTAssertEqual(qingming.text, "清明")
        XCTAssertEqual(qingming.kind, "term")

        // 调休「班」+ 初一显示月份
        let makeUpDay = try XCTUnwrap(PlannerCalendar.dayInfo("2026-10-10", using: data))
        XCTAssertEqual(makeUpDay.text, "九月")
        XCTAssertEqual(makeUpDay.kind, "lunar")
        XCTAssertEqual(makeUpDay.holiday, "班")
        XCTAssertEqual(makeUpDay.holidayName, "")

        // 普通农历日
        let ordinary = try XCTUnwrap(PlannerCalendar.dayInfo("2026-11-13", using: data))
        XCTAssertEqual(ordinary.text, "初五")
        XCTAssertEqual(ordinary.full, "农历十月初五")
    }

    func testDayInfoNamesStayChineseAndOutOfRangeReturnsNil() throws {
        guard let data = LunarData.bundled else {
            throw XCTSkip("lunar-data.json 未随 App target 打包，检查 Resources phase")
        }
        // A-13：dayInfo 不走 i18n，两种语言下拿到的是同一条中文记录。
        let springFestival = try XCTUnwrap(PlannerCalendar.dayInfo("2026-02-17", using: data))
        XCTAssertEqual(springFestival.text, "春节")
        XCTAssertEqual(springFestival.full, "农历正月初一")

        // 2028+ JS 侧 HolidayUtil 无调休数据，查表结果 holiday 为空而非报错。
        let y2028 = try XCTUnwrap(PlannerCalendar.dayInfo("2028-01-01", using: data))
        XCTAssertEqual(y2028.text, "元旦")
        XCTAssertEqual(y2028.holiday, "")

        // 表覆盖范围外明确返回 nil，不伪造成农历数据。
        XCTAssertNil(PlannerCalendar.dayInfo("1899-12-31", using: data))
        XCTAssertNil(PlannerCalendar.dayInfo("2101-01-01", using: data))
    }
}
