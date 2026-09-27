import SwiftUI

struct AssistantSurface: View {
    @ObservedObject var controller: AssistantController
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            if controller.expanded || controller.recording || controller.busy {
                // Controls occupy the wings; only the body sits below the camera.
                if controller.expanded {
                    notchHeader
                    if controller.surfaceMode == .dictation { dictationRecovery }
                    else { expanded }
                }
                else {
                    Color.clear.frame(height: controller.notchInset)
                    VoicePill(controller: controller, recorder: controller.recorder)
                }
            } else {
                NotchIdleControl(controller: controller)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { notchBackground }
        .clipShape(outline)
        .preferredColorScheme(.dark)
        .onChange(of: controller.recording) { _, _ in controller.resize() }
        .onChange(of: controller.busy) { _, _ in controller.resize() }
        .onChange(of: controller.response) { _, _ in controller.resize() }
        .onChange(of: controller.context?.label) { _, _ in controller.resize() }
        .onChange(of: controller.taskNotices.count) { _, _ in controller.resize() }
        .onChange(of: controller.taskStatus) { _, _ in controller.resize() }
        .onChange(of: controller.dictationError) { _, _ in controller.resize() }
        .onChange(of: controller.surfaceMode) { _, _ in controller.resize() }
        .onChange(of: controller.pendingDictation) { _, _ in controller.resize() }
        .onChange(of: controller.proposal != nil) { _, _ in controller.resize() }
        .onChange(of: controller.draft) { _, _ in controller.resize() }
        .onReceive(controller.attachments.$attachments) { _ in controller.resize() }
        .onChange(of: controller.resultCards.count) { _, _ in controller.resize() }
        .onReceive(CorrectionLearner.shared.$notice) { _ in DispatchQueue.main.async { controller.resize() } }
        .onExitCommand { controller.collapse() }
        .onHover { controller.setHovering($0) }
    }

    private var outline: NotchOutline {
        let resting = !controller.expanded && !controller.recording && !controller.busy
        return NotchOutline(
            topRadius: NotchIdleControl.shoulderRadius,
            bottomRadius: controller.expanded ? 24 : !resting ? 18 : NotchIdleControl.cornerRadius(for: controller.notchInset),
            continuous: resting
        )
    }

