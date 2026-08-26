import SwiftUI
import AppKit

/// Usage data row. The chrome (provider titles, footer chip + page dots +
/// sync status) lives in `PanelHeader` / `PanelFooter` so it stays fixed
/// while this row swipes between usage and cost screens.
///
/// Branches on `(claudeOn, codexOn)` from `ProviderVisibilityStore`:
///   - both on:  two `ChartsBlock`s with a hairline divider (default).
///   - one on:   the live block on its native side, hairline, then a
///               per-model token breakdown filling the freed half.
///   - both off: a centered `BothHiddenPlaceholder`.
struct UsageView: View {
    @ObservedObject private var store = UsageStore.shared
    @ObservedObject private var pref = StylePref.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared

    private var style: ChartStyle { pref.style }

    var body: some View {
        let claudeOn = visibility.claudeVisible
        let codexOn = visibility.codexVisible && store.codexHasSubscriptionQuota

        HStack(spacing: 0) {
            switch (claudeOn, codexOn) {
            case (true, true):
                ChartsBlock(color: IslandColor.claude, usage: store.claude,
                            style: style, seed: 1, provider: .claude)
                hairline
                CodexUsageBlock(usage: store.codex, style: style)
            case (true, false):
                ChartsBlock(color: IslandColor.claude, usage: store.claude,
                            style: style, seed: 1, provider: .claude)
                hairline
                PerModelBreakdown(provider: .claude, metric: .tokens)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 12)
                    .transition(breakdownTransition)
            case (false, true):
                PerModelBreakdown(provider: .codex, metric: .tokens)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 12)
                    .transition(breakdownTransition)
                hairline
                CodexUsageBlock(usage: store.codex, style: style)
            case (false, false):
                BothHiddenPlaceholder()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// Slight scale + opacity gives the breakdown half a sense of "expanding
    /// into the freed space" rather than a hard crossfade. Same curve the
    /// chart-style swap uses; reads as a single morph paired with the
    /// `withAnimation(.openMorph)` on the Settings toggle.
    private var breakdownTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.97))
    }

    private var hairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear, .white.opacity(0.06), .clear],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(width: 1)
            .padding(.vertical, 8)
    }
}

/// API/custom Codex providers can legitimately expose no subscription quota.
/// Make that state explicit instead of rendering two empty black charts.
struct CodexUsageBlock: View {
    let usage: AppUsage
    let style: ChartStyle

    var body: some View {
        if usage.plan == "api" {
            VStack(alignment: .leading, spacing: 7) {
                Text("API/custom")
                    .font(Typography.rowTitle)
                    .foregroundStyle(.white.opacity(0.85))
                Text("No subscription quota")
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.52))
                Text("Local token and cost stats remain available")
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
        } else {
            ChartsBlock(color: IslandColor.codex, usage: usage,
                        style: style, seed: 3, provider: .codex)
        }
    }
}

struct ChartsBlock: View {
    let color: Color
    let usage: AppUsage
    let style: ChartStyle
    let seed: Int
    let provider: AlertEngine.Provider

    var body: some View {
        HStack(spacing: 18) {
            ChartTile(style: style, color: color, labelKey: "5h",
                      window: usage.fiveHour, seed: seed,
                      provider: provider, windowKind: .fiveHour)
            ChartTile(style: style, color: color, labelKey: "week",
                      window: usage.weekly, seed: seed + 1,
                      provider: provider, windowKind: .weekly)
        }
        .transition(.chartSwap.animation(.chartSwap))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 12)
    }
}

struct ChartTile: View {
    let style: ChartStyle
    let color: Color
    let labelKey: String
    let window: WindowUsage
    let seed: Int
    let provider: AlertEngine.Provider
    let windowKind: UsageWindow
    @ObservedObject private var usageDisplay = UsageDisplayModeStore.shared
    @ObservedObject private var historyStore = UsageHistoryStore.shared

    /// Locked tile height across all 5 styles so the panel size is
    /// identical regardless of what the user picks.
    private static let tileHeight: CGFloat = 96

    var body: some View {
        // A window with no reading carries `usedPercent: 0` as a struct
        // default, not a measurement. Feeding that to a chart draws a
        // confident "0% used" — or a full 100% ring under the `remaining`
        // toggle — for a window we know nothing about. Gate on `hasReading`
        // and hand the tile to NoReadingChart instead.
        let value: Double? = window.hasReading
            ? window.displayedFraction(mode: usageDisplay.mode) * 100   // 0-100
            : nil
        let sub = subCaption()
        let label = L10n.tr(labelKey)

        Group {
            if let value {
                switch style {
                case .ring:    RingChart(value: value, color: color, label: label, sub: sub)
                case .bar:     BarChart(value: value, color: color, label: label, sub: sub)
                case .stepped: SteppedChart(value: value, color: color, label: label, sub: sub)
                case .numeric: NumericChart(value: value, color: color, label: label, sub: compactSubCaption())
                case .spark:   SparkChart(value: value, color: color, label: label, sub: sub,
                                          seed: seed, history: historyPoints())
                }
            } else {
                NoReadingChart(label: label, sub: sub)
            }
        }
        .id(style)
        // Blur + scale + opacity, all on the same strong ease-out at 220ms.
        // The blur masks the geometric mismatch between Ring and Bar so the
        // crossfade reads as one morph instead of two stacked objects.
        .transition(.chartSwap.animation(.chartSwap))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: Self.tileHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            value.map { L10n.tr("%@, %d%%", label, Int($0)) }
                ?? L10n.tr("%@, no reading", label)
        )
        .accessibilityValue(subCaption())
    }

    /// Recorded readings for this window, mapped through the active
    /// used/remaining mode into display percent (0-100), oldest first — the
    /// same transform `value` uses, so the history and the live point agree.
    private func historyPoints() -> [Double] {
        let mode = usageDisplay.mode
        return historyStore.samples(provider: provider, window: windowKind).map { sample in
            WindowUsage(usedPercent: sample.used, resetAt: nil, error: nil)
                .displayedFraction(mode: mode) * 100
        }
    }

    private func subCaption() -> String {
        if let r = window.resetAt {
            let delta = max(0, r.timeIntervalSinceNow)
            return L10n.tr("resets in %@", Duration.compact(delta))
        }
        // "no data" is our internal sentinel for "CLI did not report this
        // window" — most commonly a plan that does not report that window.
        // Hide it so the tile reads as a passive
        // window-context cue (the "5h"/"week" header label communicates the
        // window type) instead of looking broken. Real errors still surface.
        // Any other CLI failure is a genuine per-window caption worth showing
        // verbatim.
        if let err = window.error, err != "no data" {
            return err
        }
        return ""
    }

    private func compactSubCaption() -> String {
        if let r = window.resetAt {
            let delta = max(0, r.timeIntervalSinceNow)
            return "↻ " + Duration.compact(delta)
        }
        if let err = window.error, err != "no data" {
            return err
        }
        return ""
    }
}
