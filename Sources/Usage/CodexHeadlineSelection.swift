import Foundation

/// Picks the one account-safe Codex reading that fits the compact island.
/// Quotas from profiles are never aggregated. A usable subscription reading
/// wins; if none succeeded, a subscription-shaped failure remains visible
/// before an API-only profile so a transient timeout cannot hide Codex.
enum CodexHeadlineSelection {
    static func select(
        profiles: [CodexCLIProfile], readings: [UUID: AppUsage], preferredID: UUID? = nil
    ) -> (id: UUID, usage: AppUsage)? {
        let candidates = profiles.compactMap { profile -> (UUID, AppUsage)? in
            guard let usage = readings[profile.id] else { return nil }
            return (profile.id, usage)
        }
        let hasSubscriptionCandidate = candidates.contains { !$0.1.isNonSubscriptionMode }
        if let preferredID, let preferred = candidates.first(where: { $0.0 == preferredID }),
           !preferred.1.isNonSubscriptionMode || !hasSubscriptionCandidate {
            return preferred
        }
        return candidates.first {
            $0.1.fiveHour.hasReading || $0.1.weekly.hasReading
        } ?? candidates.first {
            !$0.1.isNonSubscriptionMode
        } ?? candidates.first
    }
}
