import XCTest
import Foundation
@testable import Planner

// T-16 / M-11 + M-12 + M-16 + M-17 契约测试。
// 期望值取自 baseline_commit 97a7c4c 的真实源码 oracle：
//   node ios/PlannerTests/Fixtures/generate_t16_fixtures.mjs
// 生成器直接 import src/lib/{date,repeat,quadrant,i18n}.js 与 i18n-en*.js，
// 四个 Vue 视图的 computed 按源码逐行复刻；本文件把 Swift 契约与夹具逐项对比。
//
// 覆盖：象限分组/计数/范围、打卡 6 组与今日概览、搜索分词/排序/高亮/备注片段/副标题、
// 「我的」概览三项统计/近 7 天/语言循环/同步状态、全部中英词条（含函数值），
// 以及拖拽状态机与路由默认值等非夹具语义。

final class T16ContractTests: XCTestCase {

    private let today = "2026-11-13"

    private func root() throws -> [String: Any] {
        guard let url = Bundle(for: T16ContractTests.self)
            .url(forResource: "t16_fixtures", withExtension: "json") else {
            XCTFail("t16_fixtures.json 未随测试 target 打包")
            return [:]
        }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    private func tasks(_ root: [String: Any]) -> [PlannerTask] {
        (root["tasks"] as! [[String: Any]]).map {
            PlannerTask.normalize($0, now: 1_763_025_600_000)
        }
    }

    /// 夹具 params 里数字也要转成字符串（Swift 侧的 fill 只吃 [String: String]）。
    private func params(_ raw: [String: Any]?) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in raw ?? [:] {
            switch v {
            case let s as String: out[k] = s
            case let n as NSNumber: out[k] = n.stringValue
            case let b as Bool: out[k] = b ? "true" : "false"
            default: out[k] = "\(v)"
            }
        }
        return out
    }

