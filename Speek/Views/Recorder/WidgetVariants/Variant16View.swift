import SwiftUI

/// "Minimal Pill" — the most minimal recorder look.
///
/// A single-line capsule: a tiny live dot on the left whose glow tracks the audio
/// level, then the transcript flowing to the right on one line. Committed words are
/// solid white, the still-revising tail is dimmed. No waveform bars, no chrome, no
/// toggle. The capsule is a fixed width; once the text outgrows it the line scrolls
/// internally so the newest words stay visible.
struct Variant16View: View {
    let context: WidgetVariantContext

    private static let fontSize: CGFloat = 13
    private static let height: CGFloat = 30
    private static let maxTextWidth: CGFloat = 420
    private static let horizontalPadding: CGFloat = 12
    private static let dotSize: CGFloat = 7

    // Text still scrolls internally once it outgrows the capsule (see transcriptLine),
    // but the capsule itself no longer grows/shrinks with it — it's pinned at the
    // widest size it would otherwise expand to, so it never resizes mid-dictation.
    @State private var measuredTextWidth: CGFloat = 0
    @State private var visibleTextWidth: CGFloat = 0

    private var pillWidth: CGFloat { Self.maxTextWidth }

    var body: some View {
        capsule
            // Room below so the soft shadow isn't clipped by the panel edge.
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            // Second Escape: fade (and blur) the whole pill away so it melts off
            // instead of just flatly fading — same dismiss feel as Classic.
            .opacity(context.isCanceling ? 0 : 1)
            .blur(radius: context.isCanceling ? 12 : 0)
            .animation(.easeOut(duration: 0.3).delay(0.1), value: context.isCanceling)
    }

    private var capsule: some View {
        HStack(spacing: 8) {
            statusDot

            content
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(width: pillWidth, height: Self.height)
        .background(background)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 5)
    }

    private var background: some View {
        Color.black.overlay(
            LinearGradient(
                colors: [Color.white.opacity(0.04), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if context.isCancelConfirming || context.isCanceling {
            cancelLabel
        } else if context.hasText {
            transcriptLine
        } else {
            statusLabel
        }
    }

    // Single scrolling line. Committed white, partial dimmed. The text width is
    // measured so the capsule can hug it; once it overflows the cap the line scrolls
    // and pins to the trailing edge so the freshest words stay in view.
    private var transcriptLine: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                styledText
                    .font(.system(size: Self.fontSize, design: ThemeManager.shared.fontDesign))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: PillTextWidthKey.self, value: geo.size.width)
                        }
                    )
                    .padding(.trailing, 1)
                    .id("end")
            }
            .onPreferenceChange(PillTextWidthKey.self) { measuredTextWidth = $0 }
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear { visibleTextWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newValue in visibleTextWidth = newValue }
                }
            )
            // Soft fade on the leading edge so scrolled-off words dissolve cleanly —
            // only once the line actually overflows; short text stays fully visible.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: measuredTextWidth > visibleTextWidth ? .clear : .black, location: 0.0),
                        .init(color: .black, location: 0.06),
                        .init(color: .black, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: context.committed) { keepPinnedToEnd(proxy) }
            .onChange(of: context.partial) { keepPinnedToEnd(proxy) }
        }
    }

    private func keepPinnedToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo("end", anchor: .trailing)
        }
    }

    private var styledText: Text {
        let committed = Text(context.committed).foregroundColor(.white)
        guard !context.partial.isEmpty else { return committed }
        return committed + Text(context.partial).foregroundColor(.white.opacity(0.55))
    }

    // Idle / processing: one quiet word instead of bars.
    private var statusLabel: some View {
        Text(statusWord)
            .font(.system(size: Self.fontSize, design: ThemeManager.shared.fontDesign))
            .foregroundColor(.white.opacity(0.4))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusWord: String {
        switch context.recordingState {
        case .recording:    return "Listening"
        case .transcribing: return "Transcribing"
        case .enhancing:    return "Enhancing"
        case .starting:     return "Starting"
        case .busy:         return "Busy"
        case .idle:         return "Ready"
        }
    }

    // First Escape: keep the just-dictated text on one line, dimmed, with a hint.
    private var cancelLabel: some View {
        (Text("Esc").foregroundColor(.white).fontWeight(.semibold)
            + Text(" to cancel").foregroundColor(.white.opacity(0.45)))
            .font(.system(size: Self.fontSize, design: ThemeManager.shared.fontDesign))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Live dot

    // A single dot stands in for the whole waveform. While recording it gently
    // breathes and a soft glow ring scales with the live audio level; while
    // processing it spins a faint progress ring; idle it's a calm static dot.
    @ViewBuilder
    private var statusDot: some View {
        switch context.recordingState {
        case .recording:
            recordingDot
        case .transcribing, .enhancing, .starting, .busy:
            processingDot
        case .idle:
            staticDot(color: .white.opacity(0.35))
        }
    }

    private var recordingDot: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let level = max(context.audioMeter.averagePower, context.audioMeter.peakPower)
            let amplitude = max(0, min(1, pow(level, 0.7)))
            // A slow breathing baseline so the dot is alive even in silence, then the
            // glow ring opens up with the live level.
            let breathe = (sin(t * 2.4) * 0.5 + 0.5) * 0.12
            let glowScale = 1.0 + breathe + amplitude * 1.4

            ZStack {
                Circle()
                    .fill(AppTheme.Status.error.opacity(0.35))
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .scaleEffect(glowScale)
                    .blur(radius: 1.5)

                Circle()
                    .fill(AppTheme.Status.error)
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
            .frame(width: Self.dotSize * 2.6, height: Self.dotSize * 2.6)
        }
    }

    private var processingDot: some View {
        ProcessingIndicator(color: .white.opacity(0.7))
            .frame(width: Self.dotSize * 2.6, height: Self.dotSize * 2.6)
    }

    private func staticDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: Self.dotSize, height: Self.dotSize)
            .frame(width: Self.dotSize * 2.6, height: Self.dotSize * 2.6)
    }
}

private struct PillTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
