import SwiftUI

/// Dedicated model page. Usage remains about server quota and Cost remains
/// about today/month totals; this page makes local 5h/7d model activity from
/// Claude and Codex visible together, including API-only Codex homes.
struct ModelsView: View {
    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var usage = UsageStore.shared

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
                PerModelBreakdown(provider: provider, metric: .tokens)
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
        let windows: [ProviderQuotaWindow] = {
            switch provider {
            case .claude: return usage.claude.windows
            case .codex: return usage.codexHeadlineUsage.windows
            }
        }()
        let weekly = windows.filter { $0.id.contains("week") }
        if !weekly.isEmpty {
            HStack(spacing: 7) {
                ForEach(weekly) { window in
                    Text("\(shortWeeklyLabel(window.label)) \(Int(((1 - window.usedPercent) * 100).rounded()))%")
                        .font(Typography.micro)
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(provider == .claude ? "Claude" : "Codex") weekly quota remaining")
        }
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
