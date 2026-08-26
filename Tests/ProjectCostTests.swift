import Foundation

/// Regression coverage for multi-Codex-home project attribution. The same
/// working directory from two configured accounts must remain two rows; if it
/// were keyed by cwd alone, account totals would silently merge.
@main
struct ProjectCostTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") }
        else { print("FAIL \(label)"); failures += 1 }
    }

    static func main() {
        let now = Date()
        let sharedProject = "/work/shared-project"
        let summary = CostSummary.summarize(events: [
            TokenEvent(
                provider: .codex, timestamp: now, model: "gpt-5.6-terra",
                inputTokens: 100, outputTokens: 200, cacheCreationTokens: 0,
                cacheReadTokens: 50, projectID: sharedProject,
                projectName: "shared-project", sourceID: "personal-home", sourceName: "Personal"
            ),
            TokenEvent(
                provider: .codex, timestamp: now, model: "gpt-5.6-terra",
                inputTokens: 1_000, outputTokens: 2_000, cacheCreationTokens: 0,
                cacheReadTokens: 100, projectID: sharedProject,
                projectName: "shared-project", sourceID: "work-home", sourceName: "Work"
            ),
        ], now: now)

        expect(summary.projects.count == 2, "same cwd remains separate across Codex homes")
        expect(Set(summary.projects.compactMap(\.sourceName)) == ["Personal", "Work"], "profile names survive aggregation")
        expect(Set(summary.projects.map(\.todayTokens)) == [350, 3_100], "each profile keeps its own today tokens")
        expect(summary.today.tokens == 3_450, "provider today total remains the sum of project rows")
        expect(summary.projects.allSatisfy { $0.monthDollars > 0 }, "per-project month dollar estimates are retained")

        let canonicalized = CostSummary.summarize(events: [
            TokenEvent(
                provider: .codex, timestamp: now, model: "gpt-5.6-terra",
                inputTokens: 10, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0,
                projectID: "/work/shared-project", sourceID: "personal-home", sourceName: "Personal"
            ),
            TokenEvent(
                provider: .codex, timestamp: now, model: "gpt-5.6-terra",
                inputTokens: 20, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0,
                projectID: "/work/./shared-project", sourceID: "personal-home", sourceName: "Personal"
            ),
        ], now: now)
        expect(canonicalized.projects.count == 1, "equivalent cwd spellings share one project row")
        expect(canonicalized.projects[0].todayTokens == 30, "canonical project row keeps combined tokens")

        let futureExcluded = CostSummary.summarize(events: [
            TokenEvent(
                provider: .codex, timestamp: now.addingTimeInterval(3600), model: "gpt-5.6-terra",
                inputTokens: 999, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0,
                projectID: "/work/future", sourceID: "personal-home", sourceName: "Personal"
            ),
        ], now: now)
        expect(futureExcluded.today.tokens == 0, "future-dated local event does not inflate today")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
