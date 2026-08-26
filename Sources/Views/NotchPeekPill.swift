import SwiftUI

/// Glance-state percentage pill that lives outboard of each provider logo
/// while the island is in `.peek`. No background of its own — text painted
/// directly on the dark silhouette, like the logos.
///
/// Renders one of three states:
///   • value:    chosen 5h window → "2h" countdown; chosen weekly window →
///               "32%" percentage. The compact pill deliberately avoids
///               showing both so each provider side stays scannable.
///   • loading:  small pulsing dot (only when `loading && usedPercent == 0`)
///   • errored:  "—%"         (when error is set and we have no value)
///
/// Stateless — pure function of inputs. The parent owns visibility/animation.
struct NotchPeekPill: View {
    let usage: WindowUsage
    let loading: Bool
    let tint: Color
    let alignment: HorizontalAlignment
    var severity: AlertEngine.Severity = .none
    /// Window-length glyph shown when no active countdown is known — must
    /// match the window actually displayed ("5h", or "7d" for the Codex
    /// weekly fallback on weekly-only plans).
    var windowLengthFallback: String = "5h"
    var metric: CompactQuotaMetric = .percentage
    @ObservedObject private var usageDisplay = UsageDisplayModeStore.shared

    var body: some View {
        Group {
            if showSpinner {
                LoadingDot()
            } else if showDash {
                Text("—%")
                    .font(Typography.bodyNumber)
                    .foregroundStyle(.white.opacity(0.40))
            } else {
                HStack(spacing: 3) {
                    if alignment == .leading {
                        // Left pill: percent on the outside (left), hours
                        // remaining on the inside (toward the notch).
                        if severity != .none { warningGlyph }
                        compactValue
                    } else {
                        // Right pill: mirrored so percent stays on the
                        // outside (right) and hours remaining stays inside.
                        compactValue
                        if severity != .none { warningGlyph }
                    }
                }
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }

    private var warningGlyph: some View {
        Text("⚠")
            .font(Typography.bodyNumber)
            .foregroundStyle(effectiveTint)
    }

    private var percentLabel: some View {
        Text(percentText)
            .font(Typography.bodyNumber)
            .foregroundStyle(effectiveTint)
    }

    /// Lower opacity on the fallback differentiates a passive "5-hour
    /// window" label from an active "5h until reset" countdown — same
    /// glyph shape, weaker visual presence.
    private var resetLabel: some View {
        Text(resetText ?? windowLengthFallback)
            .font(Typography.bodyNumber)
            .foregroundStyle(.white.opacity(resetText == nil ? 0.45 : 0.70))
    }

    @ViewBuilder
    private var compactValue: some View {
        switch metric {
        case .percentage: percentLabel
        case .resetCountdown: resetLabel
        }
    }

    /// Brand tint by default; alert color when above threshold so the
    /// percent + warning glyph share a consistent severity color.
    private var effectiveTint: Color {
        switch severity {
        case .none:     return tint
        case .warning:  return IslandColor.alertAmber
        case .critical: return IslandColor.alertRed
        }
    }

    /// Spinner only fires for a true cold start. A real 0% window can still
    /// have a reset time (for example Codex's fresh 5h window) and must keep
    /// showing its useful remaining-time label while a refresh runs.
    private var showSpinner: Bool {
        loading && usage.usedPercent == 0 && usage.error == nil && usage.resetAt == nil
    }

    private var showDash: Bool {
        // No measurement to show — a failed fetch, or a window the parsed
        // response doesn't report at all (permanent on single-window Codex
        // plans since mid-2026). The old "no data" carve-out rendered the
        // sentinel as a value, which fabricated a steady "0% · 5h" — a full
        // budget under the `remaining` toggle — for a window the plan
        // doesn't have.
        !usage.hasReading
    }

    private var percentText: String {
        "\(usage.displayedPercentInt(mode: usageDisplay.mode))%"
    }

    /// Shared compact countdown (`Nm` / `Nh` / `Nd Nh`). Returns nil if
    /// there's no resetAt or the reset has already passed (happens
    /// transiently when a window rolls over before the next fetch lands).
    private var resetText: String? {
        guard let resetAt = usage.resetAt else { return nil }
        let remaining = resetAt.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        return Duration.compact(remaining)
    }
}

private struct LoadingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.white.opacity(0.55))
            .frame(width: 6, height: 6)
            .opacity(pulsing ? 0.30 : 0.85)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
