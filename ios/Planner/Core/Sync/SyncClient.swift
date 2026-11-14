import Foundation

// MARK: - M-08 同步客户端（T-10）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/lib/sync.js（99 行）与 §2.6 网络协议。
// 服务器零改动（F-15.3）：POST /api/sync、GET /api/wait?rev=N、Bearer token、
// body { tasks, deleted, meta:{ tz } }；合并只调 T-05 的 MergeEngine。
//
// 设计：网络经 `SyncTransport` 注入，因此契约测试可用 MockTransport 逐项断言
// 请求 / 状态机，端到端联调用 URLSessionSyncTransport 打真实本地 server（OPEN-13=A）。
// App 生命周期由 M-20 调用 setActive / start / stop，本任务不改 App 文件。
//
// 与 JS 的两处实现层对齐（不改协议语义）：
// 1. JS 的 `document.visibilityState === 'visible'` → `active` 标志，由 App 的 scenePhase 设置。
// 2. JS 的 `withTimeout(fetch, 15s/40s)` → URLRequest.timeoutInterval；
//    JSON 解码失败按 `String(describing:)` 保留（正常服务器不会返回非法 JSON）。

struct SyncRequest: Sendable {
    let url: URL
    let method: String
    let token: String
    let body: Data?
    let timeout: TimeInterval
}

struct SyncResponse: Sendable {
    let status: Int
    let data: Data
}

/// Swift 6 严格并发：客户端在 @MainActor，请求会跨隔离域交给传输层，故协议须 Sendable。
protocol SyncTransport: AnyObject, Sendable {
    func request(_ request: SyncRequest) async throws -> SyncResponse
}

final class URLSessionSyncTransport: SyncTransport, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func request(_ r: SyncRequest) async throws -> SyncResponse {
        var req = URLRequest(url: r.url, timeoutInterval: r.timeout)
        req.httpMethod = r.method
        req.setValue("Bearer \(r.token)", forHTTPHeaderField: "authorization")
        if let body = r.body {
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = body
        }
        let (data, response) = try await session.data(for: req)
        return SyncResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }
}

/// 单元测试 / 联调夹具用：按序返回预置响应或错误，并记录收到的请求。
final class MockSyncTransport: SyncTransport, @unchecked Sendable {
    private(set) var requests: [SyncRequest] = []
    private var responses: [SyncResponse] = []
    private var errors: [Error] = []

    init(responses: [SyncResponse] = [], errors: [Error] = []) {
        self.responses = responses
        self.errors = errors
    }

    func enqueue(_ response: SyncResponse) { responses.append(response) }
    func enqueue(_ error: Error) { errors.append(error) }

    func request(_ r: SyncRequest) async throws -> SyncResponse {
        requests.append(r)
        if !errors.isEmpty { throw errors.removeFirst() }
        if !responses.isEmpty { return responses.removeFirst() }
        return SyncResponse(status: 200, data: Data())
    }
}

// MARK: 服务器响应

private struct ServerState: Decodable {
    let tasks: [PlannerTask]
    let deleted: [String: Double]
    let meta: [String: String]
    let rev: Int

    enum CodingKeys: String, CodingKey { case tasks, deleted, meta, rev }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = (try? c.decode([PlannerTask].self, forKey: .tasks)) ?? []
        deleted = (try? c.decode([String: Double].self, forKey: .deleted)) ?? [:]
        meta = (try? c.decode([String: String].self, forKey: .meta)) ?? [:]
        rev = (try? c.decode(Int.self, forKey: .rev)) ?? -1
    }
}

private struct SyncFailure: Error { let message: String }

// MARK: 载荷编码

enum SyncPayloadCodec {
    /// `{ ...syncPayload(), meta: { tz } }` 的逐字等价输出（键序 tasks / deleted / meta）。
    static func encode(_ p: MergeState, tz: String) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let frag = { (v: Encodable) in
            String(data: try! encoder.encode(v), encoding: .utf8)!
        }
        let tasks = "[" + p.tasks.map { $0.jsJSONString() }.joined(separator: ",") + "]"
        let deleted = "{" + p.deleted.keys.sorted().map {
            "\(frag($0)):\(frag(p.deleted[$0]!))"
        }.joined(separator: ",") + "}"
        let out = "{\"tasks\":\(tasks),\"deleted\":\(deleted),\"meta\":{\"tz\":\(frag(tz))}}"
        return Data(out.utf8)
    }
}

// MARK: 客户端

@MainActor
final class SyncClient {

    private let store: TaskStore
    private let transport: SyncTransport
    private let now: () -> Double
    private let timeZone: () -> String

    /// `sync.js:11` 的可观察状态。
    private(set) var state = SyncState()
    var onStateChange: ((SyncState) -> Void)?

    private var lastRev = -1
    private var again = false
    private var watching = false
    private var active = true
    private var watchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?

