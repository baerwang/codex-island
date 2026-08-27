import Combine
import Foundation

/// Account filter for local Codex consumption surfaces. nil means all active
/// profiles and is intentionally the launch default; unlike quota selection,
/// it includes API-only homes because their local logs remain meaningful.
@MainActor
final class CodexCostProfileStore: ObservableObject {
    static let shared = CodexCostProfileStore()

    @Published var selectedProfileID: UUID?

    private init() {
        selectedProfileID = nil
    }

    func advance(in profiles: [CodexCLIProfile]) {
        selectedProfileID = CodexCostProfileCycle.next(
            current: selectedProfileID, profileIDs: profiles.map(\.id)
        )
    }

    func normalize(in profiles: [CodexCLIProfile]) {
        guard let selectedProfileID,
              !profiles.contains(where: { $0.id == selectedProfileID })
        else { return }
        self.selectedProfileID = nil
    }
}

enum CodexCostProfileCycle {
    /// Cycle All → profile 1 → … → profile N → All.
    static func next(current: UUID?, profileIDs: [UUID]) -> UUID? {
        guard !profileIDs.isEmpty else { return nil }
        guard let current,
              let index = profileIDs.firstIndex(of: current)
        else { return profileIDs[0] }
        let nextIndex = index + 1
        return nextIndex < profileIDs.count ? profileIDs[nextIndex] : nil
    }
}
