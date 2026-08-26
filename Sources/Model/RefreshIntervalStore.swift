import Foundation

/// User-controlled poll cadence for `UsageStore`. Interactive CLI probes are
/// deliberately bounded work, so we expose only 5min / 15min / 30min — never
/// anything below 5min.
@MainActor
final class RefreshIntervalStore: ObservableObject {
    static let shared = RefreshIntervalStore()

    private static let key = "MacIsland.refreshInterval"
    static let allowed: [Int] = [300, 900, 1800]

    @Published var seconds: Int {
        didSet { UserDefaults.standard.set(seconds, forKey: Self.key) }
    }

    private init() {
        self.seconds = Pref.int(key: Self.key, default: 300, allowed: Self.allowed)
    }
}
