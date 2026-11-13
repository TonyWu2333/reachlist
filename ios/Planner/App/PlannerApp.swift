import SwiftUI

// T-13：正式 App 骨架（TabView 4 tab）。
// T-03 技术原型与 T-02 占位页没有删除，改由「我的」tab 的自检页里的「查看…」按钮
// 以 fullScreenCover 打开，保持可回溯；工程/签名/版本号链路与 T-02 一致。
@main
struct PlannerApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

// T-02 的空白 App 占位页保留为独立视图，供 T-13 自检页回溯。
// 版本号显示同时是 OPEN-11=A（从 package.json 注入）的运行时证据。
struct T02PlaceholderView: View {
    private var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("可及清单")
                    .font(.largeTitle.bold())
                Text("iOS 工程地基 · T-02 占位页")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("v\(marketingVersion) (\(buildVersion))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .navigationTitle("T-02 占位页")
        }
    }
}
