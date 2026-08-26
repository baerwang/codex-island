import Foundation

/// Opt-in end-to-end verification for the two Claude Code screens. It is not
/// part of run-tests.sh: run only with an already logged-in local CLI and an
/// explicit proxy. It prints parsed, non-identifying fields only.
@main
struct ClaudeProbeSmoke {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        guard let proxy = env["STATUS_CLAUDE_PROXY"], !proxy.isEmpty else {
            fputs("STATUS_CLAUDE_PROXY is required\n", stderr)
            exit(2)
        }

        let executable = "/opt/homebrew/bin/claude"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            fputs("claude not found at \(executable)\n", stderr)
            exit(2)
        }

        let request = CLIStatusProbe.Request(
            provider: .claude,
            command: .usage,
            executable: executable,
            proxyURL: proxy,
            workdir: "/private/tmp",
            codexHome: nil,
            codexFullAccess: false
        )
        let usageTranscript = await CLIStatusProbe.run(request)
        let statusTranscript = await CLIStatusProbe.run(.init(
            provider: .claude,
            command: .status,
            executable: executable,
            proxyURL: proxy,
            workdir: "/private/tmp",
            codexHome: nil,
            codexFullAccess: false
        ))
        let usage = CLIUsageParser.parseClaude(
            usageTranscript.text,
            timedOut: usageTranscript.timedOut,
            loginMethodText: statusTranscript.text
        )

        print("Claude usage: 5h \(usage.fiveHour.percentInt)% · week \(usage.weekly.percentInt)%")
        print("Claude plan: \(usage.plan ?? "not reported")")
        print("Claude windows: \(usage.windows.count)")
        if let error = usage.fiveHour.error ?? usage.weekly.error {
            print("Claude probe: \(error)")
            fflush(stdout)
            exit(1)
        }
        fflush(stdout)
        exit(0)
    }
}
