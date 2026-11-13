import SwiftUI

// T-03 原型根视图：TabView 本身就是 VERIFY-06 的系统 Liquid Glass 观察对象。
// 第 5 个 tab 保留 T-02 空白 App 占位页，便于回溯 T-02 产物。
struct PrototypeRootView: View {
    var body: some View {
        TabView {
            ATSProbeView()
                .tabItem { Label("ATS", systemImage: "network") }
            SwipeProbeView()
                .tabItem { Label("手势", systemImage: "hand.draw") }
            GlassProbeView()
                .tabItem { Label("玻璃", systemImage: "sparkles") }
            LocalizationProbeView()
                .tabItem { Label("语言", systemImage: "globe") }
            T02PlaceholderView()
                .tabItem { Label("T-02", systemImage: "app") }
        }
    }
}
