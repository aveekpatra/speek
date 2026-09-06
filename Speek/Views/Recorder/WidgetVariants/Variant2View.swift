import SwiftUI
import AppKit

struct Variant2View: View {
    let context: WidgetVariantContext

    // Click the bottom waveform to cycle through the prototype designs.
    @AppStorage("WaveformStyle") private var waveformStyle: Int = 1
    // Escape/cancel dismiss look — picked in Settings → Interface.
    @AppStorage(DismissEffectStyle.storageKey) private var dismissEffectRaw: Int = DismissEffectStyle.contentScatter.rawValue
    private var dismissEffect: DismissEffectStyle {
        DismissEffectStyle.resolved(rawValue: dismissEffectRaw)
    }

    private static let widthKey = "MiniWidgetVariant2Width"
    private static let minWidth: CGFloat = 240
    private static let maxWidth: CGFloat = 520
    private static let defaultWidth: CGFloat = 384
    private static let collapsedWidth: CGFloat = 138
    private static let collapsedHeight: CGFloat = 46

    // Transcript grows with the text from a 2-row floor up to a 2-row cap, then scrolls
    // (one row shorter than before, so the panel takes up less vertical space).
    private static let fontSize: CGFloat = 13
    private static let lineSpacing: CGFloat = 3
    private static let lineHeight: CGFloat = fontSize + lineSpacing + 4
    private static let defaultLines: CGFloat = 2
    private static let maxLines: CGFloat = 2
    private static let textTopPadding: CGFloat = 16
    private static let textBottomPadding: CGFloat = 6

    private static var minTextHeight: CGFloat {
        lineHeight * defaultLines + textTopPadding + textBottomPadding
    }
    private static var maxTextHeight: CGFloat {
        lineHeight * maxLines + textTopPadding + textBottomPadding
    }

