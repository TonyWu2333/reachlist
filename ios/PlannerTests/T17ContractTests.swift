import XCTest
import Foundation
@testable import Planner

// T-17 / M-13 + M-14 契约测试。
// 期望值取自 baseline_commit 97a7c4c 的真实源码 oracle：
//   node ios/PlannerTests/Fixtures/generate_t17_fixtures.mjs
// 生成器直接 import src/lib/{parse,date,repeat,quadrant,i18n}.js 与 i18n-en*.js；
// QuickAdd.vue:32-122 / TaskDetail.vue:28-219 的 computed 按源码逐行复刻。
//
// 覆盖：快速添加的识别/手改覆盖/提示拆分/提交字段/三种 toast，
// 任务详情的导航栈与 occ、完成/放弃判定、日期与页脚文案、五个面板值、四种删除文案、
// 全部中英词条（含函数值）。

final class T17ContractTests: XCTestCase {

    private let today = "2026-11-13"

    private lazy var now: Date = {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 11; dc.day = 13; dc.hour = 12; dc.minute = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: dc)!
    }()

    private func root() throws -> [String: Any] {
        guard let url = Bundle(for: T17ContractTests.self)
            .url(forResource: "t17_fixtures", withExtension: "json") else {
            XCTFail("t17_fixtures.json 未随测试 target 打包")
            return [:]
        }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    private func tasks(_ root: [String: Any]) -> [PlannerTask] {
        (root["tasks"] as! [[String: Any]]).map {
            PlannerTask.normalize($0, now: 1_763_025_600_000)
        }
    }

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
    private func bool(_ v: Any?) -> Bool { (v as? NSNumber)?.boolValue ?? false }
    private func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }

    // MARK: F-07 快速添加

    private func state(for c: [String: Any]) -> QuickAddState {
        let d = c["defaults"] as? [String: Any]
        var defaults = QuickAddDefaults()
        if let d {
            if let v = d["date"] as? String { defaults.date = v }
            if let v = d["q"] as? NSNumber { defaults.quadrant = v.intValue }
            if let v = d["repeat"] as? String { defaults.repeatRule = v }
        }
        var s = QuickAddState.opened(defaults, today: today)
        s.text = str(c["text"])
        s.note = str(c["note"])
        if let v = c["useParse"] as? NSNumber { s.useParse = v.boolValue }
        if let st = c["state"] as? [String: Any] {
            if let v = st["date"] as? String { s.date = v }
            if let v = st["time"] as? String { s.time = v }
            if let v = st["repeat"] as? String { s.repeatRule = v }
        }
        if let m = c["manual"] as? [String: Any] {
            if let v = m["date"] as? NSNumber { s.manualDate = v.boolValue }
            if let v = m["time"] as? NSNumber { s.manualTime = v.boolValue }
            if let v = m["repeat"] as? NSNumber { s.manualRepeat = v.boolValue }
        }
        return s
    }

    func testQuickAddFixtureContrast() throws {
        let r = try root()
        let cases = r["quickAdd"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 36)
        for c in cases {
            let name = str(c["name"]), lang = str(c["lang"])
            let e = c["expected"] as! [String: Any]
            let s = state(for: c["case"] as! [String: Any])
            let p = QuickAddContract.parsed(s, now: now)
            XCTAssertEqual(p.title, str(e["title"]), "title/\(name)/\(lang)")
            XCTAssertEqual(p.date, str(e["parsedDate"]), "parsedDate/\(name)")
            XCTAssertEqual(p.time, str(e["parsedTime"]), "parsedTime/\(name)")
            XCTAssertEqual(p.repeatRule, str(e["parsedRepeat"]), "parsedRepeat/\(name)")
            XCTAssertEqual(p.hits, e["hits"] as! [String], "hits/\(name)")
            XCTAssertEqual(QuickAddContract.effDate(s, now: now), str(e["effDate"]), "effDate/\(name)")
            XCTAssertEqual(QuickAddContract.effTime(s, now: now), str(e["effTime"]), "effTime/\(name)")
            XCTAssertEqual(QuickAddContract.effRepeat(s, now: now), str(e["effRepeat"]), "effRepeat/\(name)")
            XCTAssertEqual(QuickAddContract.recognized(s, now: now), bool(e["recognized"]), "recognized/\(name)")
            XCTAssertEqual(QuickAddContract.whenLabel(s, now: now, lang: lang, today: today),
                           str(e["whenLabel"]), "whenLabel/\(name)/\(lang)")
            XCTAssertEqual(QuickAddContract.recognizedWhen(s, now: now, lang: lang, today: today),
                           str(e["when"]), "when/\(name)/\(lang)")
            let msg = QuickAddContract.parseMsg(p, lang: lang)
            XCTAssertEqual(msg.before, str(e["before"]), "msg.before/\(name)/\(lang)")
            XCTAssertEqual(msg.after, str(e["after"]), "msg.after/\(name)/\(lang)")
            XCTAssertEqual(QuickAddContract.canSend(s), bool(e["canSend"]), "canSend/\(name)")
            let submit = QuickAddContract.submitFields(s, now: now)
            let es = e["submit"] as! [String: Any]
            XCTAssertEqual(submit["title"] as? String ?? "", str(es["title"]), "submit.title/\(name)")
            XCTAssertEqual(submit["note"] as? String ?? "", str(es["note"]), "submit.note/\(name)")
            XCTAssertEqual(submit["date"] as? String ?? "", str(es["date"]), "submit.date/\(name)")
            XCTAssertEqual(submit["time"] as? String ?? "", str(es["time"]), "submit.time/\(name)")
            XCTAssertEqual(submit["repeat"] as? String ?? "", str(es["repeat"]), "submit.repeat/\(name)")
            XCTAssertEqual((submit["important"] as? Bool) ?? false, bool(es["important"]), "submit.important/\(name)")
            XCTAssertEqual((submit["urgent"] as? Bool) ?? false, bool(es["urgent"]), "submit.urgent/\(name)")
            XCTAssertEqual(QuickAddContract.toastMessage(s, now: now, lang: lang, today: today),
                           str(e["toast"]), "toast/\(name)/\(lang)")
        }
    }

    /// 三个面板手改的联动：补今天 / 清时间 / 自定义规则面板留着（夹具只测 computed，不测迁移）。
    func testQuickAddPanelMutations() {
        var s = QuickAddState.opened(QuickAddDefaults.empty, today: today)
        s.text = "明天下午3点 交报告"
        XCTAssertFalse(s.manualDate)
        s.setDate("2026-11-20")
        XCTAssertTrue(s.manualDate)
        XCTAssertNil(s.panel)
        XCTAssertEqual(QuickAddContract.effDate(s, now: now), "2026-11-20")

        s = QuickAddState.opened(QuickAddDefaults.empty, today: today)
        s.date = ""
        s.text = ""
        s.setTime("20:00", now: now, today: today)
        XCTAssertEqual(s.date, today, "设时间且没日期 → 补今天")
        XCTAssertTrue(s.manualDate)
        XCTAssertTrue(s.manualTime)

        s = QuickAddState.opened(QuickAddDefaults.empty, today: today)
        s.date = ""
        s.setRepeat("w1:135", done: false, now: now, today: today)
        XCTAssertEqual(s.date, today, "设重复且没日期 → 补今天")
        XCTAssertEqual(s.panel, nil, "done=false 时面板状态由调用方保持，状态层不改")
        s.setRepeat("w1:135", done: true, now: now, today: today)
        XCTAssertTrue(s.manualRepeat)

        s = QuickAddState.opened(QuickAddDefaults.empty, today: today)
        s.setDate("")
        XCTAssertTrue(s.manualTime, "清日期时把时间也锁成手改，避免解析结果回填")
        XCTAssertEqual(s.time, "")
    }

    // MARK: F-06 任务详情

    func testTaskDetailFixtureContrast() throws {
        let r = try root()
        let list = tasks(r)
        let cases = r["detail"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 20)
        for c in cases {
            let name = str(c["name"]), lang = str(c["lang"])
            let cc = c["case"] as! [String: Any]
            let e = c["expected"] as! [String: Any]
            let rootId = str(cc["rootId"]), rootOcc = str(cc["rootOcc"])
            let t0 = list.first { $0.id == rootId }!
            let parent: PlannerTask? = t0.parentId.isEmpty ? nil : list.first { $0.id == t0.parentId }
            let occDay = TaskDetailContract.occOf(t0, rootId: rootId, rootOcc: rootOcc, today: today)
            let parentOcc = TaskDetailContract.occOf(parent, rootId: rootId, rootOcc: rootOcc, today: today)
            XCTAssertEqual(occDay, str(e["occDay"]), "occDay/\(name)")
            XCTAssertEqual(parentOcc, str(e["parentOcc"]), "parentOcc/\(name)")
            XCTAssertEqual(TaskDetailContract.isDone(t0, parent: parent, occDay: occDay, parentOcc: parentOcc),
                           bool(e["isDone"]), "isDone/\(name)")
            XCTAssertEqual(TaskDetailContract.canDrop(t0, parent: parent), bool(e["canDrop"]), "canDrop/\(name)")
            XCTAssertEqual(TaskDetailContract.dateText(t0, lang: lang, today: today),
                           str(e["dateText"]), "dateText/\(name)/\(lang)")
            XCTAssertEqual(TaskDetailContract.footer(t0, lang: lang), str(e["footer"]), "footer/\(name)/\(lang)")
            XCTAssertEqual(TaskDetailContract.remindValue(t0, remindOn: true, lang: lang),
                           str(e["remindValue"]), "remindValue/\(name)/\(lang)")
            XCTAssertEqual(TaskDetailContract.repeatValue(t0, lang: lang), str(e["repeatValue"]), "repeatValue/\(name)/\(lang)")
            XCTAssertEqual(TaskDetailContract.droppedText(t0, lang: lang), str(e["droppedText"]), "droppedText/\(name)/\(lang)")
            let prog = TaskDetailContract.subProgress(list, parent: t0, occ: occDay)
            XCTAssertEqual([prog.done, prog.total], e["progress"] as! [Int], "progress/\(name)")
            let kids = TaskDetailContract.children(list, parentId: t0.id)
            let view = kids.map { (id: $0.id,
                                     done: TaskDetailContract.subDone(t0, $0, occ: occDay)) }
            let expectView = e["subView"] as! [[String: Any]]
            XCTAssertEqual(view.map(\.id), expectView.map { str($0["id"]) }, "subView.id/\(name)")
            XCTAssertEqual(view.map(\.done), expectView.map { bool($0["done"]) }, "subView.done/\(name)")
            let deletes = [
                TaskDetailContract.deleteMessage(title: t0.title, kids: 0, isRepeat: false, lang: lang),
                TaskDetailContract.deleteMessage(title: t0.title, kids: 2, isRepeat: false, lang: lang),
                TaskDetailContract.deleteMessage(title: t0.title, kids: 0, isRepeat: true, lang: lang),
                TaskDetailContract.deleteMessage(title: t0.title, kids: 3, isRepeat: true, lang: lang),
            ]
            XCTAssertEqual(deletes, e["deleteMessages"] as! [String], "deleteMessages/\(name)/\(lang)")
        }
    }

    /// 导航栈：push / pop / 底层子任务返回父任务（左上「‹ 父任务」保留）。
    func testDetailNavigation() throws {
        let r = try root()
        let list = tasks(r)
        let cases = r["nav"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 3)
        for c in cases {
            var nav = DetailNav(rootId: str(c["rootId"]))
            var seen: [String] = []
            for a in c["actions"] as! [String] {
                if a.hasPrefix("push:") {
                    nav.pushSub(String(a.dropFirst(5)))
                } else if a == "back" {
                    let id = nav.currentId
                    let parentId = list.first { $0.id == id }?.parentId ?? ""
                    _ = nav.goBack(parentId: parentId.isEmpty ? nil : parentId)
                }
                seen.append(nav.currentId)
            }
            XCTAssertEqual(seen, c["expected"] as! [String], "nav/\(str(c["name"]))")
        }
    }

    func testDetailValueBranches() throws {
        let r = try root()
        let list = tasks(r)
        let parent = list.first { $0.id == "parent" }!
        let child = list.first { $0.id == "child-repeat" }!
        let rep = list.first { $0.id == "repeat" }!
        XCTAssertTrue(TaskDetailContract.isPerOcc(rep, child, today))
        XCTAssertFalse(TaskDetailContract.isPerOcc(parent, child, today))
        XCTAssertFalse(TaskDetailContract.canDrop(child, parent: rep), "重复父任务下的单日子任务不能放弃")
        XCTAssertTrue(TaskDetailContract.canDrop(parent, parent: nil))
        XCTAssertEqual(TaskDetailContract.subtasksLabel((done: 2, total: 3), lang: "zh"), "子任务 · 2/3")
        XCTAssertEqual(TaskDetailContract.dropMessage(title: "写周报", lang: "zh"), "已放弃「写周报」")
        XCTAssertEqual(TaskDetailContract.deleteSubtaskMessage(title: "订场地", lang: "en"),
                       "Deleted subtask “订场地”")
    }

    // MARK: 中英词条全量（含 i18n-en 的函数值）

    func testAllStrings() throws {
        let r = try root()
        let cases = r["strings"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 70)
        var failures: [String] = []
        for c in cases {
            let key = str(c["key"]), lang = str(c["lang"]), expected = str(c["value"])
            let actual = FeatureStrings.t(key, lang: lang, params(c["params"] as? [String: Any]))
            if actual != expected { failures.append("\(lang)/\(key): expected=\(expected) actual=\(actual)") }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
