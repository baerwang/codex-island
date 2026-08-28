import Foundation

/// Visibility for the two decorative provider logos while the island is fully
/// at rest. This does not change provider visibility, quota pills, or panel
/// content. Hiding them lets IslandModel reclaim both logo tabs in compact
/// mode; percentage peek and expanded modes restore the logos automatically.
@MainActor
final class LogoVisibilityStore: ObservableObject {
    static let shared = LogoVisibilityStore()

    private static let key = "MacIsland.sideLogosVisible"

    @Published var visible: Bool {
        didSet { UserDefaults.standard.set(visible, forKey: Self.key) }
    }

    private init() {
        visible = Pref.seededBool(key: Self.key, default: true)
    }
}
