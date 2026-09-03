import SwiftUI

/// Dedicated model page. Usage remains about server quota and Cost remains
/// about today/month totals; this page makes local 5h/7d model activity from
/// Claude and Codex visible together, including API-only Codex homes.
struct ModelsView: View {
    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var usage = UsageStore.shared
    @ObservedObject private var cost = CostStore.shared
    @ObservedObject private var codexProfile = CodexCostProfileStore.shared
    @ObservedObject private var usageDisplay = UsageDisplayModeStore.shared

    var body: some View {
        HStack(spacing: 0) {
            providerColumn(provider: .claude, visible: visibility.claudeVisible)
            hairline
            providerColumn(provider: .codex, visible: visibility.codexVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func providerColumn(
        provider: AlertEngine.Provider, visible: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if visible {
                weeklyQuotaStrip(provider: provider)
                switch provider {
                case .claude:
                    PerModelBreakdown(provider: provider, metric: .tokens)
                case .codex:
                    PerModelBreakdown(
                        provider: provider,
                        metric: .tokens,
                        cost: cost.codexCost(profileID: codexProfile.selectedProfileID)
                    )
                }
            } else {
                Spacer(minLength: 0)
                Text(L10n.tr("Provider hidden"))
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.36))
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func weeklyQuotaStrip(provider: AlertEngine.Provider) -> some View {
        if provider == .codex, codexProfile.selectedProfileID == nil {
            Text(L10n.tr("All accounts · quotas are not combined"))
                .font(Typography.micro)
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
        } else {
            let windows: [ProviderQuotaWindow] = {
                switch provider {
                case .claude: return usage.claude.windows
                case .codex:
                    guard let selectedID = codexProfile.selectedProfileID else { return [] }
                    return usage.codexByProfile[selectedID]?.windows ?? []
                }
            }()
            let weekly = windows.filter { $0.id.contains("week") }
            if !weekly.isEmpty {
                HStack(spacing: 7) {
                    ForEach(weekly) { window in
                        quotaLabel(window)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(provider == .claude ? "Claude" : "Codex") weekly quota \(usageDisplay.mode.label.lowercased())"
                )
            }
        }
    }

    private func quotaLabel(_ window: ProviderQuotaWindow) -> some View {
        Text(
            "\(shortWeeklyLabel(window.label)) · "
                + "\(L10n.tr(usageDisplay.mode.label)) \(quotaPercent(window))%"
        )
        .font(Typography.micro)
        .foregroundStyle(.white.opacity(0.48))
        .lineLimit(1)
    }

    private func quotaPercent(_ window: ProviderQuotaWindow) -> Int {
        let fraction: Double
        switch usageDisplay.mode {
        case .used:      fraction = window.usedPercent
        case .remaining: fraction = 1 - window.usedPercent
        }
        return Int((max(0, min(1, fraction)) * 100).rounded())
    }

    private func shortWeeklyLabel(_ label: String) -> String {
        let lower = label.lowercased()
        if lower.contains("fable") { return "Fable" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("opus") { return "Opus" }
        if lower.contains("all models") { return L10n.tr("All") }
        if lower.hasPrefix("weekly") { return L10n.tr("Account") }
        if lower.contains("model") { return L10n.tr("Model") }
        return label
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
