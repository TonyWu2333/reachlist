import SwiftUI

// MARK: - M-16 搜索 sheet（T-16 / F-08 全量）
//
// 系统 .sheet（§5.0 裁决，非自建模态容器）+ 独立搜索框（§5.2 允许「.searchable 或独立 sheet」）。
// 多词 AND、待办/已完成分组、命中高亮用 SwiftUI Text 拼接（对应上游不用 v-html）、
// 备注命中片段、点击失焦后打开详情。

struct SearchSheetView: View {
    @EnvironmentObject private var store: CalendarDataStore
    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var onOpen: (String) -> Void = { _ in }
    var onClose: () -> Void = {}

    @State private var query = ""
    @FocusState private var focused: Bool

    private var today: String { PlannerCalendar.today() }
    private var terms: [String] { SearchContract.terms(query) }
    private var results: (open: [PlannerTask], done: [PlannerTask]) {
        SearchContract.results(store.tasks, query: query)
    }
    private var total: Int { results.open.count + results.done.count }

    var body: some View {
        VStack(spacing: 0) {
            SheetTopBar(title: AppStrings.t("搜索", lang: lang), onClose: close)

            HStack(spacing: 8) {
                ReachIcon(name: .search, size: 18)
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                TextField(AppStrings.t("搜索任务、子任务、备注", lang: lang), text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { focused = false }
                if !query.isEmpty {
                    Button {
                        query = ""
                        focused = true
                    } label: {
                        ReachIcon(name: .x, size: 16)
                            .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(DesignTokens.color("--fill", scheme: scheme)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.t("清空", lang: lang))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(DesignTokens.color("--surface-2", scheme: scheme))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            List {
                if terms.isEmpty {
                    hint(icon: true, lines: [
                        AppStrings.t("输入关键词，搜索全部任务的标题、子任务和备注", lang: lang),
                        AppStrings.t("多个词用空格分开", lang: lang),
                    ])
                } else if total == 0 {
                    hint(icon: false, lines: [SearchContract.noResultText(query, lang: lang)])
                } else {
                    if !results.open.isEmpty { section("待办", results.open, isDone: false) }
                    if !results.done.isEmpty { section("已完成", results.done, isDone: true) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(DesignTokens.color("--surface", scheme: scheme))
        .onAppear { focused = true }
    }

    private func close() {
        focused = false
        dismiss()
        onClose()
    }

    // MARK: 结果分组

    private func section(_ label: String, _ items: [PlannerTask], isDone: Bool) -> some View {
        Section {
            ForEach(items, id: \.id) { t in
                resultRow(t, isDone: isDone)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
            }
        } header: {
            Text("\(AppStrings.t(label, lang: lang)) · \(items.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
        }
    }

    private func resultRow(_ t: PlannerTask, isDone: Bool) -> some View {
        let q = CalendarContract.quadrantOf(t)
        let color = DesignTokens.color(PanelCatalog.quadrants[q - 1].colorToken, scheme: scheme)
        let snippet = SearchContract.noteSnippet(t.note, query: query)
        return Button {
            focused = false               // SearchSheet.vue:pick 先 blur
            onOpen(t.id)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(isDone ? DesignTokens.color("--text-3", scheme: scheme) : color, lineWidth: 2)
                    .background(Circle().fill(isDone ? DesignTokens.color("--text-3", scheme: scheme) : .clear))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    marked(t.title, base: isDone
                           ? DesignTokens.color("--text-3", scheme: scheme)
                           : DesignTokens.color("--text", scheme: scheme))
                        .font(.body)
                        .strikethrough(isDone)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(SearchContract.sub(t, tasks: store.tasks, lang: lang, today: today))
                            .font(.caption)
                            .foregroundStyle(!isDone && CalendarContract.isOverdue(t, today: today)
                                ? DesignTokens.color("--danger", scheme: scheme)
                                : DesignTokens.color("--text-3", scheme: scheme))
                            .lineLimit(1)
                        if !snippet.isEmpty {
                            marked(snippet, base: DesignTokens.color("--text-3", scheme: scheme))
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                ReachIcon(name: .chevronRight, size: 16)
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(DesignTokens.color("--surface", scheme: scheme))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// 命中片段用 Text 拼接上色，不引入 HTML / NSAttributedString 渲染。
    private func marked(_ text: String, base: Color) -> Text {
        let accent = DesignTokens.color("--accent", scheme: scheme)
        return SearchContract.marks(text, query: query).reduce(Text("")) { acc, part in
            acc + Text(part.text)
                .foregroundColor(part.hit ? accent : base)
                .fontWeight(part.hit ? .semibold : .regular)
        }
    }

    private func hint(icon: Bool, lines: [String]) -> some View {
        VStack(spacing: 10) {
            if icon {
                ReachIcon(name: .search, size: 36)
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme).opacity(0.5))
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
