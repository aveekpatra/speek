import SwiftUI
import AppKit

/// The floating recording window content. Renders the Classic panel or the Mini pill
/// depending on `SpeekSettings.recordingWindowStyle`; the hosting NSPanel is managed
/// by `MiniWindowManager`.
struct SpeekRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject private var settings = SpeekSettings.shared
    @ObservedObject private var modeManager = ModeManager.shared
    @ObservedObject private var loadState = VoiceModelLoadState.shared
    let onStopTapped: () -> Void
    let onCancelTapped: () -> Void

    var body: some View {
        Group {
            switch settings.recordingWindowStyle {
            case .classic:
                ClassicRecorderPanel(
                    state: stateProvider.recordingState,
                    audioMeter: recorder.audioMeter,
                    transcript: liveTranscript,
                    modeName: modeManager.currentEffectiveConfiguration?.name ?? "Voice to text",
                    isCancelConfirming: stateProvider.isCancelConfirming,
                    isCanceling: stateProvider.isCanceling,
                    pasteHint: stateProvider.pasteHintText,
                    onCopy: stateProvider.pasteHintCopyText == nil ? nil : { stateProvider.copyPasteHintText() },
                    resultPreview: stateProvider.resultPreview,
                    loadingModelName: loadState.loadingModelName,
                    onStop: onStopTapped,
                    onCancel: onCancelTapped
                )
            case .mini, .none:
                if stateProvider.recordingState == .idle,
                   stateProvider.pasteHintText == nil,
                   settings.keepsRecorderVisibleWhenIdle {
                    IdleRecorderStrip(edge: settings.panelPosition, onRecord: onStopTapped)
                } else {
                    MiniRecorderPill(
                        state: stateProvider.recordingState,
                        audioMeter: recorder.audioMeter,
                        isCancelConfirming: stateProvider.isCancelConfirming,
                        isCanceling: stateProvider.isCanceling,
                        pasteHint: stateProvider.pasteHintText,
                        onCopy: stateProvider.pasteHintCopyText == nil ? nil : { stateProvider.copyPasteHintText() }
                    )
                    .onTapGesture {
                        if stateProvider.recordingState == .recording { onStopTapped() }
                    }
                }
            }
        }
        .padding(edgeInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    /// Gap the content keeps from the anchored edge of the host window (room for the
    /// glass shadow). MiniRecorderPanel pulls the host back by the same amount.
    static func contentInset(for position: PanelPosition) -> CGFloat {
        position == .bottom ? 18 : 3
    }

    private var position: PanelPosition { settings.panelPosition }

    /// Content hugs the anchored edge so it grows away from it, never across it.
    private var alignment: Alignment {
        switch position {
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        case .bottom: return .bottom
        }
    }

    private var edgeInsets: EdgeInsets {
        let inset = Self.contentInset(for: position)
        switch position {
        case .top: return EdgeInsets(top: inset, leading: 0, bottom: 0, trailing: 0)
        case .left: return EdgeInsets(top: 0, leading: inset, bottom: 0, trailing: 0)
        case .right: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: inset)
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: inset, trailing: 0)
        }
    }

    private var liveTranscript: String {
        let committed = stateProvider.committedTranscript
        let tail = stateProvider.partialTail
        if committed.isEmpty && tail.isEmpty { return stateProvider.partialTranscript }
        return committed + (tail.isEmpty ? "" : " " + tail)
    }
}

// MARK: - Classic panel

struct ClassicRecorderPanel: View {
    let state: RecordingState
    let audioMeter: AudioMeter
    let transcript: String
    let modeName: String
    let isCancelConfirming: Bool
    let isCanceling: Bool
    let pasteHint: String?
    var onCopy: (() -> Void)? = nil
    var resultPreview: String? = nil
    var loadingModelName: String? = nil
    let onStop: () -> Void
    let onCancel: () -> Void

    static let width: CGFloat = 420
    static let height: CGFloat = 112

    private var stopTokens: [String] {
        ShortcutStore.shortcut(for: .primaryRecording)?.displayTokens ?? ["⌘"]
    }

