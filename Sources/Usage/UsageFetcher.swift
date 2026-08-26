import Foundation

/// Provider quota readings come only from the user's installed interactive
/// CLIs. This module never reads auth.json, Keychain entries, OAuth tokens, or
/// a provider HTTP endpoint.
enum UsageFetcher {
    static func fetchClaude() async -> AppUsage {
        let configuration = await MainActor.run {
            (CLIProviderConfigStore.shared.claudeProxyURL, CLIProviderConfigStore.shared.claudeWorkdir)
        }
        guard isProxy(configuration.0) else { return errorPair("proxy required") }
        guard isDirectory(configuration.1) else { return errorPair("claude workdir required") }
        guard let executable = executable(named: "claude") else { return errorPair("claude not found") }

        let transcript = await CLIStatusProbe.run(.init(
            provider: .claude, executable: executable, proxyURL: configuration.0,
            workdir: configuration.1, codexHome: nil, codexFullAccess: false
        ))
        return CLIUsageParser.parseClaude(transcript.text, timedOut: transcript.timedOut)
    }

    /// The island headline uses the first manually-configured, enabled Codex
    /// profile. Every configured profile remains isolated in configuration;
    /// expanded settings can surface them individually.
    static func fetchCodex() async -> AppUsage {
        guard let profile = await MainActor.run(body: {
            CLIProviderConfigStore.shared.activeCodexProfiles.first
        }) else { return errorPair("add codex profile") }
        let workdir = await MainActor.run { CLIProviderConfigStore.shared.codexWorkdir }
        return await fetchCodex(profile: profile, workdir: workdir)
    }

    static func fetchCodex(profile: CodexCLIProfile, workdir: String) async -> AppUsage {
        guard !profile.expandedHome.isEmpty,
              FileManager.default.fileExists(atPath: profile.expandedHome)
        else { return errorPair("codex home required") }
        guard isProxy(profile.proxyURL) else { return errorPair("proxy required") }
        guard isDirectory(workdir) else { return errorPair("codex workdir required") }
        guard let executable = executable(named: "codex") else { return errorPair("codex not found") }

        let transcript = await CLIStatusProbe.run(.init(
            provider: .codex, executable: executable, proxyURL: profile.proxyURL,
            workdir: workdir, codexHome: profile.expandedHome, codexFullAccess: false
        ))
        return CLIUsageParser.parseCodex(transcript.text, timedOut: transcript.timedOut)
    }

