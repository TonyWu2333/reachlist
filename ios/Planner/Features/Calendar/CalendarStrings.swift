import Foundation

// MARK: - T-15 组合文案（T-19 起全部走 M-23）
//
// 这里只负责按「是否有重复 / 是否有子任务」挑出正确的中文词条 key，
// 翻译与函数值（复数、lowerRel）统一交给 LocalizationService，Swift 侧不再有第二套英文文案。
// 调用点（DayAgendaView / T15CalendarContractTests）签名不变。

enum CalendarStrings {

    /// 删除提示：重复任务 + 子任务数量决定四种分支（CalendarView.vue:onDelete）。
    static func deleted(title: String, kids: Int, isRepeat: Bool, lang: String) -> String {
        let key: String
        if isRepeat && kids > 0 { key = "已删除「{title}」及以后的重复和{n} 个子任务" }
        else if isRepeat { key = "已删除「{title}」及以后的重复" }
        else if kids > 0 { key = "已删除「{title}」及{n} 个子任务" }
        else { key = "已删除「{title}」" }
        return LocalizationService.t(key, lang: lang, ["title": title, "n": String(kids)])
    }

    /// i18n-en/calendar.js:39 —— lowerRel 由函数值词条实现。
    static func postponed(_ label: String, lang: String) -> String {
        LocalizationService.t("已推迟到{date}", lang: lang, ["date": label])
    }

    /// i18n-en/calendar.js:40 —— 复数由函数值词条实现。
    static func movedAll(_ n: Int, lang: String) -> String {
        LocalizationService.t("{n} 个任务已移到今天", lang: lang, ["n": String(n)])
    }
}
