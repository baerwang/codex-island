import Foundation

/// Pure compact-island window choice. Honor the user's provider-specific
/// preference when available, but fall back to the other real reading rather
/// than showing an empty weekly/5h tile on plans that omit one window.
enum CompactQuotaSelection {
    static func select(usage: AppUsage, preferred: UsageWindow) -> (window: WindowUsage, kind: UsageWindow) {
        let selected = window(usage, kind: preferred)
        if selected.hasReading { return (selected, preferred) }
        let fallback: UsageWindow = preferred == .weekly ? .fiveHour : .weekly
        return (window(usage, kind: fallback), fallback)
    }

    private static func window(_ usage: AppUsage, kind: UsageWindow) -> WindowUsage {
        kind == .weekly ? usage.weekly : usage.fiveHour
    }
}
