import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

// MARK: - M-17 我的（T-16 / F-09 全量）
//
// 今日概览 / 三项统计 / 近 7 天柱状图、通用（语言循环切换）、日历显示、提醒、
// 数据（备份导出导入）、同步与 Agent、隐私说明、版本号（A-36）。
// 呈现层按 §5.0 / OPEN-18：系统 Toggle / List / fileExporter / fileImporter，
// 不套用 DESIGN.md 的自定义 switch 与实体阴影；导入确认沿用上游 confirm 语义。
//
// 备份服务只调 T-12 的 BackupService（不重写 JSON）；同步 UI 的文案全集来自 T-10 SyncState，
// 实际网络请求与 App 生命周期接线按 v0.25 约定留 T-18，本页不伪造同步结果。

/// `.fileExporter` 的 JSON 文档载体；内容由 BackupService.exportText 逐字产出。
struct BackupJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct MeScreen: View {
    @EnvironmentObject private var store: CalendarDataStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.appLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    /// T-18 注入真实 SyncClient.syncNow；T-16 只把 UI 与状态文案接通，不发假请求。
    var onSyncNow: () -> Void = {}
    /// 自检页入口（A-42 / A-44 的真机观察路径）。
    var onOpenSelfCheck: () -> Void = {}

    @State private var exportOpen = false
    @State private var importOpen = false
    @State private var confirmImportOpen = false
    @State private var exportDocument: BackupJSONDocument?
    @State private var exportFilename = "planner-backup.json"
    @State private var pendingImportText: String?
    @State private var notifyDenied = false

    /// 卡片左右留白与底部 Tab Bar 玻璃胶囊对齐（实测 21..409 pt @430pt 宽）。
    /// 本页是 ScrollView 自绘卡片，不经过 insetGrouped 的 20pt 页边距，需显式给 21。
    private let pageInset: CGFloat = 21

    private var today: String { PlannerCalendar.today() }
    private var settings: UISettings { store.settings }
    private var bars: [MeDayBar] { MeContract.last7(store.tasks, today: today, lang: lang) }
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
    private var hour: Int { Calendar.current.component(.hour, from: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(AppStrings.t("我的", lang: lang)).font(DesignTokens.font(.title))
                    Spacer(minLength: 0)
                    Button(action: onOpenSelfCheck) {
                        ReachIcon(name: .info, size: 18)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(DesignTokens.color("--fill", scheme: scheme)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.t("设计系统自检", lang: lang))
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 14)

                hero
                stats
                weekChart

                groupTitle("通用")
                card {
                    actionRow(icon: .info, color: .teal,
                              title: AppStrings.t("语言", lang: lang),
                              value: MeContract.langLabel(settings.lang, lang: lang)) {
                        store.settings.lang = MeContract.cycleLang(settings.lang)
                        HapticFeedback.play(.select)
                    }
                }

                groupTitle("日历显示")
                card {
                    toggleRow(icon: .lunar, color: .purple,
                              title: AppStrings.t("农历与节气", lang: lang),
                              value: binding(\.showLunar))
                    toggleRow(icon: .holiday, color: .red,
                              title: AppStrings.t("法定节假日与调休", lang: lang),
                              value: binding(\.showHoliday))
                }

                groupTitle("提醒")
                card {
                    toggleRow(icon: .bell, color: .orange,
                              title: AppStrings.t("到点提醒", lang: lang),
                              detail: AppStrings.t("设置时间的任务会发送系统通知", lang: lang),
                              value: binding(\.remindOn))
                    actionRow(icon: .clock, color: .indigo,
                              title: AppStrings.t("新任务默认提醒", lang: lang),
                              detail: AppStrings.t("单个任务时间可以在详情页修改", lang: lang),
                              value: PanelCatalog.remindLabel(settings.defaultRemind, isEnglish: lang == "en"),
                              disabled: !settings.remindOn) {
                        store.settings.defaultRemind = MeContract.cycleDefaultRemind(settings.defaultRemind)
                        HapticFeedback.play(.select)
                    }
                }
                if settings.remindOn && notifyDenied {
                    Text(AppStrings.t("通知权限没开，提醒发不出来：系统设置 → 应用 → 可及清单 → 通知，打开“允许通知”。", lang: lang))
                        .font(.caption)
                        .foregroundStyle(DesignTokens.color("--danger", scheme: scheme))
                        .padding(.horizontal, pageInset)
                }

                groupTitle("数据")
                card {
                    actionRow(icon: .upload, color: .blue,
                              title: AppStrings.t("导出备份", lang: lang),
                              detail: AppStrings.t("生成 JSON 文件，发到微信或网盘保存", lang: lang),
                              value: nil, arrow: true) { exportBackup() }
                    actionRow(icon: .download, color: .green,
                              title: AppStrings.t("从备份恢复", lang: lang),
                              detail: FeatureStrings.t("会替换当前全部 {n} 条任务", lang: lang,
                                                       ["n": String(store.tasks.count)]),
                              value: nil, arrow: true) { importOpen = true }
                }

                groupTitle("同步与 Agent")
                card {
                    toggleRow(icon: .cloud, color: .indigo,
                              title: AppStrings.t("同步到自己的服务器", lang: lang),
                              detail: AppStrings.t("让电脑或服务器上的 agent（Claude Code、Codex、Hermes）也能看和改你的任务", lang: lang),
                              value: binding(\.syncOn))
                    if settings.syncOn {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppStrings.t("连接码", lang: lang)).font(.subheadline)
                            Text(AppStrings.t("服务器启动时会打印，格式是 地址#令牌", lang: lang))
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("http://192.168.1.5:18787#…", text: binding(\.syncCode))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.footnote.monospaced())
                                .padding(10)
                                .background(DesignTokens.color("--surface-2", scheme: scheme))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        actionRow(icon: .`repeat`, color: .indigo,
                                  title: AppStrings.t("立即同步", lang: lang),
                                  detail: MeContract.syncStatus(settings: settings, state: store.syncState, lang: lang),
                                  value: nil, arrow: true,
                                  disabled: !MeContract.codeOk(settings.syncCode) || store.syncState.busy) {
                            HapticFeedback.play(.light)
                            onSyncNow()
                        }
                    }
                }

