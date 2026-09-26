import SwiftUI
import AppKit

private enum IntegrationSheet: Identifiable {
    case editor(MCPPlugin?), plugin(UUID), skill(UUID)
    var id: String {
        switch self {
        case .editor(let plugin): return "edit-" + (plugin?.id.uuidString ?? "new")
        case .plugin(let id): return "plugin-" + id.uuidString
        case .skill(let id): return "skill-" + id.uuidString
        }
    }
}

struct IntegrationsShellView: View {
    @ObservedObject private var store = IntegrationStore.shared
    @State private var tab = "Plugins"
    @State private var sheet: IntegrationSheet?
    @State private var error: String?
    @State private var removing: MCPPlugin?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Integrations").font(.system(size: 25, weight: .semibold))
                    Text("Extend Speek with tools and skills.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                PillTabs(items: ["Plugins", "Native apps", "Local tools", "Skills"], selection: $tab)
                if let message = error ?? store.storageError {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                switch tab {
                case "Native apps": NativeAppsIntegrationView()
                case "Local tools":
                    VStack(alignment: .leading, spacing: 28) {
                        CodingIntegrationSettingsView()
                        LocalPluginSettingsView()
                    }
                case "Skills": skills
                default: plugins
                }
            }.frame(maxWidth: 880, alignment: .leading)
                .padding(.vertical, 12).padding(24).frame(maxWidth: .infinity)
        }
        .task { await store.restoreEnabledConnections() }
        .sheet(item: $sheet) { selection in
            switch selection {
            case .editor(let plugin): MCPPluginEditor(plugin: plugin, store: store)
            case .plugin(let id): MCPPluginDetail(pluginID: id, store: store) { plugin in sheet = .editor(plugin) }
            case .skill(let id): LocalSkillDetail(skillID: id, store: store)
            }
        }
        .alert("Remove plugin?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Cancel", role: .cancel) { removing = nil }
            Button("Remove", role: .destructive) {
                if let removing { perform { try store.remove(pluginID: removing.id) } }
                removing = nil
            }
        } message: { Text("This disconnects the server and removes its saved credentials. The server itself is not deleted.") }
    }

    private var plugins: some View {
        VStack(alignment: .leading, spacing: 16) {
            IntegrationSectionHeader(title: "MCP servers", info: "Remote services or tools running on this Mac. Their tools become available to the agent; actions still wait for your review.") {
                Button { sheet = .editor(nil) } label: { Label("Add plugin", systemImage: "plus") }
                    .buttonStyle(SpeekActionButtonStyle()).fixedSize().disabled(store.storageError != nil)
            }
            if store.plugins.isEmpty {
                IntegrationEmptyTile(symbol: "server.rack", title: "No plugins yet", text: "Add an MCP server to give Speek new tools.")
            } else {
                LazyVGrid(columns: IntegrationTile<EmptyView, EmptyView>.columns, alignment: .leading, spacing: 16) {
                    ForEach(store.plugins) { plugin in pluginTile(plugin) }
                }
            }
        }
    }

    private var skills: some View {
        VStack(alignment: .leading, spacing: 16) {
            IntegrationSectionHeader(title: "Skill library", info: "Enabled skills guide matching requests. Instructions are copied on import; scripts are never run. Reimport a skill to update it.") {
                Button { importSkill() } label: { Label("Import skill", systemImage: "plus") }
                    .buttonStyle(SpeekActionButtonStyle()).fixedSize().disabled(store.storageError != nil)
            }
            if store.skills.isEmpty {
                IntegrationEmptyTile(symbol: "book.closed", title: "No skills yet", text: "Import a SKILL.md file to teach Speek a workflow.")
            } else {
                LazyVGrid(columns: IntegrationTile<EmptyView, EmptyView>.columns, alignment: .leading, spacing: 16) {
                    ForEach(store.skills) { skill in
                        IntegrationTile(symbol: "book.closed", title: skill.name, subtitle: skill.summary,
                                        status: skill.enabled ? "Enabled" : "Off", statusSymbol: skill.enabled ? "checkmark.circle.fill" : "circle",
                                        open: { sheet = .skill(skill.id) }) {
                            Toggle("Enable " + skill.name, isOn: Binding(get: { skill.enabled }, set: { enabled in
                                perform { try store.setSkillEnabled(id: skill.id, enabled: enabled) }
                            })).labelsHidden().toggleStyle(.switch)
                        } menu: {
                            Button("Details") { sheet = .skill(skill.id) }
                            Divider()
                            Button("Remove", role: .destructive) { perform { try store.removeSkill(id: skill.id) } }
                        }
                    }
                }
            }
        }
    }

    private func pluginTile(_ plugin: MCPPlugin) -> some View {
        let state = store.state(for: plugin.id)
        var busy = false
        if case .connecting = state { busy = true }
        let location = plugin.transport == .http ? (URL(string: plugin.endpoint)?.host ?? plugin.endpoint) : (plugin.executable as NSString).lastPathComponent
        return IntegrationTile(symbol: plugin.transport == .http ? "server.rack" : "terminal", title: plugin.name,
                               subtitle: location.isEmpty ? plugin.transport.title : plugin.transport.title + ", " + location,
                               status: state.label, statusSymbol: stateSymbol(state), busy: busy,
                               open: { sheet = .plugin(plugin.id) }) {
            if case .connecting = state {
                Button("Cancel") { store.disconnect(pluginID: plugin.id) }.buttonStyle(SpeekActionButtonStyle())
            } else if case .connected = state {
                Button("Manage") { sheet = .plugin(plugin.id) }.buttonStyle(SpeekActionButtonStyle())
            } else {
                Button("Connect") { connect(plugin) }.buttonStyle(SpeekActionButtonStyle())
            }
        } menu: {
            Button("Details") { sheet = .plugin(plugin.id) }
            Button("Edit") { sheet = .editor(plugin) }
            Divider()
            Button("Remove", role: .destructive) { removing = plugin }
        }
    }

    private func stateSymbol(_ state: IntegrationStore.ConnectionState) -> String {
        switch state { case .connected: return "checkmark.circle.fill"; case .failed: return "exclamationmark.circle"; default: return "circle" }
    }
    private func connect(_ plugin: MCPPlugin) {
        error = nil
        Task { do { try await store.connect(pluginID: plugin.id) } catch { self.error = IntegrationStore.safeError(error) } }
    }
    private func perform(_ work: () throws -> Void) { do { try work(); error = nil } catch { self.error = IntegrationStore.safeError(error) } }
    private func importSkill() {
        let panel = NSOpenPanel()
        panel.title = "Import skill"
        panel.message = "Choose SKILL.md or its folder. Instructions are copied; scripts are not run."
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            perform { try store.importSkill(from: url) }
        }
    }
}

