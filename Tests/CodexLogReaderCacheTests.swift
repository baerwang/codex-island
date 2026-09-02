import Foundation

@main
struct CodexLogReaderCacheTests {
    static func main() {
        var failures = 0
        func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
            if condition() { print("PASS \(label)") }
            else { failures += 1; print("FAIL \(label)") }
        }

        let personal = CodexLogReader.cacheFilename(codexHome: "/profiles/personal")
        let personalAgain = CodexLogReader.cacheFilename(codexHome: "/profiles/personal")
        let work = CodexLogReader.cacheFilename(codexHome: "/profiles/work")

        expect(personal == personalAgain, "same Codex home keeps a stable cache namespace")
        expect(personal != work, "different Codex homes cannot prune each other's cache")
        expect(
            personal.range(of: #"^codex-parse-cache\.[0-9a-f]{16}\.v1\.json$"#,
                           options: .regularExpression) != nil,
            "cache namespace is filesystem-safe"
        )

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
