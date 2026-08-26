import SwiftUI

/// Dedicated model page. Usage remains about server quota and Cost remains
/// about today/month totals; this page makes local 5h/7d model activity from
/// Claude and Codex visible together, including API-only Codex homes.
struct ModelsView: View {
    @ObservedObject private var visibility = ProviderVisibilityStore.shared

    var body: some View {
        HStack(spacing: 0) {
            providerColumn(provider: .claude, title: "Claude", visible: visibility.claudeVisible)
            hairline
            providerColumn(provider: .codex, title: "Codex", visible: visibility.codexVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func providerColumn(
        provider: AlertEngine.Provider, title: String, visible: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.tr(title))
                .font(Typography.rowTitle)
                .foregroundStyle(.white.opacity(visible ? 0.82 : 0.34))
            if visible {
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
