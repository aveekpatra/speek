import SwiftUI
import AppKit

@MainActor
final class SpeekMainWindow: ObservableObject {
    @Published var section: ShellSection = .tasks
    enum TaskPage { case chat, history, activity, coding }
    @Published var taskPage: TaskPage = .chat
    @Published var showingCodingTasks = false
    func showActivity() { section = .tasks; taskPage = .activity; show() }
    var codingRequest = ""
    var codingSource: UUID?
    var codingImages: [Data] = []
    var codingContext: String?
    var codingConnection = ActionConnection.localCodex
    var codingModel: String?
    var codingReasoning: String?
    func showCodingTasks() { showingCodingTasks = true; show() }
    static let shared = SpeekMainWindow()
    private var window: NSWindow?
    @Published var settingsTab = "General"
    func showSettings(tab: String = "General") {
        settingsTab = tab
        section = .settings
        show()
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SpeekMainShell()))
            window.title = "Speek"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            let toolbar = NSToolbar(identifier: "SpeekWindowToolbar")
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
            window.toolbarStyle = .unifiedCompact
            window.isOpaque = false
            window.backgroundColor = .clear
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 840, height: 560)
            window.setContentSize(NSSize(width: 1120, height: 740))
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum ShellSection: String, CaseIterable {
    case tasks = "Tasks", memory = "Memory", connections = "Models & Voice", integrations = "Integrations", settings = "Settings"
    var icon: String {
        switch self {
        case .tasks: return "tray"
        case .memory: return "point.3.connected.trianglepath.dotted"
        case .connections: return "sparkles.rectangle.stack"
        case .integrations: return "puzzlepiece.extension"
        case .settings: return "gearshape"
        }
    }
    var filledIcon: String {
        self == .memory ? "point.3.filled.connected.trianglepath.dotted" : icon + ".fill"
    }
}

struct SpeekMainShell: View {
    @ObservedObject private var store = ActionThreadStore.shared
    @ObservedObject private var assistant = AssistantController.shared
    @State private var contextMenuPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var railActivations: [String: Int] = [:]
    @ObservedObject private var navigation = SpeekMainWindow.shared
    private var section: ShellSection {
        get { navigation.section }
        nonmutating set { navigation.section = newValue }
    }
    @AppStorage("speek.ui.taskSidebarWidth") private var sidebarWidth = 242.0
    @State private var resizeOrigin: Double?
    @State private var resizing = false
    @Environment(\.displayScale) private var displayScale
    @State private var search = ""
    @State private var searching = false
    @State private var showingPrompts = false
    @State private var showingCreatePrompt = false
    @State private var showingArchive = false
    @State private var hoveredThread: UUID?
    @State private var deletingThread: ActionThread?
    @FocusState private var composerFocused: Bool
    private let canvas = Color(white: 0.092)
    private let muted = Color(white: 0.53)

