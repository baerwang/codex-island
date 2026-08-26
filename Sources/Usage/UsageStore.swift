import Foundation
import Combine

/// Live provider status sourced exclusively from interactive CLI sessions.
/// The app never reads a provider credential or sends a provider HTTP request.
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published var claude: AppUsage = .empty
    @Published var codex: AppUsage = .empty
    @Published private(set) var codexByProfile: [UUID: AppUsage] = [:]
    @Published var lastUpdated: Date?
    @Published var loading = false

    private var refreshTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var intervalCancellable: AnyCancellable?

    private init() {}

    private var pollInterval: TimeInterval {
        TimeInterval(RefreshIntervalStore.shared.seconds)
    }

    func refresh() {
        guard !loading else { return }
        if AppEnvironment.isDemo {
            loadDemoUsage()
            return
        }

        loading = true
        refreshTask?.cancel()
        refreshTask = Task {
            let profiles = CLIProviderConfigStore.shared.activeCodexProfiles
            let codexWorkdir = CLIProviderConfigStore.shared.codexWorkdir
            async let claudeResult = UsageFetcher.fetchClaude()
            let profileReadings = await withTaskGroup(of: (UUID, AppUsage).self, returning: [(UUID, AppUsage)].self) { group in
                for profile in profiles {
                    group.addTask {
                        (profile.id, await UsageFetcher.fetchCodex(profile: profile, workdir: codexWorkdir))
                    }
                }
                var out: [(UUID, AppUsage)] = []
                for await reading in group { out.append(reading) }
                return out
            }
            let newClaude = await claudeResult
            guard !Task.isCancelled else {
                loading = false
                return
            }

            let now = Date()
            claude = AppUsage.merged(fetched: newClaude, retaining: claude, at: now)
            var nextProfiles: [UUID: AppUsage] = [:]
            for (id, fetched) in profileReadings {
                let prior = codexByProfile[id] ?? .empty
                nextProfiles[id] = AppUsage.merged(fetched: fetched, retaining: prior, at: now)
            }
            codexByProfile = nextProfiles
            if let first = profiles.first, let fetched = nextProfiles[first.id] {
                codex = fetched
            } else {
                codex = UsageFetcher.errorPair("add codex profile")
            }
            UsageHistoryStore.shared.record(provider: .claude, usage: newClaude, at: now)
            if let first = profiles.first, let fetched = nextProfiles[first.id] {
                UsageHistoryStore.shared.record(provider: .codex, usage: fetched, at: now)
            }
            lastUpdated = now
            loading = false
        }
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        // Direct rework: old endpoint-derived history is not reused as a
        // launch seed. The first values are always from the new CLI probes.
        refresh()
        armTimer()
        intervalCancellable = RefreshIntervalStore.shared.$seconds
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.armTimer() }
            }
    }

    func stopAutoRefresh() {
        pollTimer?.invalidate()
        pollTimer = nil
        intervalCancellable?.cancel()
        intervalCancellable = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func armTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func injectPreviewUsage(claudeFiveHour: Double, codexFiveHour: Double) {
        let now = Date()
        let fiveHourReset = now.addingTimeInterval(2 * 3600 + 14 * 60)
        let weeklyReset = now.addingTimeInterval(4 * 86400 + 6 * 3600)
        claude = AppUsage(
            fiveHour: WindowUsage(usedPercent: claudeFiveHour, resetAt: fiveHourReset, error: nil),
            weekly: WindowUsage(usedPercent: 0.45, resetAt: weeklyReset, error: nil),
            plan: claude.plan
        )
        codex = AppUsage(
            fiveHour: WindowUsage(usedPercent: codexFiveHour, resetAt: fiveHourReset, error: nil),
            weekly: WindowUsage(usedPercent: 0.30, resetAt: weeklyReset, error: nil),
            plan: codex.plan
        )
        lastUpdated = now
    }

    private func loadDemoUsage() {
        let now = Date()
        claude = AppUsage(
            fiveHour: WindowUsage(usedPercent: 0.73, resetAt: now.addingTimeInterval(6420), error: nil),
            weekly: WindowUsage(usedPercent: 0.81, resetAt: now.addingTimeInterval(4 * 86400 + 11 * 3600), error: nil),
            plan: "max"
        )
        codex = AppUsage(
            fiveHour: WindowUsage(usedPercent: 0.67, resetAt: now.addingTimeInterval(8580), error: nil),
            weekly: WindowUsage(usedPercent: 0.76, resetAt: now.addingTimeInterval(4 * 86400 + 18 * 3600), error: nil),
            plan: "pro"
        )
        lastUpdated = now
    }
}
