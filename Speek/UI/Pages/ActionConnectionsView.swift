import SwiftUI

struct ActionConnectionsView: View {
    @ObservedObject private var codex = CodexConnection.shared
    @AppStorage("speek.actions.connection") private var preferred = ActionConnection.localCodex.rawValue
    @AppStorage("speek.actions.voiceProvider") private var voice = ActionCloudProvider.openRouter.rawValue
    @AppStorage("speek.assistant.readReplies") private var readReplies = false
    @State private var expanded: ActionConnection?
    @State private var voiceExpanded = false
    @State private var chatExpanded = true
    @State private var defaultModel = AgentDefaults.model(for: .preferred)
    @State private var defaultReasoning = AgentDefaults.reasoning(for: .preferred) ?? "default"
    @State private var chatModels: [AssistantModelOption] = []
    @State private var modelsLoading = false
    @State private var modelsError: String?
    @State private var key = ""
    @State private var connected = ActionCredentials.hasKey(for: .openRouter)
    @State private var message: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Models & Voice").font(.system(size: 25, weight: .semibold))
                Text("Choose what powers Speek.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Accounts").font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
                VStack(spacing: 0) {
                    ForEach(ActionConnection.allCases) { connection in
                        account(connection)
                        if connection != ActionConnection.allCases.last { Divider().padding(.leading, 60) }
                    }
                }.settingsSurface()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Defaults").font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
                VStack(spacing: 0) {
                    Button {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { chatExpanded.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bubble.left.fill").foregroundStyle(.white).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("New chats").font(.system(size: 13, weight: .medium))
                                Text(defaultConnection.title).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
                                .rotationEffect(.degrees(chatExpanded ? 90 : 0))
                        }.padding(16).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if chatExpanded { chatSettings.padding(.horizontal, 16).padding(.bottom, 16) }
                    Divider().padding(.horizontal, 16)
                    Button {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { voiceExpanded.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform").foregroundStyle(.white).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Voice").font(.system(size: 13, weight: .medium))
                                Text(voice == ActionCloudProvider.openRouter.rawValue ? "OpenRouter" : "OpenAI API").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
                                .rotationEffect(.degrees(voiceExpanded ? 90 : 0))
                        }.padding(16).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if voiceExpanded { voiceSettings.padding(.horizontal, 16).padding(.bottom, 16) }
                }.settingsSurface()
            }
            Text("ChatGPT covers agent requests. Dictation and spoken replies use a separate voice connection.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
        }
        .frame(maxWidth: 680).frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
        .task { await codex.refresh() }
        .task(id: preferred) { await loadDefaultModels() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            connected = ActionCredentials.hasKey(for: .openRouter)
            Task { await codex.refresh() }
        }
    }

    private func account(_ connection: ActionConnection) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
                    expanded = expanded == connection ? nil : connection
                    message = nil
                }
            } label: {
                HStack(spacing: 12) {
                    Image(connection.logoAsset).resizable().scaledToFit()
                        .foregroundStyle(.white).frame(width: 24, height: 24).frame(width: 28, height: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(connection.title).font(.system(size: 13, weight: .medium))
                        Text(status(connection)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if isConnected(connection) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
                        .rotationEffect(.degrees(expanded == connection ? 90 : 0))
                }.padding(16).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded == connection {
                VStack(alignment: .leading, spacing: 16) {
                    Text(connection.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    if connection == .openRouter {
                        DisclosureGroup(connected ? "Replace API key" : "Add API key") {
                            VStack(alignment: .leading, spacing: 10) {
                                SecureField("OpenRouter API key", text: $key).textFieldStyle(.roundedBorder)
                                HStack {
                                    Text("Stored in this Mac's Keychain.").font(.system(size: 11)).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Save key") {
                                        if APIKeyManager.shared.saveAPIKey(key.trimmingCharacters(in: .whitespacesAndNewlines), forProvider: "openrouter") {
                                            connected = true; key = ""; message = "Key saved."
                                        } else { message = "Could not save the key. Try again." }
                                    }.buttonStyle(SpeekActionButtonStyle()).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }.padding(.top, 10)
                        }.font(.system(size: 12))
                        if let message { Text(message).font(.caption) }
                    } else {
                        HStack {
                            Spacer()
                            Button(codex.signingIn == connection ? "Signing in..." : isConnected(connection) ? "Reconnect" : "Sign in with ChatGPT") {
                                Task { await codex.signIn(connection) }
                            }.buttonStyle(SpeekActionButtonStyle()).disabled(codex.signingIn != nil)
                        }
                    }
                }
                .padding(16).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
        }
    }

    private var defaultConnection: ActionConnection { ActionConnection(rawValue: preferred) ?? .localCodex }
    private var supportedEfforts: [String] { chatModels.first { $0.id == defaultModel }?.efforts ?? [] }

    private var chatSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingRow("Provider", detail: "Used for every new chat.") {
                Picker("Default provider", selection: $preferred) {
                    ForEach(ActionConnection.allCases) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden().fixedSize()
            }
            settingRow("Model", detail: "You can override it in an individual chat.") {
                AudioOptionPicker(title: "Default model", selected: defaultModel,
                    options: chatModels.map { ($0.id, $0.name) }, fallback: defaultModel.replacingOccurrences(of: "gpt-6-", with: "GPT-6 ").replacingOccurrences(of: "-", with: " ")) { id in
                    AgentDefaults.setModel(id, for: defaultConnection)
                    defaultModel = id
                    defaultReasoning = AgentDefaults.reasoning(for: defaultConnection) ?? "default"
                }
            }
            settingRow("Reasoning", detail: supportedEfforts.isEmpty ? "Uses the model's default behavior." : "How much reasoning the model uses.") {
                Picker("Default reasoning", selection: Binding(get: { defaultReasoning }, set: { value in
                    defaultReasoning = value
                    AgentDefaults.setReasoning(value == "default" ? nil : value, for: defaultConnection)
                })) {
                    Text("Model default").tag("default")
                    ForEach(supportedEfforts, id: \.self) { Text($0.capitalized).tag($0) }
                    if defaultReasoning != "default" && !supportedEfforts.contains(defaultReasoning) {
                        Text(defaultReasoning.capitalized + " (saved)").tag(defaultReasoning)
                    }
                }.labelsHidden().fixedSize().disabled(modelsLoading)
            }
            if modelsLoading { ProgressView().controlSize(.small) }
            if let modelsError {
                HStack {
                    Text(modelsError).font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Retry") { Task { await loadDefaultModels() } }.buttonStyle(SpeekActionButtonStyle())
                }
            }
            Text("Defaults apply to new chats. Existing chats keep their provider, model, and reasoning.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func loadDefaultModels() async {
        let connection = defaultConnection
        defaultModel = AgentDefaults.model(for: connection)
        defaultReasoning = AgentDefaults.reasoning(for: connection) ?? "default"
        chatModels = []; modelsLoading = true; modelsError = nil
        do {
            let catalog = try await AssistantModelCatalog.load(connection: connection, requiresImages: true)
            try Task.checkCancellation()
            guard connection == defaultConnection else { return }
            chatModels = catalog
            if catalog.isEmpty { modelsError = "No models returned. Your saved default is kept." }
            modelsLoading = false
        } catch is CancellationError {
        } catch {
            guard connection == defaultConnection else { return }
            modelsLoading = false
            modelsError = "Could not load models. Your saved default is kept."
        }
    }

    private var voiceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingRow("Connection", detail: "For dictation and spoken replies.") {
                Picker("Voice connection", selection: $voice) {
                    Text("OpenRouter").tag(ActionCloudProvider.openRouter.rawValue)
                    if ActionCredentials.hasKey(for: .openAI) { Text("OpenAI API").tag(ActionCloudProvider.openAI.rawValue) }
                }.labelsHidden().fixedSize()
            }
            Toggle("Read replies aloud", isOn: $readReplies).toggleStyle(.switch).controlSize(.small)
            if voice == ActionCloudProvider.openRouter.rawValue {
                Divider()
                RouterAudioSettings()
            }
        }.padding(16).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func settingRow<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { rowLabel(title, detail); Spacer(minLength: 16); content() }
            VStack(alignment: .leading, spacing: 10) {
                rowLabel(title, detail)
                content().frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
    private func rowLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private func isConnected(_ connection: ActionConnection) -> Bool { status(connection).hasPrefix("Connected") }
    private func status(_ connection: ActionConnection) -> String {
        switch connection {
        case .localCodex: return codex.localStatus
        case .subscription: return codex.subscriptionStatus
        case .openRouter: return connected ? "Connected" : "API key needed"
        }
    }
}

extension View {
    func settingsSurface() -> some View {
        background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.055)))
    }
}

/// Shared flat action styling for pages and assistant controls.
struct SpeekActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ActionBody(configuration: configuration)
    }

    private struct ActionBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.35))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white.opacity(isEnabled ? (configuration.isPressed ? 0.16 : hovered ? 0.12 : 0.075) : 0.035), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { hovered = $0 }
        }
    }
}
