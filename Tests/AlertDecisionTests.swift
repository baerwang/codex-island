import Foundation

@main
struct AlertDecisionTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") }
        else { print("FAIL \(label)"); failures += 1 }
    }

    static func input(
        _ provider: AlertEngine.Provider, percent: Double, reset: Date,
        visible: Bool = true, error: String? = nil
    ) -> AlertDecision.WindowInput {
        AlertDecision.WindowInput(
            provider: provider,
            visible: visible,
            window: WindowUsage(usedPercent: percent, resetAt: reset, error: error)
        )
    }

    static func main() {
        let resetA = Date(timeIntervalSince1970: 1_800_000_000)
        let resetB = resetA.addingTimeInterval(5 * 3600)

        let severity = AlertDecision.computeSeverity(
            inputs: [
                input(.claude, percent: 0.81, reset: resetA),
                input(.codex, percent: 0.96, reset: resetA),
                input(.claude, percent: 0.99, reset: resetA, visible: false),
                input(.codex, percent: 0, reset: resetA, error: "timeout"),
            ],
            warning: 80, critical: 95
        )
        expect(severity[.claude] == .warning, "visible Claude warning threshold computes")
        expect(severity[.codex] == .critical, "Codex critical threshold computes")

        let first = AlertDecision.evaluateCrossings(
            previous: [], inputs: [input(.claude, percent: 0.81, reset: resetA)],
            warning: 80, critical: 95, warmedUp: false
        )
        expect(first.pulse == nil, "first observed threshold warms up without pulsing")
        expect(first.next.count == 1, "warmup records the crossing")

        let sameCycle = AlertDecision.evaluateCrossings(
            previous: first.next, inputs: [input(.claude, percent: 0.96, reset: resetA)],
            warning: 80, critical: 95, warmedUp: true
        )
        expect(sameCycle.pulse?.severity == .critical, "critical escalation pulses within same reset")

        let repeated = AlertDecision.evaluateCrossings(
            previous: sameCycle.next, inputs: [input(.claude, percent: 0.96, reset: resetA)],
            warning: 80, critical: 95, warmedUp: true
        )
        expect(repeated.pulse == nil, "same threshold does not repeat within reset")

        let nextReset = AlertDecision.evaluateCrossings(
            previous: sameCycle.next, inputs: [input(.claude, percent: 0.81, reset: resetB)],
            warning: 80, critical: 95, warmedUp: true
        )
        expect(nextReset.pulse?.severity == .warning, "new reset permits a new warning pulse")

        let profileA = UsageHistoryStore.seriesKey(
            provider: .codex, window: .weekly, sourceID: "account-a"
        )
        let profileB = UsageHistoryStore.seriesKey(
            provider: .codex, window: .weekly, sourceID: "account-b"
        )
        expect(profileA != profileB, "Codex history stays isolated by profile")

        let historyNow = Date(timeIntervalSince1970: 1_800_000_000)
        let retainedSamples = UsageHistoryStore.samplesWithinRetention([
            UsageSample(at: historyNow.addingTimeInterval(-8 * 86400), used: 0.1),
            UsageSample(at: historyNow.addingTimeInterval(-6 * 86400), used: 0.2),
            UsageSample(at: historyNow.addingTimeInterval(60), used: 0.3),
        ], now: historyNow)
        expect(retainedSamples.count == 1, "usage history hides expired and future samples on read")
        expect(retainedSamples.first?.used == 0.2, "usage history keeps the current-window sample")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
