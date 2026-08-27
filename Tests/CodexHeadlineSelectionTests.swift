import Foundation

@main
struct CodexHeadlineSelectionTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") }
        else { print("FAIL \(label)"); failures += 1 }
    }

    static func usage(
        fiveHour: Double? = nil, weekly: Double? = nil,
        plan: String? = nil, error: String = "no data"
    ) -> AppUsage {
        AppUsage(
            fiveHour: fiveHour.map {
                WindowUsage(usedPercent: $0, resetAt: nil, error: nil)
            } ?? WindowUsage(usedPercent: 0, resetAt: nil, error: error),
            weekly: weekly.map {
                WindowUsage(usedPercent: $0, resetAt: nil, error: nil)
            } ?? WindowUsage(usedPercent: 0, resetAt: nil, error: error),
            plan: plan
        )
    }

    static func main() {
        let api = CodexCLIProfile(name: "API", codexHome: "/api")
        let subscription = CodexCLIProfile(name: "Subscription", codexHome: "/sub")
        let selection = CodexHeadlineSelection.select(
            profiles: [api, subscription],
            readings: [
                api.id: usage(plan: "api", error: "API mode — no subscription quota"),
                subscription.id: usage(fiveHour: 0.29, weekly: 0.29, plan: "pro"),
            ]
        )
        expect(selection?.id == subscription.id, "subscription quota wins over earlier API profile")

        let weeklyOnly = CodexCLIProfile(name: "Weekly", codexHome: "/weekly")
        let fiveHour = CodexCLIProfile(name: "5H", codexHome: "/five-hour")
        let fiveHourSelection = CodexHeadlineSelection.select(
            profiles: [weeklyOnly, fiveHour],
            readings: [
                weeklyOnly.id: usage(weekly: 0.41, plan: "plus"),
                fiveHour.id: usage(fiveHour: 0.23, weekly: 0.19, plan: "pro"),
            ]
        )
        expect(
            fiveHourSelection?.id == fiveHour.id,
            "real 5h reading wins over an earlier weekly-only profile"
        )

        let realZero = CodexHeadlineSelection.select(
            profiles: [weeklyOnly, fiveHour],
            readings: [
                weeklyOnly.id: usage(weekly: 0.41, plan: "plus"),
                fiveHour.id: usage(fiveHour: 0, weekly: 0.19, plan: "pro"),
            ]
        )
        expect(
            realZero?.id == fiveHour.id,
            "a genuine 0% 5h measurement still wins over weekly-only quota"
        )

        let weeklySelection = CodexHeadlineSelection.select(
            profiles: [weeklyOnly, subscription],
            readings: [
                weeklyOnly.id: usage(weekly: 0.41, plan: "plus"),
                subscription.id: usage(plan: "pro", error: "codex timeout"),
            ]
        )
        expect(
            weeklySelection?.id == weeklyOnly.id,
            "weekly quota wins when no profile has a real 5h reading"
        )

        let unavailable = CodexCLIProfile(name: "Unavailable", codexHome: "/missing")
        let fallback = CodexHeadlineSelection.select(
            profiles: [unavailable, api],
            readings: [
                unavailable.id: usage(error: "codex home required"),
                api.id: usage(plan: "api", error: "API mode — no subscription quota"),
            ]
        )
        expect(
            fallback?.id == unavailable.id,
            "subscription failure stays visible ahead of API-only profile"
        )

        let allAPI = CodexHeadlineSelection.select(
            profiles: [api],
            readings: [
                api.id: usage(plan: "api", error: "API mode — no subscription quota"),
            ]
        )
        expect(allAPI?.id == api.id, "API profile remains selectable when every profile is API")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
