import Combine
import Foundation

/// Which rate-limit window each provider contributes to its compact island
/// pill. The expanded Usage page still shows both windows; this only controls
/// the at-a-glance number. Weekly is the calmer, more useful default.
@MainActor
final class QuotaWindowPreferenceStore: ObservableObject {
    static let shared = QuotaWindowPreferenceStore()

    private static let claudeKey = "CodexIsland.quotaWindow.claude"
    private static let codexKey = "CodexIsland.quotaWindow.codex"

    @Published var claude: UsageWindow {
        didSet { UserDefaults.standard.set(claude.rawValue, forKey: Self.claudeKey) }
    }
    @Published var codex: UsageWindow {
        didSet { UserDefaults.standard.set(codex.rawValue, forKey: Self.codexKey) }
    }

    private init() {
        claude = UsageWindow(rawValue: UserDefaults.standard.string(forKey: Self.claudeKey) ?? "") ?? .weekly
        codex = UsageWindow(rawValue: UserDefaults.standard.string(forKey: Self.codexKey) ?? "") ?? .weekly
    }

    func selectedWindow(for provider: AlertEngine.Provider) -> UsageWindow {
        provider == .claude ? claude : codex
    }

}
