import SwiftUI

// T-03 原型 / VERIFY-09：真机上中英切换的可观察界面。
struct LocalizationProbeView: View {
    @StateObject private var loc = LocalizationProbe()
    @State private var showInfo = false

    private var rows: [(String, String, [String: String])] {
        [
            ("普通词条", "可及清单", [:]),
            ("普通词条", "四象限", [:]),
            ("普通词条", "撤销", [:]),
            ("普通词条", "不提醒", [:]),
            ("{placeholder}", "服务器返回 {code}", ["code": "500"]),
            ("复数函数（1）", "提前 {n} 小时", ["n": "1"]),
            ("复数函数（3）", "提前 {n} 小时", ["n": "3"]),
            ("复数函数（1）", "已恢复 {n} 条任务", ["n": "1"]),
            ("复数函数（5）", "已恢复 {n} 条任务", ["n": "5"]),
            ("多占位符 + 复数", "用备份里的 {a} 条任务替换当前的 {b} 条？", ["a": "3", "b": "7"]),
            ("缺失回退中文", "共 {n} 项", ["n": "2"]),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section("语言设置（点击循环切换 auto → zh → en）") {
                    Button {
                        loc.pref = loc.pref.next
                    } label: {
                        HStack {
                            Text("当前")
                            Spacer()
                            Text(loc.pref.label).foregroundStyle(.secondary)
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    LabeledContent("有效语言", value: loc.effective)
                    LabeledContent("系统语言", value: LocalizationProbe.systemLang())
                    LabeledContent("缺失词条回退次数", value: "\(loc.missingCount)")
                }

                Section("词条渲染（逐条对照 JS oracle）") {
                    ForEach(rows.indices, id: \.self) { i in
                        let row = rows[i]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.0).font(.caption).foregroundStyle(.secondary)
                            Text(loc.t(row.1, row.2))
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("英文长文案窄屏截断（需人工观察）") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("中文：用备份里的 3 条任务替换当前的 7 条？")
                        Text("英文：Replace your 7 tasks with the 3 tasks in the backup?")
                        Text("请在窄屏上观察是否折行 / 截断；全页面遍历留到 T-19。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("语言 VERIFY-09")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("说明") { showInfo = true }
                }
            }
            .sheet(isPresented: $showInfo) {
                // sheet 本身也是 VERIFY-06 的系统 Liquid Glass 观察对象
                VStack(spacing: 12) {
                    Text("T-03 技术原型").font(.title2.bold())
                    Text("本页只做本地化方案选型验证，不是 M-23 实现。\n词条来源：baseline_commit 97a7c4c 的 src/lib/i18n.js / i18n-en.js。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("下滑可关闭（系统 sheet 行为，供 VERIFY-06 观察）")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding()
                .presentationDetents([.medium])
            }
        }
    }
}
