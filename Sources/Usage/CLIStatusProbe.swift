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

    struct EnvironmentChange: Equatable {
        let name: String
        let value: String?
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
        // Codex must finish drawing before its prompt marker can be trusted;
        // Claude accepts a queued slash command as soon as its PTY starts.
        // Sending /usage at 3s keeps Claude within the bounded probe timeout
        // on slower machines without changing its one-command behavior.
        var nextCommandAt = started.addingTimeInterval(request.provider == .codex ? 8 : 3)
        var lastOutputAt = started
        var sawPrompt = false
        var raw = Data()
        var timedOut = false
        var childExited = false
        var cursorQueryTail = Data()
        var acceptedStatusWorkspaceTrust = false
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
                    // The fixed status workspace can show Codex's trust
                    // picker on its first use. It is not a user project and
                    // this probe never submits a task, so accept the picker
                    // (whose default button is Yes) rather than leaving a
                    // background status refresh stuck behind it.
                    let recent = String(decoding: raw.suffix(4_096), as: UTF8.self).lowercased()
                    if !acceptedStatusWorkspaceTrust,
                       (recent.contains("trust this folder") || recent.contains("trust this directory")) {
                        write(master, Data("\r".utf8))
                        acceptedStatusWorkspaceTrust = true
                    }
                }
            }

            let ready = request.provider == .claude || sawPrompt
            if commandsSent < maximumAttempts,
               ready,
               now >= nextCommandAt,
               now.timeIntervalSince(lastOutputAt) >= 0.25 {
                switch request.provider {
                case .claude: write(master, Data("/usage\r".utf8))
                case .codex: write(master, Data("/status\r".utf8))
                }
                commandsSent += 1
                nextCommandAt = now.addingTimeInterval(3)
            }

            var status: Int32 = 0
            childExited = waitpid(pid, &status, WNOHANG) == pid
            if now.timeIntervalSince(started) >= timeout {
                timedOut = true
                terminateAndReap(pid)
                break
            }
            usleep(50_000)
        }
        close(master)
        return Transcript(text: terminalText(raw), raw: raw, timedOut: timedOut)
    }

    private static func launchChild(_ request: Request) -> Never {
        guard chdir(request.workdir) == 0 else { _exit(126) }
        for change in proxyEnvironmentChanges(provider: request.provider, proxyURL: request.proxyURL) {
            if let value = change.value { setenv(change.name, value, 1) }
            else { unsetenv(change.name) }
        }
        if request.provider == .claude { setenv("NO_PROXY", "localhost,127.0.0.1,::1", 1) }
        if let home = request.codexHome { setenv("CODEX_HOME", home, 1) }

        var arguments = [request.executable]
        if request.provider == .codex {
            arguments += ["-c", "check_for_update_on_startup=false"]
            if request.codexFullAccess { arguments.append("--dangerously-bypass-approvals-and-sandbox") }
        }
        exec(arguments: arguments)
    }

    /// Codex profiles may opt into a direct connection. Clearing both upper-
    /// and lower-case variants matters when the GUI was launched from a shell
    /// that happened to export a global proxy.
    static func proxyEnvironmentChanges(provider: Provider, proxyURL: String) -> [EnvironmentChange] {
        let names = ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"]
        let proxy = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if proxy.isEmpty {
            switch provider {
            case .claude: return [] // Claude is rejected before launch.
            case .codex: return names.map { EnvironmentChange(name: $0, value: nil) }
            }
        }
        return names.map { EnvironmentChange(name: $0, value: proxy) }
    }

    /// Reap the direct PTY child after escalating its process group. Without
    /// the final blocking wait, a timed-out polling cycle can leave a zombie
    /// until the app next handles SIGCHLD.
    private static func terminateAndReap(_ pid: Int32) {
        var status: Int32 = 0
        for signal in [SIGINT, SIGTERM] {
            kill(-pid, signal)
            usleep(400_000)
            if waitpid(pid, &status, WNOHANG) == pid { return }
        }
        kill(-pid, SIGKILL)
        kill(pid, SIGKILL) // Fallback if a terminal implementation changed pgrp.
        _ = waitpid(pid, &status, 0)
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

    /// Render the final TUI frame instead of merely deleting ANSI codes.
    /// Claude and Codex both position text with CSI cursor commands; dropping
    /// those commands joins unrelated cells (for example `Resets1:40pm`) and
    /// makes a real `/usage` response look like a parse failure.
    ///
    /// This intentionally implements only the tiny VT100 subset emitted by
    /// the two status screens: cursor movement, erasing, alternate screen,
    /// and style/OSC suppression. It is not a general terminal emulator.
    static func terminalText(_ raw: Data) -> String {
        let bytes = Array(raw)
        guard !bytes.isEmpty else { return "" }

        var primary = TerminalBuffer()
        var alternate = TerminalBuffer()
        var usesAlternate = false
        var index = 0

        func mutateActive(_ body: (inout TerminalBuffer) -> Void) {
            if usesAlternate { body(&alternate) } else { body(&primary) }
        }

        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case 0x1B:
                guard index + 1 < bytes.count else { index += 1; continue }
                let introducer = bytes[index + 1]
                if introducer == 0x5B { // CSI
                    var end = index + 2
                    while end < bytes.count, !(0x40...0x7E).contains(bytes[end]) { end += 1 }
                    guard end < bytes.count else { break }
                    let parameters = String(decoding: bytes[(index + 2)..<end], as: UTF8.self)
                    let command = bytes[end]
                    if command == 0x68 || command == 0x6C, parameters.contains("?1049") {
                        usesAlternate = command == 0x68
                    } else {
                        mutateActive { $0.applyCSI(command: command, parameters: parameters) }
                    }
                    index = end + 1
                } else if introducer == 0x5D { // OSC ... BEL / ST
                    index += 2
                    while index < bytes.count {
                        if bytes[index] == 0x07 { index += 1; break }
                        if bytes[index] == 0x1B, index + 1 < bytes.count, bytes[index + 1] == 0x5C {
                            index += 2
                            break
                        }
                        index += 1
                    }
                } else {
                    mutateActive { screen in
                        if introducer == 0x37 { screen.saveCursor() } // ESC 7
                        if introducer == 0x38 { screen.restoreCursor() } // ESC 8
                    }
                    index += 2
                }
            case 0x0D: // CR
                mutateActive { $0.carriageReturn() }
                index += 1
            case 0x0A: // LF
                mutateActive { $0.lineFeed() }
                index += 1
            case 0x08: // BS
                mutateActive { $0.backspace() }
                index += 1
            case 0x09: // TAB
                mutateActive { $0.tab() }
                index += 1
            case 0x00...0x1F, 0x7F:
                index += 1
            default:
                let length: Int
                switch byte {
                case 0xC0...0xDF: length = 2
                case 0xE0...0xEF: length = 3
                case 0xF0...0xF7: length = 4
                default: length = 1
                }
                let end = min(bytes.count, index + length)
                let scalar = String(decoding: bytes[index..<end], as: UTF8.self)
                for character in scalar { mutateActive { $0.write(character) } }
                index = end
            }
        }

        // Prefer the physical alternate screen whenever it has quota content.
        // The linear ANSI-stripped stream can contain several redraws and may
        // score higher merely by repeating damaged labels.
        let alternateText = alternate.rendered()
        if quotaScore(alternateText) > 0 { return alternateText }
        let primaryText = primary.rendered()
        if quotaScore(primaryText) > 0 { return primaryText }
        return strippedTerminalText(raw)
    }

    private static func strippedTerminalText(_ raw: Data) -> String {
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

    private static func quotaScore(_ text: String) -> Int {
        ["Current session", "Current week", "5h limit", "Weekly limit", "% used", "% left", "Resets"]
            .reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }
    }

    private struct TerminalBuffer {
        private static let rows = 24
        private static let columns = 80
        private var cells = Array(
            repeating: Array(repeating: Character(" "), count: columns), count: rows
        )
        private var row = 0
        private var column = 0
        private var wrapPending = false
        private var savedRow = 0
        private var savedColumn = 0

        mutating func write(_ character: Character) {
            if wrapPending {
                column = 0
                lineFeed()
                wrapPending = false
            }
            guard cells.indices.contains(row), cells[row].indices.contains(column) else { return }
            cells[row][column] = character
            if column == Self.columns - 1 { wrapPending = true } else { column += 1 }
        }

        mutating func carriageReturn() { column = 0; wrapPending = false }
        mutating func backspace() { column = max(0, column - 1); wrapPending = false }
        mutating func tab() { column = min(Self.columns - 1, ((column / 8) + 1) * 8); wrapPending = false }
        mutating func lineFeed() {
            if row < Self.rows - 1 { row += 1 }
            else { cells.removeFirst(); cells.append(Array(repeating: Character(" "), count: Self.columns)) }
            wrapPending = false
        }
        mutating func saveCursor() { savedRow = row; savedColumn = column; wrapPending = false }
        mutating func restoreCursor() { row = savedRow; column = savedColumn; wrapPending = false }

        mutating func applyCSI(command: UInt8, parameters: String) {
            let numbers = parameters
                .split(separator: ";", omittingEmptySubsequences: false)
                .map { Int($0.filter(\.isNumber)) ?? 0 }
            let first = numbers.first ?? 0
            let second = numbers.dropFirst().first ?? 0
            switch command {
            case 0x41: row = max(0, row - max(1, first)) // A
            case 0x42: row = min(Self.rows - 1, row + max(1, first)) // B
            case 0x43: column = min(Self.columns - 1, column + max(1, first)) // C
            case 0x44: column = max(0, column - max(1, first)) // D
            case 0x47: column = min(Self.columns - 1, max(0, first - 1)) // G
            case 0x48, 0x66: // H / f
                row = min(Self.rows - 1, max(0, first - 1))
                column = min(Self.columns - 1, max(0, second - 1))
            case 0x64: row = min(Self.rows - 1, max(0, first - 1)) // d
            case 0x4A: eraseDisplay(first) // J
            case 0x4B: eraseLine(first) // K
            case 0x58: eraseCharacters(first) // X
            case 0x73: saveCursor() // s
            case 0x75: restoreCursor() // u
            default: break // SGR, show/hide cursor, scroll region, etc.
            }
            if [0x41, 0x42, 0x43, 0x44, 0x47, 0x48, 0x66, 0x64].contains(command) {
                wrapPending = false
            }
        }

        private mutating func eraseDisplay(_ mode: Int) {
            if mode == 2 || mode == 3 {
                cells = Array(repeating: Array(repeating: Character(" "), count: Self.columns), count: Self.rows)
                row = 0; column = 0
            } else if mode == 0 {
                eraseLine(0)
                guard row + 1 < Self.rows else { return }
                for next in (row + 1)..<Self.rows {
                    cells[next] = Array(repeating: Character(" "), count: Self.columns)
                }
            }
        }

        private mutating func eraseLine(_ mode: Int) {
            guard cells.indices.contains(row) else { return }
            let range: ClosedRange<Int>
            switch mode {
            case 1: range = 0...column
            case 2: range = 0...(Self.columns - 1)
            default: range = column...(Self.columns - 1)
            }
            for index in range where cells[row].indices.contains(index) { cells[row][index] = " " }
        }

        private mutating func eraseCharacters(_ count: Int) {
            guard cells.indices.contains(row) else { return }
            let end = min(Self.columns, column + max(1, count))
            guard column < end else { return }
            for index in column..<end { cells[row][index] = " " }
        }

        func rendered() -> String {
            cells.map { String($0).trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
        }
    }
}
