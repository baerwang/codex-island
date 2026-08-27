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

    func select(_ profileID: UUID?, in profiles: [CodexCLIProfile]) {
        guard let profileID else {
            selectedProfileID = nil
            return
        }
        selectedProfileID = profiles.contains(where: { $0.id == profileID })
            ? profileID
            : nil
    }

    func normalize(in profiles: [CodexCLIProfile]) {
        guard let selectedProfileID,
              !profiles.contains(where: { $0.id == selectedProfileID })
        else { return }
        self.selectedProfileID = nil
    }
}
