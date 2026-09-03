import Foundation

@main
struct ClaudeLogReaderDedupTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        if condition() { print("PASS \(label)") }
        else { print("FAIL \(label)"); failures += 1 }
    }

    static func event(
        key: String, output: Int, second: TimeInterval
    ) -> ClaudeLogReader.CachedEvent {
        ClaudeLogReader.CachedEvent(
            timestamp: Date(timeIntervalSinceReferenceDate: second),
            model: "claude-opus-5",
            inputTokens: 10,
            outputTokens: output,
            cacheCreationTokens: 20,
            cacheReadTokens: 30,
            projectID: nil,
            projectName: nil,
            dedupKey: key
        )
    }

    static func main() {
        let rows = ClaudeLogReader.deduplicated([
            event(key: "stream", output: 2, second: 1),
            event(key: "stream", output: 3_147, second: 3),
            event(key: "stream", output: 384, second: 2),
            event(key: "stable", output: 50, second: 4),
            event(key: "stable", output: 50, second: 5),
            event(key: "", output: 7, second: 6),
            event(key: "", output: 8, second: 7),
        ])

        expect(rows.count == 4, "provider request duplicates collapse to one row")
        expect(
            rows.first { $0.dedupKey == "stream" }?.outputTokens == 3_147,
            "streaming dedup keeps the complete output count"
        )
        expect(
            rows.first { $0.dedupKey == "stable" }?.timestamp
                == Date(timeIntervalSinceReferenceDate: 4),
            "identical duplicate snapshots preserve the first timestamp"
        )
        expect(
            rows.filter { $0.dedupKey.isEmpty }.count == 2,
            "rows without both provider IDs remain independent"
        )

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
