import SwiftUI

/// Page indicator that mirrors the active screen. Sits in the
/// expanded panel footer between the style chip and the live-status group.
/// Each dot sits inside a 24pt button so regular-mouse users do not need
/// pixel-precise aim. The visible dots stay compact and quiet.
struct PageIndicator: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var screenPref = ScreenPref.shared

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ScreenPref.Screen.allCases, id: \.self) { screen in
                dot(for: screen)
            }
        }
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .animation(.strongEaseOut, value: screenPref.screen)
    }

    private func dot(for screen: ScreenPref.Screen) -> some View {
        let isActive = screenPref.screen == screen
        return Button {
            model.showScreen(screen)
        } label: {
            Circle()
                .fill(.white.opacity(isActive ? 0.82 : 0.25))
                .frame(width: isActive ? 8 : 7, height: isActive ? 8 : 7)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .help(L10n.tr("Switch to %@ (⌘%d)", screen.pageLabel, screen.pageIndex + 1))
            .accessibilityLabel(accessibilityLabel(for: screen))
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func accessibilityLabel(for screen: ScreenPref.Screen) -> String {
        L10n.tr("%@ page, %d of %d", screen.pageLabel, screen.pageIndex + 1, ScreenPref.Screen.allCases.count)
    }
}