    @State private var widthOverride: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: widthKey)
        guard saved >= minWidth && saved <= maxWidth else { return defaultWidth }
        return saved
    }()

    // Persisted so a manual collapse sticks across recordings/reopens until the user
    // expands it again — this was previously session-only and reset on every spawn.
    @AppStorage("MiniWidgetVariant2Collapsed") private var isCollapsed = false
    @State private var isHoveringPanel = false
    @State private var isHoveringToggle = false
    @State private var measuredTextHeight: CGFloat = Variant2View.minTextHeight
    // Once the transcript has grown past the 3-line cap, hold the box at maxTextHeight
    // for the rest of the dictation instead of re-deriving it from the live measured
    // height every frame. Streaming STT briefly re-wraps the tail (a word gets
    // replaced by a shorter/longer one), which can transiently shrink the measured
    // line count — without this latch the box would spring-shrink then grow back and
    // the scroll fade would flicker off/on, reading as already-written lines jumping.
    @State private var hasReachedTranscriptCap = false
    // V4 "sequential dissolve" phase 2 (shell dissolve) — flips true only once phase 1
    // (text dissolve) has finished. See the onChange(of: context.isCanceling) below.
    @State private var isShellDissolving = false
    // V5 "content scatter" phase 2 (shell exit) — flips true shortly before phase 1
    // (text + waveform scatter) fully finishes. See the onChange below.
    @State private var isContentShellExiting = false

    private var cornerRadius: CGFloat { (isCollapsed || isPasteHint) ? 22 : 18 }

    /// True while showing "⌘V to paste" — the pill morphs to the same narrow, pill-corner
    /// shape as collapsed instead of a separate view being swapped in.
    private var isPasteHint: Bool { context.pasteHintText != nil }

    // Single morphing pill: width, height, corner radius and content all animate on
    // the same view identity, so collapse/expand is one smooth shape change instead of
    // two separate views swapping in and out.
    var body: some View {
        cancelExitEffect(pill)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.18)) { isHoveringPanel = hovering }
            }
            // Room below the pill so the drop shadow isn't clipped by the panel edge.
            .padding(.bottom, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isCollapsed)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isPasteHint)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: measuredTextHeight)
            .onChange(of: context.isCanceling) { _, canceling in
                isShellDissolving = false
                isContentShellExiting = false
                guard canceling else { return }
                switch dismissEffect {
                case .sequentialDissolve:
                    // Phase 2 (shell dissolve) only starts once phase 1 (text dissolve,
                    // driven by cancelTextLayer's InvisibleInkText) has fully
                    // finished — strictly sequential, never overlapping.
                    DispatchQueue.main.asyncAfter(deadline: .now() + DismissEffectStyle.textDissolveDuration) {
                        isShellDissolving = true
                    }
                case .contentScatter:
                    // Phase 2 (shell exit) starts strictly once phase 1 (text +
                    // waveform scatter) has fully finished — no overlap.
                    DispatchQueue.main.asyncAfter(deadline: .now() + DismissEffectStyle.contentScatterDuration) {
                        isContentShellExiting = true
                    }
                case .sparkle, .vanish, .textScatterOnly:
                    // No shell phase to schedule — .textScatterOnly never touches the
                    // shell at all (see cancelExitEffect), it just lets the window's
                    // own hide fade take the panel away once the text finishes.
                    break
                }
            }
            .onAppear {
                // V2 "poof" was removed; migrate a previously-persisted pick to V4
                // instead of it silently landing on the new default.
                DismissEffectStyle.migrateLegacyPoofSelectionIfNeeded()
            }
    }

    // MARK: - Escape/cancel dismiss effect (whole-panel exit — see DismissEffectStyle)

    /// Second Escape ("isCanceling"): the whole pill plays the chosen dismiss effect
    /// instead of just fading. `cancelContent`'s own text (and, for .contentScatter,
    /// waveform) dissolve runs alongside this. Normal (non-cancel) dismissal is
    /// untouched — that's handled by MiniWindowManager's plain show/hide fade.
    @ViewBuilder
    private func cancelExitEffect(_ content: some View) -> some View {
        switch dismissEffect {
        case .sparkle:
            // Phase 1 (0–480ms): text dissolves into dust — driven directly by
            // cancelTextLayer's InvisibleInkText via context.isCanceling. Phase 2
            // (starts only once phase 1 finishes): the panel fades away underneath —
            // a plainer, non-particle sibling of .sequentialDissolve.
            content
                .opacity(context.isCanceling ? 0 : 1)
                .blur(radius: context.isCanceling ? 12 : 0)
                .animation(
                    .easeOut(duration: DismissEffectStyle.sparkleShellFadeDuration)
                        .delay(DismissEffectStyle.textDissolveDuration),
                    value: context.isCanceling
                )
        case .vanish:
            // Pure scale + blur + fade of the whole panel as one snapshot. Content
            // (text) is already sharp by the time this starts — see
            // showsStagedTextReveal — so nothing animates separately from the shell.
            content
                .scaleEffect(context.isCanceling ? 0.82 : 1, anchor: .bottom)
                .blur(radius: context.isCanceling ? 12 : 0)
                .opacity(context.isCanceling ? 0 : 1)
                .animation(.easeOut(duration: 0.4), value: context.isCanceling)
        case .sequentialDissolve:
            // Phase 1 (0–480ms): text dissolves into dust (cancelTextLayer). Phase 2
            // (480–960ms), triggered by the onChange(of: context.isCanceling) handler
            // in `body` flipping isShellDissolving: the panel shell dissolves with the
            // same dust language — ShapeDissolveView bursts particles masked to the
            // rounded-rect while the shell's own background/border fade underneath.
            content
                .opacity(isShellDissolving ? 0 : 1)
                .blur(radius: isShellDissolving ? 12 : 0)
                .animation(.easeOut(duration: DismissEffectStyle.shellDissolveDuration), value: isShellDissolving)
                .overlay(
                    ShapeDissolveView(cornerRadius: cornerRadius, isDissolving: isShellDissolving)
                        .allowsHitTesting(false)
                )
        case .contentScatter:
            // Phase 1 (0–550ms): text (cancelTextLayer) AND the waveform echo row
            // (cancelWaveformRow) scatter into the same dust language together,
            // driven directly by context.isCanceling — no staggering between the two
            // content shapes, and the panel fill itself never gets a particle
            // treatment. Phase 2 (starts strictly once phase 1 has fully finished, via
            // isContentShellExiting — no overlap): the shell exits quietly — a
            // smoother, more fluid easeInOut blur+fade+scale (softer than .vanish's
            // snappier easeOut), no particles on the shell.
            content
                .scaleEffect(isContentShellExiting ? 0.92 : 1, anchor: .bottom)
                .blur(radius: isContentShellExiting ? 10 : 0)
                .opacity(isContentShellExiting ? 0 : 1)
                .animation(.easeInOut(duration: DismissEffectStyle.contentScatterShellExitDuration), value: isContentShellExiting)
        case .textScatterOnly:
            // The ONLY effect: the text scattering, handled entirely by cancelTextLayer
            // (InvisibleInkText, with extra burstIntensity — see cancelTextLayer). The
            // shell gets no treatment of its own here at all — no fade, no blur, no
            // scale, no particles — so `content` passes through untouched. Once the
            // text finishes, RecorderUIManager's cancelRecordingAfterEffect leaves
            // MiniWindowManager's normal animated hide fade ON (see
            // DismissEffectStyle.skipsWindowFadeOnCancel) instead of skipping it, since
            // that's what makes the still-fully-opaque shell disappear.
            content
        }
    }

    private var isCanceling: Bool { context.isCancelConfirming || context.isCanceling }

    // Root cause of the Settings-preview text duplication bug (and the same bug class
    // as the ⌘V morph fix in MiniRecorderView): this used to be `if isCanceling {
    // cancelContent } else { normalContent }`, each with `.transition(.opacity)`, with
    // the crossfade gated by `.animation(value: context.isCancelConfirming)`. That gate
    // only tracks ONE of the two fields `isCanceling` is derived from — it's correct
    // for the real two-Escape flow (isCancelConfirming flips true on the first Escape,
    // which is what actually swaps the branch; the second Escape only changes
    // context.isCanceling, and the branch was already showing cancelContent so nothing
    // re-swaps). But the Settings preview drives `isCanceling` straight from idle
    // (isCancelConfirming never changes, only isCanceling does), so the branch swap
    // happened for the first time with NO animation tracking it — an untracked
    // if/else branch swap, i.e. exactly the same "conditional content has no stable
    // identity across the swap" bug as the ⌘V morph. Fix: normalContent and
    // cancelContent are now BOTH permanently mounted (never inserted/removed) and only
    // their own opacity crossfades, gated on the actual boolean that decides which one
    // reads as "current" — so there is no branch swap left to mis-animate, in the
    // preview or live.
    private var pill: some View {
        ZStack {
            normalContent
                .opacity(isCanceling ? 0 : 1)
                .allowsHitTesting(!isCanceling)
            cancelContent
                .opacity(isCanceling ? 1 : 0)
                .allowsHitTesting(isCanceling)
        }
        .animation(.easeInOut(duration: 0.28), value: isCanceling)
        .frame(
            width: (isCollapsed || isPasteHint) && !isCanceling ? Variant2View.collapsedWidth : widthOverride,
            // cancelContent stays mounted (see the comment above `pill`) and reports its
            // own full expanded height even while invisible, so the ZStack's natural
            // height stays tall unless pinned here. Only pin it while collapsed/paste-hint
            // AND not canceling — the moment isCanceling flips true, drop the pin and let
            // the ZStack's natural (cancelContent-driven) height take over, so a
            // Escape-while-collapsed cancel simply grows the pill to fit the cancel UI
            // instead of needing a second, cancel-shaped collapsed layout.
            height: (isCollapsed || isPasteHint) && !isCanceling ? Variant2View.collapsedHeight : nil
        )
        .background(pillBackground(cornerRadius: cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(pillBorder(cornerRadius: cornerRadius))
        .overlay(alignment: isCollapsed ? .trailing : .bottomTrailing) {
            if !isCanceling && !isPasteHint { toggleIcon }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: context.isCancelConfirming)
        .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 6)
    }

    private var normalContent: some View {
        VStack(spacing: 0) {
            if !isCollapsed && !isPasteHint {
                transcriptArea
            }

            HStack(spacing: 0) {
                // Same row the status/waveform normally lives in — swapping its content
                // to the hint label (instead of a separate overlay view) is what makes
                // the pill morph read as one shrinking container rather than a toast.
                if isPasteHint, let hint = context.pasteHintText {
                    Spacer(minLength: 8)
                    Text(hint)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                    Spacer(minLength: 8)
                }
                // After the mic stops (finalizing), drop the "transcribing…" label and
                // processing dots and keep a calm static waveform — progress is conveyed
                // by the shimmer over the text block instead. While still live (mic on,
                // even in the .transcribing streaming state) keep the reactive waveform.
                else if !context.isRecording
                    && (context.recordingState == .enhancing || context.recordingState == .transcribing) {
                    // Symmetric margins so the fixed-width visualizer sits centered,
                    // mirroring the right-side space the hover icon lives in onto the left.
                    Spacer(minLength: isCollapsed ? 8 : 16)
                    StaticVisualizer(color: .white.opacity(0.55))
                        .frame(height: 40)
                    Spacer(minLength: isCollapsed ? 8 : 16)
                } else if context.isRecording && !isCollapsed {
                    // The waveform (esp. the "claude" style) spans the panel's full
                    // width instead of sitting in a fixed-width centered strip — only
                    // the side padding is fixed, the waveform fills the rest. This
                    // branch only runs expanded, so the padding is always 16.
                    waveformCycler
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                } else {
                    Spacer(minLength: isCollapsed ? 8 : 16)
                    RecorderStatusDisplay(
                        currentState: context.recordingState,
                        audioMeter: context.audioMeter
                    )
                    .frame(height: 40)
                    Spacer(minLength: isCollapsed ? 8 : 16)
                }
            }
        }
    }

    private var normalizedWaveformStyle: Int {
        min(max(waveformStyle, 0), WaveformStyleView.styleCount - 1)
    }

    // Clickable live waveform: each click advances to the next approved design; the
    // cursor becomes a pointing hand on hover. Measures its own available width (after
    // the row's horizontal padding) so the waveform fills the panel edge to edge instead
    // of rendering at a fixed intrinsic width.
    private var waveformCycler: some View {
        GeometryReader { geo in
            Button(action: { waveformStyle = (normalizedWaveformStyle + 1) % WaveformStyleView.styleCount }) {
                WaveformStyleView(
                    style: normalizedWaveformStyle,
                    audioMeter: context.audioMeter,
                    isActive: true,
                    width: geo.size.width
                )
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .frame(height: 40)
    }

    // MARK: - Escape-to-cancel confirm + dissolve

    // First Escape: the just-dictated text shown centered with a "Esc again to cancel"
    // prompt. Second Escape: the text dissolves into Invisible Ink, then the pill closes.
    private var cancelText: String {
        [context.committed, context.partial].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// True for the effects where the text dissolves into dust and so needs its own
    /// un-blur/sharpen beat first. `vanish` treats text + shell as one snapshot, so the
    /// text snaps sharp instantly instead of animating separately and fighting the
    /// shell's own exit.
    private var showsStagedTextReveal: Bool {
        dismissEffect == .sparkle || dismissEffect == .sequentialDissolve
            || dismissEffect == .contentScatter || dismissEffect == .textScatterOnly
    }

    private var cancelContent: some View {
        ZStack {
            // The just-dictated text stays in its normal place (top, left-aligned, padded).
            // While confirming it's lightly blurred + dimmed to 40%. On the second Escape,
            // every effect except "vanish" turns it into Invisible Ink that scatters into
            // dust; "vanish" snaps it sharp instantly and lets the whole panel
            // (cancelExitEffect) handle the exit as one snapshot instead.
            cancelTextLayer
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.top, Variant2View.textTopPadding)
                .blur(radius: context.isCanceling ? 0 : 9)
                .opacity(context.isCanceling ? 1 : 0.4)
                .animation(showsStagedTextReveal ? .easeOut(duration: 0.5) : nil, value: context.isCanceling)

            if context.isCancelConfirming {
                (Text("Esc").foregroundColor(.white).fontWeight(.semibold)
                    + Text(" again to cancel").foregroundColor(.white.opacity(0.45)))
                    .font(.system(size: 13))
                    .frame(maxWidth: 800)
                    .shadow(color: .black, radius: 16, x: 0, y: 0)
                    .transition(.opacity)
            }
        }
        // Keep the panel exactly the height it had before Escape (default or expanded);
        // Escape never resizes it. Every staged-text-dissolve effect (sparkle,
        // sequentialDissolve, contentScatter) also adds a waveform echo row (see
        // cancelWaveformRow) so the bars scatter the same way the text does instead of
        // just vanishing with the crossfade. `vanish` treats the whole panel as one
        // snapshot (no separate content dust) and `textScatterOnly` is deliberately
        // text-only by design — both leave this bottom strip empty.
        .overlay(alignment: .bottom) {
            if showsWaveformDust {
                cancelWaveformRow
            }
        }
        .frame(width: widthOverride, height: transcriptDisplayHeight + 40)
    }

    /// True for the effects where the waveform bars should scatter into dust alongside
    /// the text (see `cancelWaveformRow`) — every staged-dissolve effect except
    /// `textScatterOnly`, which is deliberately text-only by design (see its case
    /// comment in DismissEffectStyle).
    private var showsWaveformDust: Bool {
        dismissEffect == .sparkle || dismissEffect == .sequentialDissolve || dismissEffect == .contentScatter
    }

    /// A quiet echo of the waveform row so there is something for the same particle
    /// language as the text to scatter — otherwise the waveform would simply vanish
    /// with no exit of its own the moment Escape swaps normalContent for cancelContent,
    /// which is exactly the kind of "pops instead of exits" the craft rules forbid.
    /// `StaticVisualizer` is reused as-is (no live audio dependency, safe during cancel)
    /// but hidden INSTANTLY like the text (no fade — see InvisibleInkText's
    /// setDissolving) so the dust is the only visible motion; `BarDustView` samples
    /// particle seed points directly from the bars' own geometry (same mechanism as the
    /// text's glyph sampling — see InvisibleInkText.swift) so the dust visibly
    /// originates from the actual bar shapes, not a generic rect.
    private var cancelWaveformRow: some View {
        HStack {
            Spacer(minLength: 16)
            StaticVisualizer(color: .white.opacity(0.55))
                .frame(height: 40)
                .opacity(context.isCanceling ? 0 : 1)
            Spacer(minLength: 16)
        }
        .frame(height: 40)
        .overlay(
            BarDustView(isDissolving: context.isCanceling)
                .allowsHitTesting(false)
        )
    }

    /// V6 is the text scatter on its own — nothing else is happening on screen to sell
    /// the effect, so it gets more visible outward motion than the other three staged
    /// effects (which keep the original, subtler tuning since the text dissolve there
    /// is only one phase among several). See `InvisibleInkText.burstIntensity`.
    private var textBurstIntensity: CGFloat {
        dismissEffect == .textScatterOnly ? 1.7 : 1.0
    }

    @ViewBuilder
    private var cancelTextLayer: some View {
        if showsStagedTextReveal {
            InvisibleInkText(
                text: cancelText,
                fontSize: Variant2View.fontSize,
                isDissolving: context.isCanceling,
                burstIntensity: textBurstIntensity
            )
        } else {
            Text(cancelText)
                .font(.system(size: Variant2View.fontSize))
                .foregroundColor(.white)
        }
    }

    private var transcriptDisplayHeight: CGFloat {
        if hasReachedTranscriptCap { return Variant2View.maxTextHeight }
        return min(Variant2View.maxTextHeight, max(Variant2View.minTextHeight, measuredTextHeight))
    }

    private func pillBackground(cornerRadius: CGFloat) -> some View {
        Color.black
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.04), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private func pillBorder(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
    }

    // MARK: - Transcript

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                styledText
                    .font(.system(size: Variant2View.fontSize))
                    .lineSpacing(Variant2View.lineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, Variant2View.textTopPadding)
                    .padding(.bottom, Variant2View.textBottomPadding)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: TranscriptHeightKey.self, value: geo.size.height)
                        }
                    )
                    .id("bottom")
            }
            .frame(height: transcriptDisplayHeight)
            .onPreferenceChange(TranscriptHeightKey.self) { newHeight in
                measuredTextHeight = newHeight
                if newHeight > Variant2View.maxTextHeight + 1 { hasReachedTranscriptCap = true }
            }
            .onChange(of: context.committed) { keepPinnedToBottom(proxy) }
            .onChange(of: context.partial) { keepPinnedToBottom(proxy) }
            .onChange(of: context.hasText) { _, hasText in
                if !hasText { hasReachedTranscriptCap = false }
            }
        }
    }

    // Always follow the newest text. No-op (native ScrollView already rests at top)
    // while the transcript still fits inside the cap.
    private func keepPinnedToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    // committed = solid white, partial (unconfirmed tail) settles from gray to white.
    // A shimmer sweep over the live text gives the fill a smooth, animated feel
    // instead of words snapping from 0.4 to full opacity.
    private var styledText: some View {
        // After the mic stops (Enter/close), sweep a strong shimmer across the whole
        // block while it's being finalized and polished — both the transcribing and
        // enhancing phases.
        let isFinalizing = !context.isRecording
            && (context.recordingState == .transcribing || context.recordingState == .enhancing)
        return ShimmerTranscriptText(
            committed: context.committed,
            partial: context.partial,
            isLive: context.isRecording,
            isEnhancing: isFinalizing
        )
    }

    // MARK: - Expand / Collapse toggle icon

    // One adaptive icon: collapsed → bigger circular expand glyph on the right edge;
    // expanded → circular collapse glyph in the bottom-right corner. Both get the same
    // white hover circle behind the arrows.
    private var toggleIcon: some View {
        Button(action: toggleCollapsed) {
            toggleGlyph(
                size: isCollapsed ? 24 : 22,
                bgOpacity: 0.12,
                circular: true
            )
        }
        .buttonStyle(.plain)
        // Collapsed: flush to the right edge with the same 8px inset it has top/bottom
        // (24px glyph centered in the 40px-tall pill). Expanded: off the corner.
        .padding(.trailing, isCollapsed ? 8 : 12)
        .padding(.bottom, isCollapsed ? 0 : 11)
        .opacity(isHoveringPanel ? 1 : 0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHoveringToggle = hovering }
        }
        .animation(.easeOut(duration: 0.18), value: isHoveringPanel)
    }

    @ViewBuilder
    private func toggleGlyph(size: CGFloat = 18, bgOpacity: Double = 0.04, cornerRadius: CGFloat = 5, circular: Bool = false) -> some View {
        Image(systemName: isCollapsed
              ? "arrow.up.left.and.arrow.down.right"
              : "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white.opacity(isHoveringToggle ? 1.0 : 0.8))
            .frame(width: size, height: size)
            .background(
                Group {
                    if circular {
                        // A black-on-black stroke used to sit at the badge edge, which is
                        // invisible against the identical panel-black fill — the badge read
                        // as a plain circle with no separation from the waveform bars right
                        // behind it. Fixed with an actual ring: a wider panel-black circle
                        // behind the (unchanged) inner badge, so there's a clean masked gap
                        // before the bars instead of the two edges touching.
                        let innerDiameter = size + 8
                        let ringThickness: CGFloat = 3.5
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: innerDiameter + ringThickness * 2, height: innerDiameter + ringThickness * 2)
                            Circle()
                                .fill(Color.black)
                                .overlay(Circle().fill(Color.white.opacity(isHoveringToggle ? bgOpacity : 0)))
                                .frame(width: innerDiameter, height: innerDiameter)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(isHoveringToggle ? bgOpacity : 0))
                    }
                }
            )
    }

    private func toggleCollapsed() {
        isCollapsed.toggle()
    }
}

