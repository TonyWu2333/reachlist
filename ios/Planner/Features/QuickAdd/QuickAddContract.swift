import Foundation

// MARK: - M-14 快速添加：事实层（T-17）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/components/QuickAdd.vue:17-122：
// 默认值注入、输入即解析（只识别中文，F-07.7）、「已识别 {when}」提示拆成 [前, 后] 两段、
// 三个 manual 覆盖标志、四个面板的联动（补今天 / 清时间 / 面板收起时机）、
// 提交字段（象限 flags）与提交后的中英 toast。解析只调 M-04 NaturalLanguageParser。
//
// 纯 Foundation，可在 Xcode 外用 swiftc + JS oracle 夹具逐字对比。

enum QuickAddPanel: String, CaseIterable, Equatable, Sendable {
    case date, time, `repeat`, quad
}

struct QuickAddState: Equatable, Sendable {
    var text = ""
    var note = ""
    var showNote = false
    var date = ""
    var time = ""
    var quadrant = 4
    var repeatRule = ""
    var manualDate = false
    var manualTime = false
    var manualRepeat = false
    var useParse = true
    var panel: QuickAddPanel? = nil

    /// QuickAdd.vue:watch(open)：每次打开重置全部字段，再注入 defaults。
    static func opened(_ defaults: QuickAddDefaults, today: String) -> QuickAddState {
        var s = QuickAddState()
        s.date = defaults.date ?? today
        s.quadrant = defaults.quadrant ?? 4
        s.repeatRule = defaults.repeatRule ?? ""
        return s
    }

    mutating func setDate(_ v: String) {
        date = v
        manualDate = true
        if v.isEmpty {
            time = ""
            manualTime = true
        }
        panel = nil
    }

    /// setTime 先看「改动前」的 effDate（与上游 computed 求值顺序一致）。
    mutating func setTime(_ v: String, now: Date, today: String) {
        let effectiveDate = QuickAddContract.effDate(self, now: now)
        time = v
        manualTime = true
        if !v.isEmpty && effectiveDate.isEmpty {
            date = today
            manualDate = true
        }
        panel = nil
    }

    mutating func setRepeat(_ v: String, done: Bool, now: Date, today: String) {
        let effectiveDate = QuickAddContract.effDate(self, now: now)
        repeatRule = v
        manualRepeat = true
        if !v.isEmpty && effectiveDate.isEmpty {
            date = today
            manualDate = true
        }
        if !done { return }     // 自定义规则还在调，面板留着
        panel = nil
    }

    mutating func setQuadrant(_ n: Int) {
        quadrant = n
        panel = nil
    }
}

enum QuickAddContract {

    /// `useParse ? parseInput(text) : {title: text.trim(), date:'', time:'', repeat:'', hits:[]}`
    static func parsed(_ state: QuickAddState, now: Date) -> ParsedInput {
        guard state.useParse else {
            return ParsedInput(title: SearchContract.trimmed(state.text),
                               date: "", time: "", repeatRule: "", hits: [])
        }
        return NaturalLanguageParser.parseInput(state.text, now: now)
    }

    static func effDate(_ state: QuickAddState, now: Date) -> String {
        state.manualDate ? state.date : (parsed(state, now: now).date.isEmpty ? state.date : parsed(state, now: now).date)
    }

    static func effTime(_ state: QuickAddState, now: Date) -> String {
        state.manualTime ? state.time : (parsed(state, now: now).time.isEmpty ? state.time : parsed(state, now: now).time)
    }

    static func effRepeat(_ state: QuickAddState, now: Date) -> String {
        state.manualRepeat ? state.repeatRule
            : (parsed(state, now: now).repeatRule.isEmpty ? state.repeatRule : parsed(state, now: now).repeatRule)
    }

    static func recognized(_ state: QuickAddState, now: Date) -> Bool {
        !parsed(state, now: now).hits.isEmpty
            && !(state.manualDate && state.manualTime && state.manualRepeat)
    }

    /// 重复任务显示「每周五」，普通任务显示「明天」。
    static func whenLabel(_ state: QuickAddState, now: Date, lang: String, today: String) -> String {
        let en = lang == "en"
        let rule = effRepeat(state, now: now)
        let date = effDate(state, now: now)
        if !rule.isEmpty {
            return RepeatEngine.repeatLabel(rule, date: date, isEnglish: en)
        }
        return date.isEmpty ? "" : PlannerCalendar.dateLabel(date, today: today, isEnglish: en)
    }

    /// 「已识别 {when}，标题「{title}」」：英文语序不同，提示拆成 [前, 后] 两段保留中间加粗。
    static func parseMsg(_ parsed: ParsedInput, lang: String) -> (before: String, after: String) {
        let s = FeatureStrings.t("已识别 {when}，标题「{title}」", lang: lang, ["title": parsed.title])
        let ns = s as NSString
        let r = ns.range(of: "{when}")
        guard r.location != NSNotFound else { return (s, "") }
        return (ns.substring(to: r.location), ns.substring(from: NSMaxRange(r)))
    }

    /// 识别提示里加粗的 when = [whenLabel, effTime].filter(Boolean).join(' ')。
    static func recognizedWhen(_ state: QuickAddState, now: Date, lang: String, today: String) -> String {
        [whenLabel(state, now: now, lang: lang, today: today), effTime(state, now: now)]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func canSend(_ state: QuickAddState) -> Bool {
        !SearchContract.trimmed(state.text).isEmpty
    }

    /// 交给 store.addTask 的字段（remind 由 store 按 time + defaultRemind 推导）。
    static func submitFields(_ state: QuickAddState, now: Date) -> [String: Any] {
        let flags = PanelLinkage.setQuadrant(state.quadrant)
        return [
            "title": parsed(state, now: now).title,
            "note": state.note,
            "date": effDate(state, now: now),
            "time": effTime(state, now: now),
            "repeat": effRepeat(state, now: now),
            "important": flags.important,
            "urgent": flags.urgent,
        ]
    }

    /// QuickAdd.vue:submit 的三种 toast 文案。
    static func toastMessage(_ state: QuickAddState, now: Date, lang: String, today: String) -> String {
        let rule = effRepeat(state, now: now)
        let date = effDate(state, now: now)
        let when = [whenLabel(state, now: now, lang: lang, today: today),
                    effTime(state, now: now)].filter { !$0.isEmpty }.joined(separator: " ")
        if !rule.isEmpty {
            return FeatureStrings.t("已添加 · {when}", lang: lang, ["when": when])
        }
        if !date.isEmpty {
            return FeatureStrings.t("已添加到{when}", lang: lang, ["when": whenLabel(state, now: now, lang: lang, today: today)])
        }
        return FeatureStrings.t("已添加（无日期）", lang: lang)
    }
}
