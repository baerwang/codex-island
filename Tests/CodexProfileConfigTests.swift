import Foundation

@main
struct CodexProfileConfigTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") }
        else { print("FAIL \(label)"); failures += 1 }
    }

    @MainActor
    static func main() {
        let id = UUID()
        let legacy = """
        [{"id":"\(id.uuidString)","name":"Legacy","codexHome":"/tmp/codex","proxyURL":"","enabled":true}]
        """.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode([CodexCLIProfile].self, from: legacy)
        expect(decoded?.count == 1, "legacy profile JSON remains decodable")
        expect(decoded?.first?.quotaMode == nil, "legacy profile keeps automatic quota mode")
        expect(decoded?.first?.effectiveQuotaMode == .auto, "missing mode resolves to automatic")

        var api = CodexCLIProfile(name: "API", codexHome: "/tmp/api")
        api.quotaMode = .api
        expect(api.effectiveQuotaMode == .api, "explicit API mode is retained")

        let profileA = CodexCLIProfile(id: UUID(), name: "A", codexHome: "/tmp/a")
        let profileB = CodexCLIProfile(id: UUID(), name: "B", codexHome: "/tmp/b")
        let selector = CodexCostProfileStore.shared
        selector.select(profileA.id, in: [profileA, profileB])
        expect(selector.selectedProfileID == profileA.id, "menu selection chooses the exact profile")
        selector.select(nil, in: [profileA, profileB])
        expect(selector.selectedProfileID == nil, "menu selection returns explicitly to All")
        selector.select(UUID(), in: [profileA, profileB])
        expect(selector.selectedProfileID == nil, "unknown profile cannot create a stale selection")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
