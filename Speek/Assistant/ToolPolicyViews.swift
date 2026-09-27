import SwiftUI

/// One tool's approval choice, shown next to the tool wherever it appears.
struct ToolPolicyMenu: View {
    let toolID: String
    let changesData: Bool
    var title = "Approval"
    @ObservedObject private var policies = ToolPolicyStore.shared

    var body: some View {
        Picker(title, selection: Binding(get: { policies.override(for: toolID)?.rawValue ?? "default" }, set: { value in
            policies.set(ToolPolicy(rawValue: value), for: toolID)
        })) {
            Text("Default (" + policies.defaultPolicy(changesData: changesData).title + ")").tag("default")
            Divider()
            ForEach(ToolPolicy.allCases) { Text($0.title).tag($0.rawValue) }
        }.labelsHidden().fixedSize()
    }
}

/// The tools under an expanded integration row, indented to the row's title.
struct ToolPolicyRows: View {
    let tools: [ToolPolicyEntry]

    var body: some View {
        ForEach(tools) { tool in
            SettingsRowDivider(leading: 60)
            SettingsRow(title: tool.title, value: tool.changesData ? nil : "Read only", info: tool.summary.isEmpty ? nil : tool.summary) {
                ToolPolicyMenu(toolID: tool.id, changesData: tool.changesData, title: tool.title)
            }.padding(.leading, 44)
        }
    }
}

/// "Set All" for an integration's tools, placed beside the tool list's heading.
struct ToolPolicySetAllMenu: View {
    let tools: [ToolPolicyEntry]

    var body: some View {
        Menu {
            ForEach(ToolPolicy.allCases) { policy in
                Button(policy.title) { ToolPolicyStore.shared.set(policy, forAll: tools) }
            }
            Divider()
            Button("Use Defaults") { ToolPolicyStore.shared.set(nil, forAll: tools) }
        } label: { Text("Set All").font(.system(size: 12, weight: .medium)) }
            .menuStyle(.borderlessButton).fixedSize()
            .disabled(tools.isEmpty)
    }
}

extension ToolPolicyStore {
    /// Short state for a collapsed row, such as "Asks before 2 of 5 actions".
    func summary(_ tools: [ToolPolicyEntry]) -> String? {
        guard !tools.isEmpty else { return nil }
        let resolved = tools.map { policy(for: $0.id, changesData: $0.changesData) }
        let ask = resolved.filter { $0 == .ask }.count, never = resolved.filter { $0 == .never }.count
        var parts: [String] = []
        if ask == 0 && never == 0 { parts.append("Runs without asking") }
        if ask > 0 { parts.append(ask == tools.count ? "Asks before every action" : "Asks before \(ask) of \(tools.count) actions") }
        if never > 0 { parts.append("\(never) blocked") }
        return parts.joined(separator: ", ")
    }

    func tools(inGroup id: String) -> [ToolPolicyEntry] { groups.first { $0.id == id }?.tools ?? [] }
}
