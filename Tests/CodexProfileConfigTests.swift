import Foundation

@main
struct CodexProfileConfigTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") }
        else { print("FAIL \(label)"); failures += 1 }
    }

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

        let profileA = UUID()
        let profileB = UUID()
        expect(
            CodexCostProfileCycle.next(current: nil, profileIDs: [profileA, profileB]) == profileA,
            "local usage filter cycles from All to first profile"
        )
        expect(
            CodexCostProfileCycle.next(current: profileA, profileIDs: [profileA, profileB]) == profileB,
            "local usage filter cycles through profiles"
        )
        expect(
            CodexCostProfileCycle.next(current: profileB, profileIDs: [profileA, profileB]) == nil,
            "local usage filter cycles back to All"
        )

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
