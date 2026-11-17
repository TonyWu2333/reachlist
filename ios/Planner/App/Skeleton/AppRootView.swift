import SwiftUI
import UserNotifications

// MARK: - M-20 AppRoot：4 tab 骨架 + T-18 生命周期接线
//
// 已落地：TabView + 4 tab、切换 select 触感、选中图标 -fill 变体、明暗跟随系统、
// 语言初始化（auto/zh/en，写 planner-settings 第 7 字段，A-45 不进同步载荷）、
// 跨天钩子、Toast 全局覆盖层、4 个真实业务页面、搜索 / 快速添加 / 任务详情三个系统 sheet。
//
// T-18 接线（v0.27 之前明确留到本任务）：
// · 数据源 = CalendarDataStore → 真实 TaskStore（UI 适配层，调用点不变）；
// · SyncClient：scenePhase → setActive / start / 60s 兜底 / 本地改动 2s 防抖、
//   「我的 → 立即同步」真实请求、状态文案回写；
// · ReminderScheduler：tasks / remindOn 变化 → 600ms 防抖全量重排；
// · 通知点击：UNUserNotificationCenterDelegate → ReminderPlanner.route → 打开详情 sheet。
// 系统通知 delegate 用 SwiftUI 的 @StateObject 持有，不引入 UIKit 视图（OPEN-04=A）。

