import SwiftUI

// T-03 原型 / VERIFY-04：观测 swipeActions 能否等价实现
// 「右滑 76pt 触发完成」与「左滑 3 个按钮 + 阻尼 + 只展开一行」。
// SwiftUI 系统 swipeActions 不公开触发阈值，故本页只提供可量化参照，
// 等价性结论必须由真机人工观察给出，不在此推断。
struct SwipeProbeView: View {
    @State private var dragWidth: CGFloat = 0
    @State private var peakWidth: CGFloat = 0
    @State private var completed = Set<Int>()
    @State private var lastAction = "无"
    @State private var expandedRows = 0

    var body: some View {
        NavigationStack {
            List {
                Section("位移参照（拖动下方卡片，读取实际 pt）") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前位移 \(String(format: "%.1f", dragWidth)) pt · 峰值 \(String(format: "%.1f", peakWidth)) pt")
                            .font(.footnote.monospacedDigit())
                        Text(dragWidth >= 76 ? "已达 76pt 参照线" : "未达 76pt 参照线")
                            .font(.caption)
                            .foregroundStyle(dragWidth >= 76 ? .green : .secondary)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.12))
                                .frame(height: 54)
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.35))
                                .frame(width: min(76, max(0, dragWidth)), height: 54)
                            Text("拖动我").padding(.leading, 12)
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    dragWidth = v.translation.width
                                    peakWidth = max(peakWidth, abs(v.translation.width))
                                }
                                .onEnded { _ in dragWidth = 0 }
                        )
                    }
                    .padding(.vertical, 4)
                }

                Section("系统 swipeActions（右滑完成 / 左滑 3 按钮）") {
                    ForEach(0..<3, id: \.self) { i in
                        HStack {
                            Image(systemName: completed.contains(i) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(completed.contains(i) ? .green : .secondary)
                            Text("任务行 \(i + 1)")
                            Spacer()
                            Text("o\(i + 1)").font(.caption).foregroundStyle(.tertiary)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                completed.insert(i)
                                lastAction = "行 \(i + 1) 完成"
                                expandedRows += 1
                            } label: {
                                Label("完成", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { lastAction = "行 \(i + 1) 推迟"; expandedRows += 1 } label: {
                                Label("推迟", systemImage: "clock")
                            }.tint(.orange)
                            Button { lastAction = "行 \(i + 1) 象限"; expandedRows += 1 } label: {
                                Label("象限", systemImage: "square.grid.2x2")
                            }.tint(.blue)
                            Button { lastAction = "行 \(i + 1) 删除"; expandedRows += 1 } label: {
                                Label("删除", systemImage: "trash")
                            }.tint(.red)
                        }
                    }
                }

                Section("观察记录") {
                    LabeledContent("最近动作", value: lastAction)
                    LabeledContent("动作累计", value: "\(expandedRows)")
                    Text("请人工判断：系统触发距离 vs 上方 76pt 参照、左滑三按钮的阻尼手感、"
                         + "以及同时是否只有一行保持展开。SwiftUI 不提供展开状态 API，本页只能记录动作，不能证明「只展开一行」。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("手势 VERIFY-04")
        }
    }
}