    var body: some View {
        HStack(spacing: 0) {
            iconRail
            HStack(spacing: 0) {
                if section == .tasks { taskSidebar }
                Group {
                    if section == .tasks {
                        switch navigation.taskPage {
                        case .chat: taskContent
                        case .history: DictationHistoryView()
                        case .activity: ActivityCenterView()
                        case .coding: CodingTaskHistoryView()
                        }
                    }
                    else if section == .integrations { IntegrationsShellView() }
                    else if section == .memory { MemoryShellView() }
                    else if section == .connections {
                        ScrollView { ActionConnectionsView().padding(24).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                    else { AssistantSettingsView() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(section == .tasks ? canvas : Color(nsColor: .windowBackgroundColor))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .overlay(alignment: .leading) {
            if section == .tasks {
                sidebarDivider.offset(x: 56 + sidebarWidth - 4)
            }
        }
        .padding(.trailing, 6).padding(.bottom, 6)
        .background(ShellFrostedMaterial().ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingCreatePrompt) {
            CreatePromptView(initialText: assistant.draft,
                             contextText: [assistant.context?.text ?? "", assistant.attachments.textContext].filter { !$0.isEmpty }.joined(separator: "\n\n"),
                             images: [assistant.context?.image].compactMap { $0 } + assistant.attachments.images,
                             connection: assistant.connection, modelID: assistant.modelID, reasoningEffort: assistant.reasoningEffort) { text in
                assistant.draft = text; showingCreatePrompt = false; composerFocused = true
            }
        }
        .sheet(isPresented: $showingPrompts) {
            VStack(spacing: 0) {
                HStack { Spacer(); Button("Done") { showingPrompts = false }.buttonStyle(SpeekActionButtonStyle()) }.padding(16)
                PromptLibraryView { prompt in assistant.draft = prompt; showingPrompts = false; composerFocused = true }
            }.frame(minWidth: 680, idealWidth: 820, minHeight: 560)
        }
        .sheet(isPresented: $navigation.showingCodingTasks) {
            CodingTaskReviewView(initialRequest: navigation.codingRequest, initialDirectory: UserDefaults.standard.string(forKey: "speek.actions.projectFolder") ?? "", sourceThreadID: navigation.codingSource, images: navigation.codingImages, contextText: navigation.codingContext, initialConnection: navigation.codingConnection, initialModel: navigation.codingModel, initialReasoning: navigation.codingReasoning)
        }
        .onAppear {
            let initialSection = section
            if !assistant.hasConversation {
                if let thread = store.selectedThread { assistant.resume(thread, present: false) }
                else { newTask() }
            }
            section = initialSection
        }
    }

    private var iconRail: some View {
        VStack(spacing: 10) {
            railButton(.tasks)
            railButton(.memory)
            railButton(.connections)
            railButton(.integrations)
            Spacer()
            railButton(.settings)

        }
        // The shell adds 6 points below the rail: 3 + 6 matches the 9-point side inset.
        .padding(.top, 12).padding(.bottom, 3).frame(width: 56)
    }
    private func railButton(_ item: ShellSection) -> some View {
        Button {
            section = item
            railActivations[item.rawValue, default: 0] += 1
        } label: {
            ZStack {
                Image(systemName: section == item ? item.filledIcon : item.icon)
                    .font(.system(size: 18, weight: .regular))
                    .id(reduceMotion ? 0 : railActivations[item.rawValue, default: 0])
                    .transition(AsymmetricTransition(
                        insertion: .symbolEffect(.drawOn.byLayer),
                        removal: .identity
                    ))
            }
                .animation(reduceMotion ? nil : .default, value: railActivations[item.rawValue, default: 0])
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(section == item ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 11))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(ShellHoverButton()).help(item.rawValue).accessibilityLabel(item.rawValue)
    }

    private func sidebarDestination(_ title: String, icon: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15)).frame(width: 18)
                Text(title).font(.system(size: 15)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(ShellHoverButton())
            .background(selected ? Color.white.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .padding(.horizontal, 9)
    }

    private var taskSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Speek").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button { searching.toggle() } label: { Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .light)) }
                    .buttonStyle(.plain).foregroundStyle(.white).help("Find a task")
            }.padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 20)
            Button(action: newTask) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.pencil").frame(width: 18)
                    Text("New task")
                    Spacer(minLength: 0)
                }
                    .font(.system(size: 15)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(ShellHoverButton())
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 9)
            sidebarDestination("Activity and schedules", icon: "clock", selected: navigation.taskPage == .activity) { navigation.showActivity() }
                .padding(.top, 6)
            sidebarDestination("Dictation history", icon: "waveform", selected: navigation.taskPage == .history) { navigation.taskPage = .history }
            sidebarDestination("Coding tasks", icon: "terminal", selected: navigation.taskPage == .coding) { navigation.taskPage = .coding }
            if searching {
                TextField("Find a task", text: $search).textFieldStyle(.plain).font(.system(size: 15))
                    .padding(9).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 9).padding(.top, 10)
            }
            HStack {
                Text(showingArchive ? "Archived" : "Recents").font(.system(size: 13, weight: .medium)).foregroundStyle(muted)
                Spacer()
                Button { showingArchive.toggle() } label: {
                    Image(systemName: showingArchive ? "tray.fill" : "archivebox").foregroundStyle(.white)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).help(showingArchive ? "Show recent chats" : "Show archived chats")
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 20).padding(.trailing, 9)
            .padding(.top, 18).padding(.bottom, 4)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(visibleThreads) { thread in
                        HStack(spacing: 0) {
                            Button {
                                guard !assistant.busy && !assistant.recording else { return }
                                navigation.taskPage = .chat
                                store.selectedID = thread.id
                                assistant.resume(thread, present: false)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: thread.isPinned == true ? "pin.fill" : (store.selectedID == thread.id && navigation.taskPage == .chat) ? "bubble.left.fill" : "bubble.left")
                                        .font(.system(size: 15)).foregroundStyle(.white).frame(width: 18)
                                    Text(thread.title).font(.system(size: 15)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.padding(.leading, 11)
                                    .padding(.trailing, hoveredThread == thread.id ? 0 : 11)
                                    .padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if hoveredThread == thread.id {
                            Menu { threadActions(thread) } label: {
                                Image(systemName: "ellipsis").foregroundStyle(.white).frame(width: 26, height: 30)
                            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                .help("Chat actions").padding(.trailing, 4)
                            }
                        }
                        .background(store.selectedID == thread.id && navigation.taskPage == .chat ? Color.white.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle()).onHover { hoveredThread = $0 ? thread.id : nil }
                        .contextMenu { threadActions(thread) }
                    }
                    if visibleThreads.isEmpty {
                        Text(search.isEmpty ? (showingArchive ? "No archived chats" : "No chats yet") : "No matching chats")
                            .font(.system(size: 13)).foregroundStyle(muted).padding(.vertical, 20)
                    }
                }.padding(.horizontal, 9)
            }
            .alert("Delete chat?", isPresented: Binding(get: { deletingThread != nil }, set: { if !$0 { deletingThread = nil } })) {
                Button("Cancel", role: .cancel) { deletingThread = nil }
                Button("Delete", role: .destructive) {
                    if let thread = deletingThread { removeThread(thread, archive: false) }
                    deletingThread = nil
                }
            } message: { Text("This permanently deletes the chat and its messages. Project files are kept.") }

        }
        .frame(width: sidebarWidth)
        .background(.black.opacity(0.28))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.white.opacity(resizing || resizeOrigin != nil ? 0.38 : 0.08))
                .frame(width: 1 / displayScale)
                .animation(.easeOut(duration: 0.12), value: resizing || resizeOrigin != nil)
                .allowsHitTesting(false)
        }
    }

    private var visibleThreads: [ActionThread] {
        store.threads.filter {
            ($0.isArchived == true) == showingArchive && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }.sorted {
            if ($0.isPinned == true) != ($1.isPinned == true) { return $0.isPinned == true }
            return $0.updatedAt > $1.updatedAt
        }
    }

    @ViewBuilder private func threadActions(_ thread: ActionThread) -> some View {
        Button(thread.isPinned == true ? "Unpin chat" : "Pin chat", systemImage: "pin") {
            store.setPinned(thread.isPinned != true, for: thread.id)
        }
        Button(thread.isArchived == true ? "Restore chat" : "Archive chat", systemImage: "archivebox") {
            if thread.isArchived == true { store.setArchived(false, for: thread.id) }
            else { removeThread(thread, archive: true) }
        }.disabled(assistant.busy || assistant.recording)
        Divider()
        Button("Delete chat", systemImage: "trash", role: .destructive) { deletingThread = thread }
            .disabled(assistant.busy || assistant.recording)
    }

    private func removeThread(_ thread: ActionThread, archive: Bool) {
        guard !assistant.busy && !assistant.recording else { return }
        let wasSelected = store.selectedID == thread.id
        if archive { store.setArchived(true, for: thread.id) } else { store.delete(thread.id) }
        if wasSelected {
            if let next = store.selectedThread { assistant.resume(next, present: false) }
            else { assistant.newConversation() }
        }
    }

    private var sidebarDivider: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { inside in
                guard resizing != inside else { return }
                resizing = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if resizing { NSCursor.pop(); resizing = false }
                resizeOrigin = nil
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if resizeOrigin == nil { resizeOrigin = sidebarWidth }
                    sidebarWidth = min(380, max(180, (resizeOrigin ?? sidebarWidth) + value.translation.width))
                }
                .onEnded { _ in resizeOrigin = nil })
            .accessibilityLabel("Task list width")
            .accessibilityValue("\(Int(sidebarWidth)) points")
            .accessibilityAdjustableAction { direction in
                sidebarWidth = min(380, max(180, sidebarWidth + (direction == .increment ? 20 : -20)))
            }
            .help("Drag to resize the task list")
    }

    private var taskContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !assistant.visibleMessages.isEmpty {
                            ForEach(assistant.visibleMessages) { message in
                                VStack(alignment: .leading, spacing: 9) {
                                    Text(message.role == .user ? "You" : "Speek")
                                        .font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                                    Text((try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text)).font(.system(size: 14)).lineSpacing(5)
                                        .foregroundStyle(.white.opacity(0.86)).textSelection(.enabled)
                                }.frame(maxWidth: .infinity, alignment: .leading).id(message.id)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("What would you like to do?").font(.system(size: 27, weight: .medium))
                                Text("A request, a question, or something on your screen.")
                                    .font(.system(size: 13)).foregroundStyle(muted)
                            }.padding(.top, 110)
                        }
                        if assistant.busy || assistant.recording {
                            HStack(spacing: 9) {
                                ProgressView().controlSize(.small)
                                Text(assistant.phase).font(.system(size: 12)).foregroundStyle(muted)
                            }
                        }
                        if assistant.phase == "Needs attention" {
                            Text(assistant.response).font(.system(size: 12)).foregroundStyle(.orange)
                        }
                        if let proposal = assistant.proposal {
                            ActionReviewView(assistant: assistant, proposal: proposal)
                        }
                        ComputerTaskListView()
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 38).padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: store.selectedThread?.messages.count) { _, _ in scroll.scrollTo("bottom", anchor: .bottom) }
            }
            BackgroundTaskNoticeView(controller: assistant)
                .frame(maxWidth: 720).padding(.horizontal, 38).padding(.bottom, assistant.taskNotices.isEmpty ? 0 : 12)
            ComputerUseApprovalView()
            composer
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            ComposerAttachmentStrip(store: assistant.attachments)
            TextField("Ask Speek", text: $assistant.draft, axis: .vertical)
                .font(.system(size: 14)).lineLimit(2...6).textFieldStyle(.plain)
                .focused($composerFocused)
                .onSubmit { assistant.submit() }
                .padding(.top, 3)
            HStack(spacing: 14) {
                Button { contextMenuPresented.toggle() } label: {
                    Image(systemName: "plus").font(.system(size: 17)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Add context")
                    .popover(isPresented: $contextMenuPresented, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Button { contextMenuPresented = false; assistant.circleContext() } label: {
                                Label("Circle screen context", systemImage: "lasso")
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(8).contentShape(Rectangle())
                            }
                            Button { contextMenuPresented = false; assistant.attachments.chooseFiles() } label: {
                                Label("Attach files", systemImage: "paperclip").frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            }
                            Button {
                                let request = assistant.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                                TaskScheduler.shared.enqueue(title: String(request.prefix(80)), request: request, connection: assistant.connection, modelID: assistant.modelID, reasoningEffort: assistant.reasoningEffort)
                                assistant.draft = ""; contextMenuPresented = false; navigation.showActivity()
                            } label: {
                                Label("Run in background", systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            }.disabled(assistant.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !assistant.attachments.attachments.isEmpty || assistant.busy)
                            Button { contextMenuPresented = false; showingCreatePrompt = true } label: {
                                Label("Create prompt", systemImage: "text.badge.plus").frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            }.disabled(assistant.busy || assistant.recording || assistant.attachments.isImporting)
                            Button { contextMenuPresented = false; showingPrompts = true } label: {
                                Label("Saved prompts", systemImage: "text.book.closed").frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            }
                            if assistant.context != nil {
                                Button { assistant.context = nil; contextMenuPresented = false } label: {
                                    Label("Remove context", systemImage: "xmark")
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(8).contentShape(Rectangle())
                                }
                            }
                        }.buttonStyle(.plain).padding(6).frame(width: 210)
                    }
                if let context = assistant.context {
                    Label { Text(context.label) } icon: { Image(systemName: "macwindow").foregroundStyle(.white) }.font(.system(size: 11)).foregroundStyle(muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                AssistantModelPicker(assistant: assistant) { section = .connections }
                Button { assistant.toggleVoice(present: false) } label: {
                    Image(systemName: assistant.recording ? "stop.circle.fill" : "mic").font(.system(size: 16)).foregroundStyle(.white)
                        .symbolEffect(.breathe, isActive: assistant.recording && !reduceMotion)
                        .frame(width: 28, height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).help(assistant.recording ? "Finish speaking" : "Voice input").disabled(assistant.busy)
                Button { if assistant.busy { assistant.cancel() } else { assistant.submit() } } label: {
                    Image(systemName: assistant.busy ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(.white.opacity(0.12), in: Circle())
                }.buttonStyle(.plain).help(assistant.busy ? "Stop" : "Send")
                    .disabled(!assistant.busy && (assistant.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistant.recording))
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !assistant.busy && !assistant.recording else { return false }
            assistant.attachments.add(urls: urls); return true
        }
        .padding(16).background(Color(white: 0.19), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.035)))
        .frame(maxWidth: 720).padding(.horizontal, 30).padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    private func newTask() {
        guard !assistant.busy && !assistant.recording else { return }
        section = .tasks
        navigation.taskPage = .chat
        showingArchive = false
        search = ""
        assistant.newConversation()
        let id = store.newThread()
        if let thread = store.threads.first(where: { $0.id == id }) { assistant.resume(thread, present: false) }
        composerFocused = true
    }
}

private struct ShellHoverButton: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.08 : hovered ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 8))
            .onHover { hovered = $0 }
    }
}

// One native material spans the title area, rail, and outer window frame.
private struct ShellFrostedMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

