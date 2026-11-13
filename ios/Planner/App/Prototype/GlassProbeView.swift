import SwiftUI
import UIKit

// T-03 原型 / VERIFY-06：TabView / toolbar / sheet 的系统 Liquid Glass 由
// PrototypeRootView + 各页 NavigationStack 提供；本页负责「自定义 glassEffect
// 同屏数量」的可调观测与帧率采样。
//
// FPS 用 CADisplayLink 采样，是可复现的量化数据；§8.2 第 6 条要求的
// Instruments 记录仍需 Xcode GUI 人工操作，本页不冒充 Instruments 结论。

private final class DisplayLinkProxy: NSObject {
    var onTick: ((CFTimeInterval) -> Void)?
    @objc func step(_ link: CADisplayLink) { onTick?(link.timestamp) }
}

@MainActor
final class FPSMeter: ObservableObject {
    @Published private(set) var current = 0
    @Published private(set) var lowest = 0
    @Published private(set) var average = 0
    @Published private(set) var samples = 0

    private let proxy = DisplayLinkProxy()
    private var link: CADisplayLink?
    private var last: CFTimeInterval?
    private var total = 0.0
    private var count = 0

    func start() {
        guard link == nil else { return }
        proxy.onTick = { [weak self] ts in
            Task { @MainActor in self?.apply(ts) }
        }
        let l = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
        last = nil
    }

    private func apply(_ ts: CFTimeInterval) {
        guard let prev = last else { last = ts; return }
        let dt = ts - prev
        last = ts
        guard dt > 0 else { return }
        let fps = 1.0 / dt
        current = Int(fps.rounded())
        count += 1
        total += fps
        samples = count
        average = Int((total / Double(count)).rounded())
        if lowest == 0 || current < lowest { lowest = current }
    }
}

struct GlassProbeView: View {
    private let counts = [0, 4, 8, 16, 32, 64]
    @State private var count = 8
    @StateObject private var fps = FPSMeter()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("同屏玻璃元素数", selection: $count) {
                        ForEach(counts, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前 \(fps.current) FPS · 最低 \(fps.lowest) · 平均 \(fps.average) · 采样 \(fps.samples) 帧")
                            .font(.footnote.monospacedDigit())
                        Text("把数量从 0 逐步调到 64，记录帧率开始下滑的档位；"
                             + "同时观察 tabbar / 导航栏 / sheet 的系统玻璃表现。")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    GlassEffectContainer(spacing: 16) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
                            ForEach(0..<count, id: \.self) { i in
                                Text("\(i + 1)")
                                    .font(.footnote.monospacedDigit())
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .background(Color.white.opacity(0.001))
                                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .frame(minHeight: 120)
                }
                .padding()
            }
            .navigationTitle("玻璃 VERIFY-06")
            .onAppear { fps.start() }
            .onDisappear { fps.stop() }
        }
    }
}
