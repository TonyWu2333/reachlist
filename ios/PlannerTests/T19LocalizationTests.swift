import XCTest
import Foundation
@testable import Planner

// T-19 / M-23 全量本地化契约测试。
// 期望值取自 baseline_commit 97a7c4c 的真实源码 oracle：
//   node ios/PlannerTests/Fixtures/generate_t19_fixtures.mjs
// 生成器直接 import src/lib/i18n-en*.js（211 个最终生效词条），并以只替换 3 处环境依赖的
// src/lib/i18n.js 运行副本执行 t / applyLang / plural，词条与函数体逐字未改。
//
// 覆盖：1688 条中英词条（含 19 条函数值、复数、占位符）、缺失回退、语言判定与跟随、
// 术语表、全部界面调用点无缺失、settings.lang 落盘与不进同步载荷（A-05 / A-43 / A-45）。

final class T19LocalizationTests: XCTestCase {

    private func root() throws -> [String: Any] {
        guard let url = Bundle(for: T19LocalizationTests.self)
            .url(forResource: "t19_fixtures", withExtension: "json") else {
            XCTFail("t19_fixtures.json 未随测试 target 打包")
            return [:]
        }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    /// 夹具 params 中的数字（JS number）要转成字符串，Swift 侧 fill 只吃 [String: String]。
    private func params(_ raw: [String: Any]?) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in raw ?? [:] {
            switch v {
            case let s as String: out[k] = s
            case let n as NSNumber: out[k] = n.stringValue
            default: out[k] = "\(v)"
            }
        }
        return out
    }

