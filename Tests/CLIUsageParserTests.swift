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

        // Claude writes its Usage tab by moving the cursor around an
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

        // A real Claude redraw can temporarily leave its progress bar over a
        // label and use box drawing for its section rule. The completed Usage
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