    private var isProcessing: Bool {
        state == .transcribing || state == .enhancing
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if isCancelConfirming {
                    statusLabel("Press esc again to cancel", symbol: "xmark.circle")
                } else if let pasteHint {
                    VStack(spacing: 8) {
                        if let resultPreview, !resultPreview.isEmpty {
                            Text(resultPreview)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(3)
                                .multilineTextAlignment(.center)
                                .textSelection(.enabled)
                        }
                        HStack(spacing: 10) {
                            statusLabel(pasteHint, symbol: onCopy == nil ? "doc.on.clipboard" : "exclamationmark.triangle")
                                .font(.system(size: 12, weight: .medium))
                            if let onCopy {
                                CopyHintButton(action: onCopy)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                } else if isProcessing {
                    processingLabel
                } else {
                    RollingWaveformView(audioMeter: audioMeter, isActive: state == .recording)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }
            .frame(height: Self.height - 40)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)

            HStack(spacing: 8) {
                Image(systemName: "mic")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(transcript.isEmpty ? modeName : transcript)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(transcript.isEmpty ? 0.7 : 0.9))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 10)
                if state == .recording {
                    hintButton(title: "Stop", keys: stopTokens, action: onStop)
                    hintButton(title: "Cancel", keys: ["esc"], action: onCancel)
                } else if isProcessing {
                    hintButton(title: "Cancel", keys: ["esc"], action: onCancel)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
        }
        .frame(width: Self.width, height: Self.height)
        .glassEffect(.regular.tint(Color.black.opacity(0.62)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 10)
        .opacity(isCanceling ? 0 : 1)
        .scaleEffect(isCanceling ? 0.9 : 1)
        .animation(.easeOut(duration: 0.25), value: isCanceling)
        .colorScheme(.dark)
    }

    private func hintButton(title: String, keys: [String], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 3) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                        Text(key)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(minWidth: 20)
                            .padding(.horizontal, 4)
                            .frame(height: 20)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.14)))
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusLabel(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
    }

    private var processingLabel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text(processingTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            if loadingModelName != nil, state == .transcribing {
                Text("First use compiles the model for the Neural Engine. This can take a few minutes, once per launch.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
        }
    }

    private var processingTitle: String {
        if state == .enhancing { return "Rewriting" }
        if let loadingModelName { return "Loading \(loadingModelName)" }
        return "Transcribing"
    }
}

// MARK: - Mini pill

struct MiniRecorderPill: View {
    let state: RecordingState
    let audioMeter: AudioMeter
    let isCancelConfirming: Bool
    let isCanceling: Bool
    let pasteHint: String?
    var onCopy: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if isCancelConfirming {
                Text("esc again to cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            } else if let pasteHint {
                if onCopy != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(pasteHint)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                if let onCopy {
                    CopyHintButton(action: onCopy)
                }
            } else if state == .transcribing || state == .enhancing {
                ProgressView().controlSize(.mini).tint(.white)
                Text(state == .enhancing ? "Rewriting" : "Transcribing")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                LiveBarsView(audioMeter: audioMeter, isActive: state == .recording, barCount: 11, maxHeight: 18)
            }
        }
        // With the Copy button the pill is a capsule holding a smaller capsule: the
        // button sits at the same inset from the top, bottom and trailing edge, so the
        // two curves are concentric.
        .padding(.leading, 12)
        .padding(.trailing, onCopy == nil ? 12 : CopyHintButton.inset)
        .frame(minWidth: 96, minHeight: 36, maxHeight: 36)
        // Clear, interactive glass: the pill reads as a water droplet that bends what is
        // behind it instead of a dark capsule. A faint tint and the white content keep the
        // bars legible over light windows.
        .glassEffect(.clear.tint(Color.black.opacity(0.16)).interactive(), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 6)
        .opacity(isCanceling ? 0 : 1)
        .scaleEffect(isCanceling ? 0.9 : 1)
        .animation(.easeOut(duration: 0.25), value: isCanceling)
        .colorScheme(.dark)
    }
}

// MARK: - Always-show idle strip

/// "Always show" mini window at rest: a thin strip on the chosen screen edge that
/// expands on hover into three controls (change mode, start recording, open Speek).
struct IdleRecorderStrip: View {
    let edge: PanelPosition
    let onRecord: () -> Void

    @State private var isHovering = false
    @State private var collapseTask: Task<Void, Never>?

    private var isVertical: Bool { edge == .left || edge == .right }

    private var recordTokens: String {
        (ShortcutStore.shortcut(for: .primaryRecording)?.displayTokens ?? ["⌘"]).joined()
    }

    private var anchor: UnitPoint {
        switch edge {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private var frameAlignment: Alignment {
        switch edge {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }

    var body: some View {
        ZStack {
            if isHovering {
                expanded
                    .transition(.scale(scale: 0.5, anchor: anchor).combined(with: .opacity))
            } else {
                collapsed
                    .transition(.scale(scale: 0.5, anchor: anchor).combined(with: .opacity))
            }
        }
        .frame(width: isVertical ? 64 : 170, height: isVertical ? 170 : 64, alignment: frameAlignment)
        .contentShape(Rectangle())
        .onHover { hovering in
            collapseTask?.cancel()
            if hovering {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isHovering = true }
            } else {
                collapseTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isHovering = false }
                }
            }
        }
        .colorScheme(.dark)
    }