                let privacy = MeContract.privacyText(syncOn: settings.syncOn, lang: lang)
                card {
                    HStack(spacing: 12) {
                        iconBox(.shield, color: .gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(privacy.title).font(.subheadline)
                            Text(privacy.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                }
                .padding(.top, 12)

                Text(MeContract.versionText(version))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .background(DesignTokens.color("--bg", scheme: scheme))
        .fileExporter(isPresented: $exportOpen, document: exportDocument,
                      contentType: .json, defaultFilename: exportFilename) { result in
            if case .failure(let error) = result {
                toastCenter.show(text: FeatureStrings.t("导出失败：{msg}", lang: lang,
                                                        ["msg": error.localizedDescription]))
            }
        }
        .fileImporter(isPresented: $importOpen, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                guard let data = try? Data(contentsOf: url),
                      let text = String(data: data, encoding: .utf8) else { return }
                pendingImportText = text
                confirmImportOpen = true
            case .failure:
                break
            }
        }
        .alert(FeatureStrings.t("用备份里的 {a} 条任务替换当前的 {b} 条？", lang: lang,
                                ["a": String((BackupService.parseBackup(text: pendingImportText ?? "") ?? []).count),
                                 "b": String(store.tasks.count)]),
               isPresented: $confirmImportOpen) {
            Button(AppStrings.t("取消", lang: lang), role: .cancel) { pendingImportText = nil }
            Button(AppStrings.t("从备份恢复", lang: lang), role: .destructive) { confirmImport() }
        }
        .onAppear {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                // Swift 6 region isolation：只把标量跨隔离域传出去，不传 UNNotificationSettings。
                let denied = settings.authorizationStatus == .denied
                DispatchQueue.main.async { notifyDenied = denied }
            }
        }
    }

    // MARK: 顶部三块

