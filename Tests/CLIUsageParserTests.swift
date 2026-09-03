import Foundation

@main
struct CLIUsageParserTests {
    static func main() {
        var failures = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if condition() { print("PASS \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }

        let claude = CLIUsageParser.parseClaude("""
        Current session
        ████ 8% used
        Resets 1:40pm (Asia/Shanghai)
        Current week (all models)
        █████████████████▌ 35% used
        Resets Aug 31 at 12pm (Asia/Shanghai)
        Current week (Fable)
        ██████████████████████████████ 61% used
        Resets Aug 31 at 12pm (Asia/Shanghai)
        Claude Max
        """, timedOut: false)
        expect(claude.fiveHour.percentInt == 8, "Claude current session parses")
        expect(claude.weekly.percentInt == 35, "Claude all-model weekly parses")
        expect(claude.windows.count == 3, "Claude Fable window retained")
        expect(claude.windows.allSatisfy { $0.resetAt != nil }, "Claude timezone-tagged resets parse")
        expect(claude.plan == "max", "Claude plan parses")

        let claudeSonnetWindow = CLIUsageParser.parseClaude("""
        Current session 8% used Resets 1:40pm (Asia/Shanghai)
        Current week (all models) 35% used Resets Aug 31 at 12pm (Asia/Shanghai)
        Current week (Sonnet only) 61% used Resets Aug 31 at 12pm (Asia/Shanghai)
        """, timedOut: false)
        expect(claudeSonnetWindow.windows.count == 3, "Claude model-specific weekly window is retained")
        expect(
            claudeSonnetWindow.windows.last?.label == "Current week (Sonnet only)",
            "Claude model-specific window keeps its real label"
        )

        let claudeStatusPlan = CLIUsageParser.parseClaude("""
        Account: user@example.com (Claude Max 20x)
        Current session
        ████ 8% used
        Resets 1:40pm (Asia/Shanghai)
        Current week (all models)
        █████████████████▌ 35% used
        Resets Aug 31 at 12pm (Asia/Shanghai)
        """, timedOut: false)
        expect(claudeStatusPlan.plan == "max ×20", "Claude status preserves stated Max multiplier")

        let claudeLoginMethod = CLIUsageParser.parseClaude("""
        Login method:     Claude Max account
        Current session
        ████ 8% used
        Resets 1:40pm (Asia/Shanghai)
        Current week (all models)
        █████████████████▌ 35% used
        Resets Aug 31 at 12pm (Asia/Shanghai)
        """, timedOut: false)
        expect(claudeLoginMethod.plan == "max", "Claude Login method is the plan source")
        expect(claudeLoginMethod.fiveHour.percentInt == 8, "Claude Status tab keeps session quota")
        expect(claudeLoginMethod.weekly.percentInt == 35, "Claude Status tab keeps weekly quota")

        let claudeSeparateScreens = CLIUsageParser.parseClaude("""
        Current session 8% used Resets 1:40pm
        Current week (all models) 35% used Resets Aug 31 at 12pm
        """, timedOut: false, loginMethodText: "Login method: Claude Max account")
        expect(claudeSeparateScreens.fiveHour.percentInt == 8, "Claude usage screen remains the quota source")
        expect(claudeSeparateScreens.plan == "max", "Claude status screen remains the login-method source")

        let claudeDetailedLogin = CLIUsageParser.parseClaude("""
        Login method: Claude Max account (Max 20x)
        Current session 8% used Resets 1:40pm
        Current week (all models) 35% used Resets Aug 31 at 12pm
        """, timedOut: false)
        expect(claudeDetailedLogin.plan == "max ×20", "Claude Login method keeps stated Max multiplier")

        for (loginMethod, expectedPlan) in [
            ("Claude Pro account", "pro"),
            ("Claude Team account", "team"),
            ("Claude Enterprise account", "enterprise"),
            ("API key", "api"),
        ] {
            let usage = CLIUsageParser.parseClaude("""
            Login method: \(loginMethod)
            Current session 8% used Resets 1:40pm
            Current week (all models) 35% used Resets Aug 31 at 12pm
            """, timedOut: false)
            expect(usage.plan == expectedPlan, "Claude login method \(loginMethod) is identified")
        }

        let claudeConsole = CLIUsageParser.parseClaude("""
        Login method: Anthropic Console account
        Current session 8% used Resets 1:40pm
        Current week (all models) 35% used Resets Aug 31 at 12pm
        """, timedOut: false)
        expect(claudeConsole.plan == "api", "Claude Console login is not mislabeled as subscription")
        expect(!claudeConsole.fiveHour.hasReading, "Claude Console ignores subscription-like status text")

        let claudeConsoleNoQuota = CLIUsageParser.parseClaude(
            "Login method: Anthropic Console account", timedOut: false
        )
        expect(claudeConsoleNoQuota.plan == "api", "Claude Console without plan windows remains API mode")
        expect(!claudeConsoleNoQuota.fiveHour.hasReading, "Claude Console does not fabricate subscription quota")

        let claudeBedrock = CLIUsageParser.parseClaude("""
        Login method: 3rd-party platform · Amazon Bedrock
        Current session 8% used Resets 1:40pm
        Current week (all models) 35% used Resets Aug 31 at 12pm
        """, timedOut: false)
        expect(claudeBedrock.plan == "third-party", "Claude managed-platform login is identified")
        expect(!claudeBedrock.fiveHour.hasReading, "Claude managed platform ignores subscription-like status text")

        let claudeSignedOut = CLIUsageParser.parseClaude(
            "Not logged in · Please run /login", timedOut: false
        )
        expect(claudeSignedOut.fiveHour.error == "not logged in", "Claude signed-out status is actionable")

        let codexSignedOut = CLIUsageParser.parseCodex(
            "Not logged in. Please run /login", timedOut: false
        )
        expect(codexSignedOut.fiveHour.error == "not logged in", "Codex signed-out status is actionable")

        let codex = CLIUsageParser.parseCodex("""
        Account: user@example.com (Pro)
        Weekly limit: [███████████████████░] 94% left
        (resets 22:14 on 1 Sep)
        GPT-5.3-Codex-Spark limit:
        5h limit: [████████████████████] 100% left
        (resets 16:50)
        Weekly limit: [██████░░░░░░░░░░░░░░] 29% left
        (resets 17:16 on 31 Aug)
        """, timedOut: false)
        expect(codex.fiveHour.percentInt == 0, "Codex 5h remaining maps to used fraction")
        expect(codex.weekly.percentInt == 6, "Codex account weekly remaining maps to used fraction")
        expect(codex.windows.count == 3, "Codex retains every weekly/model window")
        expect(codex.plan == "pro", "Codex plan parses")

        let codexNamedQuotaPool = CLIUsageParser.parseCodex("""
        │  gpt-reserve Weekly limit: 100% left
        │  (resets 09:45 on 10 Sep)
        │  Weekly limit: 82% left
        │  (resets 10:25 on 7 Sep)
        │  GPT-5.3-Codex-Spark limit:
        │  5h limit: 100% left
        │  (resets 14:45)
        │  Weekly limit: 100% left
        │  (resets 09:45 on 10 Sep)
        """, timedOut: false)
        expect(
            codexNamedQuotaPool.weekly.percentInt == 18,
            "Codex account week ignores a prefixed named quota pool"
        )
        expect(
            codexNamedQuotaPool.windows.first { $0.id == "codex.week.0" }?.usedPercent
                == 0.18,
            "Codex account weekly detail keeps the unprefixed 82% remaining row"
        )
        expect(
            codexNamedQuotaPool.windows.contains { $0.id.hasPrefix("codex.week.model") },
            "Codex named/model weekly quota remains available as detail"
        )

        let codexTier = CLIUsageParser.parseCodex("""
        Account: user@example.com (Pro x5)
        5h limit: 100% left (resets 16:50)
        Weekly limit: 94% left (resets 22:14 on 1 Sep)
        """, timedOut: false)
        expect(codexTier.plan == "pro ×5", "Codex status preserves stated Pro multiplier")

        let codexWeeklyOnly = CLIUsageParser.parseCodex("""
        Account: weekly@example.com (Pro)
        Weekly limit: 91% left (resets in 6d 2h)
        """, timedOut: false)
        expect(!codexWeeklyOnly.fiveHour.hasReading, "Codex weekly-only status does not fabricate 5h quota")
        expect(codexWeeklyOnly.weekly.percentInt == 9, "Codex weekly-only status keeps weekly quota")
        expect(codexWeeklyOnly.windows.count == 1, "Codex weekly-only status keeps one real window")

        let codexFiveHourOnly = CLIUsageParser.parseCodex("""
        Account: session@example.com (Pro)
        5h limit: 88% left (resets in 3h)
        """, timedOut: false)
        expect(codexFiveHourOnly.fiveHour.percentInt == 12, "Codex 5h-only status keeps session quota")
        expect(!codexFiveHourOnly.weekly.hasReading, "Codex 5h-only status does not fabricate weekly quota")

        let redrawnCodex = CLIUsageParser.parseCodex("""
        Weekly limit: 94% left (resets 22:14 on 1 Sep)
        GPT-5.3-Codex-Spark limit:
        5h limit: 100% left (resets 16:50)
        Weekly limit: 29% left (resets 17:16 on 31 Aug)
        Weekly limit: 94% left (resets 22:14 on 1 Sep)
        GPT-5.3-Codex-Spark limit:
        5h limit: 100% left (resets 16:50)
        Weekly limit: 29% left (resets 17:16 on 31 Aug)
        """, timedOut: false)
        expect(redrawnCodex.windows.count == 3, "Codex TUI redraws do not duplicate windows")
        expect(redrawnCodex.weekly.percentInt == 6, "Codex account weekly survives redraw")

        let relativeCodex = CLIUsageParser.parseCodex("""
        Weekly limit: 91% left (resets in 6d 2h)
        5h limit: 100% left (resets in 4h)
        Weekly limit: 29% left (resets in 2d 3h)
        """, timedOut: false)
        let relativeSecond = relativeCodex.fiveHour.resetAt.map {
            Calendar.current.component(.second, from: $0)
        }
        expect(relativeSecond == 0, "relative Codex reset normalizes to the minute")
        expect(
            (relativeCodex.weekly.resetAt?.timeIntervalSinceNow ?? 0) > 5 * 86400,
            "relative Codex reset keeps day component"
        )

        let codexAPI = CLIUsageParser.parseCodex("""
        Authentication: API key
        API-key authentication does not include subscription limits.
        """, timedOut: false)
        expect(codexAPI.plan == "api", "Codex API-key mode is recognized")
        expect(!codexAPI.fiveHour.hasReading, "Codex API-key mode does not fabricate subscription quota")

        let codexCustomProvider = CLIUsageParser.parseCodex("""
        Model provider: whatai - https://example.invalid
        Token usage: 0 total
        Limits: data not available yet
        """, timedOut: true)
        expect(codexCustomProvider.plan == "api", "Codex custom provider with unavailable limits is recognized")
        expect(
            codexCustomProvider.fiveHour.error == "API/custom mode — no subscription quota",
            "custom provider does not render as a timeout"
        )

        let directCodexEnvironment = CLIStatusProbe.proxyEnvironmentChanges(
            provider: .codex, proxyURL: ""
        )
        expect(
            directCodexEnvironment.count == 4 && directCodexEnvironment.allSatisfy { $0.value == nil },
            "empty Codex proxy clears inherited proxy variables"
        )
        let configuredCodexEnvironment = CLIStatusProbe.proxyEnvironmentChanges(
            provider: .codex, proxyURL: "http://127.0.0.1:7890"
        )
        expect(
            configuredCodexEnvironment.allSatisfy { $0.value == "http://127.0.0.1:7890" },
            "configured Codex proxy sets every proxy spelling"
        )
        expect(
            CLIStatusProbe.postStatusCaptureInterval(for: .claude) == 10,
            "Claude captures one settled status frame before interruption"
        )
        expect(
            CLIStatusProbe.postStatusCaptureInterval(for: .codex) == 10,
            "Codex captures one settled status frame before interruption"
        )
        expect(
            CLIStatusProbe.maximumCommandAttempts(for: .codex) == 3,
            "Codex adaptive status refresh is capped at three commands"
        )
        expect(
            CLIStatusProbe.maximumCommandAttempts(for: .claude) == 1,
            "Claude status refresh remains single-command"
        )
        expect(
            CLIStatusProbe.codexStatusFrameDetected(
                in: "Weekly limit: 94% left (resets in 6d)"
            ),
            "Codex subscription status stops adaptive retries"
        )
        expect(
            !CLIStatusProbe.codexStatusFrameDetected(in: "Weekly limit:"),
            "Codex partial status label does not stop adaptive retries"
        )
        expect(
            CLIStatusProbe.codexStatusFrameDetected(
                in: "Model provider: custom\nLimits: data not available"
            ),
            "Codex API/custom status stops adaptive retries"
        )
        expect(
            !CLIStatusProbe.codexStatusFrameDetected(in: "OpenAI Codex\nModel: gpt-5.6"),
            "Codex welcome screen does not stop status retries"
        )

        // Claude writes its Status tab by moving the cursor around an
        // alternate screen. Removing ANSI codes alone joins cells such as
        // `Resets1:40pm`; the probe must recover the displayed screen before
        // passing it to the text parser.
        let claudeTUI = Data("""
        \u{1B}[?1049h\u{1B}[2J\u{1B}[3;4HCurrent session\u{1B}[4;4H████ 8% used\u{1B}[5;4HResets 1:40pm (Asia/Shanghai)\u{1B}[7;4HCurrent week (all models)\u{1B}[8;4H████████ 35% used\u{1B}[9;4HResets Aug 31 at 12pm (Asia/Shanghai)\u{1B}[11;4HCurrent week (Fable)\u{1B}[12;4H████████ 61% used\u{1B}[13;4HResets Aug 31 at 12pm (Asia/Shanghai)\u{1B}[?1049l
        """.utf8)
        let renderedClaudeTUI = CLIStatusProbe.terminalText(claudeTUI)
        let parsedClaudeTUI = CLIUsageParser.parseClaude(renderedClaudeTUI, timedOut: false)
        expect(renderedClaudeTUI.contains("Current session"), "terminal renderer preserves cursor-positioned labels")
        expect(parsedClaudeTUI.fiveHour.percentInt == 8, "cursor-positioned Claude session parses")
        expect(parsedClaudeTUI.weekly.percentInt == 35, "cursor-positioned Claude weekly parses")
        expect(parsedClaudeTUI.windows.count == 3, "cursor-positioned Claude keeps all windows")

        // Claude 2.1.257 can render plugin/statusline diagnostics above the
        // quota cards. The first quota row then begins below a 24-row PTY, so
        // the usage probe and renderer must share the taller viewport.
        let tallClaudeUsage = Data("""
        \u{1B}[?1049h\u{1B}[2J
        \u{1B}[25;4HCurrent session
        \u{1B}[26;4H████ 5% used
        \u{1B}[27;4HResets 1:20pm (Asia/Shanghai)
        \u{1B}[29;4HCurrent week (all models)
        \u{1B}[30;4H████████ 34% used
        \u{1B}[31;4HResets Sep 7 at 12pm (Asia/Shanghai)
        \u{1B}[33;4HCurrent week (Fable)
        \u{1B}[34;4H████████ 57% used
        \u{1B}[35;4HResets Sep 7 at 12pm (Asia/Shanghai)
        \u{1B}[?1049l
        """.utf8)
        let renderedTallClaudeUsage = CLIStatusProbe.transcriptText(
            tallClaudeUsage,
            provider: .claude,
            terminalRows: 48
        )
        let parsedTallClaudeUsage = CLIUsageParser.parseClaude(
            renderedTallClaudeUsage,
            timedOut: false
        )
        expect(
            parsedTallClaudeUsage.fiveHour.percentInt == 5,
            "tall Claude usage screen keeps the session row below line 24"
        )
        expect(
            parsedTallClaudeUsage.weekly.percentInt == 34,
            "tall Claude usage screen keeps the weekly row below line 24"
        )
        expect(
            parsedTallClaudeUsage.windows.last?.label == "Current week (Fable)",
            "tall Claude usage screen keeps its model-specific week"
        )

        expect(
            CLIStatusProbe.terminalText(Data("\u{1B}[".utf8)).isEmpty,
            "terminal renderer terminates on a bare incomplete CSI"
        )
        expect(
            CLIStatusProbe.terminalText(Data("\u{1B}[38;5".utf8)).isEmpty,
            "terminal renderer terminates on a parameterized incomplete CSI"
        )
        expect(
            CLIStatusProbe.terminalText(Data("status ready\u{1B}[12;".utf8)) == "status ready",
            "terminal renderer preserves text before an incomplete CSI tail"
        )

        let tallCodexStatus = Data("""
        \u{1B}[2J\u{1B}[1;1HWeekly limit: 81% left (resets 22:14 on 1 Sep)
        \u{1B}[2;1H5h limit: 100% left (resets 00:31 on 28 Aug)
        \u{1B}[2;1H\u{1B}[2K
        """.utf8)
        let physicalCodexStatus = CLIStatusProbe.terminalText(tallCodexStatus)
        let mergedCodexStatus = CLIStatusProbe.transcriptText(
            tallCodexStatus, provider: .codex
        )
        let parsedMergedCodexStatus = CLIUsageParser.parseCodex(
            mergedCodexStatus, timedOut: false
        )
        expect(
            !physicalCodexStatus.contains("5h limit"),
            "physical Codex frame can lose a scrolled 5h row"
        )
        expect(
            parsedMergedCodexStatus.fiveHour.hasReading
                && parsedMergedCodexStatus.fiveHour.percentInt == 0,
            "Codex transcript merge restores a scrolled 5h row"
        )
        expect(
            parsedMergedCodexStatus.weekly.percentInt == 19,
            "Codex transcript merge keeps the account weekly row"
        )

        // A real Claude redraw can temporarily leave its progress bar over a
        // label and use box drawing for its section rule. The completed Status
        // screen still has three ordered percent/reset pairs; this is the
        // shape the fallback above is designed to accept offline.
        let redrawnClaude = CLIUsageParser.parseClaude("""
        Curren█ session
        ██████▌                                            13% used
        Resets 1:40pm (Asia/Shanghai)
        ───Current─week─(all─models)───────────────────────────────────
        ██████████████████                                 36% used
        Resets Aug 31 at 12pm (Asia/Shanghai)
        ── Current week (Fable)
        ███████████████████████████████▌                    63% used
        Resets Aug 31 at 12pm (Asia/Shanghai)
        """, timedOut: false)
        expect(redrawnClaude.fiveHour.percentInt == 13, "Claude redraw fallback parses session")
        expect(redrawnClaude.weekly.percentInt == 36, "Claude redraw fallback parses all-model week")
        expect(redrawnClaude.windows.count == 3, "Claude redraw fallback retains model week")

        if failures > 0 { exit(1) }
    }
}
