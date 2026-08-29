import Foundation

/// Shared cross-model scale used by the model activity bars. Values are
/// clamped so malformed or racing inputs can never draw outside the track.
enum ModelBarScale {
    static func fraction(value: Double, maximum: Double) -> Double {
        guard value.isFinite, maximum.isFinite,
              value > 0, maximum > 0 else { return 0 }
        return min(1, value / maximum)
    }

    static func nestedFraction(
        value: Double, within upperBound: Double, maximum: Double
    ) -> Double {
        min(
            fraction(value: value, maximum: maximum),
            fraction(value: upperBound, maximum: maximum)
        )
    }
}
