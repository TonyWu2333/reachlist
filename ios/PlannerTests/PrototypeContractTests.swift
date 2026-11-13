import XCTest
@testable import Planner

// T-03 原型 / VERIFY-09 契约黄金测试。
// fixture 生成命令：node /tmp/planner_i18n_oracle.mjs
// oracle 为 baseline_commit 97a7c4c 的 src/lib/i18n.js + i18n-en.js；
// 运行副本只替换 vue 的 reactive 与 import.meta.env.DEV 两处 Vite 环境依赖，
// 词条与逻辑源码未改。共 11 组用例 × zh/en = 22 条期望值。
@MainActor
final class LocalizationContractTests: XCTestCase {
    private struct Case {
        let zh: String
        let p: [String: String]
        let zhValue: String
        let enValue: String
    }

    private let cases: [Case] = [
        .init(zh: "可及清单", p: [:], zhValue: "可及清单", enValue: "Reach List"),
        .init(zh: "四象限", p: [:], zhValue: "四象限", enValue: "Matrix"),
        .init(zh: "撤销", p: [:], zhValue: "撤销", enValue: "Undo"),
        .init(zh: "不提醒", p: [:], zhValue: "不提醒", enValue: "No reminder"),
        .init(zh: "提前 {n} 小时", p: ["n": "1"], zhValue: "提前 1 小时", enValue: "1 hour before"),
        .init(zh: "提前 {n} 小时", p: ["n": "3"], zhValue: "提前 3 小时", enValue: "3 hours before"),
        .init(zh: "服务器返回 {code}", p: ["code": "500"], zhValue: "服务器返回 500", enValue: "Server returned 500"),
        .init(zh: "已恢复 {n} 条任务", p: ["n": "1"], zhValue: "已恢复 1 条任务", enValue: "Restored 1 task"),
        .init(zh: "已恢复 {n} 条任务", p: ["n": "5"], zhValue: "已恢复 5 条任务", enValue: "Restored 5 tasks"),
        .init(zh: "用备份里的 {a} 条任务替换当前的 {b} 条？", p: ["a": "3", "b": "7"],
              zhValue: "用备份里的 3 条任务替换当前的 7 条？",
              enValue: "Replace your 7 tasks with the 3 tasks in the backup?"),
        .init(zh: "共 {n} 项", p: ["n": "2"], zhValue: "共 2 项", enValue: "共 2 项"),
    ]

    func testMatchesJSOracle() {
        let loc = LocalizationProbe()
        for c in cases {
            loc.pref = .zh
            XCTAssertEqual(loc.t(c.zh, c.p), c.zhValue, "zh 不一致: \(c.zh)")
            loc.pref = .en
            XCTAssertEqual(loc.t(c.zh, c.p), c.enValue, "en 不一致: \(c.zh)")
        }
    }

    func testMissingEntryFallsBackToChineseAndIsCounted() {
        let loc = LocalizationProbe()
        loc.pref = .en
        XCTAssertEqual(loc.t("共 {n} 项", ["n": "2"]), "共 2 项")
        XCTAssertEqual(loc.missingCount, 1)
        XCTAssertEqual(loc.missingKeys, ["共 {n} 项"])
    }

    func testFillKeepsUnknownPlaceholder() {
        let loc = LocalizationProbe()
        loc.pref = .zh
        XCTAssertEqual(loc.t("服务器返回 {code}", ["x": "1"]), "服务器返回 {code}")
        loc.pref = .en
        XCTAssertEqual(loc.t("服务器返回 {code}", ["x": "1"]), "Server returned {code}")
    }

    func testPluralHelperMatchesJS() {
        XCTAssertEqual(LocalizationProbe.plural(1, "task"), "1 task")
        XCTAssertEqual(LocalizationProbe.plural(3, "task"), "3 tasks")
        XCTAssertEqual(LocalizationProbe.plural(2, "person", "people"), "2 people")
    }

    func testSystemLanguageBoundaryMatchesJSRegex() {
        XCTAssertTrue(LocalizationProbe.isZhLanguage("zh-CN"))
        XCTAssertTrue(LocalizationProbe.isZhLanguage("zh"))
        XCTAssertTrue(LocalizationProbe.isZhLanguage("ZH-hans"))
        XCTAssertFalse(LocalizationProbe.isZhLanguage("en-US"))
        XCTAssertFalse(LocalizationProbe.isZhLanguage("zhHans"))
    }

    func testAutoFollowsSystemAndSwitchIsImmediate() {
        let loc = LocalizationProbe()
        XCTAssertEqual(loc.pref, .auto)
        XCTAssertEqual(loc.effective, LocalizationProbe.systemLang())
        loc.pref = .en
        XCTAssertEqual(loc.effective, "en")
        loc.pref = .zh
        XCTAssertEqual(loc.effective, "zh")
        loc.pref = .auto
        XCTAssertEqual(loc.effective, LocalizationProbe.systemLang())
    }
}

// VERIFY-03：真机实测 ATS 对明文 http:// 的拦截行为。
// T-10（v0.24）起 example.com 已被 OPEN-06=B 的最小例外放行，故这里改用
// **未被例外覆盖的子域** www.example.com：既保留「域名明文 HTTP 被 -1022 拒绝」的
// 原始断言，又顺带验证该例外不含 NSIncludesSubdomains、确实是最小配置。
final class ATSProbeContractTests: XCTestCase {
    /// 实测（iOS 27.3 beta）：无例外的域名明文 HTTP 被 ATS 以 -1022 拒绝。
    func testPlainHTTPDomainIsRejectedByATS() async {
        let r = await ATSProbe.request(ATSProbe.publicHTTPSubdomain, timeout: 6)
        print("ATS-PROBE-TEST \(r.url) | \(r.description)")
        print("ATS-ERROR-CODE \(r.errorCode.map(String.init) ?? "none")")
        XCTAssertFalse(r.succeeded)
        XCTAssertEqual(r.errorCode, -1022,
                       "无例外的域名明文 HTTP 应被 NSURLErrorAppTransportSecurityRequiresSecureConnection (-1022) 拒绝")
    }

    /// 实测：裸 IP 主机不受 -1022 拦截（本地服务可达时 HTTP 200，不可达时 -1004，
    /// 两者都不是 ATS 拒绝）。断言不依赖本机 server 是否运行，保证可复现。
    func testPlainHTTPToIPAddressIsNotRejectedByATS() async {
        let r = await ATSProbe.request(ATSProbe.lanHTTP, timeout: 6)
        print("ATS-PROBE-TEST \(r.url) | \(r.description)")
        XCTAssertNotEqual(r.errorCode, -1022,
                          "裸 IP 明文 HTTP 不应被 ATS 以 -1022 拒绝；实测为 HTTP 200 或 -1004")
    }
}
