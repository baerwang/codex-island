import Combine
import Foundation

enum CodexQuotaMode: String, CaseIterable, Codable, Sendable {
    case auto
    case subscription
    case api

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .subscription: return "Subscription"
        case .api: return "API"
        }
    }
}

/// User-owned launch configuration for the provider CLIs. Credentials stay in
/// those CLIs' own stores; CodexIsland persists only paths, display names and
/// proxy URLs needed to launch a status-only interactive session.
struct CodexCLIProfile: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var codexHome: String
    var proxyURL: String
    var enabled: Bool
    /// Optional to keep previously saved profile JSON decodable. nil means
    /// automatic detection from the CLI status screen.
    var quotaMode: CodexQuotaMode?

    init(
        id: UUID = UUID(), name: String, codexHome: String,
        proxyURL: String = "", enabled: Bool = true, quotaMode: CodexQuotaMode? = nil
    ) {
        self.id = id
        self.name = name
        self.codexHome = codexHome
        self.proxyURL = proxyURL
        self.enabled = enabled
        self.quotaMode = quotaMode
    }

    var expandedHome: String {
        NSString(string: codexHome).expandingTildeInPath
    }

    /// Canonical identity for deduplicating profiles that point to the same
    /// local session tree through `~`, `.` or a symlinked path.
    var canonicalHome: String? {
        let expanded = expandedHome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expanded.isEmpty else { return nil }
        return URL(fileURLWithPath: expanded)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    var effectiveQuotaMode: CodexQuotaMode { quotaMode ?? .auto }
}

@MainActor
final class CLIProviderConfigStore: ObservableObject {
    static let shared = CLIProviderConfigStore()

    private static let claudeProxyKey = "CodexIsland.cli.claudeProxy"
    private static let claudeWorkdirKey = "CodexIsland.cli.claudeWorkdir"
    private static let codexProfilesKey = "CodexIsland.cli.codexProfiles.v1"
    private static let codexWorkdirKey = "CodexIsland.cli.codexWorkdir"

    @Published var claudeProxyURL: String { didSet { saveClaude() } }
    /// `/private/tmp` is user-selected as the stable, non-project status
    /// workspace. We never create, delete or write within it.
    @Published var claudeWorkdir: String { didSet { UserDefaults.standard.set(claudeWorkdir, forKey: Self.claudeWorkdirKey) } }
    @Published var codexWorkdir: String { didSet { UserDefaults.standard.set(codexWorkdir, forKey: Self.codexWorkdirKey) } }
    @Published var codexProfiles: [CodexCLIProfile] { didSet { saveCodexProfiles() } }

    private init() {
        claudeProxyURL = UserDefaults.standard.string(forKey: Self.claudeProxyKey) ?? ""
        claudeWorkdir = UserDefaults.standard.string(forKey: Self.claudeWorkdirKey) ?? "/private/tmp"
        codexWorkdir = UserDefaults.standard.string(forKey: Self.codexWorkdirKey) ?? "/private/tmp"
        if let data = UserDefaults.standard.data(forKey: Self.codexProfilesKey),
           let decoded = try? JSONDecoder().decode([CodexCLIProfile].self, from: data) {
            codexProfiles = decoded
        } else {
            codexProfiles = []
        }
    }

    var activeCodexProfiles: [CodexCLIProfile] {
        codexProfiles.filter { $0.enabled }
    }

    func addCodexProfile() {
        codexProfiles.append(CodexCLIProfile(
            name: uniqueCodexProfileName("Codex \(codexProfiles.count + 1)"), codexHome: ""
        ))
    }

    func removeCodexProfile(id: UUID) {
        codexProfiles.removeAll { $0.id == id }
    }

    /// Profile names appear beside quota windows and project cost rows, so
    /// make them stable human identifiers rather than ambiguous duplicates.
    func uniqueCodexProfileName(_ proposed: String, excluding id: UUID? = nil) -> String {
        let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = base.isEmpty ? "Codex" : base
        let used = Set(codexProfiles
            .filter { $0.id != id }
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        guard used.contains(stem.lowercased()) else { return stem }
        var number = 2
        while used.contains("\(stem) \(number)".lowercased()) { number += 1 }
        return "\(stem) \(number)"
    }

    private func saveClaude() {
        UserDefaults.standard.set(claudeProxyURL, forKey: Self.claudeProxyKey)
    }

    private func saveCodexProfiles() {
        if let data = try? JSONEncoder().encode(codexProfiles) {
            UserDefaults.standard.set(data, forKey: Self.codexProfilesKey)
        }
    }
}
