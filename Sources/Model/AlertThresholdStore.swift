import Foundation

/// User-controlled approaching-limit alert preferences.
///
/// When `enabled` is true, the island silhouette glow shifts to amber/red
/// while the selected compact quota window is at or above the user's chosen
/// thresholds, and the peek pill auto-extends once when a window first
/// crosses a threshold inside its current reset cycle.
///
/// Default `enabled = false`: existing users should not get a surprise
/// visual change on update; alerts are opt-in via Settings.
@MainActor
final class AlertThresholdStore: ObservableObject {
    static let shared = AlertThresholdStore()

    private static let enabledKey = "MacIsland.alertsEnabled"
    private static let warningKey = "MacIsland.alertWarning"
    private static let criticalKey = "MacIsland.alertCritical"

    /// Allowed integer ranges. Steppers in the Settings UI clamp to these.
    /// Keeping warning < critical is enforced live in the UI; if a user
    /// somehow lands an invalid pair (e.g. via direct UserDefaults edit),
    /// `AlertEngine` treats the case as "no thresholds active" until the
    /// user fixes it in Settings.
    static let warningRange: ClosedRange<Int> = 50...98
    static let criticalRange: ClosedRange<Int> = 51...99

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }

    @Published var warningPercent: Int {
        didSet { UserDefaults.standard.set(warningPercent, forKey: Self.warningKey) }
    }

    @Published var criticalPercent: Int {
        didSet { UserDefaults.standard.set(criticalPercent, forKey: Self.criticalKey) }
    }

    private init() {
        self.enabled = Pref.seededBool(key: Self.enabledKey, default: false)
        self.warningPercent = Pref.int(key: Self.warningKey, default: 80, range: Self.warningRange)
        self.criticalPercent = Pref.int(key: Self.criticalKey, default: 95, range: Self.criticalRange)
    }
}
