import Foundation

/// Picks the one account-safe Codex reading that fits the compact island.
/// Quotas from profiles are never aggregated; a subscription reading wins over
/// an API-key-only profile, and an error remains visible only when no profile
/// yielded usable data.
enum CodexHeadlineSelection {
    static func select(
        profiles: [CodexCLIProfile], readings: [UUID: AppUsage], preferredID: UUID? = nil
    ) -> (id: UUID, usage: AppUsage)? {
        let candidates = profiles.compactMap { profile -> (UUID, AppUsage)? in
            guard let usage = readings[profile.id] else { return nil }
            return (profile.id, usage)
        }
        if let preferredID, let preferred = candidates.first(where: { $0.0 == preferredID }) {
            return preferred
        }
        return candidates.first {
            $0.1.fiveHour.hasReading || $0.1.weekly.hasReading
        } ?? candidates.first { $0.1.plan == "api" } ?? candidates.first
    }
}
