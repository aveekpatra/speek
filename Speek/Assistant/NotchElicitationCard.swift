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
                    Image(systemName: "questionmark.bubble.fill").font(.system(size: 12))
                    Text(request.plugin + " asks").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(request.message).font(.system(size: 12)).lineLimit(3).textSelection(.enabled)
                ForEach(request.fields) { field in fieldRow(field) }
                HStack(spacing: 8) {
                    Spacer(minLength: 8)
                    Button("Decline") { center.decline() }.buttonStyle(SpeekActionButtonStyle())
                    if let url = request.url {
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
            default:
                TextField(field.title, text: binding).textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 8).frame(width: 180, height: 24)
                    .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @MainActor static func height() -> Int {
        guard let request = MCPElicitationCenter.shared.current else { return 0 }
        return 96 + request.fields.count * 30
    }
}
