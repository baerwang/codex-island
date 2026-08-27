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
    @ObservedObject private var screenPref = ScreenPref.shared
    @ObservedObject private var costProfile = CodexCostProfileStore.shared

    var body: some View {
        HStack(spacing: 0) {
            let claudeOn = visibility.claudeVisible
            let codexOn = visibility.codexVisible
                && (screenPref.screen != .usage || usageStore.codexQuotaSurfaceVisible)
            providerTitle(name: "Claude", tag: usageStore.claude.plan?.uppercased(),
                          color: IslandColor.claude, alignment: .leading) {
                EmptyView()
            }
                .opacity(claudeOn ? 1 : 0)
                .animation(.openMorph, value: claudeOn)
                .accessibilityHidden(!claudeOn)
            Color.clear.frame(width: notch.width)
            providerTitle(name: "Codex", tag: codexPlanTag,
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

    private var codexPlanTag: String? {
        if screenPref.screen == .usage {
            return usageStore.codexHeadlineUsage.plan?.uppercased()
        }
        guard let selectedID = costProfile.selectedProfileID else { return nil }
        return usageStore.codexByProfile[selectedID]?.plan?.uppercased()
    }

    @ViewBuilder
    private var codexProfilePicker: some View {
        if screenPref.screen == .usage {
            quotaProfilePicker
        } else {
            consumptionProfilePicker
        }
    }

    @ViewBuilder
    private var quotaProfilePicker: some View {
        let profiles = config.activeCodexProfiles.filter {
            guard let usage = usageStore.codexByProfile[$0.id] else { return false }
            return !usage.isNonSubscriptionMode
        }
        if profiles.count > 1 {
            let selectedIndex = profiles.firstIndex {
                $0.id == usageStore.codexHeadlineProfileID
            } ?? 0
            let selectedName = profiles[selectedIndex].name
            Menu {
                ForEach(profiles) { profile in
                    Button {
                        usageStore.selectCodexProfile(id: profile.id)
                    } label: {
                        HStack {
                            Text(profile.name)
                            if profile.id == usageStore.codexHeadlineProfileID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                profilePickerLabel(
                    position: "\(selectedIndex + 1)/\(profiles.count)",
                    name: selectedName
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Current: \(selectedName). Select Codex profile")
            .accessibilityLabel(
                "Codex profile \(selectedName), \(selectedIndex + 1) of \(profiles.count). Select profile"
            )
        }
    }

    @ViewBuilder
    private var consumptionProfilePicker: some View {
        let profiles = config.activeCodexProfiles
        if !profiles.isEmpty {
            let selectedIndex = costProfile.selectedProfileID.flatMap { id in
                profiles.firstIndex(where: { $0.id == id })
            }
            let selectedName = selectedIndex.map { profiles[$0].name }
                ?? L10n.tr("All")
            Menu {
                Button {
                    costProfile.select(nil, in: profiles)
                } label: {
                    HStack {
                        Text(L10n.tr("All"))
                        if costProfile.selectedProfileID == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Divider()
                ForEach(profiles) { profile in
                    Button {
                        costProfile.select(profile.id, in: profiles)
                    } label: {
                        HStack {
                            Text(profile.name)
                            if profile.id == costProfile.selectedProfileID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                profilePickerLabel(
                    position: selectedIndex.map { "\($0 + 1)/\(profiles.count)" },
                    name: selectedName
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Current local usage: \(selectedName). Select Codex profile")
            .accessibilityLabel("Codex local usage profile: \(selectedName)")
        }
    }

    private func profilePickerLabel(position: String?, name: String) -> some View {
        HStack(spacing: 4) {
            if let position {
                Text(position)
                Text("·")
                    .foregroundStyle(.white.opacity(0.28))
            }
            Text(name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 76, alignment: .leading)
        }
        .font(Typography.micro)
        .foregroundStyle(.white.opacity(0.52))
        .frame(width: 122, alignment: .trailing)
        .contentShape(Rectangle())
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