private struct MCPPluginEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: IntegrationStore
    @State private var draft: MCPPlugin
    @State private var arguments: String
    @State private var replaceCredentials: Bool
    @State private var token = ""
    @State private var environment: [EnvironmentEntry] = []
    @State private var error: String?
    @State private var connecting = false
    @State private var connectionTask: Task<Void, Never>?
    let isNew: Bool
    private struct EnvironmentEntry: Identifiable { var id = UUID(); var key = ""; var value = "" }

    init(plugin: MCPPlugin?, store: IntegrationStore) {
        self.store = store
        isNew = plugin == nil
        _draft = State(initialValue: plugin ?? MCPPlugin(name: ""))
        _arguments = State(initialValue: plugin?.arguments.joined(separator: "\n") ?? "")
        _replaceCredentials = State(initialValue: plugin == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isNew ? "Add plugin" : "Edit plugin").font(.system(size: 20, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Name") { TextField("My server", text: $draft.name) }
                    field("Connection") {
                        Picker("Connection", selection: $draft.transport) {
                            ForEach(MCPPlugin.Transport.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    if draft.transport == .http {
                        field("Server address") { TextField("https://example.com/mcp", text: $draft.endpoint) }
                        Text("Use a Streamable HTTP MCP endpoint. Tokens stay in Keychain.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        field("Executable") {
                            HStack {
                                TextField("/absolute/path/to/server", text: $draft.executable)
                                Button("Choose") { chooseExecutable() }.buttonStyle(SpeekActionButtonStyle())
                            }
                        }
                        field("Arguments, one per line") {
                            TextEditor(text: $arguments).font(.system(size: 12, design: .monospaced)).frame(height: 76)
                                .padding(6).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        }
                        field("Working folder, optional") { TextField("Use the default folder", text: $draft.workingDirectory) }
                        Text("Speek runs this executable directly. It does not use a shell. Only connect local tools you trust.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if !isNew { Toggle("Replace saved credentials", isOn: $replaceCredentials).font(.system(size: 13)) }
                    if replaceCredentials {
                        if draft.transport == .http {
                            field("Bearer token, optional") { SecureField("Token", text: $token) }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Environment variables").font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Button { environment.append(EnvironmentEntry()) } label: { Label("Add", systemImage: "plus") }
                                        .buttonStyle(SpeekActionButtonStyle())
                                }
                                ForEach($environment) { $entry in
                                    HStack(spacing: 8) {
                                        TextField("NAME", text: $entry.key).frame(maxWidth: 150)
                                        SecureField("Value", text: $entry.value)
                                        Button { environment.removeAll { $0.id == entry.id } } label: { Image(systemName: "minus.circle").frame(width: 24, height: 24) }
                                            .buttonStyle(.plain).help("Remove variable")
                                    }
                                }
                                Text("Values are saved in Keychain. Replacing credentials replaces all saved variables.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    } else { Text("Saved credentials will be kept.").font(.system(size: 11)).foregroundStyle(.secondary) }
                    Text("Connecting lists the server's tools. Running an action requires a separate review.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.disabled(connecting).textFieldStyle(.roundedBorder).padding(.trailing, 2)
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 10) {
                if connecting { ProgressView().controlSize(.small); Text("Connecting").font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") {
                    connectionTask?.cancel()
                    if connecting { store.disconnect(pluginID: draft.id) }
                    dismiss()
                }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save and connect") { save() }.buttonStyle(SpeekActionButtonStyle())
                    .keyboardShortcut(.defaultAction).disabled(connecting || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(24).frame(width: 500, height: 600).interactiveDismissDisabled(connecting)
            .onDisappear { connectionTask?.cancel() }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(label).font(.system(size: 13, weight: .medium)); content() }
    }
    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.begin { if $0 == .OK, let url = panel.url { draft.executable = url.path } }
    }
    private func save() {
        error = nil
        draft.endpoint = draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.executable = draft.executable.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.arguments = arguments.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var variables: [String: String] = [:]
        for entry in environment {
            let key = entry.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !key.contains("="), !key.contains("\0"), variables[key] == nil else {
                error = "Each environment variable needs a unique name without '='."; return
            }
            variables[key] = entry.value
        }
        do {
            try store.save(draft, bearerToken: replaceCredentials ? token : nil, environment: replaceCredentials ? variables : nil)
        } catch { self.error = IntegrationStore.safeError(error); return }
        connecting = true
        connectionTask = Task {
            do { try await store.connect(pluginID: draft.id); connecting = false; dismiss() }
            catch { connecting = false; self.error = IntegrationStore.safeError(error) }
        }
    }
}

private struct MCPPluginDetail: View {
    let pluginID: UUID
    @ObservedObject var store: IntegrationStore
    var onEdit: (MCPPlugin) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    private var plugin: MCPPlugin? { store.plugins.first { $0.id == pluginID } }
    private var tools: [IntegrationTool] { store.tools.filter { $0.pluginID == pluginID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plugin?.name ?? "Plugin").font(.system(size: 20, weight: .semibold))
                    Text(store.state(for: pluginID).label).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if let plugin { Button("Edit") { onEdit(plugin) }.buttonStyle(SpeekActionButtonStyle()) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let plugin {
                        Text(plugin.transport == .http ? plugin.endpoint : plugin.executable)
                            .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if case .failed(let message) = store.state(for: pluginID) { Text(message).font(.system(size: 12)).foregroundStyle(.secondary) }
                    Text("Available tools").font(.system(size: 13, weight: .semibold))
                    if tools.isEmpty {
                        Text("Connect this server to discover its tools.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    ForEach(tools) { tool in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: Binding(get: { !(plugin?.disabledTools.contains(tool.name) ?? true) }, set: { enabled in
                                do { try store.setToolEnabled(tool, enabled: enabled) } catch { self.error = IntegrationStore.safeError(error) }
                            })) { Text(tool.title).font(.system(size: 13, weight: .medium)) }
                                .toggleStyle(.switch).controlSize(.small)
                            if !tool.description.isEmpty { Text(tool.description).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                            DisclosureGroup("Input fields") {
                                Text(tool.inputSchema.jsonString).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            }.font(.system(size: 11)).foregroundStyle(.secondary)
                        }.padding(16).settingsSurface()
                    }
                }
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.secondary) }
            HStack {
                if case .connected = store.state(for: pluginID) {
                    Button("Disconnect") { store.disconnect(pluginID: pluginID) }.buttonStyle(SpeekActionButtonStyle())
                }
                Spacer()
                Button("Test connection") {
                    Task { do { try await store.connect(pluginID: pluginID); error = nil } catch { self.error = IntegrationStore.safeError(error) } }
                }.buttonStyle(SpeekActionButtonStyle()).disabled(store.state(for: pluginID) == .connecting)
                Button("Done") { dismiss() }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520, height: 540)
    }
}

private struct LocalSkillDetail: View {
    let skillID: UUID
    @ObservedObject var store: IntegrationStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var confirmRemoval = false
    private var skill: LocalSkill? { store.skills.first { $0.id == skillID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(skill?.name ?? "Skill").font(.system(size: 20, weight: .semibold))
            if let skill {
                Text(skill.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                ScrollView { Text(skill.instructions).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .padding(16).settingsSurface()
                Text("Imported \(skill.importedAt.formatted(date: .abbreviated, time: .shortened)). Supporting scripts are not executed.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.secondary) }
            HStack {
                Button("Remove") { confirmRemoval = true }.buttonStyle(SpeekActionButtonStyle())
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520, height: 540)
            .alert("Remove skill?", isPresented: $confirmRemoval) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    do { try store.removeSkill(id: skillID); dismiss() } catch { self.error = IntegrationStore.safeError(error) }
                }
            } message: { Text("This removes Speek's saved copy. Your original file is kept.") }
    }
}
