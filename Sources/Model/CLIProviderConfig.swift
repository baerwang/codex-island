import Combine
import Foundation

/// User-owned launch configuration for the provider CLIs. Credentials stay in
/// those CLIs' own stores; CodexIsland persists only paths, display names and
/// proxy URLs needed to launch a status-only interactive session.
struct CodexCLIProfile: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var codexHome: String
    var proxyURL: String
    var enabled: Bool

    init(
        id: UUID = UUID(), name: String, codexHome: String,
        proxyURL: String = "", enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.codexHome = codexHome
        self.proxyURL = proxyURL
        self.enabled = enabled
    }

    var expandedHome: String {
        NSString(string: codexHome).expandingTildeInPath
    }
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
            name: "Codex \(codexProfiles.count + 1)", codexHome: ""
        ))
    }

    func removeCodexProfile(id: UUID) {
        codexProfiles.removeAll { $0.id == id }
    }

    func proxyConfigured(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return (url.scheme == "http" || url.scheme == "https") && url.host != nil
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
