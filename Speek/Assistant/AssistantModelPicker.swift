import SwiftUI

// Selection belongs to the task. Catalogs belong to the authenticated connection.
struct AssistantModelOption: Identifiable {
    let id: String
    let name: String
    var efforts: [String] = []
    var defaultEffort: String? = nil
}

@MainActor
struct AssistantModelPicker: View {
    @ObservedObject var assistant: AssistantController
    var manageConnections: () -> Void
    @ObservedObject private var codex = CodexConnection.shared
    @State private var hovered = false
    @State private var presented = false
    @State private var browsing: ActionConnection = .localCodex
    @State private var models: [AssistantModelOption] = []
    @State private var query = ""
    @State private var loading = false
    @State private var catalogError: String?

    private var connected: Bool { isConnected(browsing) }

    private func isConnected(_ connection: ActionConnection) -> Bool {
        switch connection {
        case .openRouter: return ActionCredentials.hasKey(for: .openRouter)
        case .localCodex: return codex.localStatus.hasPrefix("Connected")
        case .subscription: return codex.subscriptionStatus.hasPrefix("Connected")
        }
    }

    private var displayName: String {
        let id = assistant.modelID ?? AgentDefaults.model(for: assistant.connection)
        if let name = models.first(where: { $0.id == id })?.name { return name.replacingOccurrences(of: "GPT-6-", with: "GPT-6 ") }
        let leaf = String(id.split(separator: "/").last ?? Substring(id))
        return leaf.replacingOccurrences(of: "gpt-6-", with: "GPT-6 ").replacingOccurrences(of: "gpt-5.6-", with: "GPT-5.6 ").replacingOccurrences(of: "-", with: " ").capitalized.replacingOccurrences(of: "Gpt", with: "GPT")
    }
    private var providerName: String {
        assistant.connection == .openRouter ? "OpenRouter" : assistant.connection == .subscription ? "ChatGPT" : "Codex"
    }
    private var selectedEfforts: [String] {
        let id = assistant.modelID ?? AgentDefaults.model(for: browsing)
        return models.first(where: { $0.id == id })?.efforts ?? []
    }

    var body: some View {
        Button {
            browsing = assistant.connection
            presented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(displayName).lineLimit(1).truncationMode(.middle)
                Image(assistant.connection.logoAsset)
                    .resizable().scaledToFit().frame(width: 16, height: 16)
                    .accessibilityLabel(providerName)
            }
            .font(.system(size: 12)).foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 32)
            .background(.white.opacity(hovered || presented ? 0.09 : 0), in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .task { browsing = assistant.connection; await loadModels() }
        .help("\(assistant.connection.title): \(assistant.modelID ?? "default model")")
        .disabled(assistant.busy || assistant.recording)
        .popover(isPresented: $presented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Model").font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                HStack(spacing: 4) {
                    ForEach(ActionConnection.allCases) { connection in
                        Button { browsing = connection } label: {
                            HStack(spacing: 5) {
                                if !isConnected(connection) { Image(systemName: "lock.fill").font(.system(size: 10)) }
                                else { Image(connection.logoAsset).resizable().scaledToFit().frame(width: 14, height: 14) }
                                Text(connection == .localCodex ? "Codex" : connection == .subscription ? "ChatGPT" : "OpenRouter")
                            }
                                .foregroundStyle(isConnected(connection) ? Color.white : Color.gray)
                                .font(.system(size: 12, weight: browsing == connection ? .semibold : .regular))
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(.white.opacity(browsing == connection ? 0.12 : 0), in: Capsule())
                                .contentShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }.padding(4).background(.black.opacity(0.12), in: Capsule())
                if connected {
                    if browsing == assistant.connection && !selectedEfforts.isEmpty {
                        HStack {
                            Text("Reasoning").font(.system(size: 12))
                            Spacer()
                            Picker("Reasoning", selection: Binding(get: { assistant.reasoningEffort ?? "default" }, set: { assistant.reasoningEffort = $0 == "default" ? nil : $0 })) {
                                Text("Model default").tag("default")
                                ForEach(selectedEfforts, id: \.self) { Text($0.capitalized).tag($0) }
                            }.labelsHidden().fixedSize()
                        }.padding(.horizontal, 8)
                    }
                    Divider()
                    TextField("Find a model", text: $query).textFieldStyle(.roundedBorder)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            modelRow(id: nil, title: "Automatic", detail: "Use this connection's default model")
                            ForEach(models.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }) { model in
                                modelRow(id: model.id, title: model.name, detail: nil)
                            }
                        }
                    }.frame(height: 190)
                    if loading { ProgressView().controlSize(.small) }
                    if let catalogError { Text(catalogError).font(.caption).foregroundStyle(.secondary) }
                    Text(browsing == .openRouter ? "Cloud responses and app actions. File tasks require Codex." : "Cloud models. File tasks run on this Mac.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("Connect \(browsing.title) to use its models.")
                        .font(.system(size: 12)).padding(.vertical, 16)
                    Button("Open Models & Voice") { presented = false; manageConnections() }
                }
            }
            .padding(16).frame(width: 340)
            .task { await codex.refresh() }
            .task(id: browsing) { await loadModels() }
        }
    }

    private func modelRow(id: String?, title: String, detail: String?) -> some View {
        Button {
            assistant.connection = browsing
            assistant.modelID = id
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12))
                    if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Spacer()
                if assistant.connection == browsing && assistant.modelID == id {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white)
                }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(assistant.connection == browsing && assistant.modelID == id ? .white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }

    private func loadModels() async {
        models = []; query = ""; catalogError = nil; loading = true
        defer { loading = false }
        do {
            models = try await AssistantModelCatalog.load(connection: browsing, requiresImages: assistant.context?.image != nil)
            if models.isEmpty { catalogError = "No models listed yet. Automatic is still available." }
        } catch is CancellationError {
        } catch {
            catalogError = "Model list unavailable. You can still use Automatic."
        }
    }
}


@MainActor
enum AssistantModelCatalog {
    static func load(connection: ActionConnection, requiresImages: Bool = false) async throws -> [AssistantModelOption] {
            if connection == .openRouter {
                let (data, response) = try await URLSession.shared.data(from: URL(string: "https://openrouter.ai/api/v1/models")!)
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                return (root?["data"] as? [[String: Any]] ?? []).compactMap { item in
                    guard let id = item["id"] as? String, let name = item["name"] as? String,
                          let parameters = item["supported_parameters"] as? [String], parameters.contains("structured_outputs"),
                          let architecture = item["architecture"] as? [String: Any],
                          let inputs = architecture["input_modalities"] as? [String], inputs.contains("text"),
                          !requiresImages || inputs.contains("image") else { return nil }
                    return AssistantModelOption(id: id, name: name, efforts: (item["reasoning"] as? [String: Any])?["supported_efforts"] as? [String] ?? [], defaultEffort: (item["reasoning"] as? [String: Any])?["default_effort"] as? String)
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            } else {
                let env = try CodexConnection.environment(for: connection)
                let home = env["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex"
                let data = try Data(contentsOf: URL(fileURLWithPath: home).appendingPathComponent("models_cache.json"))
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                return (root?["models"] as? [[String: Any]] ?? []).compactMap { item in
                    guard item["visibility"] as? String == "list", let id = item["slug"] as? String else { return nil }
                    return AssistantModelOption(id: id, name: item["display_name"] as? String ?? id, efforts: (item["supported_reasoning_levels"] as? [[String: Any]] ?? []).compactMap { $0["effort"] as? String }, defaultEffort: item["default_reasoning_level"] as? String)
                }
            }
    }
}
