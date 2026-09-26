import SwiftUI
import AppKit

struct CodingTaskReviewView: View {
    @ObservedObject private var manager = CodingTaskManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var request: String
    @State private var directory: String
    @State private var engine = CodingTaskJob.Engine.codex
    @State private var connection = ActionConnection.localCodex
    @State private var model = ""
    @State private var reasoning = ""
    @State private var resumeSession: String?
    @State private var models: [AssistantModelOption] = []
    @State private var error: String?
    @State private var acknowledged = false
    @State private var sourceThreadID: UUID?
    @State private var images: [Data]
    @State private var contextText: String?

    init(initialRequest: String = "", initialDirectory: String = "", sourceThreadID: UUID? = nil, images: [Data] = [], contextText: String? = nil, initialConnection: ActionConnection = .localCodex, initialModel: String? = nil, initialReasoning: String? = nil, resuming: CodingTaskJob? = nil) {
        _request = State(initialValue: initialRequest)
        _directory = State(initialValue: resuming?.directory ?? initialDirectory)
        _sourceThreadID = State(initialValue: resuming?.sourceThreadID ?? sourceThreadID)
        _images = State(initialValue: images)
        _contextText = State(initialValue: contextText)
        _engine = State(initialValue: resuming?.engine ?? CodingTaskJob.Engine.allCases.first(where: { CodingIntegrationPreferences.isEnabled($0) && CodingTaskManager.binary(for: $0) != nil }) ?? .codex)
        _resumeSession = State(initialValue: resuming?.sessionID)
        _connection = State(initialValue: resuming?.connection ?? (initialConnection == .openRouter ? .localCodex : initialConnection))
        _model = State(initialValue: resuming?.model ?? initialModel ?? "")
        _reasoning = State(initialValue: resuming?.reasoning ?? initialReasoning ?? "")
    }

    var body: some View { editor }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(resumeSession == nil ? "Review integration request" : "Continue integration request").font(.system(size: 20, weight: .semibold))
            Text("Review the project and permissions before starting.").font(.system(size: 13)).foregroundStyle(.secondary)
            if !CodingIntegrationPreferences.isEnabled(engine) {
                Text("Enable " + engine.title + " in Integrations to use it.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Text("Integration"); Spacer()
                Picker("Engine", selection: $engine) { ForEach(CodingTaskJob.Engine.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().fixedSize().disabled(resumeSession != nil)
            }
            if engine == .codex {
                HStack {
                    Text("Connection"); Spacer()
                    Picker("Connection", selection: $connection) {
                        Text("Codex on this Mac").tag(ActionConnection.localCodex)
                        Text("ChatGPT subscription").tag(ActionConnection.subscription)
                    }.labelsHidden().fixedSize().disabled(resumeSession != nil)
                }
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project folder")
                    Text(directory.isEmpty ? "Choose where this agent may work." : directory)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Button("Choose folder") { chooseFolder() }.buttonStyle(SpeekActionButtonStyle()).disabled(resumeSession != nil)
            }
            HStack {
                Text("Model"); Spacer()
                Picker("Model", selection: $model) {
                    Text(engine == .codex ? "Saved default" : "CLI default").tag("")
                    if engine == .codex {
                        ForEach(models) { option in Text(option.name).tag(option.id) }
                        if !model.isEmpty && !models.contains(where: { $0.id == model }) { Text(model).tag(model) }
                    } else {
                        Text("Fable").tag("fable"); Text("Opus").tag("opus"); Text("Sonnet").tag("sonnet")
                        if !model.isEmpty && !["fable", "opus", "sonnet"].contains(model) { Text(model).tag(model) }
                    }
                }.labelsHidden().frame(maxWidth: 230, alignment: .trailing).fixedSize()
            }
            HStack {
                Text("Reasoning"); Spacer()
                Picker("Reasoning", selection: $reasoning) {
                    Text("Model default").tag("")
                    ForEach(efforts, id: \.self) { Text($0.capitalized).tag($0) }
                }.labelsHidden().fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Request").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                TextEditor(text: $request).font(.system(size: 13)).frame(height: 115)
                    .padding(8).background(.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            if !images.isEmpty {
                Label("\(images.count) attached image\(images.count == 1 ? "" : "s")", systemImage: "photo")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if engine == .claude { Text("Choose Codex to include these images.").font(.system(size: 11)).foregroundStyle(.red) }
            }
            Text(engine == .codex
                 ? "Codex can read files and edit within the selected workspace. It runs in the workspace-write sandbox; commands needing additional permission are denied."
                 : "Claude Code may edit files in this project without asking again. Its normal permission system remains active; operations needing additional permission are denied. Custom hooks and plugins are disabled.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Allow this coding task to edit the selected project", isOn: $acknowledged).toggleStyle(.checkbox)
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Start task") {
                    do {
                        guard CodingIntegrationPreferences.isEnabled(engine) else {
                            error = "Enable " + engine.title + " in Integrations first."
                            return
                        }
                        try manager.enqueue(request: request, directory: directory, engine: engine, connection: connection, model: model.isEmpty ? nil : model, reasoning: reasoning.isEmpty ? nil : reasoning, sessionID: resumeSession, sourceThreadID: sourceThreadID, images: images, contextText: contextText, approved: acknowledged)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(SpeekActionButtonStyle()).disabled(!CodingIntegrationPreferences.isEnabled(engine) || !acknowledged || directory.isEmpty || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.font(.system(size: 13)).padding(24).frame(width: 520)
            .task(id: connection) { models = (try? await AssistantModelCatalog.load(connection: connection)) ?? [] }
            .onChange(of: engine) { _, _ in model = ""; reasoning = ""; acknowledged = false }
            .onChange(of: model) { _, _ in reasoning = ""; acknowledged = false }
            .onChange(of: request) { _, _ in acknowledged = false }
            .onChange(of: directory) { _, _ in acknowledged = false }
    }

    private var efforts: [String] {
        if engine == .claude { return ["low", "medium", "high", "xhigh", "max"] }
        let actual = model.isEmpty ? AgentDefaults.model(for: connection) : model
        return models.first(where: { $0.id == actual })?.efforts ?? []
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.title = "Choose project"; panel.canChooseFiles = false
        panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.begin { response in if response == .OK, let url = panel.url { directory = url.path } }
    }
}
