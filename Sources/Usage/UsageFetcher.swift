import Foundation

/// Provider quota readings come only from the user's installed interactive
/// CLIs. This module never reads auth.json, Keychain entries, OAuth tokens, or
/// a provider HTTP endpoint.
enum UsageFetcher {
    static func fetchClaude() async -> AppUsage {
        let configuration = await MainActor.run {
            CLIProviderConfigStore.shared.claudeProxyURL
        }
        guard isProxy(configuration) else { return errorPair("proxy required") }
        guard isDirectory(CLIProviderConfigStore.statusWorkdir) else { return errorPair("claude workdir required") }
        guard let executable = executable(named: "claude") else { return errorPair("claude not found") }

        let quotaTranscript = await CLIStatusProbe.run(.init(
            provider: .claude, command: .usage,
            executable: executable, proxyURL: configuration,
            workdir: CLIProviderConfigStore.statusWorkdir, codexHome: nil, codexFullAccess: false
        ))
        let quotaUsage = CLIUsageParser.parseClaude(
            quotaTranscript.text, timedOut: quotaTranscript.timedOut
        )
        return quotaUsage
    }

    /// Reads only Claude's Login method. Quota windows remain owned by
    /// `fetchClaude()` so this secondary screen can never delay their first
    /// publication or overwrite their parser state.
    static func fetchClaudeLoginMethod() async -> String? {
        let proxy = await MainActor.run { CLIProviderConfigStore.shared.claudeProxyURL }
        guard isProxy(proxy),
              isDirectory(CLIProviderConfigStore.statusWorkdir),
              let executable = executable(named: "claude")
        else { return nil }
        let loginTranscript = await CLIStatusProbe.run(.init(
            provider: .claude, command: .status,
            executable: executable, proxyURL: proxy,
            workdir: CLIProviderConfigStore.statusWorkdir, codexHome: nil, codexFullAccess: false
        ))
        return CLIUsageParser.claudeLoginMethod(loginTranscript.text)
    }

    static func fetchCodex(profile: CodexCLIProfile, workdir: String) async -> AppUsage {
        if profile.effectiveQuotaMode == .api { return apiOnlyUsage() }
        guard !profile.expandedHome.isEmpty,
              FileManager.default.fileExists(atPath: profile.expandedHome)
        else { return errorPair("codex home required") }
        let proxy = profile.proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard proxy.isEmpty || isProxy(proxy) else { return errorPair("codex proxy invalid") }
        guard isDirectory(workdir) else { return errorPair("codex workdir required") }
        guard let executable = executable(named: "codex") else { return errorPair("codex not found") }

        let transcript = await CLIStatusProbe.run(.init(
            provider: .codex, executable: executable, proxyURL: proxy,
            workdir: workdir, codexHome: profile.expandedHome, codexFullAccess: false
        ))
        let usage = CLIUsageParser.parseCodex(transcript.text, timedOut: transcript.timedOut)
        if profile.effectiveQuotaMode == .subscription, usage.plan == "api" {
            return noSubscriptionUsage(plan: "api", message: "subscription quota unavailable")
        }
        return usage
    }

