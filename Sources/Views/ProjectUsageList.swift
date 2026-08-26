import SwiftUI

/// Compact local-log project ledger. It intentionally says "estimated" in the
/// UI because subscription rate-limit percentages are account-wide while these
/// rows are reconstructed only from this machine's session logs.
struct ProjectUsageList: View {
    private enum ProviderChoice: String, CaseIterable { case claude, codex }

    @ObservedObject private var cost = CostStore.shared
    @ObservedObject private var config = CLIProviderConfigStore.shared
    @State private var choice: ProviderChoice = .claude
    /// nil deliberately means every configured Codex profile. Selecting a
    /// profile narrows rows by the source UUID attached during local-log scan.
    @State private var codexProfileID: UUID?

    private var activeCodexProfiles: [CodexCLIProfile] {
        config.activeCodexProfiles
    }

    private var rows: [ProjectUsageRow] {
        guard choice == .codex else { return cost.claude.projects }
        guard let codexProfileID else { return cost.codex.projects }
        return cost.codex.projects.filter { $0.sourceID == codexProfileID.uuidString }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("Projects"))
                    .font(Typography.sectionLabel)
                    .tracking(1.05)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.34))
                Spacer()
                Picker("", selection: $choice) {
                    Text("Claude").tag(ProviderChoice.claude)
                    Text("Codex").tag(ProviderChoice.codex)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 132)
            }

            if choice == .codex, !activeCodexProfiles.isEmpty {
                HStack(spacing: 8) {
                    Text(L10n.tr("Codex profile"))
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.45))
                    Picker("", selection: $codexProfileID) {
                        Text(L10n.tr("All")).tag(UUID?.none)
                        ForEach(activeCodexProfiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 190, alignment: .leading)
                    .accessibilityLabel(L10n.tr("Codex profile"))
                }
                .onChange(of: config.codexProfiles) { _ in
                    if let codexProfileID,
                       !activeCodexProfiles.contains(where: { $0.id == codexProfileID }) {
                        self.codexProfileID = nil
                    }
                }
            }

            Text(L10n.tr("Local log estimate · today / month to date"))
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.42))

            if rows.isEmpty {
                Text(L10n.tr("No project activity in local logs yet."))
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.vertical, 8)
            } else {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(row.name)
                                .font(Typography.rowTitle)
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(1)
                            if let source = row.sourceName {
                                Text(source)
                                    .font(Typography.micro)
                                    .foregroundStyle(.white.opacity(0.38))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Text(monthDollars(row.monthDollars))
                                .font(Typography.bodyNumber)
                                .foregroundStyle(.white.opacity(0.78))
                        }
                        HStack(spacing: 6) {
                            Text(L10n.tr("today %@ · %@", tokenText(row.todayTokens), monthDollars(row.todayDollars)))
                            Text(L10n.tr("month %@", tokenText(row.monthTokens)))
                        }
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(.vertical, 7)
                    Divider().overlay(.white.opacity(0.06))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private func monthDollars(_ amount: Double) -> String {
        amount < 10 ? String(format: "$%.2f", amount) : String(format: "$%.0f", amount)
    }

    private func tokenText(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return "\(tokens / 1_000)K" }
        return "\(tokens)"
    }
}
