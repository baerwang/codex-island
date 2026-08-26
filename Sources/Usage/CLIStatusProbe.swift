import Darwin
import Foundation

/// Native pseudo-terminal runner for status-only Claude Code / Codex sessions.
/// A normal pipe is not a terminal and both CLIs keep slash commands behind
/// their TUI. Codex also needs a response to its cursor-position query.
enum CLIStatusProbe {
    enum Provider { case claude, codex }

    struct Request {
        let provider: Provider
        let executable: String
        let proxyURL: String
        let workdir: String
        let codexHome: String?
        let codexFullAccess: Bool
    }

    struct Transcript {
        let text: String
        let raw: Data
        let timedOut: Bool
    }

    static func run(_ request: Request) async -> Transcript {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(request))
            }
        }
    }

    private static func runSync(_ request: Request) -> Transcript {
        var master: Int32 = -1
        var window = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        let pid = forkpty(&master, nil, nil, &window)
        guard pid >= 0 else {
            return Transcript(text: "pty unavailable", raw: Data(), timedOut: false)
        }
        if pid == 0 { launchChild(request) }

        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        let started = Date()
        var commandsSent = 0
        var nextCommandAt = started.addingTimeInterval(8)
        var lastOutputAt = started
        var sawPrompt = false
        var raw = Data()
        var timedOut = false
        var childExited = false
        var cursorQueryTail = Data()
        let maximumAttempts = request.provider == .codex ? 3 : 1
        let timeout = request.provider == .codex ? 28.0 : 32.0

        while !childExited {
            let now = Date()
            let bytes = readAvailable(master)
            if !bytes.isEmpty {
                lastOutputAt = now
                raw.append(bytes)
                cursorQueryTail.append(bytes)
                if cursorQueryTail.count > 32 { cursorQueryTail.removeFirst(cursorQueryTail.count - 32) }
                if cursorQueryTail.range(of: Data([0x1B, 0x5B, 0x36, 0x6E])) != nil {
                    // Same report used by the public pty-runner workaround.
                    write(master, Data("\u{1B}[25;1R".utf8))
                    cursorQueryTail.removeAll(keepingCapacity: true)
                }
                if request.provider == .codex {
                    sawPrompt = sawPrompt || bytes.range(of: Data("›".utf8)) != nil
                }
            }

            let ready = request.provider == .claude || sawPrompt
            if commandsSent < maximumAttempts,
               ready,
               now >= nextCommandAt,
               now.timeIntervalSince(lastOutputAt) >= 0.25 {
                switch request.provider {
                case .claude: write(master, Data("/usage\r".utf8))
                case .codex: write(master, Data("/status\r\r".utf8))
                }
                commandsSent += 1
                nextCommandAt = now.addingTimeInterval(3)
            }

            var status: Int32 = 0
            childExited = waitpid(pid, &status, WNOHANG) == pid
            if now.timeIntervalSince(started) >= timeout {
                timedOut = true
                kill(-pid, SIGINT)
                usleep(400_000)
                kill(-pid, SIGTERM)
                break
            }
            usleep(50_000)
        }
        close(master)
        return Transcript(text: terminalText(raw), raw: raw, timedOut: timedOut)
    }

    private static func launchChild(_ request: Request) -> Never {
        guard chdir(request.workdir) == 0 else { _exit(126) }
        setenv("HTTP_PROXY", request.proxyURL, 1)
        setenv("HTTPS_PROXY", request.proxyURL, 1)
        if request.provider == .claude { setenv("NO_PROXY", "localhost,127.0.0.1,::1", 1) }
        if let home = request.codexHome { setenv("CODEX_HOME", home, 1) }

        var arguments = [request.executable]
        if request.provider == .codex {
            arguments += ["-c", "check_for_update_on_startup=false"]
            if request.codexFullAccess { arguments.append("--dangerously-bypass-approvals-and-sandbox") }
        }
        exec(arguments: arguments)
    }

    private static func exec(arguments: [String]) -> Never {
        var cStrings = arguments.map { strdup($0) }
        cStrings.append(nil)
        cStrings.withUnsafeMutableBufferPointer { buffer in
            guard let first = buffer.baseAddress?.pointee else { _exit(127) }
            _ = execvp(first, buffer.baseAddress)
        }
        _exit(127)
    }

    private static func readAvailable(_ fd: Int32) -> Data {
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 { out.append(buffer, count: Int(count)) } else { break }
        }
        return out
    }

    private static func write(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                if count <= 0 { return }
                offset += count
            }
        }
    }

    private static func terminalText(_ raw: Data) -> String {
        guard var value = String(data: raw, encoding: .utf8) else { return "" }
        value = value.replacingOccurrences(
            of: "\\x1B\\][^\\x07\\x1B]*(?:\\x07|\\x1B\\\\)",
            with: "", options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: "\\x1B\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression
        )
        return value.replacingOccurrences(of: "\r", with: "\n")
    }
}