// MARK: - Shimmer transcript text

/// Renders committed (solid white) + partial (settling) text. While live, a soft
/// highlight sweep travels across the partial tail so freshly recognized words
/// fade up smoothly rather than snapping from gray to white.
private struct ShimmerTranscriptText: View {
    let committed: String
    let partial: String
    let isLive: Bool
    var isEnhancing: Bool = false

    private var base: Text {
        let committedText = Text(committed).foregroundColor(.white)
        guard !partial.isEmpty else { return committedText }

        // Trust the provider's own spacing. The live tail is often the unfinished rest
        // of the current word (e.g. committed "kdy" + tail "ž" → "když"), so inserting
        // an artificial space here would split words mid-stream. Soniox already emits a
        // leading space on the tail when it starts a new word.
        return committedText + Text(partial).foregroundColor(.white.opacity(0.55))
    }

    var body: some View {
        if committed.isEmpty && partial.isEmpty {
            // Empty default state: a faint prompt so the panel isn't blank on spawn.
            Text("Start speaking...")
                .foregroundColor(.white.opacity(0.3))
        } else if isEnhancing {
            // While the text is being polished, sweep a bright highlight across the
            // whole block so it reads as one shimmering "being refined" state instead
            // of a separate loading spinner. Dim base + strong wide sweep = clearly
            // visible gradient travelling across every word.
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: 0.9)) / 0.9  // 0…1 loop
                // Strongly dim the base and run a bright, tight band so the highlight
                // reads as a very pronounced sweep crossing the whole block.
                base.foregroundColor(.white.opacity(0.22))
                    .overlay(sweep(phase: phase, intensity: 1.0, band: 0.22))
            }
        } else {
            base
        }
    }

    private func sweep(phase: Double, intensity: Double, band: Double) -> some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: max(0, phase - band)),
                .init(color: Color.white.opacity(intensity), location: phase),
                .init(color: .clear, location: min(1, phase + band))
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .blendMode(.plusLighter)
        .mask(base)
    }
}

private struct TranscriptHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
