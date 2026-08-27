import SwiftUI

/// Count-up animated dollar number — the slot-machine reveal that gives
/// the cost screen its dopamine hit. Interpolates from `lastSeenTarget`
/// (or 0 on first appearance) to `target` over ~0.65s using a cubic
/// ease-out, driven by a 60Hz TimelineView.
///
/// Matches the static cost numeral: 38pt, brand-colored, monospaced digits
/// without a halo that would soften adjacent labels and charts.
struct CountUpDollar: View {
    let target: Double
    let color: Color

    private static let duration: TimeInterval = 0.65

    @State private var animationStart: Date = Date()
    @State private var startValue: Double = 0
    @State private var lastSeenTarget: Double = 0
    /// Gates the 60Hz TimelineView. Once the count settles we render a
    /// plain `Text` so SwiftUI stops re-evaluating this body 60 times per
    /// second. Four cost cells each running idle TimelineViews adds up.
    @State private var animating: Bool = false
    @State private var animationToken: UUID = UUID()

    var body: some View {
        Group {
            if animating {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                    let elapsed = context.date.timeIntervalSince(animationStart)
                    digits(formatted(interpolatedValue(elapsed: elapsed)))
                }
            } else {
                digits(formatted(lastSeenTarget))
            }
        }
        .onAppear {
            // Slot-machine reveal on first hover: rip from $0 up to current.
            startValue = 0
            animationStart = Date()
            lastSeenTarget = target
            startAnimation()
        }
        .onChange(of: target) { newTarget in
            // Smooth update during a refresh — count from where the eye
            // last saw the number, not from zero. If a prior count is
            // still in flight, resume from the interpolated on-screen
            // value so the retarget never visibly snaps.
            startValue = displayedValue()
            animationStart = Date()
            // Use the callback value rather than this View instance's
            // captured `target`. During rapid profile switches SwiftUI can
            // deliver the change to the previous view value, which made the
            // cost numeral trail the header selection by one click.
            lastSeenTarget = newTarget
            startAnimation()
        }
    }

    private func displayedValue() -> Double {
        guard animating else { return lastSeenTarget }
        let elapsed = Date().timeIntervalSince(animationStart)
        guard elapsed < Self.duration else { return lastSeenTarget }
        let t = max(0, min(1, elapsed / Self.duration))
        let eased = 1 - pow(1 - t, 3)
        return startValue + (lastSeenTarget - startValue) * eased
    }

    @ViewBuilder
    private func digits(_ text: String) -> some View {
        Text(text)
            .font(Typography.bigNumber)
            .foregroundStyle(color)
    }

    private func startAnimation() {
        animating = true
        let token = UUID()
        animationToken = token
        // Settle slightly past `duration` so the final frame definitely
        // renders the target value before the TimelineView is torn down.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration + 0.05) {
            guard animationToken == token else { return }
            animating = false
        }
    }

    private func interpolatedValue(elapsed: TimeInterval) -> Double {
        guard elapsed < Self.duration else { return target }
        let t = max(0, min(1, elapsed / Self.duration))
        let eased = 1 - pow(1 - t, 3)
        return startValue + (target - startValue) * eased
    }

    /// Cents under $100 (where they're meaningful); rounded above so a
    /// 7-digit month total fits the 38pt slot.
    private func formatted(_ v: Double) -> String {
        if v < 100 { return String(format: "%.2f", v) }
        return String(format: "%.0f", v)
    }
}
