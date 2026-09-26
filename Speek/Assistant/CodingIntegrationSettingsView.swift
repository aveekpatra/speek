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
        SettingsSection(title: "Coding assistants", info: "Send reviewed coding tasks to Codex or Claude Code from a chat. Speek uses the CLI's existing sign-in; being installed does not confirm account access.") {
            ForEach(CodingTaskJob.Engine.allCases) { engine in
                if engine != CodingTaskJob.Engine.allCases.first { SettingsRowDivider(leading: 60) }
                let location = locations[engine.rawValue]
                let enabled = binding(for: engine)
                SettingsRow(title: engine.title, asset: engine == .codex ? "provider-codex" : "provider-anthropic",
                            value: location == nil ? "CLI not found" : nil, info: location.map { "Uses " + $0 }) {
                    Toggle("Enable " + engine.title + " integration", isOn: enabled)
                        .labelsHidden().toggleStyle(.switch)
                        .disabled(location == nil && !enabled.wrappedValue)
                        .help(location == nil ? "Install the CLI to enable this integration." : "Allow reviewed tasks through " + engine.title)
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
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
