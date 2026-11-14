import Foundation

// MARK: - M-17 我的：事实层（T-16）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/views/MeView.vue:14-115：
// 问候语 5 档、今日进度（排除放弃）、三项统计、近 7 天柱状图、语言 / 提醒 / 同步设置、
// 连接码状态文案全集。日期一律走 M-06，重复展开走 M-03，不写第二份逻辑。

struct MeDayBar: Equatable, Sendable {
    var day: String
    var count: Int
    var height: Double
    var label: String
}

enum MeContract {

    static let langs: [AppLanguagePref] = [.auto, .zh, .en]
    static let remindOptions = PanelCatalog.remindOptions

    // MARK: 顶部概览

    /// greeting：按小时 5 档（MeView.vue:43-46）。
    static func greeting(hour: Int, lang: String) -> String {
        let key = hour < 6 ? "夜深了"
            : hour < 11 ? "早上好"
            : hour < 13 ? "中午好"
            : hour < 18 ? "下午好" : "晚上好"
        return FeatureStrings.t(key, lang: lang)
    }

    /// `todayCounted` 排除 dropped；`todayDone` 是其中 done 的数量。
    static func todayCounted(_ tasks: [PlannerTask], today: String) -> [RepeatInstance] {
        RepeatEngine.tasksOn(tasks, day: today).filter { !$0.task.dropped }
    }

    static func todayDone(_ tasks: [PlannerTask], today: String) -> Int {
        todayCounted(tasks, today: today).filter { $0.task.done }.count
    }

    static func ratio(_ tasks: [PlannerTask], today: String) -> Double {
        let counted = todayCounted(tasks, today: today)
        return counted.isEmpty ? 0 : Double(todayDone(tasks, today: today)) / Double(counted.count)
    }

    static func summary(_ tasks: [PlannerTask], today: String, lang: String) -> String {
        let counted = todayCounted(tasks, today: today)
        if counted.isEmpty { return FeatureStrings.t("今天还没有安排任务", lang: lang) }
        let left = counted.count - todayDone(tasks, today: today)
        if left == 0 { return FeatureStrings.t("今天的任务全部完成了，真棒", lang: lang) }
        return FeatureStrings.t("今天还有 {n} 个任务待完成", lang: lang, ["n": String(left)])
    }

    static func doneTotalText(_ tasks: [PlannerTask], today: String, lang: String) -> String {
        FeatureStrings.t("{done} / {total} 已完成", lang: lang, [
            "done": String(todayDone(tasks, today: today)),
            "total": String(todayCounted(tasks, today: today).count),
        ])
    }

    // MARK: 三项统计

    /// 重复任务只算今天这一次（MeView.vue:21-23）。
    static func pendingAll(_ tasks: [PlannerTask], today: String) -> Int {
        let oneOff = tasks.filter { $0.repeatRule.isEmpty && !$0.done }.count
        let instances = RepeatEngine.tasksOn(tasks, day: today).filter { !$0.task.repeatRule.isEmpty && !$0.task.done }.count
        return oneOff + instances
    }

    static func overdue(_ tasks: [PlannerTask], today: String) -> Int {
        tasks.filter { CalendarContract.isOverdue($0, today: today) }.count
    }

    /// 每一次完成的日期：一次性看 doneAt（排除放弃），重复看 doneDates。
    static func doneDays(_ tasks: [PlannerTask]) -> [String] {
        tasks.flatMap { t -> [String] in
            if !t.repeatRule.isEmpty { return t.doneDates }
            if let ms = t.doneAt, !t.dropped {
                return [PlannerCalendar.ymd(Date(timeIntervalSince1970: ms / 1000))]
            }
            return []
        }
    }

    static func weekDone(_ tasks: [PlannerTask], today: String) -> Int {
        let start = PlannerCalendar.mondayOf(today)
        return doneDays(tasks).filter { $0 >= start && $0 <= today }.count
    }

