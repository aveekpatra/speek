import SwiftUI

/// A swappable recorder waveform for the V2 mini recorder. Each style is drawn inside
/// padded bounds so strokes never scrape the top or bottom of the pill.
struct WaveformStyleView: View {
    // Index stays fixed (it's a persisted @AppStorage raw value) — only the display
    // name changed. Reordering the array itself would silently flip every existing
    // user's saved 0/1 choice to the other style.
    static let styleNames = ["bars", "pulse"]
    static var styleCount: Int { styleNames.count }
    /// Visual order for pickers (Pulse shown first/default) — independent of the
    /// stored index above, so it doesn't touch existing users' saved preference.
    static let displayOrder = [1, 0]
    private static let claudeStyleIndex = 1
    /// Fixed intrinsic width used when no explicit `width` is supplied (Settings preview,
    /// snapshot tests) — the mini-panel passes its own measured width to fill edge to edge.
    private static let defaultWidth: CGFloat = 132
    private static let claudeBarWidth: CGFloat = 2
    private static let claudeGap: CGFloat = 2.5
    private static var claudePeriod: CGFloat { claudeBarWidth + claudeGap }

    let style: Int
    let audioMeter: AudioMeter
    let isActive: Bool
    var color: Color = .white.opacity(0.55)
    /// Explicit render width from the caller (e.g. the mini panel's measured available
    /// space). `nil` keeps the old fixed-width behavior for Settings preview / tests.
    var width: CGFloat? = nil

    /// Ring buffer of recent levels for the "claude" style — the view only receives an
    /// instantaneous level each tick, so history is accumulated here to scroll left over time.
    @State private var history: [Double] = []
    /// Wall-clock time of the last appended history sample, used to throttle the claude
    /// style's scroll rate independently of the 20fps redraw tick below (see
    /// `claudeSampleInterval`).
    @State private var lastAppendTime: TimeInterval = 0
    /// Minimum spacing between appended "claude" history samples (~18/sec). The redraw
    /// tick below runs faster than this so the gap between appends is filled with a
    /// continuous glide instead of a jump (see `drawClaude`'s `scrollOffset`).
    private static let claudeSampleInterval: TimeInterval = 0.055

    private var renderWidth: CGFloat { width ?? Self.defaultWidth }

    /// "claude" redraws at 60fps for a smooth continuous scroll; "bars" stays on its
    /// original 20fps clock — its sine-wave motion doesn't need the faster tick and
    /// this keeps that style's existing feel untouched.
    private var redrawInterval: TimeInterval {
        normalizedStyle == Self.claudeStyleIndex ? 1.0 / 60.0 : 1.0 / 20.0
    }

    var body: some View {
        Group {
            // Only the "isActive" path needs a per-frame clock; inactive previews (paused
            // or off-screen) render one static frame instead of ticking the TimelineView.
            if isActive {
                TimelineView(.animation(minimumInterval: redrawInterval)) { ctx in
                    Canvas { gc, size in
                        draw(&gc, size: size, t: ctx.date.timeIntervalSince1970)
                    }
                    .onChange(of: ctx.date) { _, newDate in
                        appendHistorySample(now: newDate.timeIntervalSince1970)
                    }
                }
            } else {
                Canvas { gc, size in
                    draw(&gc, size: size, t: 0)
                }
            }
        }
        .frame(width: renderWidth, height: 28)
    }

    private var normalizedStyle: Int {
        min(max(style, 0), Self.styleCount - 1)
    }

    private var level: Double {
        guard isActive else { return 0 }
        let raw = max(0, min(1, max(audioMeter.averagePower, audioMeter.peakPower)))
        let boosted = min(1, pow(raw, 0.45) * 1.35)
        return boosted < 0.035 ? 0 : boosted
    }

    /// Level used only by the "claude" style history. The mic's ambient noise floor sits
    /// well above 0 even in silence, so `level` above (which boosts low values with a <1
    /// power) reads noise as speech. Here we instead gate out a noise floor and apply a
    /// >1 power curve so quiet room noise collapses toward 0 (→ the dot) while speech
    /// still climbs to full height. Local to this style — `level`/`amp()` for "bars" is
    /// untouched.
    ///
    /// The exponent was softened from 2.0 to 1.6 and a 1.6x post-curve gain added so mid
    /// and loud speech spike more dramatically (raw 0.5 → ~0.39, raw 0.8 → clamped to max)
    /// while ambient noise (raw ≲ 0.25) still lands under the 0.06 dot threshold.
    private var claudeLevel: Double {
        guard isActive else { return 0 }
        let raw = max(0, min(1, max(audioMeter.averagePower, audioMeter.peakPower)))
        let noiseFloor = 0.15
        let gated = max(0, raw - noiseFloor) / (1 - noiseFloor)
        let shaped = pow(gated, 1.6) * 1.6
        return min(1, shaped)
    }

