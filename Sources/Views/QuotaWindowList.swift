import SwiftUI

/// Shows quota windows that do not fit the island's compact 5h/week pair,
/// including Claude Fable and model-specific Codex windows.
struct QuotaWindowList: View {
    @ObservedObject private var usage = UsageStore.shared
    @ObservedObject private var config = CLIProviderConfigStore.shared
    @ObservedObject private var usageDisplay = UsageDisplayModeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.tr("Quota windows"))
                .font(Typography.sectionLabel)
                .tracking(1.05)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.34))

            providerRows(title: "Claude", windows: usage.claude.windows)
            ForEach(config.activeCodexProfiles) { profile in
                providerRows(
                    title: "Codex · \(profile.name)",
                    windows: usage.codexByProfile[profile.id]?.windows ?? []
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func providerRows(title: String, windows: [ProviderQuotaWindow]) -> some View {
        if !windows.isEmpty {
            Text(L10n.tr(title))
                .font(Typography.rowTitle)
                .foregroundStyle(.white.opacity(0.84))
            ForEach(windows) { window in
                HStack(spacing: 8) {
                    Text(window.label)
                        .font(Typography.label)
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(quotaPercent(window.usedPercent))
                        .font(Typography.bodyNumber)
                        .foregroundStyle(.white.opacity(0.86))
                    if let reset = window.resetAt {
                        Text("↻ \(Duration.compact(max(0, reset.timeIntervalSinceNow)))")
                            .font(Typography.caption)
                            .foregroundStyle(.white.opacity(0.42))
                    }
                }
            }
        }
    }

    private func quotaPercent(_ used: Double) -> String {
        let fraction = usageDisplay.mode == .remaining ? 1 - used : used
        return "\(L10n.tr(usageDisplay.mode.label)) \(Int((fraction * 100).rounded()))%"
    }
}
