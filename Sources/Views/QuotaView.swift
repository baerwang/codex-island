import SwiftUI

/// Every quota window parsed from the installed CLIs. The Usage page keeps a
/// compact two-window summary; this page prevents model-specific windows such
/// as Claude Fable or Codex Spark from disappearing behind that summary.
struct QuotaView: View {
    @ObservedObject private var usage = UsageStore.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var displayMode = UsageDisplayModeStore.shared

    var body: some View {
        HStack(spacing: 0) {
            providerColumn(
                title: "Claude", windows: usage.claude.windows,
                visible: visibility.claudeVisible, noData: "No Claude quota data"
            )
            hairline
            providerColumn(
                title: "Codex", windows: usage.codex.windows,
                visible: visibility.codexVisible && usage.codexHasSubscriptionQuota,
                noData: usage.codex.plan == "api" ? "API/custom provider has no subscription quota" : "No Codex quota data"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func providerColumn(
        title: String, windows: [ProviderQuotaWindow], visible: Bool, noData: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.tr(title))
                    .font(Typography.rowTitle)
                    .foregroundStyle(.white.opacity(visible ? 0.84 : 0.34))
                Spacer()
                Text(displayMode.mode == .used ? L10n.tr("Used") : L10n.tr("Remaining"))
                    .font(Typography.micro)
                    .foregroundStyle(.white.opacity(0.38))
            }

            if visible && !windows.isEmpty {
                ForEach(windows) { window in
                    HStack(spacing: 7) {
                        Text(window.label)
                            .font(Typography.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                        Spacer(minLength: 3)
                        let percent = displayMode.mode == .used
                            ? Int((window.usedPercent * 100).rounded())
                            : Int(((1 - window.usedPercent) * 100).rounded())
                        Text("\(percent)%")
                            .font(Typography.bodyNumber)
                            .foregroundStyle(.white.opacity(0.82))
                        if let reset = window.resetAt {
                            Text("↻ \(Duration.compact(max(0, reset.timeIntervalSinceNow)))")
                                .font(Typography.micro)
                                .foregroundStyle(.white.opacity(0.36))
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text(L10n.tr(noData))
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.40))
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