    @ViewBuilder
    private var notchBackground: some View {
        if !controller.expanded || reduceTransparency {
            // Resting hardware extension: no material, tint, or translucent layer.
            Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
                .allowsHitTesting(false)
        } else {
            GeometryReader { geometry in
                // All fade stops are relative to the available body height. A fixed
                // midpoint can coincide with the cap in short recovery panels,
                // creating an abrupt change in opacity instead of a gradual fade.
                let cap = min(0.99, max(0, controller.notchInset / max(1, geometry.size.height)))
                let fade = 1 - cap
                ZStack {
                    Color.clear
                        .glassEffect(.regular.tint(.black.opacity(0.2)), in: outline)
                    // Keep the camera strip opaque; reveal glass below it.
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: cap),
                        .init(color: .black.opacity(0.82), location: cap + fade * 0.25),
                        .init(color: .black.opacity(0.42), location: cap + fade * 0.65),
                        .init(color: .black.opacity(0.12), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var notchHeader: some View {
        HStack(spacing: 0) {
            HStack {
                Group {
                    if controller.surfaceMode == .dictation, let icon = controller.voiceAppIcon {
                        Image(nsImage: icon).resizable().scaledToFit()
                    } else { Image(nsImage: NSApplication.shared.applicationIconImage).resizable().scaledToFit() }
                }
                .frame(width: 16, height: 16).foregroundStyle(.white)
                .help(controller.surfaceMode == .dictation ? "Dictation destination: " + controller.voiceAppName : "Speek")
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity)
            Color.clear.frame(width: controller.notchCameraWidth)
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Menu {
                    Button("New conversation") { controller.newConversation() }
                        .disabled(controller.busy || controller.recording)
                    Menu("Recent conversations") {
                        ForEach(ActionThreadStore.shared.threads.prefix(8)) { thread in
                            Button(thread.title) { controller.resume(thread) }
                        }
                    }
                    if !controller.pendingDictation.isEmpty {
                        Button("Recovered dictation") { controller.showRecoveredDictation() }
                            .disabled(controller.busy || controller.recording)
                    }
                    Divider()
                    RecentDictationsMenu()
                    Button("Dictation history...") { SpeekMainWindow.shared.showDictationHistory() }
                    Divider()
                    Button("Open Speek") { SpeekMainWindow.shared.show() }
                    Button("Settings") { AssistantSettingsWindow.shared.show() }
                } label: { Image(systemName: "ellipsis").font(.system(size: 13)).frame(width: 28, height: max(24, controller.notchInset)).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: 28, height: max(24, controller.notchInset)).help("Conversation options")
                Button { controller.collapse() } label: {
                    Image(systemName: "minus").font(.system(size: 13))
                        .frame(width: 28, height: max(24, controller.notchInset))
                        .contentShape(Rectangle())
                }.buttonStyle(AssistantControlStyle()).help("Dismiss to notch")
                    .accessibilityLabel("Dismiss to notch")
            }.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .frame(height: max(24, controller.notchInset))
    }

    private var dictationRecovery: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !controller.dictationError.isEmpty {
                        Text(controller.dictationError).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    if !controller.pendingDictation.isEmpty {
                        Text(controller.pendingDictation).font(.system(size: 14)).lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !controller.pendingDictation.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(controller.pendingDictation, forType: .string)
                    } label: { Label("Copy dictation", systemImage: "doc.on.doc") }
                    .buttonStyle(SpeekActionButtonStyle())
                }
            }
        }.padding(12)
    }

    // What the notch shows (one rule set, so it never feels random):
    // - The current exchange, as in a message thread: what you said, on the right, and Speek's
    //   reply below it. While Speek works, a status line sits where the reply will be (the
    //   spoken acknowledgment, or the step it is on); the reply replaces it.
    // - Earlier turns of the same conversation stay folded behind one line; open them if needed.
    // - Which conversation you are in is not shown: a new one starts by itself after a pause,
    //   and the pencil in the composer starts one on purpose.
    // - Approvals and plugin questions appear right under your message, in place of a reply.
    // - A background task that finished shows one compact notice at the top.

    @State private var showEarlier = false

    @ViewBuilder private var conversation: some View {
        if !controller.lastRequest.isEmpty || !controller.response.isEmpty || controller.busy {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        let earlier = controller.earlierExchanges
                        if !earlier.isEmpty {
                            if showEarlier {
                                ForEach(Array(earlier.enumerated()), id: \.offset) { _, pair in
                                    userBubble(pair.request, image: nil).opacity(0.7)
                                    Text(pair.reply).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(4)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                                }
                            } else {
                                Button { withAnimation(.easeOut(duration: 0.15)) { showEarlier = true } } label: {
                                    Label(earlier.count == 1 ? "1 earlier message" : "\(earlier.count) earlier messages", systemImage: "chevron.up")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }.buttonStyle(.plain).frame(maxWidth: .infinity)
                            }
                        }
                        if !controller.lastRequest.isEmpty { userBubble(controller.lastRequest, image: controller.lastRequestImage) }
                        if controller.recording || (controller.busy && controller.response.isEmpty) { statusRow }
                        ForEach(controller.resultCards) { card in ResultCardView(card: card) }
                        if !controller.response.isEmpty {
                            AnswerMarkdown(text: controller.response).draggable(controller.response).padding(.horizontal, 4)
                            if let message = controller.lastMessage, message.text == controller.response {
                                HStack(spacing: 4) {
                                    Spacer()
                                    CopyAnswerButton(text: message.text)
                                    InsertAnswerButton(text: message.text)
                                    NotchResponsePlayback(playback: controller.playback, message: message)
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: controller.response) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: controller.lastRequest) { _, _ in showEarlier = false; proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }

    /// What you said, on the right, with the screenshot it was sent with.
    private func userBubble(_ text: String, image: Data?) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 48)
            if let data = image, let screenshot = NSImage(data: data) {
                Image(nsImage: screenshot).resizable().scaledToFill()
                    .frame(width: 34, height: 24).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            Text(text).font(.system(size: 13)).lineLimit(3).textSelection(.enabled)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// Where the reply will appear: listening, the acknowledgment, or the current step.
    private var statusRow: some View {
        HStack(spacing: 8) {
            if controller.recording {
                Image(systemName: "waveform").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                Text("Listening...").font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
                Text(controller.statusLine ?? controller.phase).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 4)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            BackgroundTaskNoticeView(controller: controller)
            if !controller.taskStatus.isEmpty {
                HStack(spacing: 8) {
                    Button { controller.showFileTask() } label: {
                        Label(controller.taskStatus, systemImage: "terminal")
                            .font(.system(size: 11)).lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if controller.fileTaskRunning {
                        iconButton("stop.fill", help: "Stop all background tasks") { controller.stopFileTask() }
                    }
                }
            }

            conversation

            NotchApprovalCard(controller: controller)
            NotchElicitationCard()

            if controller.lastRequest.isEmpty && controller.response.isEmpty && !controller.busy {
                Spacer(minLength: 0)
            }

            if let context = controller.context {
                HStack(spacing: 8) {
                    if let data = context.image, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6))
                    } else { Image(systemName: "macwindow").foregroundStyle(.white).frame(width: 28) }
                    Text(context.label + ", sent with your next request").font(.system(size: 11)).lineLimit(1)
                    Spacer(minLength: 0)
                    iconButton("xmark", help: "Remove context") { controller.context = nil }
                }
            }

            VStack(spacing: 6) {
                NotchAttachmentStrip(store: controller.attachments)
                TextField("Ask Speek...", text: $controller.draft, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...3)
                    .focused($typing).onSubmit { controller.submit() }
                    .padding(.horizontal, 6).padding(.top, 6)
                HStack(spacing: 4) {
                    iconButton("lasso", help: "Circle screen context") { controller.circleContext() }
                        .disabled(controller.busy || controller.recording)
                    if controller.hasConversation {
                        iconButton("square.and.pencil", help: "New conversation") { controller.newConversation() }
                            .disabled(controller.recording)
                    }
                    Spacer(minLength: 0)
                    AssistantModelPicker(assistant: controller) {
                        SpeekMainWindow.shared.section = .connections
                        SpeekMainWindow.shared.show()
                    }
                    if controller.busy {
                        iconButton("stop.fill", help: "Stop request") { controller.cancel() }
                    } else {
                        iconButton(controller.recording ? "stop.fill" : "mic.fill", help: controller.recording ? "Finish speaking" : "Speak") {
                            controller.toggleVoice(mode: .agent)
                        }
                        if !controller.draft.isEmpty && !controller.recording {
                            iconButton("arrow.up", help: "Send request") { controller.submit() }
                        }
                    }
                }
            }
            .padding(6)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            // Drop files or images on the composer to attach them.
            .dropDestination(for: URL.self) { urls, _ in
                controller.attachments.add(urls: urls.filter(\.isFileURL)); return !urls.isEmpty
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(12)

    }

    private func controlImage(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { controlImage(symbol) }
            .buttonStyle(AssistantControlStyle()).help(help).accessibilityLabel(help)
    }
}

private struct NotchResponsePlayback: View {
    @ObservedObject var playback: SpeechPlaybackService
    let message: ActionMessage

    private var playing: Bool { playback.playingMessageID == message.id }
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                Task { await playback.toggle(message) }
            } label: {
                Image(systemName: playing ? "stop.fill" : "speaker.wave.2")
                    .font(.system(size: 13)).frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .help(playing ? "Stop reading" : "Read this response aloud")
                .accessibilityLabel(playing ? "Stop reading" : "Read this response aloud")
            if let error = playback.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AssistantControlStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.16 : hovered ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 10))
            .onHover { hovered = $0 }
    }
}


private struct VoicePill: View {
    @ObservedObject var controller: AssistantController
    @ObservedObject var recorder: Recorder
    @ObservedObject private var focus = VoiceFocus.shared
    @ObservedObject private var live = LiveTranscriptPreview.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { controller.recording || controller.busy }
    private var title: String {
        if controller.recording { return controller.voiceMode == .dictation ? "Dictation" : "Agent" }
        if controller.busy { return controller.statusLine ?? controller.phase }
        return focus.label
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = active ? controller.voiceAppIcon : focus.appIcon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(nsImage: VoiceFocus.defaultAppIcon).resizable().scaledToFit()
                }
            }
            .frame(width: 24, height: 24)
            .frame(width: 28, height: 28)
            .help(active ? controller.voiceAppName : focus.appName)

