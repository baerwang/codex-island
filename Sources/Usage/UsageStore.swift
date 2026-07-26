import Foundation
import Combine
import Network

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()
    private init() {}

    @Published var claude: AppUsage = .empty
    @Published var codex: AppUsage = .empty
    @Published var codexResetCredits: CodexResetCredits = .empty
    @Published var lastUpdated: Date?
    @Published var loading = false
    /// Set while a `claude auth login` flow is in progress (spawned + still
    /// polling for the keychain to update). The UI hides the re-auth button
    /// during this window so users don't double-tap and spawn duplicate CLI
    /// processes; the click ends up no-ops anyway because the spawn check
    /// gates on this.
    @Published var claudeReauthInProgress = false

    private var refreshTask: Task<Void, Never>?
    private var reauthPollTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var intervalCancellable: AnyCancellable?
    private var netMonitor: NWPathMonitor?
    private let netQueue = DispatchQueue(label: "UsageStore.network")
    private var lastNetStatus: NWPath.Status?

    /// Anthropic's /api/oauth/usage is aggressively rate-limited per token.
    /// `RefreshIntervalStore` enforces a 5-minute floor (300/900/1800).
    private var pollInterval: TimeInterval {
        TimeInterval(RefreshIntervalStore.shared.seconds)
    }

    /// The /api/oauth/usage limiter is sticky once tripped: it returns 429
    /// with `retry-after: 0` until the account has gone quiet for a while
    /// (anthropics/claude-code#30930), so polling through it never recovers.
    /// After a rate-limited fetch, skip Claude fetches for this long.
    /// Deliberately in-memory only — a quit+relaunch retries immediately.
    private static let rateLimitCooldown: TimeInterval = 900
    private var claudeCooldownUntil: Date?

    func refresh() {
        if loading { return }
        // Demo mode for screen recordings: skip the network entirely and
        // inject hand-tuned values that read as "real, healthy heavy-user
        // data". Reset times are recomputed each refresh so the countdowns
        // tick down naturally on camera. Off by default — only fires when
        // CODEXISLAND_DEMO=1 is set in the launching env.
        if AppEnvironment.isDemo {
            let now = Date()
            self.claude = AppUsage(
                fiveHour: WindowUsage(
                    usedPercent: 0.73,
                    resetAt: now.addingTimeInterval(1 * 3600 + 47 * 60),
                    error: nil
                ),
                weekly: WindowUsage(
                    usedPercent: 0.81,
                    resetAt: now.addingTimeInterval(4 * 86400 + 11 * 3600),
                    error: nil
                ),
                plan: "max"
            )
            self.codex = AppUsage(
                fiveHour: WindowUsage(
                    usedPercent: 0.67,
                    resetAt: now.addingTimeInterval(2 * 3600 + 23 * 60),
                    error: nil
                ),
                weekly: WindowUsage(
                    usedPercent: 0.76,
                    resetAt: now.addingTimeInterval(4 * 86400 + 18 * 3600),
                    error: nil
                ),
                plan: "pro"
            )
            self.codexResetCredits = CodexResetCredits(
                availableCount: 2,
                credits: [
                    CodexResetCredit(
                        id: "demo-reset-1",
                        status: "available",
                        expiresAt: now.addingTimeInterval(3 * 86400 + 4 * 3600),
                        title: "One free rate limit reset",
                        description: "Thanks for using Codex! You've been granted one free rate limit reset."
                    ),
                    CodexResetCredit(
                        id: "demo-reset-2",
                        status: "available",
                        expiresAt: now.addingTimeInterval(9 * 86400 + 3600),
                        title: "One free rate limit reset",
                        description: "Thanks for using Codex! You've been granted one free rate limit reset."
                    )
                ]
            )
            self.lastUpdated = now
            return
        }

        loading = true
        refreshTask?.cancel()
        refreshTask = Task {
            async let codexResult = UsageFetcher.fetchCodex()
            async let codexResetCreditsResult = UsageFetcher.fetchCodexResetCredits()
            let coolingDown = claudeCooldownUntil.map { Date() < $0 } ?? false
            var cl: AppUsage?
            if !coolingDown {
                cl = await UsageFetcher.fetchClaude()
            }
            let c = await codexResult
            let codexResetCredits = await codexResetCreditsResult

            // Cancellation = network monitor saw the path come up while we
            // were mid-flight on a dead one. The fetched values are the
            // dead-path errors — drop them so the supersedes refresh
            // doesn't have a brief "cancelled" caption flash to overwrite.
            if Task.isCancelled {
                self.loading = false
                return
            }

            let now = Date()

            // A failed poll must neither blank the panel nor hide the
            // failure. `merge` keeps each window's last real reading and
            // attaches the new error to it, so the tile shows a true number
            // captioned with what went wrong. A window with nothing to carry
            // stays at `hasReading == false`, which the UI renders as "—"
            // instead of the fabricated 0% it used to show.
            self.codex = AppUsage.merged(fetched: c, retaining: self.codex, at: now)
            if let cl {
                if UsageStore.isRateLimited(cl) {
                    self.claudeCooldownUntil = Date().addingTimeInterval(UsageStore.rateLimitCooldown)
                    NSLog("CodexIsland: Claude usage rate-limited; skipping Claude fetches for %.0fs", UsageStore.rateLimitCooldown)
                } else {
                    self.claudeCooldownUntil = nil
                }
                // A terminal auth failure (expired token / missing scope)
                // REPLACES the retained reading rather than carrying it: the
                // token can never refresh those numbers again, and
                // `ChartsBlock` keys the re-auth prompt off the error-only
                // shape. Transient errors (429/network) still carry forward.
                self.claude = ClaudeCredentials.isTerminalAuthFailure(cl)
                    ? cl
                    : AppUsage.merged(fetched: cl, retaining: self.claude, at: now)
            }
            if let codexResetCredits {
                self.codexResetCredits = codexResetCredits
            }

            // Record this poll's readings so the SparkChart can plot real
            // history. `record` keeps only non-errored windows, so a failed
            // or rate-limited fetch leaves a gap instead of a flat fake line.
            UsageHistoryStore.shared.record(provider: .codex, usage: c, at: now)
            if let cl { UsageHistoryStore.shared.record(provider: .claude, usage: cl, at: now) }
            self.lastUpdated = now
            self.loading = false
        }
    }

    /// Prime the panel from persisted history before the first fetch lands.
    ///
    /// `UsageHistoryStore` survives relaunch, so a cold start that hits a
    /// failing endpoint can still show the user's last real numbers. This is
    /// what makes the sticky `/api/oauth/usage` 429 survivable: that penalty
    /// outlives an app restart (anthropics/claude-code#30930), so without a
    /// seed the first failed fetch has nothing to carry and every tile falls
    /// to "—" for the whole cooldown.
    private func seedFromHistory() {
        claude = UsageStore.seeded(claude, provider: .claude)
        codex = UsageStore.seeded(codex, provider: .codex)
    }

    private static func seeded(_ current: AppUsage, provider: AlertEngine.Provider) -> AppUsage {
        func fill(_ kind: UsageWindow, _ existing: WindowUsage) -> WindowUsage {
            guard !existing.hasReading,
                  let sample = UsageHistoryStore.shared.latestReading(
                      provider: provider, window: kind)
            else { return existing }
            // No resetAt: the sample never carried one, and inventing a
            // countdown from a stored percentage would be a second fiction.
            return WindowUsage(usedPercent: sample.used, resetAt: nil, error: existing.error)
        }
        return AppUsage(
            fiveHour: fill(.fiveHour, current.fiveHour),
            weekly: fill(.weekly, current.weekly),
            plan: current.plan
        )
    }


    /// True when the fetch resolved to the rate-limited error (both windows
    /// carry the same message — see `UsageFetcher.errorPair`).
    private static func isRateLimited(_ u: AppUsage) -> Bool {
        u.fiveHour.error == ClaudeCredentials.rateLimitedMessage
            && u.weekly.error == ClaudeCredentials.rateLimitedMessage
    }

    /// Replace current usage values with hand-tuned percentages so the
    /// alert engine's pulse + tint behavior can be exercised without
    /// waiting for a real provider crossing. Auto-refresh continues — the
    /// next scheduled poll will overwrite these values with real data.
    /// Each call uses fresh `resetAt` timestamps so the alert engine
    /// treats it as a new reset window and re-evaluates crossings.
    func injectPreviewUsage(claudeFiveHour: Double, codexFiveHour: Double) {
        let now = Date()
        let fiveHourReset = now.addingTimeInterval(2 * 3600 + 14 * 60)
        let weeklyReset = now.addingTimeInterval(4 * 86400 + 6 * 3600)
        self.claude = AppUsage(
            fiveHour: WindowUsage(
                usedPercent: claudeFiveHour,
                resetAt: fiveHourReset,
                error: nil
            ),
            weekly: WindowUsage(
                usedPercent: 0.45,
                resetAt: weeklyReset,
                error: nil
            ),
            plan: claude.plan ?? "max"
        )
        self.codex = AppUsage(
            fiveHour: WindowUsage(
                usedPercent: codexFiveHour,
                resetAt: fiveHourReset,
                error: nil
            ),
            weekly: WindowUsage(
                usedPercent: 0.30,
                resetAt: weeklyReset,
                error: nil
            ),
            plan: codex.plan ?? "pro"
        )
        self.lastUpdated = now
    }

    /// Spawn `claude auth login` and poll for the keychain to update.
    ///
    /// We can't `await` the OAuth flow directly — it happens in a separate
    /// process that owns a browser tab and a localhost listener — so we kick
    /// off retries every few seconds and stop as soon as one returns success
    /// (or after a generous deadline so the button doesn't stay disabled
    /// forever if the user closes the browser without completing).
    func reauthenticateClaude() {
        guard !claudeReauthInProgress else { return }
        guard ClaudeCredentials.spawnReauth() else { return }
        claudeReauthInProgress = true
        reauthPollTask?.cancel()
        reauthPollTask = Task { [weak self] in
            // ~2 minutes total — generous enough that even a slow OAuth
            // round-trip (browser cold start, SSO redirect, 2FA prompt)
            // resolves in time, short enough to not strand the UI.
            var baseline = ClaudeCredentials.credentialStoreFingerprint()
            var sawStoreWrite = false
            for _ in 0..<24 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                // Wait for `claude auth login` to actually write the new
                // credentials before paying the secret read: the fingerprint
                // is metadata-only (never prompts), while clearing the cache
                // does a full keychain read on the next fetch — doing that
                // on every 5s tick was up to 24 ACL prompts per re-auth on
                // machines without a durable "Always Allow" grant. After the
                // first observed write, keep RETRYING from the cached
                // credential (zero extra secret reads) so one transient
                // network failure doesn't strand the button on "waiting for
                // browser…" until the deadline; the cache is cleared again
                // only when the store changes again.
                let current = ClaudeCredentials.credentialStoreFingerprint()
                if current != baseline {
                    baseline = current
                    sawStoreWrite = true
                    ClaudeCredentials.clearCache()
                }
                guard sawStoreWrite else { continue }
                let cl = await UsageFetcher.fetchClaude()
                if Task.isCancelled { return }
                // The usage limiter is sticky once tripped (see
                // rateLimitCooldown) — retrying every 5s only feeds it. Bail
                // and let the normal poll's cooldown machinery recover.
                if cl.fiveHour.error == ClaudeCredentials.rateLimitedMessage { break }
                if cl.fiveHour.error == nil || cl.weekly.error == nil {
                    await MainActor.run {
                        self?.claude = cl
                        self?.lastUpdated = Date()
                        self?.claudeReauthInProgress = false
                    }
                    return
                }
            }
            await MainActor.run { self?.claudeReauthInProgress = false }
        }
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        seedFromHistory()
        refresh()
        armTimer()
        // Re-arm whenever the user changes the refresh interval. We
        // dropFirst() the initial @Published replay so we don't re-fire
        // refresh() on subscription.
        intervalCancellable = RefreshIntervalStore.shared.$seconds
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.armTimer() }
            }
        startNetworkMonitor()
    }

    func stopAutoRefresh() {
        pollTimer?.invalidate()
        pollTimer = nil
        intervalCancellable?.cancel()
        intervalCancellable = nil
        netMonitor?.cancel()
        netMonitor = nil
        lastNetStatus = nil
    }

    private func armTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Trigger an immediate refresh whenever the network transitions from
    /// unsatisfied to satisfied — closes the launch-at-login race where
    /// Wi-Fi is still associating when our first refresh fires. Without
    /// this, the panel sits at the empty cold-start state until the next
    /// scheduled poll (5–30 minutes away). The initial path callback fires
    /// with the current state and is deliberately ignored (lastNetStatus
    /// starts nil) — startAutoRefresh's own refresh() already covers
    /// cold-start, and acting on the initial callback would double-fire.
    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let was = self.lastNetStatus
                self.lastNetStatus = path.status
                guard path.status == .satisfied,
                      let prior = was, prior != .satisfied else { return }
                // Cancel any in-flight refresh — its URLSession call was
                // started on the dead path and is going to return an
                // error. Wait for it to finalize so its loading=false
                // lands before we start the replacement, otherwise our
                // refresh() hits the `if loading { return }` guard.
                self.refreshTask?.cancel()
                await self.refreshTask?.value
                self.refresh()
            }
        }
        monitor.start(queue: netQueue)
        netMonitor = monitor
    }
}
