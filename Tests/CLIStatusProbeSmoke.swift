import Foundation

/// Opt-in live smoke test. It is intentionally excluded from run-tests.sh and
/// requires an already configured local Codex CLI; no credentials are read by
/// the test or supplied as input.
@main
struct CLIStatusProbeSmoke {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["STATUS_CODEX_HOME"],
              let proxy = env["STATUS_PROXY"] else {
            fputs("STATUS_CODEX_HOME and STATUS_PROXY are required\n", stderr)
            exit(2)
        }
        let transcript = await CLIStatusProbe.run(.init(
            provider: .codex,
            executable: "/opt/homebrew/bin/codex",
            proxyURL: proxy,
            workdir: env["STATUS_WORKDIR"] ?? "/private/tmp",
            codexHome: home,
            codexFullAccess: false
        ))
        if env["STATUS_DIAGNOSTICS"] == "1" {
            print(sanitizedDiagnostics(transcript.text))
        }
        let usage = CLIUsageParser.parseCodex(transcript.text, timedOut: transcript.timedOut)
        print("Codex: 5h \(usage.fiveHour.percentInt)% used · week \(usage.weekly.percentInt)% used · windows \(usage.windows.count)")
        if let error = usage.fiveHour.error { print("Codex probe: \(error)") }
        exit(usage.fiveHour.error == nil && usage.weekly.error == nil ? 0 : 1)
    }

    /// Opt-in, redacted diagnostics for the native PTY harness. Never print a
    /// raw transcript because it can contain account/path information.
    static func sanitizedDiagnostics(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                with: "<account>", options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"/[A-Za-z0-9._/-]+"#, with: "<path>", options: .regularExpression)
            .replacingOccurrences(
                of: #"[0-9a-f]{8}-[0-9a-f-]{27,}"#,
                with: "<id>", options: [.regularExpression, .caseInsensitive]
            )
    }
}