    private func amp(_ index: Int, count: Int, t: Double) -> Double {
        let phase = Double(index) * 0.45
        let wave = 0.45 + 0.55 * (sin(t * 7 + phase) * 0.5 + 0.5)
        let centerDist = abs(Double(index) - Double(count) / 2) / Double(count / 2)
        let centerBoost = 1.0 - centerDist * 0.35
        return level * wave * centerBoost
    }

    private func appendHistorySample(now: TimeInterval) {
        guard normalizedStyle == Self.claudeStyleIndex else { return }
        guard now - lastAppendTime >= Self.claudeSampleInterval else { return }
        lastAppendTime = now
        history.append(claudeLevel)
        // Keep just enough history to cover the current render width (plus a small
        // buffer) so a wider panel reveals more scrolled-in history instead of running
        // out of samples and leaving empty space on the left.
        let maxSamples = Int(ceil(renderWidth / Self.claudePeriod)) + 4
        if history.count > maxSamples {
            history.removeFirst(history.count - maxSamples)
        }
    }

    private func draw(_ gc: inout GraphicsContext, size: CGSize, t: Double) {
        let motionTime = level > 0 ? t : 0
        switch normalizedStyle {
        case Self.claudeStyleIndex: drawClaude(&gc, size: size, now: t)
        default: drawBars(&gc, size: size, t: motionTime)
        }
    }

    // MARK: - Styles

    private func safeRect(in size: CGSize, verticalInset: CGFloat = 4) -> CGRect {
        CGRect(
            x: 0,
            y: verticalInset,
            width: size.width,
            height: max(1, size.height - verticalInset * 2)
        )
    }

    private func bars(count: Int, width: CGFloat, spacing: CGFloat, size: CGSize) -> CGFloat {
        let total = CGFloat(count) * width + CGFloat(count - 1) * spacing
        return (size.width - total) / 2
    }

    private func drawBars(_ gc: inout GraphicsContext, size: CGSize, t: Double) {
        let rect = safeRect(in: size)
        let count = 15
        let w: CGFloat = 3
        let sp: CGFloat = 2
        let minH: CGFloat = 4
        let maxH = rect.height
        var x = bars(count: count, width: w, spacing: sp, size: size)
        for i in 0..<count {
            let h = minH + CGFloat(amp(i, count: count, t: t)) * (maxH - minH)
            let r = CGRect(x: x, y: rect.midY - h / 2, width: w, height: h)
            gc.fill(Path(roundedRect: r, cornerRadius: w / 2), with: .color(color.opacity(0.85)))
            x += w + sp
        }
    }

    /// Horizontally scrolling amplitude history, modeled on Claude's dictation waveform:
    /// each new sample appends at the right edge and older samples scroll left.
    private func drawClaude(_ gc: inout GraphicsContext, size: CGSize, now: TimeInterval) {
        let rect = safeRect(in: size)
        let barWidth = Self.claudeBarWidth
        let gap = Self.claudeGap
        let period = Self.claudePeriod
        let dotDiameter: CGFloat = 2.5
        let silenceThreshold = 0.06
        let minH: CGFloat = 4
        let maxH = rect.height

        // Glide continuously instead of jumping a whole `period` per append: shift
        // every bar left by the fraction of the sample interval elapsed since the
        // last append, resetting to 0 right as the next sample lands.
        let elapsed = max(0, now - lastAppendTime)
        let fraction = min(1, elapsed / Self.claudeSampleInterval)
        let scrollOffset = CGFloat(fraction) * period

        var x = size.width - barWidth - scrollOffset
        for amplitude in history.reversed() {
            if x < -barWidth { break }

            if amplitude < silenceThreshold {
                let d = dotDiameter
                let dot = CGRect(x: x + barWidth / 2 - d / 2, y: rect.midY - d / 2, width: d, height: d)
                gc.fill(Path(ellipseIn: dot), with: .color(color.opacity(0.85)))
            } else {
                let h = minH + CGFloat(amplitude) * (maxH - minH)
                let r = CGRect(x: x, y: rect.midY - h / 2, width: barWidth, height: h)
                gc.fill(Path(roundedRect: r, cornerRadius: barWidth / 2), with: .color(color.opacity(0.85)))
            }
            x -= period
        }
    }
}
