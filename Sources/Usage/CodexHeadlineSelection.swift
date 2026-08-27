import Foundation

/// Picks the one account-safe Codex reading that fits the compact island.
/// Quotas from profiles are never aggregated. A usable subscription reading
/// wins. A real 5h reading has priority over a weekly-only reading regardless
/// of profile order; if neither exists, a subscription-shaped failure remains
/// visible before an API-only profile so a transient timeout cannot hide Codex.
enum CodexHeadlineSelection {
    static func select(
        profiles: [CodexCLIProfile], readings: [UUID: AppUsage]
    ) -> (id: UUID, usage: AppUsage)? {
        let candidates = profiles.compactMap { profile -> (UUID, AppUsage)? in
            guard let usage = readings[profile.id] else { return nil }
            return (profile.id, usage)
        }
        return candidates.first {
            !$0.1.isNonSubscriptionMode && $0.1.fiveHour.hasReading
        } ?? candidates.first {
            !$0.1.isNonSubscriptionMode && $0.1.weekly.hasReading
        } ?? candidates.first {
            !$0.1.isNonSubscriptionMode
        } ?? candidates.first
    }
}
