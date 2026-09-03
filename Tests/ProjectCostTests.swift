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
        expect(
            summary.weekByModel.first?.tokens == 3_300,
            "model row retains input plus output total"
        )
        expect(
            summary.weekByModel.first?.allTokens == 3_450,
            "model row also retains cache-inclusive total"
        )
        expect(summary.projects.allSatisfy { $0.monthDollars > 0 }, "per-project month dollar estimates are retained")
        let personalHistory = summary.dailyTokens
            .filter { $0.sourceID == "personal-home" }
            .reduce(0) { $0 + $1.tokens }
        let workHistory = summary.dailyTokens
            .filter { $0.sourceID == "work-home" }
            .reduce(0) { $0 + $1.tokens }
        let personalBillableHistory = summary.dailyTokens
            .filter { $0.sourceID == "personal-home" }
            .reduce(0) { $0 + $1.billableTokens }
        expect(personalHistory == 350, "daily history retains personal Codex profile attribution")
        expect(workHistory == 3_100, "daily history retains work Codex profile attribution")
        expect(personalBillableHistory == 300, "daily history retains billable token mode by profile")

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

        let tokenModes = CostSummary.summarize(events: [
            TokenEvent(
                provider: .claude, timestamp: now, model: "claude-sonnet-5",
                inputTokens: 100, outputTokens: 50, cacheCreationTokens: 200,
                cacheReadTokens: 1_000
            ),
        ], now: now)
        expect(
            tokenModes.weekByModel.first?.tokens == 150,
            "input plus output model mode excludes both cache categories"
        )
        expect(
            tokenModes.weekByModel.first?.allTokens == 1_350,
            "all-token model mode includes cache creation and reads"
        )

        let exactModels = CostSummary.summarize(events: [
            TokenEvent(
                provider: .claude, timestamp: now.addingTimeInterval(-6 * 3600),
                model: "claude-fable-5", inputTokens: 10, outputTokens: 0,
                cacheCreationTokens: 0, cacheReadTokens: 0
            ),
            TokenEvent(
                provider: .claude, timestamp: now,
                model: "claude-fable-5-1", inputTokens: 20, outputTokens: 0,
                cacheCreationTokens: 0, cacheReadTokens: 0
            ),
            TokenEvent(
                provider: .claude, timestamp: now,
                model: "claude-aurora-7-2-20270101", inputTokens: 30, outputTokens: 0,
                cacheCreationTokens: 0, cacheReadTokens: 0
            ),
        ], now: now)
        expect(
            Set(exactModels.weekByModel.map(\.model)) == [
                "claude-fable-5", "claude-fable-5-1", "claude-aurora-7-2-20270101",
            ],
            "weekly model rows preserve exact log identifiers"
        )
        expect(
            exactModels.weekByModel.first { $0.model == "claude-fable-5-1" }?.displayName
                == "Fable 5.1",
            "point release renders with its exact version"
        )
        expect(
            exactModels.weekByModel.first { $0.model == "claude-aurora-7-2-20270101" }?.displayName
                == "Aurora 7.2.20270101",
            "previously unknown model displays dynamically without a client update"
        )
        expect(
            !Pricing.isKnown("claude-aurora-7-2-20270101"),
            "model visibility does not depend on a hard-coded price entry"
        )
        expect(
            exactModels.recentByModel.allSatisfy { $0.model != "claude-fable-5" },
            "old model remains weekly history without being fabricated as recent"
        )

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
