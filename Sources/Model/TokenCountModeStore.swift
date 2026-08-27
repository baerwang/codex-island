import Foundation

/// How token-based cost and overview screens sum usage. Anthropic's claude.ai
/// stats panel reports billable tokens only (input + output), while ccusage
/// — and CodexIsland by default — sum every token type that crossed the
/// wire, including cache reads. The two diverge by ~10× in normal Claude
/// Code usage because cache_read_input_tokens dwarfs the rest.
enum TokenCountMode: String, CaseIterable {
    /// input + output + cache_creation + cache_read. ccusage parity.
    case all
    /// input + output only. Matches Anthropic's stats dashboard.
    case billable

    var label: String {
        switch self {
        case .all:      L10n.tr("All tokens")
        case .billable: L10n.tr("Input + output")
        }
    }
}

@MainActor
final class TokenCountModeStore: ObservableObject {
    static let shared = TokenCountModeStore()

    private static let key = "MacIsland.tokenCountMode"

    @Published var mode: TokenCountMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.key) }
    }

    private init() {
        self.mode = Pref.enumValue(key: Self.key, default: .all)
    }
}