            if controller.recording && !live.text.isEmpty {
                // The newest words stay pinned to the trailing edge and the line scrolls
                // left as you speak; older words fade out at the leading edge.
                // The text sits in an overlay so its full width never feeds back into the pill's
                // (and the notch window's) size; only the visible slice is drawn.
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .overlay(alignment: .trailing) {
                        Text(live.text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: live.text)
                    }
                    .clipped()
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.18)],
                                         startPoint: .leading, endPoint: .trailing))
                    .accessibilityElement().accessibilityLabel("Live transcript: " + live.text)
            } else if controller.busy {
                // Tucked while working: click to open the notch and watch.
                Button { controller.show() } label: {
                    Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Show what Speek is doing")
            } else {
                Menu {
                    Picker("Voice mode", selection: $focus.override) {
                        ForEach(VoiceInputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Divider()
                    Button("Open Speek") { SpeekMainWindow.shared.show() }
                    Button("Type a request") { controller.show(typing: true) }
                } label: {
                    Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        .foregroundStyle(.white)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(maxWidth: .infinity, minHeight: 28)
                .help(active ? controller.voiceMode.rawValue : "Voice mode for " + focus.appName)
                .disabled(active)
            }

            if controller.recording {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<3) { index in
                        Capsule().fill(.white)
                            .frame(width: 2, height: 3 + CGFloat(min(1, max(0, recorder.audioMeter.peakPower))) * CGFloat(index == 1 ? 15 : 10))
                    }
                }.frame(width: 12, height: 20)
                    .accessibilityHidden(true)
            }
            Button {
                if controller.busy { controller.cancel() }
                else { controller.toggleVoice() }
            } label: {
                Group {
                    if controller.busy { ProgressView().controlSize(.mini) }
                    else {
                        Image(systemName: controller.recording ? "stop.fill" : "mic.fill")
                            .symbolEffect(.breathe, isActive: controller.recording && !reduceMotion)
                    }
                }
                .font(.system(size: 12)).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.white.opacity(controller.recording ? 0.18 : 0.07), in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(controller.busy ? "Cancel" : controller.recording ? "Finish dictation" : "Start speaking")
            .accessibilityLabel(controller.busy ? "Cancel transcription" : controller.recording ? "Stop recording" : "Start recording")
        }
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .padding(.horizontal, 12)
        .frame(height: 48)
    }
}