    static func errorPair(_ message: String) -> AppUsage {
        AppUsage(
            fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: message),
            weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: message)
        )
    }

    static func apiOnlyUsage() -> AppUsage {
        noSubscriptionUsage(plan: "api")
    }

    static func noSubscriptionUsage(
        plan: String, message: String = "API/custom mode — no subscription quota"
    ) -> AppUsage {
        AppUsage(
            fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: message),
            weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: message),
            plan: plan
        )
    }

    static func unauthenticatedUsage() -> AppUsage {
        errorPair("not logged in")
    }

    private static func executable(named name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            home.appendingPathComponent(".local/bin/\(name)").path,
            home.appendingPathComponent(".claude/local/\(name)").path,
            "/usr/bin/\(name)",
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true)
                    .appendingPathComponent(name).path
            })
        }
        var seen = Set<String>()
        return candidates.first {
            seen.insert($0).inserted && FileManager.default.isExecutableFile(atPath: $0)
        }
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
    static func parseClaude(
        _ text: String, timedOut: Bool, loginMethodText: String? = nil
    ) -> AppUsage {
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
        let modelWeeks = modelWeekReadings(in: screen)
        let identityText = loginMethodText ?? text
        let plan = claudePlan(in: identityText) ?? claudePlan(in: text)
        if isUnauthenticated(identityText) || isUnauthenticated(text) {
            return UsageFetcher.unauthenticatedUsage()
        }
        if let plan, isNonSubscriptionPlan(plan) {
            return UsageFetcher.noSubscriptionUsage(plan: plan)
        }
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
        if !modelWeeks.isEmpty {
            for (index, modelWeek) in modelWeeks.enumerated() {
                windows.append(detail(
                    id: "claude.week.model.\(quotaID(modelWeek.label, fallback: index))",
                    label: "Current week (\(modelWeek.label))",
                    reading: (modelWeek.percent, modelWeek.reset)
                ))
            }
        } else if let additionalWeek = ordered.dropFirst(2).first {
            // A damaged redraw can hide the parenthetical model label while
            // leaving an ordered third window. Preserve the value without
            // inventing a model name such as Fable.
            windows.append(detail(
                id: "claude.week.model.unknown",
                label: "Current week (model-specific)", reading: additionalWeek
            ))
        }
        return AppUsage(
            fiveHour: window(used: session.percent, reset: session.reset),
            weekly: window(used: weekly.percent, reset: weekly.reset),
            plan: plan,
            windows: windows
        )
    }

    static func claudeLoginMethod(_ text: String) -> String? {
        if isUnauthenticated(text) { return "unauthenticated" }
        return claudePlan(in: text)
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
        // The first weekly row is the account-wide limit. Later weekly rows
        // belong to model-specific limits (for example Codex Spark) and stay
        // in `windows`, but must not replace the compact account-week card.
        let weekly = weekReadings.first
        let plan = codexPlan(in: text)
        if isUnauthenticated(text) { return UsageFetcher.unauthenticatedUsage() }
        // API-key sessions have no subscription quota by design. Treat this
        // as a recognized state instead of asking the user to retry a status
        // screen that cannot contain 5h/weekly limits. Local-log cost/token
        // aggregation remains available for the same configured CODEX_HOME.
        let noSubscriptionLimits = text.range(
            of: #"(?i)(api[- ]key|limits:\s*data\s+not\s+available|model\s+provider:)"#,
            options: .regularExpression
        ) != nil
        if noSubscriptionLimits {
            return UsageFetcher.noSubscriptionUsage(plan: "api")
        }
        guard fiveHour != nil || weekly != nil else {
            return UsageFetcher.errorPair(timedOut ? "codex timeout" : "status refresh pending")
        }
        var windows: [ProviderQuotaWindow] = []
        if let fiveHour {
            windows.append(detail(id: "codex.5h", label: "5h limit", reading: fiveHour))
        }
        for (index, item) in weekReadings.enumerated() {
            let label = index == 0 ? "Weekly limit" : "Model weekly limit \(index)"
            windows.append(detail(id: "codex.week.\(index)", label: label, reading: item))
        }
        return AppUsage(
            fiveHour: fiveHour.map { window(used: $0.percent, reset: $0.reset) } ?? .unknown,
            weekly: weekly.map { window(used: $0.percent, reset: $0.reset) } ?? .unknown,
            plan: plan,
            windows: windows
        )
    }

    private static func isUnauthenticated(_ text: String) -> Bool {
        text.range(
            of: #"(?i)(not\s+logged\s+in|please\s+(?:run\s+)?/?login|authentication\s+(?:required|failed))"#,
            options: .regularExpression
        ) != nil
    }

    private static func isNonSubscriptionPlan(_ plan: String) -> Bool {
        plan == "api" || plan == "third-party"
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

    private static func modelWeekReadings(
        in text: String
    ) -> [(label: String, percent: Int, reset: String)] {
        let pattern = #"(?is)Current\s+week\s*\((?!all\s+models\))([^\)]+)\).*?(\d{1,3})%\s*used.*?Resets\s*([^\r\n]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges >= 4,
                  let labelRange = Range(match.range(at: 1), in: text),
                  let percentRange = Range(match.range(at: 2), in: text),
                  let percent = Int(text[percentRange]),
                  let resetRange = Range(match.range(at: 3), in: text)
            else { return nil }
            let label = String(text[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let reset = String(text[resetRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, seen.insert("\(label)::\(percent)::\(reset)").inserted else { return nil }
            return (label, percent, reset)
        }
    }

    private static func quotaID(_ label: String, fallback: Int) -> String {
        let slug = label.lowercased().replacingOccurrences(
            of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression
        ).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "\(fallback)" : slug
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

    /// Claude's `/status` owns the actual login method. Subscription account
    /// labels are distinct from Console/API and managed-platform logins, so
    /// never infer a subscription tier from quota percentages or local costs.
    private static func claudePlan(in text: String) -> String? {
        let plan = #"Max(?:\s*(?:(?:x|×)\s*(?:5|20)|(?:5|20)\s*(?:x|×)))?|Pro|Team|Enterprise"#
        if let loginMethod = capture(
            in: text, pattern: #"(?im)Login\s+method\s*:\s*([^\r\n]+)"#
        ) {
            if let detailedSubscription = planCapture(in: loginMethod, patterns: [
                #"(?i)\(("# + plan + #")\)"#,
            ]) {
                return detailedSubscription
            }
            if let subscription = planCapture(in: loginMethod, patterns: [
                #"(?i)Claude\s+("# + plan + #")\b"#,
            ]) {
                return subscription
            }
            if loginMethod.range(
                of: #"(?i)(Anthropic\s+Console|API(?:\s+(?:key|account))?)"#,
                options: .regularExpression
            ) != nil {
                return "api"
            }
            if loginMethod.range(
                of: #"(?i)(Amazon\s+Bedrock|Microsoft\s+Foundry|Vertex\s+AI|third[- ]party)"#,
                options: .regularExpression
            ) != nil {
                return "third-party"
            }
        }
        return planCapture(in: text, patterns: [
            #"(?i)Account\s*:\s*[^\r\n]*?\(("# + plan + #")\)"#,
            #"(?i)(?:Plan|Subscription)\s*:\s*(?:Claude\s+)?("# + plan + #")\b"#,
            #"(?i)Claude\s+("# + plan + #")\b"#,
        ])
    }

    private static func codexPlan(in text: String) -> String? {
        let plan = #"Pro(?:\s*(?:(?:x|×)\s*(?:5|20)|(?:5|20)\s*(?:x|×)))?|Plus|Business|Enterprise"#
        return planCapture(in: text, patterns: [
            #"(?i)Account\s*:\s*[^\r\n]*?\(("# + plan + #")\)"#,
            #"(?i)\(("# + plan + #")\)"#,
        ])
    }

    private static func planCapture(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let raw = capture(in: text, pattern: pattern) else { continue }
            let base = raw.range(of: #"(?i)max|pro|plus|team|business|enterprise"#, options: .regularExpression)
                .map { String(raw[$0]).lowercased() }
            guard let base else { continue }
            guard raw.range(of: #"(?i)(?:x|×)"#, options: .regularExpression) != nil,
                  let factor = capture(in: raw, pattern: #"(5|20)"#)
            else { return base }
            return "\(base) ×\(factor)"
        }
        return nil
    }

    private static func resetDate(_ text: String) -> Date? {
        let timeZoneID = capture(in: text, pattern: #"\(([A-Za-z_]+/[A-Za-z_]+)\)"#)
        let timeZone = timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
        let trimmed = text
            .replacingOccurrences(of: #"\s*\([A-Za-z_]+/[A-Za-z_]+\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        if let relative = relativeSeconds(trimmed) {
            // Relative CLI captions are refreshed every poll. Normalize the
            // result to the minute so the alert engine sees one reset window
            // instead of a new boundary caused only by changing seconds.
            let date = now.addingTimeInterval(relative)
            return Date(timeIntervalSinceReferenceDate: floor(date.timeIntervalSinceReferenceDate / 60) * 60)
        }

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
        let days = Int(capture(in: text, pattern: #"(?i)(\d+)d"#) ?? "0") ?? 0
        let hours = Int(capture(in: text, pattern: #"(?i)(\d+)h"#) ?? "0") ?? 0
        let minutes = Int(capture(in: text, pattern: #"(?i)(\d+)m"#) ?? "0") ?? 0
        let total = days * 86400 + hours * 3600 + minutes * 60
        return total > 0 ? TimeInterval(total) : nil
    }
}
