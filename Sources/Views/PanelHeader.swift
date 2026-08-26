import SwiftUI

/// Provider titles row — Claude on the left, Codex on the right, with a
/// notch-width spacer in the middle that hides the title content behind
/// the physical notch. Lives outside `PagedContent` so it stays fixed
/// while the data area swipes between usage/cost/overview screens.
///
/// Plan tags ("MAX" / "PLUS") are sourced from `UsageStore` since the
/// subscription tier is a property of the account, not the current page.
struct PanelHeader: View {
    let notch: NotchInfo
    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var usageStore = UsageStore.shared
    @ObservedObject private var config = CLIProviderConfigStore.shared

    var body: some View {
        HStack(spacing: 0) {
            let claudeOn = visibility.claudeVisible
            let codexOn = visibility.codexVisible
            providerTitle(name: "Claude", tag: usageStore.claude.plan?.uppercased(),
                          color: IslandColor.claude, alignment: .leading) {
                EmptyView()
            }
                .opacity(claudeOn ? 1 : 0)
                .animation(.openMorph, value: claudeOn)
                .accessibilityHidden(!claudeOn)
            Color.clear.frame(width: notch.width)
            providerTitle(name: "Codex", tag: usageStore.codex.plan?.uppercased(),
                          color: IslandColor.codex, alignment: .trailing) {
                codexProfilePicker
            }
                .opacity(codexOn ? 1 : 0)
                .animation(.openMorph, value: codexOn)
                .accessibilityHidden(!codexOn)
        }
        .frame(height: 22)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, min(14, max(0, notch.height - 22 - 4)))
    }

    @ViewBuilder
    private var codexProfilePicker: some View {
        let profiles = config.activeCodexProfiles
        if profiles.count > 1 {
            Menu {
                ForEach(profiles) { profile in
                    Button {
                        usageStore.selectCodexProfile(id: profile.id)
                    } label: {
                        let selected = usageStore.codexHeadlineProfileID == profile.id
                        Text(selected ? "✓ \(profile.name)" : profile.name)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(selectedCodexProfileName(profiles) ?? "Codex")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(Typography.micro)
                .foregroundStyle(.white.opacity(0.52))
                .frame(maxWidth: 76, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Codex profile")
        }
    }

    private func selectedCodexProfileName(_ profiles: [CodexCLIProfile]) -> String? {
        guard let id = usageStore.codexHeadlineProfileID else { return nil }
        return profiles.first(where: { $0.id == id })?.name
    }

    @ViewBuilder
    private func providerTitle<Accessory: View>(
        name: String,
        tag: String?,
        color: Color,
        alignment: HorizontalAlignment,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        // Push past where the overlay logo lands: 9 leading + 20 logo + 8 gap.
        let logoOffset: CGFloat = 9 + 20 + 8

        let content = HStack(spacing: 8) {
            Text(name)
                .font(Typography.providerTitle)
                .foregroundStyle(.white)
            if let tag {
                Text(tag)
                    .font(Typography.chip)
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )
            }
        }

        if alignment == .leading {
            HStack {
                content.padding(.leading, logoOffset)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                accessory()
                content.padding(.trailing, logoOffset)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