    /// 近 7 天：完成日期落在窗口内计数，柱高 = n / max(1, maxCount)，标签用中英短星期名。
    static func last7(_ tasks: [PlannerTask], today: String, lang: String) -> [MeDayBar] {
        let days = (0..<7).map { PlannerCalendar.addDays(today, $0 - 6) }
        var counts: [String: Int] = [:]
        for d in days { counts[d] = 0 }
        for d in doneDays(tasks) where counts[d] != nil { counts[d, default: 0] += 1 }
        let maxCount = max(1, counts.values.max() ?? 0)
        let en = lang == "en"
        return days.map { d in
            let n = counts[d] ?? 0
            let label = d == today
                ? AppStrings.t("今", lang: lang)
                : PlannerCalendar.weekdayName(PlannerCalendar.weekdayIndex(d), short: true, isEnglish: en)
            return MeDayBar(day: d, count: n, height: Double(n) / Double(maxCount), label: label)
        }
    }

    static func last7Total(_ bars: [MeDayBar], lang: String) -> String {
        FeatureStrings.t("共 {n} 个", lang: lang, ["n": String(bars.reduce(0) { $0 + $1.count })])
    }

    // MARK: 设置循环

    /// MeView.vue:langLabel —— `zh` 显示「中文」、`en` 显示 English，其余显示「跟随系统」。
    static func langLabel(_ pref: AppLanguagePref, lang: String) -> String {
        switch pref {
        case .zh: return "中文"
        case .en: return "English"
        case .auto: return FeatureStrings.t("跟随系统", lang: lang)
        }
    }

    static func cycleLang(_ pref: AppLanguagePref) -> AppLanguagePref {
        let i = langs.firstIndex(of: pref) ?? 0
        return langs[(i + 1) % langs.count]
    }

    /// `REMIND_OPTIONS.indexOf(x)` 找不到时 -1 → 下一项是第 0 项，逐字保留。
    static func cycleDefaultRemind(_ current: Int) -> Int {
        let i = remindOptions.firstIndex(of: current) ?? -1
        return remindOptions[(i + 1) % remindOptions.count]
    }

    static func remindText(_ minutes: Int?, remindOn: Bool, hasTime: Bool, lang: String) -> String {
        if !hasTime { return AppStrings.t("先设时间", lang: lang) }
        if !remindOn && minutes != nil { return AppStrings.t("已关闭全部提醒", lang: lang) }
        return PanelCatalog.remindLabel(minutes, isEnglish: lang == "en")
    }

    // MARK: 同步状态（MeView.vue:89-102 / sync.js）

    static func codeOk(_ code: String) -> Bool { SyncCode.parse(code) != nil }

    static func syncHost(_ code: String) -> String {
        guard let url = SyncCode.parse(code)?.url else { return "" }
        let re = try! NSRegularExpression(pattern: #"^https?://"#, options: [.caseInsensitive])
        return re.stringByReplacingMatches(in: url, range: NSRange(url.startIndex..., in: url), withTemplate: "")
    }

    static func syncStatus(settings: UISettings, state: SyncState, lang: String) -> String {
        guard settings.syncOn else { return "" }
        guard codeOk(settings.syncCode) else {
            return FeatureStrings.t(
                settings.syncCode.isEmpty
                    ? "填入服务器启动时打印的连接码"
                    : "连接码格式不对：应该是 地址#令牌",
                lang: lang
            )
        }
        if state.busy { return FeatureStrings.t("正在同步…", lang: lang) }
        if !state.error.isEmpty {
            return FeatureStrings.t("同步失败：{msg}", lang: lang, ["msg": state.error])
        }
        if state.at > 0 {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "HH:mm"
            let time = f.string(from: Date(timeIntervalSince1970: state.at / 1000))
            return FeatureStrings.t("已同步 · {time} · {host}", lang: lang,
                                    ["time": time, "host": syncHost(settings.syncCode)])
        }
        return FeatureStrings.t("还没同步过", lang: lang)
    }

    /// 隐私说明卡片两种文案（F-09.9）。
    static func privacyText(syncOn: Bool, lang: String) -> (title: String, detail: String) {
        syncOn
            ? (FeatureStrings.t("数据保存在本机和你自己的服务器", lang: lang),
               FeatureStrings.t("不经过任何第三方。连接码里有令牌，别发给别人。", lang: lang))
            : (FeatureStrings.t("数据只保存在本机", lang: lang),
               FeatureStrings.t("不联网、不上传。卸载 App 或清除应用数据会一起删除，建议定期导出备份。", lang: lang))
    }

    /// A-36：应用名固定显示「可及清单」（OPEN-17），英文界面也不换成 Reach List。
    static func versionText(_ version: String) -> String { "可及清单 · v\(version)" }
}
