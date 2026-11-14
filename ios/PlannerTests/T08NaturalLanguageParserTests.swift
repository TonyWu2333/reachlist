import XCTest
import Foundation
@testable import Planner

// T-08 / M-04 中文自然语言解析契约测试。
// 期望值取自 baseline_commit 97a7c4c 的 src/lib/parse.js（真实源码 oracle），
// 与 ios/PlannerTests/Fixtures/parse_fixtures.json 逐字一致。
// 全量逐字对比（151 条 × 5 字段 = 755 项）由独立 swiftc harness 执行：
//   node ios/PlannerTests/Fixtures/generate_parse_fixtures.mjs
//   swiftc -O ios/Planner/Core/Calendar/{PlannerCalendar,LunarData}.swift \
//             ios/Planner/Core/Parse/NaturalLanguageParser.swift /tmp/t08_harness/main.swift \
//             -o /tmp/t08_harness/verify
//   /tmp/t08_harness/verify ios/PlannerTests/Fixtures/parse_fixtures.json
//
// 所有用例注入本地 2026-11-13 12:00，与夹具生成器的固定时刻一致；
// 因为是本地时间构造，任何系统时区下「今天」都是 2026-11-13。

final class T08NaturalLanguageParserTests: XCTestCase {

    private var fixedNow: Date {
        var c = DateComponents()
        c.year = 2026
        c.month = 11
        c.day = 13
        c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: c)!
    }

    private func parse(_ text: String) -> ParsedInput {
        NaturalLanguageParser.parseInput(text, now: fixedNow)
    }

    private func assertResult(
        _ text: String, title: String, date: String, time: String,
        repeatRule: String, hits: [String], _ note: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let r = parse(text)
        let suffix = note.isEmpty ? "" : " — \(note)"
        XCTAssertEqual(r.title, title, "title: \(text)\(suffix)", file: file, line: line)
        XCTAssertEqual(r.date, date, "date: \(text)\(suffix)", file: file, line: line)
        XCTAssertEqual(r.time, time, "time: \(text)\(suffix)", file: file, line: line)
        XCTAssertEqual(r.repeatRule, repeatRule, "repeat: \(text)\(suffix)", file: file, line: line)
        XCTAssertEqual(r.hits, hits, "hits: \(text)\(suffix)", file: file, line: line)
    }

    // MARK: selfTest 25 条中的代表用例（OPEN-08=A 的等价标准）

    func testSelfTestDatesAndTimes() {
        assertResult("明天下午3点开会", title: "开会", date: "2026-11-14", time: "15:00",
                     repeatRule: "", hits: ["明天", "下午3点"])
        assertResult("周五 交周报", title: "交周报", date: "2026-11-13", time: "",
                     repeatRule: "", hits: ["周五"])
        assertResult("下周一 9:30 例会", title: "例会", date: "2026-11-16", time: "09:30",
                     repeatRule: "", hits: ["下周一", "9:30"])
        assertResult("11月20日体检", title: "体检", date: "2026-11-20", time: "",
                     repeatRule: "", hits: ["11月20日"])
        assertResult("3号交房租", title: "交房租", date: "2026-12-03", time: "",
                     repeatRule: "", hits: ["3号"])
        assertResult("买牛奶", title: "买牛奶", date: "", time: "", repeatRule: "", hits: [])
        assertResult("中午12点 吃饭", title: "吃饭", date: "2026-11-13", time: "12:00",
                     repeatRule: "", hits: ["中午12点"])
        assertResult("后天上午十点一刻 面试", title: "面试", date: "2026-11-15", time: "10:15",
                     repeatRule: "", hits: ["后天", "上午十点一刻"])
    }

    // MARK: 日期规则（7 条，顺序敏感）

    func testRelativeAndWeekdayDates() {
        assertResult("大后天 出差", title: "出差", date: "2026-11-16", time: "",
                     repeatRule: "", hits: ["大后天"])
        assertResult("后天 交报告", title: "交报告", date: "2026-11-15", time: "",
                     repeatRule: "", hits: ["后天"])
        assertResult("明晚 看电影", title: "看电影", date: "2026-11-14", time: "",
                     repeatRule: "", hits: ["明晚"])
        assertResult("下下周五 体检", title: "体检", date: "2026-11-27", time: "",
                     repeatRule: "", hits: ["下下周五"])
        assertResult("礼拜三 会议", title: "会议", date: "2026-11-18", time: "",
                     repeatRule: "", hits: ["礼拜三"])
    }

    func testMonthDayAndDayOfMonthIncludingOverflow() {
        assertResult("11月20号 体检", title: "体检", date: "2026-11-20", time: "",
                     repeatRule: "", hits: ["11月20号"])
        assertResult("十一月二十日 体检", title: "体检", date: "2026-11-20", time: "",
                     repeatRule: "", hits: ["十一月二十日"])
        assertResult("2月30日 测试溢出", title: "测试溢出", date: "2027-03-02", time: "",
                     repeatRule: "", hits: ["2月30日"], "JS new Date 越界自动滚月，且早于今天则 +1 年")
        assertResult("13月1日 测试溢出", title: "测试溢出", date: "2027-01-01", time: "",
                     repeatRule: "", hits: ["13月1日"])
        assertResult("二十五号 还款", title: "还款", date: "2026-11-25", time: "",
                     repeatRule: "", hits: ["二十五号"])
    }

    // MARK: 重复规则（10 条）

    func testRepeatDailyRules() {
        assertResult("每天 背单词", title: "背单词", date: "2026-11-13", time: "",
                     repeatRule: "d1", hits: ["每天"])
        assertResult("隔天 跑步", title: "跑步", date: "2026-11-13", time: "",
                     repeatRule: "d2", hits: ["隔天"])
        assertResult("每隔一天 跑步", title: "跑步", date: "2026-11-13", time: "",
                     repeatRule: "d2", hits: ["每隔一天"], "隔一天做一次 = 每 2 天")
        assertResult("每3天 浇花", title: "浇花", date: "2026-11-13", time: "",
                     repeatRule: "d3", hits: ["每3天"])
    }

    func testRepeatWeeklyRules() {
        assertResult("每个工作日9:30站会", title: "站会", date: "2026-11-13", time: "09:30",
                     repeatRule: "w1:12345", hits: ["每个工作日", "9:30"])
        assertResult("每周末 打扫", title: "打扫", date: "2026-11-14", time: "",
                     repeatRule: "w1:06", hits: ["每周末"])
        assertResult("每周一三五 健身", title: "健身", date: "2026-11-13", time: "",
                     repeatRule: "w1:135", hits: ["每周一三五"])
        assertResult("每周 大扫除", title: "大扫除", date: "2026-11-13", time: "",
                     repeatRule: "w1:5", hits: ["每周"], "2026-11-13 是周五，getDay()=5")
        assertResult("隔周五 周会", title: "周会", date: "2026-11-13", time: "",
                     repeatRule: "w2:5", hits: ["隔周五"])
        assertResult("每两周的周二 汇报", title: "汇报", date: "2026-11-17", time: "",
                     repeatRule: "w2:2", hits: ["每两周的周二"])
        assertResult("每周五晚上八点 羽毛球", title: "羽毛球", date: "2026-11-13", time: "20:00",
                     repeatRule: "w1:5", hits: ["每周五", "晚上八点"])
    }

    func testRepeatMonthlyAndYearlyRules() {
        assertResult("每月15号还信用卡", title: "还信用卡", date: "2026-11-15", time: "",
                     repeatRule: "m1", hits: ["每月15号"])
        assertResult("每两个月的1号 理发", title: "理发", date: "2026-12-01", time: "",
                     repeatRule: "m2", hits: ["每两个月的1号"])
        assertResult("每年5月20日 纪念日", title: "纪念日", date: "2027-05-20", time: "",
                     repeatRule: "y1", hits: ["每年5月20日"])
        assertResult("每月 总结", title: "总结", date: "2026-11-13", time: "",
                     repeatRule: "m1", hits: ["每月"])
    }

    func testUntilSuffix() {
        assertResult("每天 背单词 到12月31日", title: "背单词", date: "2026-11-13", time: "",
                     repeatRule: "d1~2026-12-31", hits: ["每天", "到12月31日"])
    }

    // MARK: 时间规则（2 条）与时段进位

    func testTimeRulesAndPeriodCarry() {
        assertResult("9:30 开会", title: "开会", date: "2026-11-13", time: "09:30",
                     repeatRule: "", hits: ["9:30"], "只有 time 没有 date 时补今天")
        assertResult("21：00 看球", title: "看球", date: "2026-11-13", time: "21:00",
                     repeatRule: "", hits: ["21：00"])
        assertResult("3点 开会", title: "开会", date: "2026-11-13", time: "15:00",
                     repeatRule: "", hits: ["3点"], "无时段且 h 在 1~6，默认按下午")
        assertResult("十点一刻 面试", title: "面试", date: "2026-11-13", time: "10:15",
                     repeatRule: "", hits: ["十点一刻"])
        assertResult("8点15 出发", title: "出发", date: "2026-11-13", time: "08:15",
                     repeatRule: "", hits: ["8点15"], "h=8 不在 1~6，不触发默认下午进位")
        assertResult("24点 睡觉", title: "睡觉", date: "2026-11-13", time: "00:00",
                     repeatRule: "", hits: ["24点"])
        assertResult("25点 无效", title: "25点 无效", date: "", time: "",
                     repeatRule: "", hits: [], "h > 24 判废，标题回退原文")
    }

    func testPeriodWordKeptForTimeRules() {
        // DATE_RULES 命中「今晚」但不从标题里删，留给 TIME_RULES 当 PERIOD；hits 两条都要有。
        assertResult("今晚8点半跑步", title: "跑步", date: "2026-11-13", time: "20:30",
                     repeatRule: "", hits: ["今晚", "今晚8点半"])
    }

    // MARK: 已知限制与边界（F-07.7 / A-45 / 空白语义）

    func testChineseOnlyAndASCIIWhitespaceSemantics() {
        assertResult("meeting tomorrow", title: "meeting tomorrow", date: "", time: "",
                     repeatRule: "", hits: [], "英文 UI 下仍只识别中文（A-45）")
        assertResult("call at 9:30", title: "call at", date: "2026-11-13", time: "09:30",
                     repeatRule: "", hits: ["9:30"], "阿拉伯数字时钟表达仍按上游行为识别")
        assertResult("３点开会", title: "３点开会", date: "", time: "",
                     repeatRule: "", hits: [], "JS \\d 只匹配 ASCII，全角数字不识别")
        assertResult("９:３０ 开会", title: "９:３０ 开会", date: "", time: "",
                     repeatRule: "", hits: [])
    }

    func testJSWhitespaceBoundary() {
        assertResult("明天\u{3000}下午3点\u{3000}开会", title: "开会", date: "2026-11-14",
                     time: "15:00", repeatRule: "", hits: ["明天", "下午3点"])
        assertResult("\u{FEFF}明天下午3点开会", title: "开会", date: "2026-11-14",
                     time: "15:00", repeatRule: "", hits: ["明天", "下午3点"])
        // U+200B 不是 JS 的 WhiteSpace：既不被 \s+ 折叠，也不被 trim() 裁掉。
        // ICU 的 \s 会误判它，实现里已改用 ES spec 的显式字符类。
        assertResult("明天\u{200B}下午3点开会", title: "\u{200B} 开会", date: "2026-11-14",
                     time: "15:00", repeatRule: "", hits: ["明天", "下午3点"])
    }

    func testTitleCollapseAndFallback() {
        assertResult("  明天  下午3点  开会  ", title: "开会", date: "2026-11-14",
                     time: "15:00", repeatRule: "", hits: ["明天", "下午3点"])
        XCTAssertEqual(parse("明天下午3点").title, "明天下午3点", "标题被删空时回退原始输入")
        XCTAssertEqual(parse("   ").title, "", "纯空白输入回退为原始输入的 trim")
    }

    func testRepeatSuppressesDateRulesAndHitsOrder() {
        // 命中重复规则后不再执行 DATE_RULES；hits 顺序为 repeat → until → time。
        assertResult("每周一 9:30 站会 到12月31日", title: "站会", date: "2026-11-16",
                     time: "09:30", repeatRule: "w1:1~2026-12-31",
                     hits: ["每周一", "到12月31日", "9:30"])
    }

    // MARK: 全量黄金夹具（随 test target 打包，真机上也跑全量，不只靠 Mac harness）

    private struct ParseFixtures: Decodable {
        struct Meta: Decodable {
            let baseline_commit: String
            let case_count: Int
            let self_test_count: Int
        }
        struct Case: Decodable {
            let text: String
            let title: String
            let date: String
            let time: String
            let repeatRule: String
            let hits: [String]
            enum CodingKeys: String, CodingKey {
                case text, title, date, time, hits
                case repeatRule = "repeat"
            }
        }
        let meta: Meta
        let cases: [Case]
    }

    func testFullFixtureContrast() throws {
        guard let url = Bundle(for: T08NaturalLanguageParserTests.self)
            .url(forResource: "parse_fixtures", withExtension: "json") else {
            XCTFail("parse_fixtures.json 未随测试 target 打包")
            return
        }
        let f = try JSONDecoder().decode(ParseFixtures.self, from: Data(contentsOf: url))
        XCTAssertEqual(f.meta.baseline_commit, "97a7c4c17602327a42d30110806a6a1e6fa0e798")
        XCTAssertEqual(f.meta.self_test_count, 25, "OPEN-08=A 的 25 条 selfTest")

        var checked = 0
        var failures: [String] = []
        for c in f.cases {
            let r = parse(c.text)
            let pairs: [(String, String, String)] = [
                ("title", c.title, r.title), ("date", c.date, r.date),
                ("time", c.time, r.time), ("repeat", c.repeatRule, r.repeatRule),
                ("hits", c.hits.joined(separator: "|"), r.hits.joined(separator: "|")),
            ]
            for (field, expected, actual) in pairs {
                checked += 1
                if expected != actual {
                    failures.append("\(c.text) / \(field): expected=\(expected) actual=\(actual)")
                }
            }
        }
        XCTAssertEqual(f.cases.count, f.meta.case_count)
        XCTAssertTrue(failures.isEmpty,
                      "\(failures.count)/\(checked) 项不一致：\n" + failures.prefix(10).joined(separator: "\n"))
    }
}