    private func str(_ v: Any?) -> String { v as? String ?? "" }
    private func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }

    // MARK: 全量词条

    /// 1688 项逐字对比（211 key × 4 组参数 × 中英），非 vacuous。
    func testFullFixtureContrast() throws {
        let r = try root()
        let entries = r["entries"] as! [[String: Any]]
        XCTAssertGreaterThan(entries.count, 1600, "夹具条数异常，可能是生成器退化为 vacuous 通过")

        var failures: [String] = []
        for e in entries {
            let key = str(e["key"])
            let lang = str(e["lang"])
            let expected = str(e["expected"])
            let got = LocalizationService.t(key, lang: lang, params(e["params"] as? [String: Any]))
            if got != expected {
                failures.append("[\(lang)] \(key) params=\(e["params"] ?? [:]) → got=\(got) expected=\(expected)")
            }
        }
        XCTAssertTrue(failures.isEmpty,
                      "\(failures.count)/\(entries.count) 条不一致：\n" + failures.prefix(20).joined(separator: "\n"))
    }

    /// 上游全部 211 个 key 都能被服务解析（纯字符串 / 函数值 / DEV 三选一）。
    func testAllUpstreamKeysResolvable() throws {
        let r = try root()
        let keys = r["dictionaryKeys"] as! [String]
        XCTAssertEqual(keys.count, 211)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(LocalizationService.businessKeyCount, keys.count)
        for key in keys {
            XCTAssertTrue(LocalizationService.hasEntry(key), "上游词条未被 Swift 侧登记：\(key)")
        }
        let functionKeys = r["functionKeys"] as! [String]
        XCTAssertEqual(functionKeys.count, 19)
        for key in functionKeys {
            XCTAssertNotNil(LocalizationFunctions.evaluate(key, [:]), "函数值词条未实现：\(key)")
        }
    }

    /// 全界面调用点（含自检页 DEV 词条）无缺失，切换英文不会出现硬编码中文。
    func testAllCallSiteKeysResolve() throws {
        let r = try root()
        let keys = r["callSiteKeys"] as! [String]
        XCTAssertGreaterThan(keys.count, 100)
        for key in keys {
            XCTAssertTrue(LocalizationService.hasEntry(key), "界面调用点缺词条：\(key)")
        }
        let devOnly = r["callSiteNotUpstream"] as! [String]
        XCTAssertEqual(devOnly.count, 26)
        XCTAssertEqual(LocalizationService.devKeyCount, 30)
    }

    /// i18n.js:21-28 —— 缺失回退中文、未知占位符保留、中文路径不查词典。
    func testMissingKeyFallback() throws {
        let r = try root()
        let cases = r["missingCases"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 5)
        for c in cases {
            let got = LocalizationService.t(str(c["key"]), lang: str(c["lang"]),
                                            params(c["params"] as? [String: Any]))
            XCTAssertEqual(got, str(c["expected"]), "key=\(str(c["key"]))")
        }
    }

    // MARK: 语言判定 / 复数 / 术语表

    /// applyLang + systemLang 的 40 组（含 zhHans / ZH-tw / 空系统语言 / 脏偏好）。
    func testLanguageResolution() throws {
        let r = try root()
        let cases = r["langCases"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 40)
        for c in cases {
            let got = LocalizationService.effectiveLang(str(c["pref"]), system: str(c["system"]))
            XCTAssertEqual(got, str(c["expected"]), "system=\(str(c["system"])) pref=\(str(c["pref"]))")
            XCTAssertEqual(LocalizationService.htmlLang(got), str(c["htmlLang"]))
        }
        XCTAssertTrue(LocalizationService.isZhLanguage("zh-Hans"))
        XCTAssertFalse(LocalizationService.isZhLanguage("zhHans"))
    }

    func testPluralCases() throws {
        let r = try root()
        let cases = r["pluralCases"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 8)
        for c in cases {
            let many = c["many"] as? String
            let got = LocalizationService.plural(int(c["n"]), str(c["one"]), many)
            XCTAssertEqual(got, str(c["expected"]))
        }
    }

    /// i18n-en.js 顶部 Glossary 的固定译法，不允许界面另造词。
    func testGlossaryCases() throws {
        let r = try root()
        let cases = r["glossaryCases"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 15)
        for c in cases {
            XCTAssertEqual(LocalizationService.t(str(c["key"]), lang: "en"), str(c["expected"]))
        }
    }

    /// 旧入口仍可用，且切换偏好即时改变输出（VERIFY-09 的即时刷新机制）。
    func testLegacyEntryPointsAndImmediateSwitch() {
        XCTAssertEqual(AppStrings.t("日程", lang: AppStrings.effectiveLang(.auto, system: "zh-CN")), "日程")
        XCTAssertEqual(AppStrings.t("日程", lang: AppStrings.effectiveLang(.en, system: "zh-CN")), "Calendar")
        XCTAssertEqual(FeatureStrings.t("已完成 {n} 次", lang: "en", ["n": "1"]), "Done once")
        XCTAssertEqual(FeatureStrings.s("会替换当前全部 {n} 条任务", "en", ["n": "3"]),
                       "Replaces all 3 current tasks")
        XCTAssertEqual(CalendarStrings.postponed("Tomorrow", lang: "en"), "Postponed to tomorrow")
        XCTAssertEqual(AppStrings.fill("共 {n} 项 / {unknown}", ["n": "3"]), "共 3 项 / {unknown}")
    }

    // MARK: settings.lang 落盘（A-05 / A-45）

    @MainActor
    func testSettingsLangPersistsAndLegacyFallsBackToAuto() throws {
        let storage = InMemoryPlannerDataStorage()
        let store = CalendarDataStore(settingsStorage: storage)
        XCTAssertEqual(store.settings.lang, .auto)

        store.settings.lang = .en
        let raw = storage.values["planner-settings"] ?? ""
        let obj = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
        XCTAssertEqual(Set(obj.keys), Set([
            "lang", "showLunar", "showHoliday", "remindOn",
            "defaultRemind", "syncOn", "syncCode",
        ]))
        XCTAssertEqual(obj["lang"] as? String, "en")

        let reloaded = CalendarDataStore(settingsStorage: storage)
        XCTAssertEqual(reloaded.settings.lang, .en)

        // 旧设置对象缺 lang → 'auto'，其余已存字段不受影响（store.js:Object.assign 语义）。
        let legacy = InMemoryPlannerDataStorage(
            settings: "{\"showLunar\":false,\"syncOn\":true,\"syncCode\":\"http://x#1234567890123456\"}")
        let old = CalendarDataStore(settingsStorage: legacy)
        XCTAssertEqual(old.settings.lang, .auto)
        XCTAssertFalse(old.settings.showLunar)
        XCTAssertTrue(old.settings.syncOn)
        XCTAssertEqual(old.settings.syncCode, "http://x#1234567890123456")
    }

    /// A-45：lang 只写 planner-settings，同步载荷只有 tasks / deleted / meta.tz。
    @MainActor
    func testLangIsNotInSyncPayload() {
        let store = TaskStore(storage: InMemoryPlannerDataStorage())
        let text = String(data: SyncPayloadCodec.encode(store.syncPayload(), tz: "Asia/Shanghai"),
                          encoding: .utf8)!
        XCTAssertTrue(PlannerSettings.defaults.jsJSONString.contains("\"lang\""))
        XCTAssertFalse(text.contains("lang"), "同步载荷不应包含语言偏好：\(text)")
        XCTAssertTrue(text.contains("\"meta\""))
        XCTAssertTrue(text.hasPrefix("{\"tasks\":"))
    }
}
