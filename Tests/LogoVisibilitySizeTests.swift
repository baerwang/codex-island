import Foundation

@main
struct LogoVisibilitySizeTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") }
        else { print("FAIL \(label)"); failures += 1 }
    }

    @MainActor
    static func main() {
        let key = "MacIsland.sideLogosVisible"
        UserDefaults.standard.removeObject(forKey: key)

        let logos = LogoVisibilityStore.shared
        expect(logos.visible, "side logos default to visible")

        let model = IslandModel(
            notch: NotchInfo(width: 180, height: 32, hasNotch: true)
        )
        expect(model.size.width == 256, "visible logos reserve two 38pt tabs")

        logos.visible = false
        expect(model.size.width == 180, "hidden logos return compact island to notch width")

        model.setState(.peek)
        expect(model.size.width == 448, "percentage peek restores logo tabs beside its pills")

        logos.visible = true
        expect(model.size.width == 448, "peek width is stable when resting logos are enabled")

        logos.visible = false
        model.setState(.expanded)
        expect(model.size.width == 800, "expanded width is stable with compact logos hidden")

        logos.visible = true
        expect(model.size.width == 800, "expanded width is stable with compact logos shown")

        UserDefaults.standard.removeObject(forKey: key)
        if failures > 0 { exit(1) }
        print("ALL PASS")
    }
}
