import SwiftUI

/// Installing or signing into a CLI does not grant Speek permission to use it.
enum CodingIntegrationPreferences {
    static func key(for engine: CodingTaskJob.Engine) -> String {
        "CodingIntegration." + engine.rawValue + ".enabled"
    }

    static func isEnabled(_ engine: CodingTaskJob.Engine) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: engine))
    }

    static func setEnabled(_ enabled: Bool, for engine: CodingTaskJob.Engine) {
        UserDefaults.standard.set(enabled, forKey: key(for: engine))
    }
}

struct CodingIntegrationSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("CodingIntegration.codex.enabled") private var codexEnabled = false
    @AppStorage("CodingIntegration.claude.enabled") private var claudeEnabled = false
    @State private var locations: [String: String] = [:]

    var body: some View {
        SettingsSection(title: "Coding assistants", info: "Send reviewed coding tasks to Codex or Claude Code from a chat. Speek uses the CLI's existing sign-in; being installed does not confirm account access.", spacing: 16) {
            ForEach(CodingTaskJob.Engine.allCases) { engine in
                if engine != CodingTaskJob.Engine.allCases.first { Divider().padding(.horizontal, 16) }
                row(engine)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func row(_ engine: CodingTaskJob.Engine) -> some View {
        let location = locations[engine.rawValue]
        let enabled = binding(for: engine)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.title).font(.system(size: 13, weight: .medium))
                    Label(location == nil ? "CLI not found" : "CLI installed", systemImage: location == nil ? "minus.circle" : "checkmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Enable " + engine.title + " integration", isOn: enabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(location == nil && !enabled.wrappedValue)
                    .help(location == nil ? "Install the CLI to enable this integration." : "Allow reviewed tasks through " + engine.title)
            }
            if let location {
                DisclosureGroup("CLI location") {
                    Text(location).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.padding(16)
    }

    private func binding(for engine: CodingTaskJob.Engine) -> Binding<Bool> {
        engine == .codex ? $codexEnabled : $claudeEnabled
    }

    private func refresh() {
        locations = Dictionary(uniqueKeysWithValues: CodingTaskJob.Engine.allCases.compactMap { engine in
            CodingTaskManager.binary(for: engine).map { (engine.rawValue, $0) }
        })
    }
}
