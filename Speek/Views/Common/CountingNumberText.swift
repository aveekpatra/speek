import SwiftUI

/// A number label that "counts up" to its target when it first appears or when the
/// value changes — the SwiftUI-native equivalent of the NumberFlow web effect.
///
/// Pass the already-formatted string the dashboard produces (e.g. "79 744"). If the
/// string is a whole number (digits + grouping spaces only) it animates by counting
/// through the intermediate values; any other string (e.g. "24 hours, 6 minutes" or
/// the "–" placeholder) is shown as-is without animation.
struct CountingNumberText: View {
    private let value: String
    private let animation: Animation
    private let tracking: CGFloat

    init(_ value: String,
         animation: Animation = .easeOut(duration: 0.9),
         tracking: CGFloat = 0) {
        self.value = value
        self.animation = animation
        self.tracking = tracking
    }

    @State private var displayed: Double = 0

    var body: some View {
        if let target = Self.wholeNumber(from: value) {
            CountingDigits(number: displayed, grouping: Self.groupingSeparator(in: value), tracking: tracking)
                .onAppear {
                    displayed = 0
                    withAnimation(animation) { displayed = target }
                }
                .onChange(of: target) { _, newTarget in
                    withAnimation(animation) { displayed = newTarget }
                }
        } else {
            Text(value)
                .tracking(tracking)
        }
    }

    /// Parses a whole number from an already-grouped string, or nil if it isn't one.
    private static func wholeNumber(from string: String) -> Double? {
        let stripped = string
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !stripped.isEmpty, stripped.allSatisfy(\.isNumber) else { return nil }
        return Double(stripped)
    }

    /// Mirrors the grouping separator already present in the source string so the
    /// counted-up value keeps the same look (e.g. "26,066" stays comma-grouped,
    /// "79 744" stays space-grouped). Defaults to a space when none is visible.
    private static func groupingSeparator(in string: String) -> String {
        if string.contains(",") { return "," }
        if string.contains("\u{00A0}") { return "\u{00A0}" }
        return " "
    }
}

/// Inner view whose `animatableData` drives the per-frame interpolation, so the
/// rendered text steps through every intermediate value during the animation.
private struct CountingDigits: View, Animatable {
    var number: Double
    let grouping: String
    let tracking: CGFloat

    var animatableData: Double {
        get { number }
        set { number = newValue }
    }

    var body: some View {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = grouping
        let rounded = Int(number.rounded())
        return Text(formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)")
            .monospacedDigit()
            .tracking(tracking)
    }
}
