import SwiftUI
import AppKit

@main
struct CodexIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // Placeholder scene — `App` requires at least one `Scene`. We never
        // trigger the system Settings menu (we're a `.accessory` app with
        // no menu bar), so this stays inert. Settings is shown via our own
        // SettingsWindowController.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var island: IslandWindowController?
    private var settingsShortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Direct migration: values persisted by the deleted HTTP/OAuth usage
        // implementation are intentionally discarded rather than displayed as
        // current CLI readings.
        UserDefaults.standard.removeObject(forKey: "CodexIsland.usageHistory.v1")
        UserDefaults.standard.removeObject(forKey: "CodexIsland.usageHistory.v2")
        UserDefaults.standard.removeObject(forKey: "MacIsland.costCache.v7")
        UserDefaults.standard.removeObject(forKey: "MacIsland.costCache.v8")
        // Status probes are permanently pinned to /private/tmp and plan tags
        // come only from CLI output. Drop transient preferences from the
        // earlier configurable-workdir/manual-plan experiments.
        UserDefaults.standard.removeObject(forKey: "CodexIsland.cli.claudeWorkdir")
        UserDefaults.standard.removeObject(forKey: "CodexIsland.cli.codexWorkdir")
        UserDefaults.standard.removeObject(forKey: "CodexIsland.cli.claudePlanPresentation")
        // Before any window or store exists: the first cost scan must price
        // against the cached catalog, not fall back to the seed and then
        // silently change its numbers a moment later.
        PricingCatalog.loadFromDisk()

        NSApp.setActivationPolicy(.accessory)
        island = IslandWindowController()
        island?.show()

        // Route Cmd+, to our hand-rolled Settings window. Without this, the
        // inert `Settings { EmptyView() }` scene below claims the shortcut and
        // opens a blank window. Consuming the event (returning nil) keeps that
        // empty scene from ever surfacing.
        settingsShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "," {
                SettingsWindowController.shared.show()
                return nil
            }
            return event
        }

        // Start fetching at app launch — NOT on view appear — so the panel
        // already has cached values the first time the user hovers, instead
        // of flashing "0%" while the first request lands.
        UsageStore.shared.startAutoRefresh()
        CostStore.shared.startAutoRefresh()
        PricingCatalog.startAutoRefresh()

        // Wire the alert engine after the usage store so its initial
        // recompute sees whatever values the first refresh has produced.
        AlertEngine.shared.start()

        // Runtime Sparkle checks are intentionally disabled. Release tooling
        // remains unchanged, but the shipped app never starts an updater.
    }

    /// Pin the app to the run loop until the user explicitly quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        UsageStore.shared.stopAutoRefresh()
        CostStore.shared.stopAutoRefresh()
    }
}