    private var hero: some View {
        let counted = MeContract.todayCounted(store.tasks, today: today)
        let done = MeContract.todayDone(store.tasks, today: today)
        return VStack(alignment: .leading, spacing: 8) {
            Text(MeContract.greeting(hour: hour, lang: lang)).font(.subheadline).opacity(0.85)
            Text(MeContract.summary(store.tasks, today: today, lang: lang))
                .font(.title3.weight(.bold))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white)
                        .frame(width: geo.size.width * MeContract.ratio(store.tasks, today: today))
                }
                .frame(height: 6)
            }
            .frame(height: 6)
            Text(MeContract.doneTotalText(store.tasks, today: today, lang: lang)
                 + " (\(done)/\(counted.count))")
                .font(.caption)
                .opacity(0.85)
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: [
                Color(red: 0.294, green: 0.361, blue: 0.941),
                Color(red: 0.427, green: 0.361, blue: 0.941),
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerLarge))
        .padding(.horizontal, pageInset)
    }

    private var stats: some View {
        HStack(spacing: 10) {
            stat(MeContract.weekDone(store.tasks, today: today), "本周完成")
            stat(MeContract.pendingAll(store.tasks, today: today), "待办总数")
            stat(MeContract.overdue(store.tasks, today: today), "已过期",
                 warn: MeContract.overdue(store.tasks, today: today) > 0)
        }
        .padding(.horizontal, pageInset).padding(.top, 12)
    }

    private func stat(_ n: Int, _ key: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(.title2.weight(.bold)).monospacedDigit()
                .foregroundStyle(warn ? DesignTokens.color("--danger", scheme: scheme) : .primary)
            Text(AppStrings.t(key, lang: lang)).font(.caption)
                .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DesignTokens.color("--surface", scheme: scheme))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerMedium))
    }

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppStrings.t("近 7 天完成", lang: lang)).font(.headline)
                Spacer()
                Text(MeContract.last7Total(bars, lang: lang)).font(.caption)
                    .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(bars, id: \.day) { bar in
                    let isToday = bar.day == today
                    VStack(spacing: 4) {
                        Text(bar.count == 0 ? "" : "\(bar.count)")
                            .font(.caption2).monospacedDigit()
                            .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                            .frame(height: 14)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isToday
                                  ? DesignTokens.color("--accent", scheme: scheme)
                                  : DesignTokens.color("--fill-2", scheme: scheme))
                            .frame(maxWidth: 22)
                            .frame(height: max(4, bar.height * 80))
                        Text(bar.label).font(.caption2)
                            .foregroundStyle(isToday
                                ? DesignTokens.color("--accent", scheme: scheme)
                                : DesignTokens.color("--text-3", scheme: scheme))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(DesignTokens.color("--surface", scheme: scheme))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerLarge))
        .padding(.horizontal, pageInset).padding(.top, 12)
    }

    // MARK: 分组与行

    private func groupTitle(_ key: String) -> some View {
        Text(AppStrings.t(key, lang: lang))
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
            .padding(.horizontal, pageInset + 16).padding(.top, 22).padding(.bottom, 8)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(DesignTokens.color("--surface", scheme: scheme))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerLarge))
            .padding(.horizontal, pageInset)
    }

    private func iconBox(_ name: ReachIconName, color: Color) -> some View {
        ReachIcon(name: name, size: 18)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 10).fill(color))
    }

    private func actionRow(icon: ReachIconName, color: Color, title: String,
                           detail: String? = nil, value: String? = nil,
                           arrow: Bool = false, disabled: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconBox(icon, color: color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                if let value { Text(value).font(.subheadline).foregroundStyle(Color.accentColor) }
                if arrow {
                    ReachIcon(name: .chevronRight, size: 16)
                        .foregroundStyle(DesignTokens.color("--text-3", scheme: scheme))
                }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private func toggleRow(icon: ReachIconName, color: Color, title: String,
                           detail: String? = nil, value: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            iconBox(icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Toggle("", isOn: value).labelsHidden()
        }
        .padding(14)
    }

    private func binding(_ keyPath: WritableKeyPath<UISettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.settings[keyPath: keyPath] },
                set: { store.settings[keyPath: keyPath] = $0; HapticFeedback.play(.select) })
    }

    private func binding(_ keyPath: WritableKeyPath<UISettings, String>) -> Binding<String> {
        Binding(get: { store.settings[keyPath: keyPath] },
                set: { store.settings[keyPath: keyPath] = $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    // MARK: 备份

    private func exportBackup() {
        HapticFeedback.play(.light)
        do {
            let payload = try BackupService.makeSharePayload(
                store.tasks, isEnglish: lang == "en"
            )
            exportDocument = BackupJSONDocument(text: payload.text)
            exportFilename = payload.fileName
            exportOpen = true
        } catch {
            toastCenter.show(text: FeatureStrings.t("导出失败：{msg}", lang: lang,
                                                    ["msg": error.localizedDescription]))
        }
    }

    private func confirmImport() {
        guard let text = pendingImportText else { return }
        let result = BackupService.importBackup(
            text: text, currentCount: store.tasks.count,
            isEnglish: lang == "en", confirmed: true,
            replaceAll: { store.replaceAll($0) }
        )
        if let message = result.message { toastCenter.show(text: message) }
        if result.ok { HapticFeedback.play(.success) }
        pendingImportText = nil
    }
}
