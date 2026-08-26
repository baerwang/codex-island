import Foundation

/// The two rate-limit windows every provider reports. Named here rather than
/// beside the history store because they name `AppUsage`'s own two fields —
/// and so the pure value layer stays free of store dependencies.
enum UsageWindow: String, Codable {
    case fiveHour
    case weekly

    /// How long the window runs before the provider resets it. Bounds how
    /// long a recorded reading stays meaningful once polling stops working.
    var span: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 3600
        case .weekly:   return 7 * 86400
        }
    }
}

/// One rate-limit window (e.g. Claude's 5h, Codex's 7d). usedPercent is
/// normalized to 0...1 regardless of what the upstream API returns.
struct WindowUsage {
    let usedPercent: Double
    let resetAt: Date?
    let error: String?

    static let unknown = WindowUsage(usedPercent: 0, resetAt: nil, error: "no data")

    /// True when `usedPercent` is a measurement rather than a struct default.
    ///
    /// A failed fetch produces `usedPercent: 0` alongside an error
    /// (`UsageFetcher.errorPair`), so a bare zero is ambiguous: it reads
    /// identically to a genuinely empty window. Rendering it anyway shows a
    /// confident `0%` — or, in `remaining` mode, a full `100%` ring — for a
    /// window we know nothing about. Every consumer that displays or alerts
    /// on a percentage must gate on this first.
    ///
    /// An error alongside a *non-zero* percentage is the carry-forward shape
    /// from `AppUsage.merged`: a real prior reading with a fresh failure
    /// attached. That still counts as a reading.
    var hasReading: Bool { !(error != nil && usedPercent == 0) }

    /// True for the passive sentinel a successfully parsed response leaves on
    /// a window it doesn't include (`WindowUsage.unknown`) — the provider
    /// affirmatively not offering the window, as opposed to a fetch failure,
    /// whose error carries the failure message. `merged` treats the two
    /// differently: a failure preserves the prior reading; an unreported
    /// window displaces it. A history seed also wears the "no data" caption
    /// but with a real percentage, so it stays a reading, not this.
    var isUnreported: Bool { !hasReading && error == WindowUsage.unknown.error }

    var percentInt: Int { Int((usedPercent * 100).rounded()) }

    func displayedFraction(mode: UsageDisplayMode) -> Double {
        switch mode {
        case .used:
            return usedPercent
        case .remaining:
            return max(0, 1 - usedPercent)
        }
    }

    func displayedPercentInt(mode: UsageDisplayMode) -> Int {
        Int((displayedFraction(mode: mode) * 100).rounded())
    }
}

/// A provider-reported quota window retained verbatim from the CLI status
/// screen. `AppUsage.fiveHour` / `.weekly` remain the compact island's two
/// headline slots, while this list preserves all plan/model-specific windows.
struct ProviderQuotaWindow: Identifiable, Equatable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetAt: Date?

    init(id: String, label: String, usedPercent: Double, resetAt: Date?) {
        self.id = id
        self.label = label
        self.usedPercent = min(1, max(0, usedPercent))
        self.resetAt = resetAt
    }
}

struct AppUsage {
    var fiveHour: WindowUsage
    var weekly: WindowUsage
    /// Provider-reported plan tier — Claude's `subscriptionType` (free/pro/max)
    /// or Codex's `plan_type` (free/plus/pro). nil when unknown.
    var plan: String?
    /// Every parsed CLI quota window, including model-specific windows that do
    /// not fit the island's compact two-tile layout.
    var windows: [ProviderQuotaWindow]

    init(fiveHour: WindowUsage, weekly: WindowUsage, plan: String? = nil,
         windows: [ProviderQuotaWindow] = []) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.plan = plan
        self.windows = windows
    }

    static let empty = AppUsage(fiveHour: .unknown, weekly: .unknown)

    var peekWindow: WindowUsage { fiveHour.hasReading ? fiveHour : weekly }

    /// Which window `peekWindow` selected — the peek chrome (VoiceOver label,
    /// window-length fallback glyph) must describe the same window it shows.
    var peekWindowIsWeekly: Bool { !fiveHour.hasReading }

    /// Fold a fetch result into the values currently on screen.
    ///
    /// Per window: a fresh reading wins outright. A failed window keeps the
    /// prior reading and takes the new error, so the panel shows the last
    /// true number captioned with what went wrong, instead of either blanking
    /// to a fabricated 0% or hiding the failure entirely. The carried reading
    /// is released once its own reset time has passed — past that boundary the
    /// percentage describes a window that no longer exists, and a confident
    /// stale number is worse than an honest "—".
    ///
    /// Callers that must NOT carry forward (a terminal auth failure, where the
    /// token can never refresh those numbers again) skip this and assign the
    /// fetched value directly — see `UsageStore.refresh`.
    static func merged(fetched: AppUsage, retaining prior: AppUsage, at now: Date) -> AppUsage {
        AppUsage(
            fiveHour: carryForward(fetched.fiveHour, prior: prior.fiveHour, at: now),
            weekly: carryForward(fetched.weekly, prior: prior.weekly, at: now),
            // Plan tier is read from the credential store, not the usage
            // response, so a failed fetch shouldn't blank the chip's badge.
            plan: fetched.plan ?? prior.plan,
            windows: fetched.windows.isEmpty ? prior.windows : fetched.windows
        )
    }

    private static func carryForward(
        _ fetched: WindowUsage, prior: WindowUsage, at now: Date
    ) -> WindowUsage {
        guard !fetched.hasReading, prior.hasReading else { return fetched }
        // A parsed response that omits the window is the provider saying the
        // plan doesn't have one (single-window Codex plans, mid-2026) —
        // displace the prior reading rather than papering over it. Carrying
        // here froze a mislabeled history seed forever: seeds have no
        // resetAt, so the release below could never fire.
        if fetched.isUnreported { return fetched }
        if let reset = prior.resetAt, reset <= now { return fetched }
        return WindowUsage(
            usedPercent: prior.usedPercent, resetAt: prior.resetAt, error: fetched.error
        )
    }

    /// Placeholder values shown when a provider is toggled off. Non-zero
    /// so the chart vocabulary stays visible (a 0% ring reads as broken,
    /// a 45% ring reads as "data we're choosing not to surface").
    static let dummy = AppUsage(
        fiveHour: WindowUsage(usedPercent: 0.45, resetAt: nil, error: nil),
        weekly: WindowUsage(usedPercent: 0.28, resetAt: nil, error: nil)
    )
}