    private func str(_ v: Any?) -> String { v as? String ?? "" }
    private func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
    private func bool(_ v: Any?) -> Bool { (v as? NSNumber)?.boolValue ?? false }
    private func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }

    private func assertClose(_ a: Double, _ b: Double, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(abs(a - b), 0.000001, label, file: file, line: line)
    }

    // MARK: F-04 四象限

    func testQuadrantGroupsAndCounts() throws {
        let r = try root()
        let list = tasks(r)
        let cases = r["quadrant"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 6)
        var checked = 0
        for c in cases {
            let range = QuadrantRange(rawValue: str(c["range"]))!
            let showDone = bool(c["showDone"])
            let g = QuadrantContract.groups(list, range: range, showDone: showDone, today: today)
            let expectGroups = c["groups"] as! [String: [String]]
            let expectCounts = c["counts"] as! [String: Int]
            for q in 1...4 {
                let key = String(q)
                XCTAssertEqual(g[q]?.map(\.id) ?? [], expectGroups[key] ?? [],
                               "\(str(c["range"]))/done=\(showDone)/q\(q)")
                XCTAssertEqual(QuadrantContract.openCount(g[q] ?? []), expectCounts[key] ?? -1,
                               "\(str(c["range"]))/done=\(showDone)/q\(q) 未完成计数")
                checked += 2
            }
        }
        XCTAssertEqual(checked, 48)
    }

    func testQuadrantRangeBoundariesAndFlags() {
        let mk = { (date: String) -> PlannerTask in
            PlannerTask.normalize(["id": "x", "title": "x", "date": date], now: 0)
        }
        XCTAssertTrue(QuadrantContract.inRange(mk(""), range: .today, today: today), "无日期任何范围都显示")
        XCTAssertTrue(QuadrantContract.inRange(mk("2026-11-01"), range: .today, today: today), "今天含逾期")
        XCTAssertFalse(QuadrantContract.inRange(mk("2026-11-14"), range: .today, today: today))
        XCTAssertTrue(QuadrantContract.inRange(mk("2026-11-15"), range: .week, today: today), "本周到周日")
        XCTAssertFalse(QuadrantContract.inRange(mk("2026-11-16"), range: .week, today: today))
        XCTAssertEqual(QuadrantContract.flags(1).important, true)
        XCTAssertEqual(QuadrantContract.flags(3).important, false)
        XCTAssertEqual(QuadrantContract.flags(4).urgent, false)
        XCTAssertEqual(QuadrantContract.emptyText[1], "没有需要马上处理的事")
        XCTAssertEqual(QuadrantContract.pressMilliseconds, 340)
        XCTAssertEqual(QuadrantContract.pressCancelDistance, 8)
        XCTAssertEqual(QuadrantContract.dropGuardMilliseconds, 300)
    }

    func testDragStateMachine() {
        var s = QuadrantContract.DragState()
        s.pressedID = "a"
        s.moved(distance: 9)
        XCTAssertNil(s.draggingID, "超过 8pt 取消长按")
        s.longPressFired(id: "a")
        XCTAssertFalse(s.isDragging)

        s = QuadrantContract.DragState()
        s.pressedID = "a"
        s.moved(distance: 8)
        s.longPressFired(id: "a")
        XCTAssertTrue(s.isDragging)
        XCTAssertTrue(s.updateDrop(2))
        XCTAssertFalse(s.updateDrop(2))
        let drop = s.end()
        XCTAssertEqual(drop?.id, "a")
        XCTAssertEqual(drop?.q, 2)
        XCTAssertNil(s.draggingID)
        XCTAssertEqual(s.dropQ, 0)
        let t = PlannerTask.normalize(["id": "a", "title": "a"], now: 0)
        XCTAssertTrue(QuadrantContract.shouldMove(t, to: 2))
        XCTAssertFalse(QuadrantContract.shouldMove(t, to: 4))
        XCTAssertFalse(QuadrantContract.shouldMove(nil, to: 2))
        XCTAssertEqual(QuadrantContract.movedText(4, lang: "zh"), "已移到「不重要不紧急」")
        XCTAssertEqual(QuadrantContract.movedText(4, lang: "en"), "Moved to “Neither”")
    }

    /// 回归：长按起手位置必须是任务行中心，不能是网格中心。
    /// 旧实现直接写 `gridSize/2`，长按瞬间卡片会蹦到屏幕正中（用户 2026-11-14 报的缺陷）。
    func testDragGhostStartsAtRowCenter() {
        let grid = CGSize(width: 430, height: 700)
        let row = CGRect(x: 12, y: 120, width: 199, height: 40)
        let origin = QuadrantContract.ghostOrigin(rowFrame: row, grid: grid)
        XCTAssertEqual(origin.x, 111.5, accuracy: 0.01)
        XCTAssertEqual(origin.y, 140, accuracy: 0.01)
        XCTAssertNotEqual(origin, CGPoint(x: grid.width / 2, y: grid.height / 2),
                          "起手位置不能退回网格中心")

        // 行还没布局完（拿不到 frame / 尺寸为 0）时才退回网格中心。
        let center = CGPoint(x: grid.width / 2, y: grid.height / 2)
        XCTAssertEqual(QuadrantContract.ghostOrigin(rowFrame: nil, grid: grid), center)
        XCTAssertEqual(QuadrantContract.ghostOrigin(rowFrame: .zero, grid: grid), center)
    }

    // MARK: F-05 打卡

    func testRoutineGroupsAndSummary() throws {
        let r = try root()
        let list = tasks(r)
        let cases = r["routine"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 2)
        let groups = RoutineContract.groups(list, today: today)
        let sum = RoutineContract.summary(list, today: today, lang: "zh")
        for c in cases {
            let lang = str(c["lang"])
            let s = RoutineContract.summary(list, today: today, lang: lang)
            XCTAssertEqual(s.headline, str(c["headline"]), "headline/\(lang)")
            XCTAssertEqual(s.detail, str(c["detail"]), "detail/\(lang)")
            assertClose(RoutineContract.progress(list, today: today), num(c["progress"]), "progress/\(lang)")
            let expect = c["groups"] as! [[String: Any]]
            XCTAssertEqual(groups.map(\.key), expect.map { str($0["key"]) }, "分组顺序")
            for (i, g) in groups.enumerated() {
                let eg = expect[i]
                XCTAssertEqual(g.key, str(eg["key"]))
                XCTAssertEqual(FeatureStrings.t(g.labelKey, lang: lang), str(eg["labelText"]), "组名/\(g.key)/\(lang)")
                let items = eg["items"] as! [[String: Any]]
                XCTAssertEqual(g.items.count, items.count, "\(g.key) 条数")
                for (j, item) in g.items.enumerated() {
                    let e = items[j]
                    XCTAssertEqual(item.task.id, str(e["id"]), "\(g.key)[\(j)].id")
                    XCTAssertEqual(item.occ, str(e["occ"]), "\(g.key)[\(j)].occ")
                    XCTAssertEqual(item.isToday, bool(e["isToday"]), "\(g.key)[\(j)].isToday")
                    XCTAssertEqual(item.streak, int(e["streak"]), "\(g.key)[\(j)].streak")
                    XCTAssertEqual(item.unit, str(e["unit"]), "\(g.key)[\(j)].unit")
                    XCTAssertEqual(item.task.date, str(e["date"]), "\(g.key)[\(j)].date")
                    XCTAssertEqual(item.task.done, bool(e["done"]), "\(g.key)[\(j)].done")
                }
            }
        }
        _ = sum
        XCTAssertEqual(RoutineContract.skipText(occ: today, today: today, lang: "zh"), "今天这次已跳过")
        XCTAssertEqual(RoutineContract.skipText(occ: "2026-11-14", today: today, lang: "en"), "Skipped the next one")
        XCTAssertEqual(RoutineContract.deleteText(title: "周会", kids: 0, lang: "zh"), "已删除「周会」")
        XCTAssertEqual(RoutineContract.deleteText(title: "周会", kids: 1, lang: "en"), "Deleted “周会” and 1 subtask")
    }

    // MARK: F-08 搜索

    func testSearchFixtureContrast() throws {
        let r = try root()
        let list = tasks(r)
        let cases = r["search"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 18)
        for c in cases {
            let q = str(c["q"]), lang = str(c["lang"])
            let res = SearchContract.results(list, query: q)
            XCTAssertEqual(res.open.map(\.id), c["open"] as! [String], "open/\(q)/\(lang)")
            XCTAssertEqual(res.done.map(\.id), c["done"] as! [String], "done/\(q)/\(lang)")
            let hit = res.open + res.done
            let expectMarks = c["marks"] as! [[String: Any]]
            let actualMarks: [[String: Any]] = hit.isEmpty ? [] : SearchContract.marks(hit[0].title, query: q).map {
                ["text": $0.text, "hit": $0.hit]
            }
            XCTAssertEqual(actualMarks.count, expectMarks.count, "marks 段数/\(q)/\(lang)")
            for (i, m) in actualMarks.enumerated() where i < expectMarks.count {
                XCTAssertEqual(str(m["text"]), str(expectMarks[i]["text"]), "marks[\(i)].text/\(q)")
                XCTAssertEqual(bool(m["hit"]), bool(expectMarks[i]["hit"]), "marks[\(i)].hit/\(q)")
            }
            let snippet = hit.isEmpty ? "" : SearchContract.noteSnippet(hit[0].note, query: q)
            XCTAssertEqual(snippet, str(c["snippet"]), "snippet/\(q)/\(lang)")
            let subs = hit.prefix(4).map { SearchContract.sub($0, tasks: list, lang: lang, today: today) }
            XCTAssertEqual(subs, c["subs"] as! [String], "subs/\(q)/\(lang)")
            XCTAssertEqual(SearchContract.noResultText(q, lang: lang), str(c["noResult"]), "noResult/\(q)/\(lang)")
        }
    }

    func testWhitespaceAndHighlightEdgeCases() {
        XCTAssertEqual(SearchContract.terms("  Ab\u{00A0}  cd "), ["ab", "cd"])
        XCTAssertEqual(SearchContract.terms(""), [])
        XCTAssertEqual(SearchContract.terms("a\u{200B}b"), ["a\u{200B}b"], "U+200B 不是 ES 空白")
        XCTAssertEqual(SearchContract.marks("", query: "x"), [])
        XCTAssertEqual(SearchContract.trimmed("  hi  "), "hi")
    }

    // MARK: F-09 我的

    func testMeFixtureContrast() throws {
        let r = try root()
        let list = tasks(r)
        let cases = r["me"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 2)
        for c in cases {
            let lang = str(c["lang"])
            let greetings = [2, 8, 12, 15, 20].map { MeContract.greeting(hour: $0, lang: lang) }
            XCTAssertEqual(greetings, c["greetings"] as! [String], "greetings/\(lang)")
            XCTAssertEqual(MeContract.summary(list, today: today, lang: lang), str(c["summary"]), "summary/\(lang)")
            XCTAssertEqual(MeContract.doneTotalText(list, today: today, lang: lang), str(c["doneTotal"]), "doneTotal/\(lang)")
            assertClose(MeContract.ratio(list, today: today), num(c["ratio"]), "ratio/\(lang)")
            XCTAssertEqual(MeContract.weekDone(list, today: today), int(c["weekDone"]), "weekDone/\(lang)")
            XCTAssertEqual(MeContract.pendingAll(list, today: today), int(c["pendingAll"]), "pendingAll/\(lang)")
            XCTAssertEqual(MeContract.overdue(list, today: today), int(c["overdue"]), "overdue/\(lang)")
            let bars = MeContract.last7(list, today: today, lang: lang)
            let expect = c["last7"] as! [[String: Any]]
            XCTAssertEqual(bars.count, 7)
            for (i, b) in bars.enumerated() {
                XCTAssertEqual(b.day, str(expect[i]["d"]), "last7[\(i)].day")
                XCTAssertEqual(b.count, int(expect[i]["n"]), "last7[\(i)].count/\(lang)")
                assertClose(b.height, num(expect[i]["h"]), "last7[\(i)].height/\(lang)")
                XCTAssertEqual(b.label, str(expect[i]["label"]), "last7[\(i)].label/\(lang)")
            }
            XCTAssertEqual(MeContract.last7Total(bars, lang: lang), str(c["last7Total"]), "last7Total/\(lang)")
            XCTAssertEqual(MeContract.langs.map { MeContract.langLabel($0, lang: lang) },
                           c["langLabels"] as! [String], "langLabels/\(lang)")
            XCTAssertEqual(FeatureStrings.t("会替换当前全部 {n} 条任务", lang: lang,
                                            ["n": String(list.count)]), str(c["replaceHint"]), "replaceHint/\(lang)")
        }
    }

    func testSyncStatusAllBranches() throws {
        let r = try root()
        let cases = r["sync"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 32)
        for c in cases {
            let s = c["settings"] as! [String: Any]
            let st = c["state"] as! [String: Any]
            var settings = UISettings()
            settings.syncOn = bool(s["syncOn"])
            settings.syncCode = str(s["syncCode"])
            var state = SyncState()
            state.busy = bool(st["busy"])
            state.error = str(st["error"])
            state.at = num(st["at"])
            XCTAssertEqual(MeContract.syncStatus(settings: settings, state: state, lang: str(c["lang"])),
                           str(c["status"]), "sync/\(str(c["lang"]))/\(str(s["syncCode"]))/\(str(st["error"]))")
        }
    }

    func testSettingsCyclesAndPrivacy() {
        XCTAssertEqual(MeContract.cycleLang(.auto), .zh)
        XCTAssertEqual(MeContract.cycleLang(.zh), .en)
        XCTAssertEqual(MeContract.cycleLang(.en), .auto)
        XCTAssertEqual(MeContract.cycleDefaultRemind(0), 5)
        XCTAssertEqual(MeContract.cycleDefaultRemind(60), 0)
        XCTAssertEqual(MeContract.cycleDefaultRemind(7), 0, "indexOf 找不到时 -1 → 第 0 项")
        XCTAssertEqual(MeContract.remindText(nil, remindOn: true, hasTime: false, lang: "zh"), "先设时间")
        XCTAssertEqual(MeContract.remindText(15, remindOn: false, hasTime: true, lang: "en"), "All reminders off")
        XCTAssertEqual(MeContract.remindText(15, remindOn: true, hasTime: true, lang: "en"), "15 minutes before")
        XCTAssertEqual(MeContract.privacyText(syncOn: false, lang: "zh").title, "数据只保存在本机")
        XCTAssertEqual(MeContract.versionText("1.2.3"), "可及清单 · v1.2.3", "A-36 应用名不翻译")
        XCTAssertTrue(MeContract.codeOk("http://192.168.1.5:18787#abcdefghijklmnop"))
        XCTAssertEqual(MeContract.syncHost("http://192.168.1.5:18787#abcdefghijklmnop"), "192.168.1.5:18787")
    }

    // MARK: 中英词条全量（含 i18n-en 的函数值）

    func testAllStrings() throws {
        let r = try root()
        let cases = r["strings"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 138)
        var failures: [String] = []
        for c in cases {
            let key = str(c["key"]), lang = str(c["lang"]), expected = str(c["value"])
            let actual = FeatureStrings.t(key, lang: lang, params(c["params"] as? [String: Any]))
            if actual != expected { failures.append("\(lang)/\(key): expected=\(expected) actual=\(actual)") }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    // MARK: 路由默认值（App.vue:openQuick）

    func testQuickAddDefaultsRouting() {
        XCTAssertEqual(QuickAddDefaults.empty, QuickAddDefaults())
        XCTAssertEqual(QuickAddDefaults.onDate(today).date, today)
        XCTAssertNil(QuickAddDefaults.onDate(today).quadrant)
        XCTAssertEqual(QuickAddDefaults.inQuadrant(1, date: today).quadrant, 1)
        XCTAssertEqual(QuickAddDefaults.routine().repeatRule, "d1")
        XCTAssertNil(QuickAddDefaults.routine().date)
        XCTAssertEqual(DetailRoute(id: "x").occ, "")
        XCTAssertEqual(AppTab.allCases.count, 4)
    }
}