    init(
        store: TaskStore,
        transport: SyncTransport,
        now: @escaping () -> Double = { Date().timeIntervalSince1970 * 1000 },
        timeZone: @escaping () -> String = { TimeZone.current.identifier }
    ) {
        self.store = store
        self.transport = transport
        self.now = now
        self.timeZone = timeZone
    }

    // MARK: 配置与文案

    /// `sync.js:17` conf()：syncOn 关闭时返回 nil —— 默认一个网络请求都不发（§4.1.1）。
    func configuration() -> ConnectionCode? {
        let s = store.settings
        return s.syncOn ? SyncCode.parse(s.syncCode) : nil
    }

    /// 临时语言判定（`i18n.js:systemLang` 的 `/^zh\b/i` 等价），T-19 的 M-23 落地后替换。
    private func isEnglish() -> Bool {
        switch store.settings.lang {
        case "zh": return false
        case "en": return true
        default:
            let preferred = Locale.preferredLanguages.first ?? "zh"
            return !preferred.lowercased().hasPrefix("zh")
        }
    }

    private func notifyState() { onStateChange?(state) }

    // MARK: syncNow（sync.js:20-55）

    func syncNow() async {
        guard let c = configuration() else { return }
        if state.busy { again = true; return }   // 同步中又来改动：结束后再跑一次
        state.busy = true
        notifyState()
        defer {
            state.busy = false
            notifyState()
            if again {
                again = false
                Task { await self.syncNow() }
            }
        }

        do {
            let payload = store.syncPayload()
            let body = SyncPayloadCodec.encode(payload, tz: timeZone())
            let url = URL(string: c.url + "/api/sync")!
            let res = try await transport.request(
                SyncRequest(url: url, method: "POST", token: c.token, body: body, timeout: 15))
            if res.status == 401 {
                throw SyncFailure(message: SyncStrings.wrongToken(isEnglish: isEnglish()))
            }
            guard (200..<300).contains(res.status) else {
                throw SyncFailure(message: SyncStrings.serverReturned(res.status, isEnglish: isEnglish()))
            }
            let server = try JSONDecoder().decode(ServerState.self, from: res.data)
            store.applyRemote(MergeState(tasks: server.tasks, deleted: server.deleted, meta: server.meta))
            lastRev = server.rev
            state.at = now()
            state.error = ""
            notifyState()
            startWatching()
        } catch let failure as SyncFailure {
            state.error = failure.message
            notifyState()
        } catch {
            let ns = error as NSError
            let isNetwork = ns.domain == NSURLErrorDomain
                || ns.localizedDescription.lowercased().contains("network")
                || ns.localizedDescription.lowercased().contains("connect")
            state.error = isNetwork
                ? SyncStrings.cannotReach(isEnglish: isEnglish())
                : ns.localizedDescription
            notifyState()
        }
    }

    // MARK: 长轮询（sync.js:57-85）

    private func startWatching() {
        guard !watching, active, configuration() != nil else { return }
        watching = true
        watchTask = Task { [weak self] in
            var backoff: Double = 2
            while let self, self.active, self.configuration() != nil {
                guard let c = self.configuration() else { break }
                do {
                    let url = URL(string: "\(c.url)/api/wait?rev=\(self.lastRev)")!
                    let res = try await self.transport.request(
                        SyncRequest(url: url, method: "GET", token: c.token, body: nil, timeout: 40))
                    guard (200..<300).contains(res.status) else { throw SyncFailure(message: "\(res.status)") }
                    let obj = (try? JSONSerialization.jsonObject(with: res.data)) as? [String: Any]
                    let rev = obj?["rev"] as? Int ?? self.lastRev
                    backoff = 2
                    if rev != self.lastRev {
                        await self.syncNow()
                        if self.lastRev != rev {
                            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                        }
                    }
                } catch {
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    backoff = min(backoff * 2, 30)
                }
            }
            self?.watching = false
        }
    }

    // MARK: 触发时机（sync.js:90-99 / F-12.3）

    /// 本地改动 → 2 秒防抖 → syncNow。
    func localChanged() {
        guard configuration() != nil else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.syncNow()
        }
    }

    /// initSync()：注册本地改动、前台每 60 秒兜底、启动时同步一次。
    func start() {
        store.onLocalChange { [weak self] in self?.localChanged() }
        tickerTask = Task { [weak self] in
            while let self, self.active {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard self.active, self.configuration() != nil else { continue }
                await self.syncNow()
            }
        }
        Task { [weak self] in await self?.syncNow() }
    }

    /// App 回前台 / 退后台时调用（对应 visibilitychange）。
    func setActive(_ value: Bool) {
        active = value
        if value {
            startWatching()
        } else {
            watchTask?.cancel()
            watchTask = nil
            watching = false
            store.flushNow()
        }
    }

    func stop() {
        active = false
        watchTask?.cancel()
        debounceTask?.cancel()
        tickerTask?.cancel()
        watching = false
    }
}