    static func errorPair(_ message: String) -> AppUsage {
        AppUsage(
            fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: message),
            weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: message)
        )
    }

    private static func executable(named name: String) -> String? {
        for path in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        where FileManager.default.isExecutableFile(atPath: path) { return path }
        return nil
    }

    private static func isProxy(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return (url.scheme == "http" || url.scheme == "https") && url.host != nil
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

enum CLIUsageParser {
    static func parseClaude(_ text: String, timedOut: Bool) -> AppUsage {
        // The rendered TUI uses box/block glyphs for separators and progress
        // bars. Normalize them to whitespace before matching its labels.
        let screen = text.replacingOccurrences(
            of: #"[\u{2500}-\u{259F}]"#, with: " ", options: .regularExpression
        )
        let session = reading(
            in: screen,
            pattern: #"(?is)Curren(?:t)?\s+session.*?(\d{1,3})%\s*used.*?Resets\s*([^\r\n]+)"#
        )
        let weekly = reading(
            in: screen,
            pattern: #"(?is)Current\s+week\s*\(all\s+models\).*?(\d{1,3})%\s*used.*?Resets\s*([^\r\n]+)"#
        )
        let fable = reading(
            in: screen,
            pattern: #"(?is)Current\s+week\s*\(Fable\).*?(\d{1,3})%\s*used.*?Resets\s*([^\r\n]+)"#
        )
        // At the moment the Usage tab has finished drawing, the first two
        // percent/reset pairs are necessarily current-session then all-model
        // week. This fallback handles Claude redraws that overwrite part of
        // the label while preserving label-first parsing for normal text.
        let ordered = readings(
            in: screen,
            pattern: #"(?is)(\d{1,3})%\s*used.*?Resets\s*([^\r\n]+)"#
        )
        guard let session = session ?? ordered.first,
              let weekly = weekly ?? ordered.dropFirst().first
        else {
            return UsageFetcher.errorPair(timedOut ? "claude timeout" : "usage parse error")
        }
        var windows = [
            detail(id: "claude.current", label: "Current session", reading: session),
            detail(id: "claude.week.all", label: "Current week (all models)", reading: weekly),
        ]
        if let fable = fable ?? ordered.dropFirst(2).first {
            windows.append(detail(id: "claude.week.fable", label: "Current week (Fable)", reading: fable))
        }
        return AppUsage(
            fiveHour: window(used: session.percent, reset: session.reset),
            weekly: window(used: weekly.percent, reset: weekly.reset),
            plan: capture(in: text, pattern: #"(?i)Claude\s+(Max|Pro|Team|Enterprise)"#),
            windows: windows
        )
    }

    static func parseCodex(_ text: String, timedOut: Bool) -> AppUsage {
        let fiveHours = readings(
            in: text,
            pattern: #"(?is)5h\s+limit:.*?(\d{1,3})%\s+left.*?\(resets\s+([^\)]+)\)"#,
            remaining: true
        )
        let weekReadings = uniqueReadings(readings(
            in: text,
            pattern: #"(?is)Weekly\s+limit:.*?(\d{1,3})%\s+left.*?\(resets\s+([^\)]+)\)"#,
            remaining: true
        ))
        // A TUI redraw re-emits its full table into the PTY transcript. The
        // last 5h value is the final screen; weekly rows are de-duplicated so
        // that one account weekly limit plus one model weekly limit stays two
        // rows instead of being repeated for each /status refresh.
        let fiveHour = fiveHours.last
        let weekly = weekReadings.last
        let plan = capture(in: text, pattern: #"(?i)\((Pro|Plus|Business|Enterprise)\)"#)
        // API-key sessions have no subscription quota by design. Treat this
        // as a recognized state instead of asking the user to retry a status
        // screen that cannot contain 5h/weekly limits. Local-log cost/token
        // aggregation remains available for the same configured CODEX_HOME.
        if fiveHour == nil || weekly == nil,
           text.range(of: #"(?i)api[- ]key"#, options: .regularExpression) != nil {
            return AppUsage(
                fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: "API mode — no subscription quota"),
                weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: "API mode — no subscription quota"),
                plan: "api"
            )
        }
        guard let fiveHour, let weekly else {
            return UsageFetcher.errorPair(timedOut ? "codex timeout" : "status refresh pending")
        }
        var windows = [detail(id: "codex.5h", label: "5h limit", reading: fiveHour)]
        for (index, item) in weekReadings.enumerated() {
            let label = index == 0 ? "Weekly limit" : "Model weekly limit \(index)"
            windows.append(detail(id: "codex.week.\(index)", label: label, reading: item))
        }
        return AppUsage(
            fiveHour: window(used: fiveHour.percent, reset: fiveHour.reset),
            weekly: window(used: weekly.percent, reset: weekly.reset),
            plan: plan,
            windows: windows
        )
    }

    private static func window(used: Int, reset: String) -> WindowUsage {
        WindowUsage(
            usedPercent: min(1, max(0, Double(used) / 100)),
            resetAt: resetDate(reset), error: nil
        )
    }

    private static func detail(id: String, label: String, reading: (percent: Int, reset: String)) -> ProviderQuotaWindow {
        ProviderQuotaWindow(
            id: id, label: label, usedPercent: Double(reading.percent) / 100,
            resetAt: resetDate(reading.reset)
        )
    }

    private static func reading(in text: String, pattern: String, remaining: Bool = false) -> (percent: Int, reset: String)? {
        readings(in: text, pattern: pattern, remaining: remaining).first
    }

    private static func readings(in text: String, pattern: String, remaining: Bool = false) -> [(percent: Int, reset: String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let pctRange = Range(match.range(at: 1), in: text),
                  let raw = Int(text[pctRange]),
                  let resetRange = Range(match.range(at: 2), in: text)
            else { return nil }
            return (remaining ? 100 - raw : raw, String(text[resetRange]).trimmingCharacters(in: .whitespaces))
        }
    }

    private static func uniqueReadings(
        _ readings: [(percent: Int, reset: String)]
    ) -> [(percent: Int, reset: String)] {
        var seen = Set<String>()
        return readings.filter { item in
            seen.insert("\(item.percent)::\(item.reset)").inserted
        }
    }

    private static func capture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let result = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[result]).lowercased()
    }

    private static func resetDate(_ text: String) -> Date? {
        let timeZoneID = capture(in: text, pattern: #"\(([A-Za-z_]+/[A-Za-z_]+)\)"#)
        let timeZone = timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
        let trimmed = text
            .replacingOccurrences(of: #"\s*\([A-Za-z_]+/[A-Za-z_]+\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        if let relative = relativeSeconds(trimmed) { return now.addingTimeInterval(relative) }

        let candidates: [(String, String)] = [
            ("h:mma", trimmed.replacingOccurrences(of: " ", with: "")),
            ("HH:mm", trimmed),
            ("MMM d 'at' h a", normalizedAMPM(trimmed)),
            ("HH:mm 'on' d MMM", trimmed),
        ]
        for (format, input) in candidates {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            guard var parsed = formatter.date(from: input) else { continue }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = formatter.timeZone
            if format == "h:mma" || format == "HH:mm" {
                let clock = calendar.dateComponents([.hour, .minute], from: parsed)
                parsed = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: now) ?? parsed
                if parsed < now { parsed = calendar.date(byAdding: .day, value: 1, to: parsed) ?? parsed }
            } else {
                var parts = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
                parts.year = calendar.component(.year, from: now)
                parsed = calendar.date(from: parts) ?? parsed
                if parsed < now { parsed = calendar.date(byAdding: .year, value: 1, to: parsed) ?? parsed }
            }
            return parsed
        }
        return nil
    }

    private static func normalizedAMPM(_ text: String) -> String {
        text.replacingOccurrences(of: "pm", with: " pm", options: .caseInsensitive)
            .replacingOccurrences(of: "am", with: " am", options: .caseInsensitive)
    }

    private static func relativeSeconds(_ text: String) -> TimeInterval? {
        let hours = Int(capture(in: text, pattern: #"(?i)(\d+)h"#) ?? "0") ?? 0
        let minutes = Int(capture(in: text, pattern: #"(?i)(\d+)m"#) ?? "0") ?? 0
        let total = hours * 3600 + minutes * 60
        return total > 0 ? TimeInterval(total) : nil
    }
}
