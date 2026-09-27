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
        .onExitCommand { controller.collapse() }
    }

    private var outline: NotchOutline {
        NotchOutline(
            topRadius: 4,
            bottomRadius: controller.expanded ? 24 : controller.recording || controller.busy ? 18 : 12
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

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 12) {
            BackgroundTaskNoticeView(controller: controller)
            if !controller.taskStatus.isEmpty {
                HStack(spacing: 8) {
                    Button { controller.showFileTask() } label: {
                        Label(controller.taskStatus, systemImage: "terminal")
                            .font(.system(size: 11)).lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if controller.fileTaskRunning {
                        iconButton("stop.fill", help: "Stop all background tasks") { controller.stopFileTask() }
                    }
                }
            }

            if let context = controller.context {
                HStack(spacing: 8) {
                    if let data = context.image, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6))
                    } else { Image(systemName: "macwindow").foregroundStyle(.white).frame(width: 28) }
                    Text(context.isRegion ? context.label : "Context: " + context.label).font(.system(size: 11)).lineLimit(1)
                    Spacer(minLength: 0)
                    iconButton("xmark", help: "Remove context") { controller.context = nil }
                }
            }

            if !controller.response.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !controller.response.isEmpty {
                            AnswerMarkdown(text: controller.response).draggable(controller.response)
                        }
                        if let message = controller.lastMessage, message.text == controller.response {
                            HStack(spacing: 4) {
                                Spacer()
                                CopyAnswerButton(text: message.text)
                                InsertAnswerButton(text: message.text)
                                NotchResponsePlayback(playback: controller.playback, message: message)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 4)
            }

            NotchApprovalCard(controller: controller)
            NotchElicitationCard()

            if controller.response.isEmpty {
                Spacer(minLength: 0)
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
                    iconButton("pencil.tip.crop.circle", help: "Mark up the screen") { controller.markUpScreen() }
                        .disabled(controller.busy || controller.recording)
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
        if controller.busy { return controller.phase }
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
    @ObservedObject var controller: AssistantController
    @ObservedObject private var focus = VoiceFocus.shared

    var body: some View {
        HStack(spacing: 0) {
            Button { controller.show(typing: true) } label: {
                Group {
                    if let icon = focus.appIcon {
                        Image(nsImage: icon).resizable().scaledToFit()
                    } else { Image(nsImage: VoiceFocus.defaultAppIcon).resizable().scaledToFit() }
                }
                .frame(width: 17, height: 17)
                .offset(y: -2)
                .frame(width: 32, height: controller.notchInset > 0 ? controller.notchInset : 28)
                .contentShape(Rectangle())
            }
            .help("Open Speek for " + focus.appName)
            .accessibilityLabel("Open Speek")
            Spacer(minLength: 0)
            Button { controller.toggleVoice() } label: {
                Image(systemName: focus.mode == .dictation ? "waveform" : "sparkle")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                    .offset(y: -2)
                    .frame(width: 32, height: controller.notchInset > 0 ? controller.notchInset : 28)
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

    func path(in rect: CGRect) -> Path {
        // Keep circular curves; idle uses the preferred softer 12-point contour.
        let shoulder = min(topRadius, rect.height / 2)
        let radius = min(max(8, bottomRadius), (rect.height - shoulder), (rect.width - shoulder * 2) / 2)
        let left = rect.minX + shoulder
        let right = rect.maxX - shoulder
        let top = rect.minY
        let bottom = rect.maxY
        let k: CGFloat = 0.55228475
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: top))
            path.addLine(to: CGPoint(x: rect.maxX, y: top))
            path.addCurve(to: CGPoint(x: right, y: top + shoulder),
                          control1: CGPoint(x: rect.maxX - shoulder * k, y: top),
                          control2: CGPoint(x: right, y: top + shoulder * (1 - k)))
            path.addLine(to: CGPoint(x: right, y: bottom - radius))
            path.addCurve(to: CGPoint(x: right - radius, y: bottom),
                          control1: CGPoint(x: right, y: bottom - radius * (1 - k)),
                          control2: CGPoint(x: right - radius * (1 - k), y: bottom))
            path.addLine(to: CGPoint(x: left + radius, y: bottom))
            path.addCurve(to: CGPoint(x: left, y: bottom - radius),
                          control1: CGPoint(x: left + radius * (1 - k), y: bottom),
                          control2: CGPoint(x: left, y: bottom - radius * (1 - k)))
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
