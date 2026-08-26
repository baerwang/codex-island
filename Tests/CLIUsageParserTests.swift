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
        expect(codex.weekly.percentInt == 71, "Codex model weekly remaining maps to used fraction")
        expect(codex.windows.count == 3, "Codex retains every weekly/model window")
        expect(codex.plan == "pro", "Codex plan parses")

        if failures > 0 { exit(1) }
    }
}