/// 通知点击路由（F-11.3）。delegate 回调是 nonisolated，只把 Sendable 的 id / occ 切回 MainActor。
@MainActor
final class NotificationTapRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var pending: DetailRoute?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let route = ReminderPlanner.route(
            from: response.notification.request.content.userInfo)
        if let route {
            let id = route.id, occ = route.occ
            Task { @MainActor in self.pending = DetailRoute(id: id, occ: occ) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

@MainActor
struct AppRootView: View {
    @StateObject private var uiStore = CalendarDataStore()
    @StateObject private var toastCenter = ToastCenter()
    @StateObject private var notificationRouter = NotificationTapRouter()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme

    @State private var syncClient: SyncClient?
    @State private var reminderScheduler: ReminderScheduler?

    @State private var selection: AppTab = .calendar
    @State private var activeDay = AppRootView.currentDay()
    @State private var dayChangeCount = 0

    @State private var quickOpen = false
    @State private var quickDefaults = QuickAddDefaults.empty
    @State private var searchOpen = false
    @State private var detailRoute: DetailRoute? = nil
    @State private var selfCheckOpen = false

    private var lang: String {
        LocalizationService.effectiveLang(
            uiStore.settings.lang,
            system: Locale.preferredLanguages.first ?? "zh"
        )
    }

    private var langPrefBinding: Binding<AppLanguagePref> {
        Binding(
            get: { uiStore.settings.lang },
            set: { uiStore.settings.lang = $0 }
        )
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Tab(value: tab) {
                    NavigationStack {
                        content(for: tab)
                    }
                    // TabView 级 tint 只服务于 tab bar 选中色：内容层必须显式清空，
                    // 否则长按菜单里的分享（黑）/ 删除（红）等系统控件会被继承成主色。
                    .tint(nil)
                } label: {
                    Label {
                        Text(tab.title(lang: lang))
                    } icon: {
                        // OPEN-03=B：自定义 SVG 图标，不用 SF Symbols；选中态用 -fill 变体。
                        Image(tab.asset(selected: selection == tab))
                            .renderingMode(.template)
                    }
                }
            }
        }
        // 选中 tab 用项目主色 --accent（与日历页 FAB「+」同色），而非系统默认蓝。
        // 未选中仍交给系统次级色；背景保留 TabView 自带 Liquid Glass。
        .tint(DesignTokens.color("--accent", scheme: scheme))
        .environment(\.appLanguage, lang)
        .environmentObject(toastCenter)
        .environmentObject(uiStore)
        .overlay(alignment: .bottom) {
            ToastOverlay(center: toastCenter)
                .padding(.bottom, 72)
                .animation(.spring, value: toastCenter.current?.id)
        }
        .onChange(of: selection) { _, _ in
            HapticFeedback.play(.select) // F-14.1：切换时触感
        }
        // F-02.10 跨天钩子 + F-12.3 前后台：同步客户端与落盘时机。
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                syncClient?.setActive(true)
                let day = AppRootView.currentDay()
                if day != activeDay {
                    activeDay = day
                    dayChangeCount += 1
                }
            case .inactive, .background:
                syncClient?.setActive(false)     // 内部会 flushNow
                uiStore.taskStore.flushNow()
            @unknown default:
                break
            }
        }
        // M-07：任务数据或提醒总开关变化 → 600ms 防抖全量重排。
        .onChange(of: uiStore.tasks) { _, _ in scheduleReminders() }
        .onChange(of: uiStore.settings.remindOn) { _, _ in scheduleReminders() }
        .onChange(of: notificationRouter.pending) { _, route in
            guard let route else { return }
            openDetail(route.id, route.occ)
            notificationRouter.pending = nil
        }
        .task { wireLifecycle() }
        // App.vue:90-92 的三个 bottom sheet：全部交给系统 .sheet（§5.0 裁决）。
        // ⚠️ iOS 27 实测：.sheet / .fullScreenCover 呈现的视图**不继承** TabView 上挂的
        // @EnvironmentObject（崩溃报告栈：EnvironmentObject.error() → wrappedValue.getter）。
        // 每个模态内容必须显式注入它自己用到的环境依赖，否则一打开就 SIGTRAP 闪退。
        // 固定 .large：早前按面板展开态在 .medium ↔ .large 之间切换，
        // 与键盘收放动画叠加会让整张 sheet 上下抖动（用户 2026-11-15 反馈）。
        // 内容已放进 ScrollView，单一档位也不会再裁掉月历。
        .reachSheet(isPresented: $quickOpen, detents: [.large],
                    topInset: 4, surfaceToken: "--bg") {
            QuickAddSheet(defaults: quickDefaults, onClose: { quickOpen = false })
                .environmentObject(uiStore)
                .environmentObject(toastCenter)
                .environment(\.appLanguage, lang)
        }
        .reachSheet(isPresented: $searchOpen, detents: [.large], topInset: 4) {
            SearchSheetView(onOpen: openDetailFromSearch, onClose: { searchOpen = false })
                .environmentObject(uiStore)
                .environment(\.appLanguage, lang)
        }
        // 任务详情走 item 驱动：内容由本次要打开的任务现场生成，避免复用启动期
        // 以占位空 route 建好的旧实例，导致首次打开整页只显示「—」。
        .reachSheet(item: $detailRoute, detents: [.large]) { route in
            TaskDetailSheet(route: route, onClose: { detailRoute = nil })
                .environmentObject(uiStore)
                .environmentObject(toastCenter)
                .environment(\.appLanguage, lang)
                .id(route.id)
        }
        // T-13 自检页保留为「我的」页的回溯入口，供 A-42 / A-44 真机人工观察。
        .fullScreenCover(isPresented: $selfCheckOpen) {
            DesignSystemPreview(langPref: langPrefBinding, dayChangeCount: dayChangeCount)
                .environment(\.appLanguage, lang)
                .environmentObject(toastCenter)
                .environmentObject(uiStore)
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .calendar:
            CalendarScreen(
                onOpenDetail: { id, occ in openDetail(id, occ) },
                onAddTask: openQuick,
                onSearch: { searchOpen = true }
            )
        case .quadrant:
            QuadrantScreen(
                onOpen: { id, occ in openDetail(id, occ) },
                onAdd: openQuick,
                onSearch: { searchOpen = true }
            )
        case .routine:
            RoutineScreen(
                onOpen: { id, occ in openDetail(id, occ) },
                onAdd: openQuick,
                onSearch: { searchOpen = true }
            )
        case .me:
            MeScreen(
                onSyncNow: syncNowHook,
                onOpenSelfCheck: { selfCheckOpen = true }
            )
        }
    }

    // MARK: T-18 生命周期接线

    /// 只执行一次：`SyncClient.start()` 内部注册 store.onLocalChange（2s 防抖 → syncNow）、
    /// 启动 60s 兜底并立即同步一次；syncOn=false 时 configuration() 为 nil，一个请求都不发。
    private func wireLifecycle() {
        guard syncClient == nil else { return }
        let client = SyncClient(store: uiStore.taskStore, transport: URLSessionSyncTransport())
        client.onStateChange = { [weak uiStore] state in
            uiStore?.syncState = state
            // SyncClient 直接写 TaskStore（applyRemote / syncPayload 的 stamp），
            // 适配层的 @Published 快照不会自动跟着变，这里统一镜像一次。
            uiStore?.refreshFromStore()
        }
        let scheduler = ReminderScheduler()
        syncClient = client
        reminderScheduler = scheduler
        UNUserNotificationCenter.current().delegate = notificationRouter
        client.start()
        scheduleReminders()
    }

    private func scheduleReminders() {
        reminderScheduler?.scheduleSync(
            tasks: uiStore.tasks,
            remindOn: uiStore.settings.remindOn,
            isEnglish: lang == "en"
        )
    }

    /// 「我的 → 立即同步」：真实网络请求，状态与错误文案由 SyncClient 回写（T-16 曾留空）。
    private func syncNowHook() {
        Task { await syncClient?.syncNow() }
    }

    // MARK: App.vue:34-37 的路由

    private func openQuick(_ defaults: QuickAddDefaults) {
        quickDefaults = defaults
        quickOpen = true
    }

    private func openDetail(_ id: String, _ occ: String) {
        detailRoute = DetailRoute(id: id, occ: occ)
    }

    /// 搜索结果先关搜索 sheet（对应上游 pick 的 blur），再推详情；
    /// 系统 sheet 不允许同层同时替换，等关闭动画结束再呈现。
    private func openDetailFromSearch(_ id: String) {
        searchOpen = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            openDetail(id, "")
        }
    }

    /// 对齐 src/lib/date.js:today 的本地时间语义（yyyy-MM-dd）。
    static func currentDay() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f.string(from: Date())
    }
}