    private var collapsed: some View {
        Color.clear
            .frame(width: isVertical ? 7 : 56, height: isVertical ? 56 : 7)
            .glassEffect(.regular.tint(Color.black.opacity(0.55)), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8))
    }

    @ViewBuilder
    private var expanded: some View {
        let layout = isVertical ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            stripButton(systemName: "sparkles", help: "Change mode") {
                NotificationCenter.default.post(name: .speekShowModeSwitcher, object: nil)
            }
            Button(action: onRecord) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.16)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Start recording  \(recordTokens)")
            stripButton(systemName: "arrow.up.left.and.arrow.down.right", help: "Open Speek") {
                NSApplication.shared.setActivationPolicy(.regular)
                _ = WindowManager.shared.showMainWindow()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .padding(isVertical ? .vertical : .horizontal, 10)
        .frame(width: isVertical ? 48 : nil, height: isVertical ? nil : 48)
        .glassEffect(.regular.tint(Color.black.opacity(0.6)), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.3), radius: 14, x: 0, y: 4)
    }

    private func stripButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Waveforms

/// Scrolling amplitude history, newest on the right, mirrored around the midline.
struct RollingWaveformView: View {
    let audioMeter: AudioMeter
    let isActive: Bool

    @State private var history: [Double] = []
    @State private var lastSample: TimeInterval = 0

    private let barWidth: CGFloat = 2.5
    private let gap: CGFloat = 2.0
    private let sampleInterval: TimeInterval = 1.0 / 30.0

    private var level: Double {
        // Meter is 0...1 over a -60 dB floor; gate room noise so silence reads flat.
        let raw = max(audioMeter.averagePower, audioMeter.peakPower * 0.8)
        let gated = max(0, (raw - 0.28) / 0.72)
        return min(1, pow(gated, 0.85))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Canvas { gc, size in
                draw(&gc, size: size)
            }
            .onChange(of: context.date) { _, date in
                append(now: date.timeIntervalSince1970, width: 0)
            }
        }
    }

    private func append(now: TimeInterval, width: CGFloat) {
        guard now - lastSample >= sampleInterval else { return }
        lastSample = now
        history.append(isActive ? level : 0)
        if history.count > 400 { history.removeFirst(history.count - 400) }
    }

    private func draw(_ gc: inout GraphicsContext, size: CGSize) {
        let period = barWidth + gap
        let count = Int(size.width / period)
        let midY = size.height / 2
        let maxHalf = size.height / 2 - 4
        let samples = history.suffix(count)
        let offset = count - samples.count
        for (i, value) in samples.enumerated() {
            let index = offset + i
            let x = CGFloat(index) * period + gap / 2
            let half = max(1.2, CGFloat(value) * maxHalf)
            let rect = CGRect(x: x, y: midY - half, width: barWidth, height: half * 2)
            let fade = min(1, Double(index) / Double(max(count / 4, 1)))
            gc.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(.white.opacity(0.35 + 0.55 * fade)))
        }
        // Dotted baseline for the not-yet-filled part.
        if offset > 0 {
            for index in stride(from: 0, to: offset, by: 3) {
                let x = CGFloat(index) * period + gap / 2
                gc.fill(Path(ellipseIn: CGRect(x: x, y: midY - 1, width: 2, height: 2)), with: .color(.white.opacity(0.25)))
            }
        }
    }
}

/// Small symmetric bars that react to the live level (used by the Mini pill).
struct LiveBarsView: View {
    let audioMeter: AudioMeter
    let isActive: Bool
    var barCount: Int = 11
    var maxHeight: CGFloat = 18

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSince1970
            HStack(spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 2.5, height: height(for: index, t: t))
                }
            }
        }
    }

    private func height(for index: Int, t: Double) -> CGFloat {
        guard isActive else { return 3 }
        let raw = max(audioMeter.averagePower, audioMeter.peakPower * 0.8)
        let level = min(1, pow(max(0, (raw - 0.28) / 0.72), 0.85))
        let phase = Double(index) * 0.7
        let wave = sin(t * 9 + phase) * 0.5 + 0.5
        let centerBoost = 1 - abs(Double(index) - Double(barCount) / 2) / Double(barCount) * 0.8
        return max(3, CGFloat(level * (0.4 + 0.6 * wave) * centerBoost) * maxHeight)
    }
}

/// Small glass "Copy" button shown in the recorder when a paste could not be confirmed.
/// Sized explicitly (no system button padding) so it nests concentrically in the pill.
/// Clicks work without the panel taking key status, so the user's focus stays put.
private struct CopyHintButton: View {
    /// Gap between this capsule and the pill's edge on the top, bottom and trailing side.
    static let inset: CGFloat = 3.5
    static let height: CGFloat = 36 - inset * 2

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "doc.on.clipboard")
                Text("Copy")
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: Self.height)
            .background(Color.black.opacity(0.78), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Put the transcript on the clipboard")
    }
}