private struct NotchIdleControl: View {
    /// The notch's top shoulders curve outward with this radius.
    static let shoulderRadius: CGFloat = 4
    /// The resting notch's lower corners: a continuous curve like the hardware notch's, spanning
    /// about 49% of the notch's height (radius 0.32 of the height).
    static func cornerRadius(for height: CGFloat) -> CGFloat { max(20, height) * 0.32 }
    /// Visible gap between the app icon's rounded square and the notch's edges.
    static let iconGap: CGFloat = 6
    /// The surface's own horizontal padding, already between the edge and the icon.
    static let surfaceInset: CGFloat = 4
    @ObservedObject var controller: AssistantController
    @ObservedObject private var focus = VoiceFocus.shared
    @ObservedObject private var learner = CorrectionLearner.shared

    var body: some View {
        VStack(spacing: 0) {
            // Full screen: the resting notch is only as wide as the camera, with nothing beside it.
            let resting = controller.tucked && !controller.expanded && !controller.recording && !controller.busy
            if !resting { controls }
            if !resting, let entry = learner.notice {
                // A correction the user just made, saved to Vocabulary.
                HStack(spacing: 6) {
                    Image(systemName: "character.book.closed").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    Text("Learned " + entry.term).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                        .help(entry.heardAs.isEmpty ? "Added to Vocabulary as a hint" : "\"" + entry.heardAs + "\" will be written as \"" + entry.term + "\"")
                    Spacer(minLength: 4)
                    Button("Undo") { learner.undoLast() }.font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                }
                .padding(.horizontal, 12).frame(height: 30)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button { controller.show(typing: true) } label: {
                // The app's own icon, unaltered, centered in a square as tall as the notch, like a
                // menu bar item: the same gap above, below, and to its left. The icon file has a
                // transparent margin around its rounded square, so the frame is larger than what shows.
                let height = controller.notchInset > 0 ? controller.notchInset : 28
                let icon = focus.appIcon ?? VoiceFocus.defaultAppIcon
                let visible = max(14, height - Self.iconGap * 2)
                // Measured per icon: the part of the image that is not transparent.
                let box = IconBounds.visible(in: icon)
                let frame = visible / max(box.width, box.height)
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                    .frame(width: frame, height: frame)
                    // Move the visible part, not the image file, to the center.
                    .offset(x: (0.5 - box.midX) * frame, y: (0.5 - box.midY) * frame)
                    .frame(width: AssistantController.idleWing(height) - Self.surfaceInset, height: height)
                    // Center in the black body, which starts after the top shoulder's curve.
                    .offset(x: (Self.shoulderRadius - Self.surfaceInset) / 2)
                    .contentShape(Rectangle())
            }
            .help("Open Speek for " + focus.appName)
            .accessibilityLabel("Open Speek")
            Spacer(minLength: 0)
            Button { controller.toggleVoice() } label: {
                // Vertically centered, like the app icon on the other side.
                Image(systemName: focus.mode == .dictation ? "waveform" : "sparkle")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                    .frame(width: AssistantController.idleWing(controller.notchInset > 0 ? controller.notchInset : 28) - Self.surfaceInset, height: controller.notchInset > 0 ? controller.notchInset : 28)
                    .contentShape(Rectangle())
            }
            .help(focus.label + ". Hold your shortcut to speak.")
            .accessibilityLabel("Start " + focus.label)
            .contextMenu {
                Picker("Voice mode", selection: $focus.override) {
                    ForEach(VoiceInputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Concave shoulders join the screen edge; convex lower corners finish the notch.
private struct NotchOutline: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// Apple's continuous (squircle) curve for the lower corners, as on the hardware notch.
    var continuous = false

    /// One continuous corner, from 1.5287 radii along the first edge to 1.5287 along the second
    /// (the curve UIKit and SwiftUI use for continuous rounded rectangles). Pairs are line points,
    /// sixes are curves (control 1, control 2, end).
    private static let continuousCorner: [[CGFloat]] = [
        [1.08849323, 0, 0.86840689, 0.02229591, 0.66993427, 0.06549600],
        [0.63149399, 0.07491100],
        [0.37282392, 0.16905899, 0.16905899, 0.37282392, 0.07491100, 0.63149399],
        [0.06549600, 0.66993427],
        [0.02229591, 0.86840689, 0, 1.08849323, 0, 1.52866483]
    ]

    func path(in rect: CGRect) -> Path {
        // Concave top shoulders join the screen edge; the lower corners are convex.
        let shoulder = min(topRadius, rect.height / 2)
        let reach: CGFloat = continuous ? 1.52866483 : 1
        let radius = min(bottomRadius, (rect.height - shoulder) / reach, (rect.width - shoulder * 2) / 2 / reach)
        let left = rect.minX + shoulder
        let right = rect.maxX - shoulder
        let top = rect.minY
        let bottom = rect.maxY
        let k: CGFloat = 0.55228475
        func corner(_ path: inout Path, _ point: (CGFloat, CGFloat) -> CGPoint) {
            for part in Self.continuousCorner {
                if part.count == 2 { path.addLine(to: point(part[0], part[1])) }
                else { path.addCurve(to: point(part[4], part[5]), control1: point(part[0], part[1]), control2: point(part[2], part[3])) }
            }
        }
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: top))
            path.addLine(to: CGPoint(x: rect.maxX, y: top))
            path.addCurve(to: CGPoint(x: right, y: top + shoulder),
                          control1: CGPoint(x: rect.maxX - shoulder * k, y: top),
                          control2: CGPoint(x: right, y: top + shoulder * (1 - k)))
            if continuous {
                path.addLine(to: CGPoint(x: right, y: bottom - reach * radius))
                corner(&path) { along, across in CGPoint(x: right - across * radius, y: bottom - along * radius) }
                path.addLine(to: CGPoint(x: left + reach * radius, y: bottom))
                corner(&path) { along, across in CGPoint(x: left + along * radius, y: bottom - across * radius) }
            } else {
                path.addLine(to: CGPoint(x: right, y: bottom - radius))
                path.addCurve(to: CGPoint(x: right - radius, y: bottom),
                              control1: CGPoint(x: right, y: bottom - radius * (1 - k)),
                              control2: CGPoint(x: right - radius * (1 - k), y: bottom))
                path.addLine(to: CGPoint(x: left + radius, y: bottom))
                path.addCurve(to: CGPoint(x: left, y: bottom - radius),
                              control1: CGPoint(x: left + radius * (1 - k), y: bottom),
                              control2: CGPoint(x: left, y: bottom - radius * (1 - k)))
            }
            path.addLine(to: CGPoint(x: left, y: top + shoulder))
            path.addCurve(to: CGPoint(x: rect.minX, y: top),
                          control1: CGPoint(x: left, y: top + shoulder * (1 - k)),
                          control2: CGPoint(x: rect.minX + shoulder * k, y: top))
            path.closeSubpath()
        }
    }
}

/// Attached files in the notch composer, each removable.
private struct NotchAttachmentStrip: View {
    @ObservedObject var store: ComposerAttachmentStore

    var body: some View {
        if !store.attachments.isEmpty || store.isImporting {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.attachments) { item in
                        HStack(spacing: 4) {
                            Image(systemName: item.kind == .image ? "photo" : "doc.text").font(.system(size: 10))
                            Text(item.name).font(.system(size: 11)).lineLimit(1).frame(maxWidth: 120)
                            Button { store.remove(id: item.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                                .buttonStyle(.plain).accessibilityLabel("Remove " + item.name)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(.white.opacity(0.1), in: Capsule())
                    }
                    if store.isImporting { ProgressView().controlSize(.mini) }
                }.padding(.horizontal, 6).padding(.top, 6)
            }.frame(height: 30)
        }
    }
}

/// Where an image's solid pixels are, as a fraction of its size (top-left origin). App icons
/// carry different transparent margins and a soft shadow below, so centering the file (or
/// every faint pixel) does not center the icon's rounded square.
@MainActor
enum IconBounds {
    private static var cache: [ObjectIdentifier: CGRect] = [:]

    static func visible(in image: NSImage) -> CGRect {
        let key = ObjectIdentifier(image)
        if let known = cache[key] { return known }
        let side = 256
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        var result = CGRect(x: 0, y: 0, width: 1, height: 1)
        if let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
           let cgImage = { var rect = CGRect(x: 0, y: 0, width: side, height: side); return image.cgImage(forProposedRect: &rect, context: nil, hints: nil) }() {
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            var minX = side, minY = side, maxX = -1, maxY = -1
            for row in 0..<side { for column in 0..<side where pixels[(row * side + column) * 4 + 3] > 200 {
                minX = min(minX, column); maxX = max(maxX, column); minY = min(minY, row); maxY = max(maxY, row)
            } }
            // Bitmap rows run top to bottom in memory.
            if maxX >= minX, maxY >= minY {
                result = CGRect(x: CGFloat(minX) / CGFloat(side), y: CGFloat(minY) / CGFloat(side),
                                width: CGFloat(maxX - minX + 1) / CGFloat(side), height: CGFloat(maxY - minY + 1) / CGFloat(side))
            }
        }
        if cache.count > 64 { cache.removeAll() }
        cache[key] = result
        return result
    }
}
