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
    @Published private(set) var codexHeadlineProfileID: UUID?
    @Published var lastUpdated: Date?
    @Published private(set) var claudeLastUpdated: Date?
    @Published private(set) var codexLastUpdated: Date?
    @Published private(set) var claudeLoading = false
    @Published private(set) var codexLoading = false

    private var refreshTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var intervalCancellable: AnyCancellable?
    private var refreshPending = false
    private var codexRefreshPending = false
    private var activeRefreshID: UUID?

    private init() {}

    /// Compatibility surface for callers that only need to know whether any
    /// quota provider is still in flight. Refresh serialization deliberately
    /// does not use this value: Claude's secondary `/status` probe may keep
    /// the refresh task alive after both quota loads have completed.
    var loading: Bool { claudeLoading || codexLoading }

    var codexQuotaSurfaceVisible: Bool {
        !codexHeadlineUsage.isNonSubscriptionMode
    }

    /// Single source of truth for every quota surface. The selected profile
    /// ID and its reading resolve together, avoiding a one-render lag between
    /// the separately published ID and the legacy `codex` mirror.
    var codexHeadlineUsage: AppUsage {
        Self.resolveCodexHeadlineUsage(
            profileID: codexHeadlineProfileID,
            readings: codexByProfile,
            fallback: codex
        )
    }

    nonisolated static func resolveCodexHeadlineUsage(
        profileID: UUID?, readings: [UUID: AppUsage], fallback: AppUsage
    ) -> AppUsage {
        guard let profileID, let selected = readings[profileID] else { return fallback }
        return selected
    }

    private var pollInterval: TimeInterval {
        TimeInterval(RefreshIntervalStore.shared.seconds)
    }

    func refresh() {
        guard activeRefreshID == nil else {
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

        let refreshID = UUID()
        activeRefreshID = refreshID
        claudeLoading = true
        codexLoading = true
        refreshTask = Task {
            let profiles = CLIProviderConfigStore.shared.activeCodexProfiles
            let codexWorkdir = CLIProviderConfigStore.statusWorkdir
            // Every configured account owns an independent PTY, proxy and
            // CODEX_HOME. Run those bounded status sessions together so one
            // slow/API-only profile never delays another account's quota.
            await withTaskGroup(of: FullRefreshResult.self) { group in
                group.addTask {
                    .claudeQuota(await UsageFetcher.fetchClaude())
                }
                group.addTask {
                    .codexQuota(await Self.fetchCodexReadings(profiles, workdir: codexWorkdir))
                }

                for await result in group {
                    guard !Task.isCancelled, activeRefreshID == refreshID else {
                        group.cancelAll()
                        return
                    }

                    switch result {
                    case .claudeQuota(let newClaude):
                        // Publish and clear Claude independently. A slow Codex
                        // account must not leave the completed Claude surface
                        // looking as if it were still synchronizing.
                        let now = Date()
                        claude = AppUsage.merged(
                            fetched: newClaude, retaining: claude, at: now
                        )
                        UsageHistoryStore.shared.record(
                            provider: .claude, usage: newClaude, at: now
                        )
                        claudeLastUpdated = now
                        updateCombinedTimestamp()
                        claudeLoading = false

                        // Login method is secondary metadata. Run it beside
                        // any remaining Codex work, but never represent it as
                        // Claude quota loading.
                        if newClaude.fiveHour.hasReading || newClaude.weekly.hasReading {
                            group.addTask {
                                .claudeLoginMethod(
                                    await UsageFetcher.fetchClaudeLoginMethod()
                                )
                            }
                        }

                    case .codexQuota(let readings):
                        applyCodexReadings(readings, profiles: profiles, at: Date())
                        codexLoading = false

                    case .claudeLoginMethod(let method):
                        applyClaudeLoginMethod(method, at: Date())
                    }
                }
            }

            finishRefresh(id: refreshID)
        }
    }

    /// Refresh only the manually configured Codex accounts. Settings calls
    /// this when a Codex launch field changes so editing CODEX_HOME/proxy does
    /// not repeatedly open unrelated Claude `/usage` and `/status` sessions.
    func refreshCodexForConfiguredProfiles() {
        guard activeRefreshID == nil else {
            codexRefreshPending = true
            return
        }
        if AppEnvironment.isDemo {
            loadDemoUsage()
            return
        }

        let refreshID = UUID()
        activeRefreshID = refreshID
        codexLoading = true
        refreshTask = Task {
            let profiles = CLIProviderConfigStore.shared.activeCodexProfiles
            let readings = await Self.fetchCodexReadings(
                profiles, workdir: CLIProviderConfigStore.statusWorkdir
            )
            guard !Task.isCancelled, activeRefreshID == refreshID else {
                finishRefresh(id: refreshID)
                return
            }
            applyCodexReadings(readings, profiles: profiles, at: Date())
            codexLoading = false
            finishRefresh(id: refreshID)
        }
    }

    private enum FullRefreshResult {
        case claudeQuota(AppUsage)
        case codexQuota([(UUID, AppUsage)])
        case claudeLoginMethod(String?)
    }

    private func applyCodexReadings(
        _ readings: [(UUID, AppUsage)], profiles: [CodexCLIProfile], at now: Date
    ) {
        var nextProfiles: [UUID: AppUsage] = [:]
        for (id, fetched) in readings {
            let prior = codexByProfile[id] ?? .empty
            nextProfiles[id] = AppUsage.merged(fetched: fetched, retaining: prior, at: now)
        }
        codexByProfile = nextProfiles
        if profiles.isEmpty {
            codex = UsageFetcher.errorPair("add codex profile")
            codexHeadlineProfileID = nil
        } else if let headline = CodexHeadlineSelection.select(
            profiles: profiles, readings: nextProfiles
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
        for (profileID, profileUsage) in nextProfiles {
            UsageHistoryStore.shared.record(
                provider: .codex, usage: profileUsage, at: now,
                sourceID: profileID.uuidString
            )
        }
        codexLastUpdated = now
        updateCombinedTimestamp()
    }

    private func updateCombinedTimestamp() {
        switch (claudeLastUpdated, codexLastUpdated) {
        case let (claude?, codex?): lastUpdated = min(claude, codex)
        case let (claude?, nil): lastUpdated = claude
        case let (nil, codex?): lastUpdated = codex
        case (nil, nil): lastUpdated = nil
        }
    }

    private func applyClaudeLoginMethod(_ method: String?, at now: Date) {
        guard let method else { return }
        switch method {
        case "api", "third-party":
            claude = AppUsage.merged(
                fetched: UsageFetcher.noSubscriptionUsage(plan: method),
                retaining: claude,
                at: now
            )
        case "unauthenticated":
            claude = AppUsage.merged(
                fetched: UsageFetcher.unauthenticatedUsage(), retaining: claude, at: now
            )
        default:
            claude.plan = method
        }
    }

    nonisolated private static func fetchCodexReadings(
        _ profiles: [CodexCLIProfile], workdir: String
    ) async -> [(UUID, AppUsage)] {
        var immediateReadings: [(UUID, AppUsage)] = []
        var seenCodexHomes = Set<String>()
        return await withTaskGroup(
            of: (UUID, AppUsage).self, returning: [(UUID, AppUsage)].self
        ) { group in
            for profile in profiles {
                if let home = profile.canonicalHome, !seenCodexHomes.insert(home).inserted {
                    immediateReadings.append((profile.id, UsageFetcher.errorPair("duplicate codex home")))
                } else {
                    group.addTask {
                        (profile.id, await UsageFetcher.fetchCodex(profile: profile, workdir: workdir))
                    }
                }
            }
            var output = immediateReadings
            for await reading in group { output.append(reading) }
            return output
        }
    }

    private func finishRefresh(id: UUID) {
        guard activeRefreshID == id else { return }
        activeRefreshID = nil
        refreshTask = nil
        claudeLoading = false
        codexLoading = false
        if refreshPending {
            refreshPending = false
            codexRefreshPending = false
            refresh()
        } else if codexRefreshPending {
            codexRefreshPending = false
            refreshCodexForConfiguredProfiles()
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
        refreshPending = false
        codexRefreshPending = false
        refreshTask?.cancel()
        refreshTask = nil
        CLIStatusProbe.terminateAllActiveProbes()
        activeRefreshID = nil
        claudeLoading = false
        codexLoading = false
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
        claudeLastUpdated = now
        codexLastUpdated = now
        updateCombinedTimestamp()
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
        claudeLastUpdated = now
        codexLastUpdated = now
        updateCombinedTimestamp()
    }
}
