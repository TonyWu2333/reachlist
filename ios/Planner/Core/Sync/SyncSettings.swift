import Foundation

// MARK: - M-09 连接码与同步状态（T-10）
//
// 逐字对齐 baseline_commit 97a7c4c 的 src/lib/sync.js:11-17 与 agent/cli.js:71。
// 错误文案的英文值逐字取自 src/lib/i18n-en.js:50-52 与 i18n-en/pages.js:46-52，
// 与 Web 端术语表一致（A-35）；M-23 落地后由 T-19 包一层，调用点不变。

struct ConnectionCode: Equatable, Sendable {
    let url: String
    let token: String
}

enum SyncCode {
    /// `^(https?:\/\/[^\s#]+?)\/?#([A-Za-z0-9._~-]{16,})$`
    /// 与 `src/lib/sync.js:14`、`agent/cli.js:71` 两处相同的正则。
    private static let pattern = #"^(https?://[^\s#]+?)/?#([A-Za-z0-9._~-]{16,})$"#

    static func parse(_ code: String?) -> ConnectionCode? {
        let text = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let re = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 3,
              let u = Range(m.range(at: 1), in: text), let t = Range(m.range(at: 2), in: text) else {
            return nil
        }
        return ConnectionCode(url: String(text[u]), token: String(text[t]))
    }
}

/// `sync.js:11` 的 `syncState`：busy / at / error。
struct SyncState: Equatable, Sendable {
    var busy: Bool = false
    var at: Double = 0
    var error: String = ""
}

/// 同步相关中英文案。中文原文即键，英文值来自上游 i18n-en（A-35 / A-43）。
enum SyncStrings {
    static func wrongToken(isEnglish: Bool) -> String {
        isEnglish ? "Wrong token" : "令牌不对"
    }

    static func serverReturned(_ code: Int, isEnglish: Bool) -> String {
        isEnglish ? "Server returned \(code)" : "服务器返回 \(code)"
    }

    static func cannotReach(isEnglish: Bool) -> String {
        isEnglish ? "Can't reach the server" : "连不上服务器"
    }

    /// MeView 的连接码格式错误提示（F-09.8 / A-35）。
    static func invalidCode(isEnglish: Bool) -> String {
        isEnglish
            ? "Invalid connection code. It should look like address#token"
            : "连接码格式不对：应该是 地址#令牌"
    }

    static func syncing(isEnglish: Bool) -> String { isEnglish ? "Syncing…" : "正在同步…" }

    static func syncFailed(_ msg: String, isEnglish: Bool) -> String {
        isEnglish ? "Sync failed: \(msg)" : "同步失败：\(msg)"
    }

    static func syncedAt(_ time: String, host: String, isEnglish: Bool) -> String {
        isEnglish ? "Synced · \(time) · \(host)" : "已同步 · \(time) · \(host)"
    }

    static func neverSynced(isEnglish: Bool) -> String {
        isEnglish ? "Not synced yet" : "还没同步过"
    }

    static func syncComplete(isEnglish: Bool) -> String {
        isEnglish ? "Sync complete" : "同步完成"
    }
}
