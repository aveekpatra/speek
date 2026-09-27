import SwiftUI
import AppKit

/// The plugin question card, styled like the permission card in the notch.
struct NotchElicitationCard: View {
    @ObservedObject private var center = MCPElicitationCenter.shared
    @State private var values: [String: String] = [:]

    var body: some View {
        if let request = center.current {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: request.sampling == nil ? "questionmark.bubble.fill" : "sparkles").font(.system(size: 12))
                    Text(request.plugin + (request.sampling == nil ? " asks" : " " + request.message)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                if let prompt = request.sampling {
                    // What will be sent to the model, so it can be checked before allowing.
                    ScrollView {
                        Text(prompt).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 64)
                } else {
                    Text(request.message).font(.system(size: 12)).lineLimit(3).textSelection(.enabled)
                }
                ForEach(request.fields) { field in fieldRow(field) }
                HStack(spacing: 8) {
                    Spacer(minLength: 8)
                    Button(request.sampling == nil ? "Decline" : "Deny") { center.decline() }.buttonStyle(SpeekActionButtonStyle())
                    if request.sampling != nil {
                        Button("Allow") { center.submit([:]) }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction)
                    } else if let url = request.url {
                        Button("Open") { NSWorkspace.shared.open(url) }.buttonStyle(SpeekActionButtonStyle()).help(url.host ?? "")
                        Button("Done") { center.submit([:]) }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction)
                    } else {
                        Button("Submit") { center.submit(values) }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction)
                            .disabled(request.fields.contains { $0.required && (values[$0.id] ?? $0.defaultValue).trimmingCharacters(in: .whitespaces).isEmpty })
                    }
                }.padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .onChange(of: request.id) { _, _ in values = [:] }
        }
    }

    @ViewBuilder private func fieldRow(_ field: MCPElicitation.Field) -> some View {
        let binding = Binding(get: { values[field.id] ?? field.defaultValue }, set: { values[field.id] = $0 })
        HStack(spacing: 8) {
            Text(field.title + (field.required ? "" : " (optional)")).font(.system(size: 12)).lineLimit(1).help(field.detail ?? "")
            Spacer(minLength: 8)
            switch field.kind {
            case .toggle:
                Toggle(field.title, isOn: Binding(get: { binding.wrappedValue == "true" }, set: { binding.wrappedValue = $0 ? "true" : "false" }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            case .choice(let options, let labels):
                Picker(field.title, selection: binding) {
                    Text("Choose").tag("")
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in Text(index < labels.count ? labels[index] : option).tag(option) }
                }.labelsHidden().fixedSize()
            case .multiChoice(let options, let labels):
                let selected = Set(binding.wrappedValue.components(separatedBy: MCPElicitation.separator).filter { !$0.isEmpty })
                Menu(selected.isEmpty ? "Choose" : options.enumerated().filter { selected.contains($0.element) }
                        .map { $0.offset < labels.count ? labels[$0.offset] : $0.element }.joined(separator: ", ")) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Toggle(index < labels.count ? labels[index] : option, isOn: Binding(get: { selected.contains(option) }, set: { on in
                            let next = on ? selected.union([option]) : selected.subtracting([option])
                            binding.wrappedValue = options.filter(next.contains).joined(separator: MCPElicitation.separator)
                        }))
                    }
                }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 12))
            default:
                TextField(field.title, text: binding).textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 8).frame(width: 180, height: 24)
                    .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @MainActor static func height() -> Int {
        guard let request = MCPElicitationCenter.shared.current else { return 0 }
        return 96 + request.fields.count * 30 + (request.sampling == nil ? 0 : 50)
    }
}
