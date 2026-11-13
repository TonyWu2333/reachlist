import Foundation
import SwiftUI

// T-03 原型 / VERIFY-03：观测 ATS 对 http:// 的拦截行为。
// 2026-11-14（T-10 / v0.24）VERIFY-03 已真机实测并回填：
// · Config/ATS-Development.xcconfig 与 Info.plist 现在按 OPEN-06=B 配置了最小例外
//   NSExceptionDomains.example.com.NSExceptionAllowsInsecureHTTPLoads = true；
// · http://example.com 因此放行（HTTP 200），不再返回 -1022；
// · 例外不含 NSIncludesSubdomains，故 http://www.example.com 仍被 -1022 拒绝，
//   原型的「域名明文 HTTP 被拒」断言改用这个未被覆盖的子域，同时验证例外的最小性；
// · 裸 IP（192.168.x.x）本就不受 -1022 拦截（v0.7 实测），本地联调不依赖例外。

struct ATSProbeResult: Identifiable, CustomStringConvertible {
    let id = UUID()
    let url: String
    let succeeded: Bool
    let httpStatus: Int?
    let errorDomain: String?
    let errorCode: Int?
    let errorDescription: String?
    let elapsedMS: Int

    var description: String {
        if succeeded { return "成功 · HTTP \(httpStatus ?? 0) · \(elapsedMS)ms" }
        return "失败 · \(errorDomain ?? "-") \(errorCode.map(String.init) ?? "-") · \(errorDescription ?? "-") · \(elapsedMS)ms"
    }
}

enum ATSProbe {
    static let lanHTTP = "http://127.0.0.1:8765/probe.json"
    static let publicHTTP = "http://example.com"
    /// 未被 ATS 例外覆盖的子域（NSIncludesSubdomains 缺省为 false）。
    static let publicHTTPSubdomain = "http://www.example.com"
    static let publicHTTPS = "https://example.com"

    static func request(_ urlString: String, timeout: TimeInterval = 8) async -> ATSProbeResult {
        let started = Date()
        let elapsed: () -> Int = { Int(Date().timeIntervalSince(started) * 1000) }
        guard let url = URL(string: urlString) else {
            return ATSProbeResult(url: urlString, succeeded: false, httpStatus: nil,
                                  errorDomain: "invalidURL", errorCode: nil,
                                  errorDescription: "URL 无法解析", elapsedMS: elapsed())
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        do {
            let (_, response) = try await session.data(from: url)
            return ATSProbeResult(url: urlString, succeeded: true,
                                  httpStatus: (response as? HTTPURLResponse)?.statusCode,
                                  errorDomain: nil, errorCode: nil, errorDescription: nil,
                                  elapsedMS: elapsed())
        } catch let e as NSError {
            return ATSProbeResult(url: urlString, succeeded: false, httpStatus: nil,
                                  errorDomain: e.domain, errorCode: e.code,
                                  errorDescription: e.localizedDescription, elapsedMS: elapsed())
        }
    }
}

struct ATSProbeView: View {
    @State private var urlText = ATSProbe.lanHTTP
    @State private var results: [ATSProbeResult] = []
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section("请求地址") {
                    TextField("URL", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    HStack {
                        preset("HTTP 局域网", ATSProbe.lanHTTP)
                        preset("HTTP 公网", ATSProbe.publicHTTP)
                        preset("HTTPS", ATSProbe.publicHTTPS)
                    }
                    .buttonStyle(.borderless)
                    Button(busy ? "请求中…" : "发起请求") {
                        Task { await run(urlText) }
                    }
                    .disabled(busy)
                }

                Section("实测结果") {
                    if results.isEmpty {
                        Text("尚未请求").foregroundStyle(.secondary)
                    } else {
                        ForEach(results) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.url).font(.caption.monospaced()).textSelection(.enabled)
                                Text(r.description).font(.footnote)
                            }
                        }
                    }
                }

                Section("说明") {
                    Text("VERIFY-03 已实测（T-10 / v0.24）：Info.plist 按 OPEN-06=B 配置了最小例外 "
                         + "NSExceptionDomains.example.com.NSExceptionAllowsInsecureHTTPLoads = true，"
                         + "故 http://example.com 放行（HTTP 200）；"
                         + "未配置 NSIncludesSubdomains，子域 http://www.example.com 仍被 -1022 拒绝；"
                         + "裸 IP 主机不受 -1022 拦截（本机服务可达时 HTTP 200）。"
                         + "上架前需移除 Info.plist 的 ATS 段与 Config/ 的例外配置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("ATS VERIFY-03")
        }
    }

    private func preset(_ title: String, _ url: String) -> some View {
        Button(title) { urlText = url }
            .font(.caption)
    }

    @MainActor
    private func run(_ url: String) async {
        busy = true
        let r = await ATSProbe.request(url)
        results.insert(r, at: 0)
        print("ATS-PROBE \(r.url) | \(r.description)")
        busy = false
    }
}
