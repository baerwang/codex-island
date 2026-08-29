import Foundation

@main
struct ModelBarScaleTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") }
        else { print("FAIL \(label)"); failures += 1 }
    }

    static func main() {
        let maximum = 42_300_000.0
        let second = ModelBarScale.fraction(value: 29_800_000, maximum: maximum)
        let smallest = ModelBarScale.fraction(value: 923_000, maximum: maximum)

        expect(ModelBarScale.fraction(value: maximum, maximum: maximum) == 1,
               "largest weekly model fills the track")
        expect(second > 0.70 && second < 0.71,
               "second model uses the same cross-model scale")
        expect(smallest > 0.02 && smallest < 0.03,
               "small model stays proportionally short")
        expect(ModelBarScale.fraction(value: 5, maximum: 10) == 0.5,
               "recent overlay uses the shared denominator")
        expect(
            ModelBarScale.nestedFraction(value: 12, within: 6, maximum: 20) == 0.3,
            "recent overlay cannot exceed its weekly fill"
        )
        expect(ModelBarScale.fraction(value: 12, maximum: 10) == 1,
               "fraction clamps malformed values")
        expect(ModelBarScale.fraction(value: 5, maximum: 0) == 0,
               "zero maximum produces an empty bar")
        expect(ModelBarScale.fraction(value: .nan, maximum: 10) == 0,
               "NaN input produces an empty bar")
        expect(ModelBarScale.fraction(value: 5, maximum: .infinity) == 0,
               "infinite maximum produces an empty bar")

        if failures > 0 { exit(1) }
        print("ALL PASS")
    }
}
