import SwiftUI
import AppKit

private enum IntegrationSheet: Identifiable {
    case editor(MCPPlugin?), template(MCPDirectoryEntry), plugin(UUID), skill(UUID)
    var id: String {
        switch self {
        case .editor(let plugin): return "edit-" + (plugin?.id.uuidString ?? "new")
        case .template(let entry): return "template-" + entry.id
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
                        CodingAgentHooksView()
                        SettingsSection(title: "Shell") {
                            SettingsRow(title: "Run shell commands", image: AppIcon.image(for: "com.apple.Terminal"),
                                        info: "Speek can run commands in your login shell, including command-line tools that skills describe. Commands can change anything your account can.") {
                                ToolPolicyMenu(toolID: ShellTool.id, changesData: true, title: "Run shell commands")
                            }
                        }
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
            case .template(let entry): MCPPluginEditor(plugin: nil, store: store, template: entry)
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
                IntegrationEmptyTile(symbol: "server.rack", title: "No plugins yet", text: "Add one from the directory below, or add any MCP server.")
            } else {
                LazyVGrid(columns: IntegrationTile<EmptyView, EmptyView>.columns, alignment: .leading, spacing: 16) {
                    ForEach(store.plugins) { plugin in pluginTile(plugin) }
                }
            }
            let suggestions = directorySuggestions
            if !suggestions.isEmpty {
                IntegrationSectionHeader(title: "Directory", info: "Hosted servers you can add in one step. Gmail and Google Calendar use your own Google Cloud OAuth client. Outlook and Slack only let pre-approved apps sign in, so they connect through Composio, which asks you to link each app the first time it is used.")
                    .padding(.top, 12)
                LazyVGrid(columns: IntegrationTile<EmptyView, EmptyView>.columns, alignment: .leading, spacing: 16) {
                    ForEach(suggestions) { entry in
                        IntegrationTile(symbol: "server.rack", asset: entry.logo, title: entry.name, subtitle: entry.summary,
                                        status: entry.accessLabel, statusSymbol: entry.access == .signIn ? "person.crop.circle" : entry.access == .viaComposio ? "link" : "key.fill",
                                        showsMenu: false, open: { add(entry) }) {
                            Button("Add") { add(entry) }.buttonStyle(SpeekActionButtonStyle())
                        } menu: { EmptyView() }
                    }
                }
            }
        }
    }

    /// Directory entries not added yet. Composio-backed apps disappear once Composio is added.
    private var directorySuggestions: [MCPDirectoryEntry] {
        let added = Set(store.plugins.compactMap(\.directoryID))
        let hasComposio = added.contains(MCPDirectoryEntry.composio.id)
        return MCPDirectoryEntry.all.filter { entry in
            !added.contains(entry.id) && !(entry.access == .viaComposio && hasComposio)
        }
    }

    private func add(_ entry: MCPDirectoryEntry) {
        switch entry.access {
        case .token, .ownClient: sheet = .template(entry); return
        default: break
        }
        let target = entry.access == .viaComposio ? MCPDirectoryEntry.composio : entry
        if let existing = store.plugins.first(where: { $0.directoryID == target.id }) { connect(existing); return }
        let plugin = target.plugin
        perform { try store.save(plugin) }
        connect(plugin)
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
        if case .signingIn = state { busy = true }
        let location = plugin.transport == .http ? (URL(string: plugin.endpoint)?.host ?? plugin.endpoint) : (plugin.executable as NSString).lastPathComponent
        return IntegrationTile(symbol: plugin.transport == .http ? "server.rack" : "terminal", asset: MCPDirectoryEntry.logo(for: plugin), title: plugin.name,
                               subtitle: location.isEmpty ? plugin.transport.title : plugin.transport.title + ", " + location,
                               status: state.label, statusSymbol: stateSymbol(state), busy: busy,
                               open: { sheet = .plugin(plugin.id) }) {
            if busy {
                Button("Cancel") { store.disconnect(pluginID: plugin.id) }.buttonStyle(SpeekActionButtonStyle())
            } else if case .connected = state {
                Button("Manage") { sheet = .plugin(plugin.id) }.buttonStyle(SpeekActionButtonStyle())
            } else if case .failed(let message) = state, message.hasPrefix("Sign-in required") {
                Button("Sign In") { connect(plugin) }.buttonStyle(SpeekActionButtonStyle())
            } else {
                Button("Connect") { connect(plugin) }.buttonStyle(SpeekActionButtonStyle())
            }
        } menu: {
            Button("Details") { sheet = .plugin(plugin.id) }
            Button("Edit") { sheet = .editor(plugin) }
            if store.hasSignIn(plugin.id) { Button("Sign Out") { store.signOut(pluginID: plugin.id) } }
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
    let template: MCPDirectoryEntry?
    private struct EnvironmentEntry: Identifiable { var id = UUID(); var key = ""; var value = "" }

    init(plugin: MCPPlugin?, store: IntegrationStore, template: MCPDirectoryEntry? = nil) {
        self.store = store
        self.template = template
        isNew = plugin == nil
        _draft = State(initialValue: plugin ?? template?.plugin ?? MCPPlugin(name: ""))
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
                        Text("Leave the token empty to sign in with your account when you connect. Tokens stay in Keychain.")
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
                    if draft.transport == .http {
                        if case .ownClient(_, let help)? = template?.access {
                            field("OAuth client ID") { TextField("From your Google Cloud project", text: clientID) }
                            field("Client secret") { SecureField("Client secret", text: clientSecret) }
                            Link("How to create a Google OAuth client", destination: help).font(.system(size: 12))
                        } else {
                            DisclosureGroup("Advanced sign-in") {
                                VStack(alignment: .leading, spacing: 12) {
                                    field("OAuth client ID, optional") { TextField("For servers without self-registration", text: clientID) }
                                    field("Client secret, optional") { SecureField("Client secret", text: clientSecret) }
                                    field("Scopes, optional") { TextField("Space-separated", text: scopes) }
                                    field("Token command, optional") { TextField("Such as gh auth token", text: tokenCommand) }
                                }.padding(.top, 8)
                            }.font(.system(size: 13))
                        }
                    }
                    if !isNew { Toggle("Replace saved credentials", isOn: $replaceCredentials).font(.system(size: 13)) }
                    if replaceCredentials {
                        if draft.transport == .http {
                            if case .token(let label, let help)? = template?.access {
                                field(label) { SecureField("Paste the token", text: $token) }
                                Link("Create a token on " + (help.host ?? "the website"), destination: help).font(.system(size: 12))
                            } else {
                                field("Bearer token, optional") { SecureField("Token", text: $token) }
                            }
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
    private func optional(_ keyPath: WritableKeyPath<MCPPlugin, String?>) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] ?? "" }, set: { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            draft[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
        })
    }
    private var clientID: Binding<String> { optional(\.oauthClientID) }
    private var clientSecret: Binding<String> { optional(\.oauthClientSecret) }
    private var scopes: Binding<String> { optional(\.oauthScopes) }
    private var tokenCommand: Binding<String> { optional(\.tokenCommand) }
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
                    HStack(spacing: 6) {
                        Text("Available tools").font(.system(size: 13, weight: .semibold))
                        InfoButton(text: "Choose when Speek asks before using each tool. Never hides the tool from Speek. Read-only labels come from the server.", subject: "Available tools")
                        Spacer(minLength: 8)
                        ToolPolicySetAllMenu(tools: tools.map { ToolPolicyEntry(id: $0.id, title: $0.title, summary: $0.description, changesData: !$0.readOnly) })
                    }
                    if tools.isEmpty {
                        Text("Connect this server to discover its tools.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    ForEach(tools) { tool in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Text(tool.title).font(.system(size: 13, weight: .medium))
                                if tool.readOnly { Text("Read only").font(.system(size: 11)).foregroundStyle(.secondary) }
                                Spacer(minLength: 8)
                                ToolPolicyMenu(toolID: tool.id, changesData: !tool.readOnly, title: tool.title)
                            }
                            if !tool.description.isEmpty { Text(tool.description).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                            DisclosureGroup("Input fields") {
                                Text(tool.inputSchema.jsonString).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            }.font(.system(size: 11)).foregroundStyle(.secondary)
                        }.padding(16).settingsSurface()
                    }
                    MCPPluginExtras(pluginID: pluginID, store: store) { dismiss() }
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

/// A plugin's prompts (use one as a request) and resources (attach one to the next request).
private struct MCPPluginExtras: View {
    let pluginID: UUID
    @ObservedObject var store: IntegrationStore
    let close: () -> Void
    @State private var resources: [MCPResourceInfo]?
    @State private var loading = false
    @State private var openPrompt: String?
    @State private var values: [String: String] = [:]
    @State private var message: String?

    private var hasResources: Bool { store.tools.contains { $0.pluginID == pluginID && $0.name == IntegrationStore.listResourcesTool } }

    var body: some View {
        let prompts = store.prompts[pluginID] ?? []
        if !prompts.isEmpty {
            HStack(spacing: 6) {
                Text("Prompts").font(.system(size: 13, weight: .semibold))
                InfoButton(text: "Ready-made requests from this plugin. Use one to put it in the composer.", subject: "Prompts")
            }.padding(.top, 8)
            VStack(spacing: 0) {
                ForEach(prompts) { prompt in
                    if prompt.id != prompts.first?.id { SettingsRowDivider() }
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsRow(title: prompt.title, info: prompt.detail) {
                            Button(openPrompt == prompt.id ? "Cancel" : "Use") {
                                if prompt.arguments.isEmpty { use(prompt) } else { openPrompt = openPrompt == prompt.id ? nil : prompt.id; values = [:] }
                            }.buttonStyle(SpeekActionButtonStyle())
                        }
                        if openPrompt == prompt.id {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(prompt.arguments, id: \.name) { argument in
                                    TextField(argument.name + (argument.required ? "" : " (optional)"), text: Binding(get: { values[argument.name] ?? "" }, set: { values[argument.name] = $0 }))
                                        .textFieldStyle(.roundedBorder).help(argument.detail ?? "")
                                }
                                HStack { Spacer(); Button("Use prompt") { use(prompt) }.buttonStyle(SpeekActionButtonStyle())
                                    .disabled(prompt.arguments.contains { $0.required && (values[$0.name] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }) }
                            }.padding(.horizontal, 16).padding(.bottom, 12)
                        }
                    }
                }
            }.settingsSurface()
        }
        if hasResources {
            HStack(spacing: 6) {
                Text("Resources").font(.system(size: 13, weight: .semibold))
                InfoButton(text: "Documents and data this plugin shares. Attach one to include it with your next request. Speek can also read them on its own when a request needs them.", subject: "Resources")
                Spacer()
                if resources == nil { Button(loading ? "Loading" : "Browse") { load() }.buttonStyle(SpeekActionButtonStyle()).disabled(loading) }
            }.padding(.top, 8)
            if let resources {
                VStack(spacing: 0) {
                    if resources.isEmpty { Text("No resources.").font(.system(size: 12)).foregroundStyle(.secondary).padding(16) }
                    ForEach(resources.prefix(100)) { resource in
                        if resource.id != resources.first?.id { SettingsRowDivider() }
                        SettingsRow(title: resource.name, value: resource.uri, info: resource.detail) {
                            Button("Attach") { attach(resource) }.buttonStyle(SpeekActionButtonStyle())
                        }
                    }
                }.settingsSurface()
            }
        }
        if let message { Text(message).font(.system(size: 12)).foregroundStyle(.secondary) }
    }

    private func load() {
        loading = true
        Task { do { resources = try await store.listResources(pluginID: pluginID) } catch { message = IntegrationStore.safeError(error) }; loading = false }
    }

    private func attach(_ resource: MCPResourceInfo) {
        Task {
            do {
                let text = try await store.readResource(pluginID: pluginID, uri: resource.uri)
                AssistantController.shared.attachments.addText(name: resource.name, text: text)
                message = "Attached " + resource.name + " to your next request."
            } catch { message = IntegrationStore.safeError(error) }
        }
    }

    private func use(_ prompt: MCPPromptInfo) {
        Task {
            do {
                let text = try await store.prompt(prompt, arguments: values.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty })
                AssistantController.shared.draft = text
                SpeekMainWindow.shared.showSection(.tasks)
                close()
            } catch { message = IntegrationStore.safeError(error) }
        }
    }
}
