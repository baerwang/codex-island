import Foundation

@main
struct CompactQuotaSelectionTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") }
        else { print("FAIL \(label)"); failures += 1 }
    }

    static func reading(_ percent: Double) -> WindowUsage {
        WindowUsage(usedPercent: percent, resetAt: nil, error: nil)
    }

    static func main() {
        let twoWindow = AppUsage(fiveHour: reading(0.12), weekly: reading(0.34))
        let weeklyDefault = CompactQuotaSelection.select(usage: twoWindow, preferred: .weekly)
        expect(weeklyDefault.kind == .weekly && weeklyDefault.window.percentInt == 34, "weekly is the default compact choice")
        let fiveHourChoice = CompactQuotaSelection.select(usage: twoWindow, preferred: .fiveHour)
        expect(fiveHourChoice.kind == .fiveHour && fiveHourChoice.window.percentInt == 12, "5h preference is honored")

        let weeklyOnly = AppUsage(fiveHour: .unknown, weekly: reading(0.34))
        let fallback = CompactQuotaSelection.select(usage: weeklyOnly, preferred: .fiveHour)
        expect(fallback.kind == .weekly && fallback.window.percentInt == 34, "missing preferred window falls back to reported window")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
