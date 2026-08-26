import Foundation
import Combine

/// Live provider status sourced exclusively from interactive CLI sessions.
/// The app never reads a provider credential or sends a provider HTTP request.
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()
    private static let preferredCodexProfileKey = "CodexIsland.preferredCodexProfileID"

    @Published var claude: AppUsage = .empty
    @Published var codex: AppUsage = .empty
    @Published private(set) var codexByProfile: [UUID: AppUsage] = [:]
    @Published private(set) var codexHeadlineProfileID: UUID?
    @Published private(set) var preferredCodexProfileID: UUID?
    @Published var lastUpdated: Date?
    @Published var loading = false

    private var refreshTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var intervalCancellable: AnyCancellable?
    private var refreshPending = false
    private var activeRefreshID: UUID?

    private init() {
        preferredCodexProfileID = UserDefaults.standard.string(forKey: Self.preferredCodexProfileKey)
            .flatMap(UUID.init(uuidString:))
    }

    var codexHasSubscriptionQuota: Bool {
        codex.fiveHour.hasReading || codex.weekly.hasReading
    }

    private var pollInterval: TimeInterval {
        TimeInterval(RefreshIntervalStore.shared.seconds)
    }

    func refresh() {
        guard !loading else {
            // Settings can settle while a previous CLI session is still
            // running. Coalesce those edits into one follow-up pass rather
            // than silently making the user wait for the next 5-minute tick.
            refreshPending = true
            return
        }
        if AppEnvironment.isDemo {
            loadDemoUsage()
            return
        }

        loading = true
        let refreshID = UUID()
        activeRefreshID = refreshID
        refreshTask = Task {
            let profiles = CLIProviderConfigStore.shared.activeCodexProfiles
            let codexWorkdir = CLIProviderConfigStore.statusWorkdir
            if let preferredCodexProfileID,
               !profiles.contains(where: { $0.id == preferredCodexProfileID }) {
                self.preferredCodexProfileID = nil
                UserDefaults.standard.removeObject(forKey: Self.preferredCodexProfileKey)
            }
            // Every configured account owns an independent PTY, proxy and
            // CODEX_HOME. Run those bounded status sessions together so one
            // slow/API-only profile never delays another account's quota.
            async let claudeResult = UsageFetcher.fetchClaude()
            var immediateReadings: [(UUID, AppUsage)] = []
            var seenCodexHomes = Set<String>()
            let profileReadings = await withTaskGroup(
                of: (UUID, AppUsage).self, returning: [(UUID, AppUsage)].self
            ) { group in
                for profile in profiles {
                    if let home = profile.canonicalHome, !seenCodexHomes.insert(home).inserted {
                        immediateReadings.append((profile.id, UsageFetcher.errorPair("duplicate codex home")))
                    } else {
                        group.addTask {
                            (profile.id, await UsageFetcher.fetchCodex(profile: profile, workdir: codexWorkdir))
                        }
                    }
                }
                var output = immediateReadings
                for await reading in group { output.append(reading) }
                return output
            }
            let newClaude = await claudeResult
            guard !Task.isCancelled, activeRefreshID == refreshID else {
                finishRefresh(id: refreshID)
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
            if profiles.isEmpty {
                codex = UsageFetcher.errorPair("add codex profile")
                codexHeadlineProfileID = nil
            } else if let headline = CodexHeadlineSelection.select(
                profiles: profiles, readings: nextProfiles, preferredID: preferredCodexProfileID
            ) {
                // Quotas from accounts are never combined. The compact island
                // shows one usable manually configured profile; Settings and
                // the expanded quota list retain every profile separately.
                codex = headline.usage
                codexHeadlineProfileID = headline.id
            } else {
                codex = UsageFetcher.errorPair("codex status unavailable")
                codexHeadlineProfileID = nil
            }
            UsageHistoryStore.shared.record(provider: .claude, usage: newClaude, at: now)
            for (profileID, profileUsage) in nextProfiles {
                UsageHistoryStore.shared.record(
                    provider: .codex, usage: profileUsage, at: now,
                    sourceID: profileID.uuidString
                )
            }
            lastUpdated = now
            finishRefresh(id: refreshID)
        }
    }

    private func finishRefresh(id: UUID) {
        guard activeRefreshID == id else { return }
        activeRefreshID = nil
        refreshTask = nil
        loading = false
        if refreshPending {
            refreshPending = false
            refresh()
        }
    }

    /// An explicit in-memory profile choice is never an account aggregate and
    /// is cleared if the profile is removed. It lets the compact island switch
    /// between manually configured Codex accounts and persists only after the
    /// user makes that explicit choice (there is no implicit default profile).
    func selectCodexProfile(id: UUID) {
        guard let usage = codexByProfile[id] else { return }
        preferredCodexProfileID = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.preferredCodexProfileKey)
        codexHeadlineProfileID = id
        codex = usage
    }

    func selectNextCodexProfile(in profiles: [CodexCLIProfile]) {
        let available = profiles.filter { codexByProfile[$0.id] != nil }
        guard !available.isEmpty else { return }
        let current = codexHeadlineProfileID.flatMap { id in
            available.firstIndex(where: { $0.id == id })
        } ?? -1
        let next = available[(current + 1) % available.count]
        selectCodexProfile(id: next.id)
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
        refreshPending = false
        refreshTask?.cancel()
        refreshTask = nil
        activeRefreshID = nil
        loading = false
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
