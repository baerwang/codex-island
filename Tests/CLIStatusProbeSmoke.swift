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
        print(transcript.text)
        exit(transcript.timedOut ? 124 : 0)
    }
}
