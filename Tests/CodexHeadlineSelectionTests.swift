import Foundation

@main
struct CodexHeadlineSelectionTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") }
        else { print("FAIL \(label)"); failures += 1 }
    }

    static func usage(_ percent: Double, plan: String? = nil, error: String? = nil) -> AppUsage {
        AppUsage(
            fiveHour: WindowUsage(usedPercent: percent, resetAt: nil, error: error),
            weekly: WindowUsage(usedPercent: percent, resetAt: nil, error: error),
            plan: plan
        )
    }

    static func main() {
        let api = CodexCLIProfile(name: "API", codexHome: "/api")
        let subscription = CodexCLIProfile(name: "Subscription", codexHome: "/sub")
        let selection = CodexHeadlineSelection.select(
            profiles: [api, subscription],
            readings: [
                api.id: usage(0, plan: "api", error: "API mode — no subscription quota"),
                subscription.id: usage(0.29, plan: "pro"),
            ]
        )
        expect(selection?.id == subscription.id, "subscription quota wins over earlier API profile")

        let explicitAPI = CodexHeadlineSelection.select(
            profiles: [api, subscription],
            readings: [
                api.id: usage(0, plan: "api", error: "API/custom mode — no subscription quota"),
                subscription.id: usage(0.29, plan: "pro"),
            ],
            preferredID: api.id
        )
        expect(explicitAPI?.id == api.id, "explicit profile choice is preserved")

        let unavailable = CodexCLIProfile(name: "Unavailable", codexHome: "/missing")
        let fallback = CodexHeadlineSelection.select(
            profiles: [unavailable, api],
            readings: [
                unavailable.id: usage(0, error: "codex home required"),
                api.id: usage(0, plan: "api", error: "API mode — no subscription quota"),
            ]
        )
        expect(fallback?.id == api.id, "API profile wins when no subscription profile is usable")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
