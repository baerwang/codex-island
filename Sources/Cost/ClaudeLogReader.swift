import Foundation

/// Walks the local Claude Code session JSONL files and emits TokenEvents for
/// every assistant message that recorded usage. Mirrors ccusage's data path:
///   - reads from ~/.claude/projects/**/*.jsonl AND ~/.config/claude/projects/**/*.jsonl
///   - honors CLAUDE_CONFIG_DIR (comma-separated) when set
///   - dedupes by `messageId:requestId`
///   - skips synthetic placeholder models
///
/// Per-file parse results are memoized in `~/Library/Caches/.../claude-parse-cache.v1.json`
/// keyed by (path, mtime, size). Between two 5/15/30-minute polls almost no
/// file has changed, so the steady-state refresh skips the JSONL scan entirely
/// and only walks the events list to dedup + filter by cutoff.
enum ClaudeLogReader {
    /// Walk the configured project roots and return every usage-bearing
    /// assistant turn from the last `lookbackDays` days. Pure file IO; no
    /// network. Safe to call from a background thread.
    static func scan(lookbackDays: Int = 30) -> [TokenEvent] {
        let cutoff = Date().addingTimeInterval(-Double(lookbackDays) * 86400)
        var seen = Set<String>()
        var out: [TokenEvent] = []

        LogParseCache.walk(
            roots: projectRoots(),
            cutoff: cutoff,
            cacheFilename: "claude-parse-cache.v1.json",
            cacheVersion: cacheVersion,
            parse: parseFile(at:),
            emit: { (ev: CachedEvent) in
                guard ev.timestamp >= cutoff else { return }
                if !ev.dedupKey.isEmpty {
                    if seen.contains(ev.dedupKey) { return }
                    seen.insert(ev.dedupKey)
                }
                out.append(TokenEvent(
                    provider: .claude,
                    timestamp: ev.timestamp,
                    model: ev.model,
                    inputTokens: ev.inputTokens,
                    outputTokens: ev.outputTokens,
                    cacheCreationTokens: ev.cacheCreationTokens,
                    cacheReadTokens: ev.cacheReadTokens,
                    projectID: ev.projectID,
                    projectName: ev.projectName
                ))
            }
        )
        return out
    }

    private static func projectRoots() -> [URL] {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !env.isEmpty {
            return env.split(separator: ",").map {
                URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces))
                    .appendingPathComponent("projects", isDirectory: true)
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            home.appendingPathComponent(".config/claude/projects", isDirectory: true),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Parse a single file end-to-end. Caller is responsible for cutoff
    /// filtering — the cache keeps everything we found so a later scan with
    /// a wider window doesn't have to re-read.
    private static func parseFile(at url: URL) -> [CachedEvent] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFractional = ISO8601DateFormatter()
        formatterNoFractional.formatOptions = [.withInternetDateTime]

        var out: [CachedEvent] = []
        LogParseCache.streamLines(at: url) { lineData in
            if let event = parseLine(
                lineData,
                formatter: formatter,
                formatterNoFractional: formatterNoFractional
            ) {
                out.append(event)
            }
        }
        return out
    }

    /// Returns nil for non-assistant rows, synthetic placeholder models,
    /// noop usage entries, and lines that fail to parse.
    private static func parseLine(
        _ lineData: Data,
        formatter: ISO8601DateFormatter,
        formatterNoFractional: ISO8601DateFormatter
    ) -> CachedEvent? {
        guard let raw = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
        else { return nil }

        // Only assistant messages carry usage. The shape is consistent
        // across Claude Code versions: top-level `type == "assistant"`,
        // `message.usage`, `message.model`, `message.id`, top-level
        // `requestId`, top-level `timestamp`.
        guard (raw["type"] as? String) == "assistant",
              let message = raw["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String
        else { return nil }

        // Skip synthetic placeholder models (ccusage parity).
        if model == "<synthetic>" || model.hasPrefix("synthetic") { return nil }

        let messageId = message["id"] as? String ?? ""
        let requestId = raw["requestId"] as? String ?? ""

        // ccusage requires BOTH IDs for dedup; entries missing either
        // are processed without dedup. Match that behavior so a partial
        // log doesn't silently drop turns.
        let dedupKey = (messageId.isEmpty || requestId.isEmpty)
            ? ""
            : "\(messageId):\(requestId)"

        let timestampString = raw["timestamp"] as? String ?? ""
        let timestamp = formatter.date(from: timestampString)
            ?? formatterNoFractional.date(from: timestampString)
            ?? Date.distantPast

        let input = (usage["input_tokens"] as? Int) ?? 0
        let output = (usage["output_tokens"] as? Int) ?? 0
        let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
        let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
        let projectID = (raw["cwd"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip noop entries — ccusage filters these so totals match exactly.
        if input == 0 && output == 0 && cacheCreate == 0 && cacheRead == 0 { return nil }

        return CachedEvent(
            timestamp: timestamp,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cacheCreate,
            cacheReadTokens: cacheRead,
            projectID: projectID?.isEmpty == false ? projectID : nil,
            projectName: projectID?.isEmpty == false ? URL(fileURLWithPath: projectID!).lastPathComponent : nil,
            dedupKey: dedupKey
        )
    }

    // MARK: - Per-file cache

    /// Bump on any breaking change to `CachedEvent` to force a clean re-parse.
    private static let cacheVersion = 2

    private struct CachedEvent: Codable {
        let timestamp: Date
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int
        let projectID: String?
        let projectName: String?
        let dedupKey: String
    }
}
