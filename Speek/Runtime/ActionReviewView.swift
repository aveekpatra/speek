import SwiftUI

struct ActionReviewView: View {
    @ObservedObject var assistant: AssistantController
    let proposal: ProposedAction
    @State private var values: [String: String] = [:]
    @State private var error: String?
    private var call: RuntimeCall? { try? RuntimeCall(target: proposal.target) }
    private var tool: RuntimeTool? { call.flatMap { call in ActionRuntime.shared.tools.first { $0.id == call.tool } } }
    private var properties: [String: [String: Any]] { tool?.schema["properties"] as? [String: [String: Any]] ?? [:] }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(tool?.title ?? proposal.title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "hand.raised.fill").foregroundStyle(.secondary)
            }
            Text(tool?.summary ?? "Run in your chosen project folder.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let call {
                ForEach(Array(Set(tool?.schema["required"] as? [String] ?? []).union(call.arguments.keys)).sorted(), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 5) {
                        let label = key.replacingOccurrences(of: "_", with: " ").capitalized
                        if properties[key]?["type"] as? String == "boolean" {
                            HStack {
                                Text(label).font(.system(size: 12, weight: .medium))
                                Spacer()
                                Toggle(label, isOn: Binding(get: { values[key] == "true" }, set: { values[key] = $0 ? "true" : "false" })).labelsHidden().toggleStyle(.switch)
                            }
                        } else if let options = properties[key]?["enum"] as? [String] {
                            HStack {
                                Text(label).font(.system(size: 12, weight: .medium))
                                Spacer()
                                Picker(label, selection: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })) {
                                    Text("Choose").tag("")
                                    ForEach(options, id: \.self) { Text($0.capitalized).tag($0) }
                                }.labelsHidden().fixedSize()
                            }
                        } else {
                            Text(label).font(.system(size: 12, weight: .medium))
                            TextField("Value", text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }), axis: .vertical)
                                .lineLimit(1...5).textFieldStyle(.plain).font(.system(size: 13))
                                .padding(9).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }

                }
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { assistant.cancelProposal() }.buttonStyle(SpeekActionButtonStyle())
                if let call {
                    Button("Always Allow") { ToolPolicyStore.shared.set(.allow, for: call.tool); approve() }
                        .buttonStyle(SpeekActionButtonStyle()).help("Run now and stop asking for this tool")
                }
                Button("Approve action") { approve() }.buttonStyle(SpeekActionButtonStyle())
            }
        }.padding(18).settingsSurface()
            .onAppear { loadValues() }
            .onChange(of: proposal.target) { _, _ in loadValues() }
    }
    private func loadValues() {
        guard let call, let data = try? JSONEncoder().encode(call.arguments), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        values = object.mapValues { value in
            if let text = value as? String { return text }
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), let text = String(data: data, encoding: .utf8) { return text }
            return ""
        }
    }
    private func approve() {
        do {
            if let call {
                var object: [String: Any] = [:]
                let required = tool?.schema["required"] as? [String] ?? []
                for key in Set(tool?.schema["required"] as? [String] ?? []).union(call.arguments.keys) {
                    let value = (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.isEmpty {
                        if required.contains(key) { throw ActionClientError.requestFailed("Enter " + key + ".") }
                        continue
                    }
                    let type = properties[key]?["type"] as? String ?? "string"
                    if type == "string" { object[key] = value }
                    else { object[key] = try JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed]) }
                }
                let arguments = try JSONDecoder().decode([String: MCPValue].self, from: JSONSerialization.data(withJSONObject: object))
                if let tool { try ToolArguments.validate(object, schema: tool.schema) }
                assistant.updateReviewedArguments(arguments)
            }
            error = nil; assistant.runProposal()
        } catch { self.error = error.localizedDescription }
    }
}
