import SwiftUI

struct VoiceCaptureSettingsView: View {
    var isRecording: Bool = false
    @ObservedObject private var devices = AudioDeviceManager.shared
    @AppStorage("speek.voice.recognitionLanguage") private var language = ""
    @AppStorage("speek.voice.vocabularyHints") private var vocabularyHints = true
    @AppStorage("speek.actions.voiceProvider") private var provider = "openRouter"

    private var selection: Binding<String> {
        Binding(get: {
            if devices.inputMode == .systemDefault { return "system" }
            if devices.inputMode == .prioritized { return "prioritized" }
            return devices.availableDevices.first(where: { $0.id == devices.selectedDeviceID })?.uid ?? "unavailable"
        }, set: { value in
            guard !isRecording, !devices.isRecordingActive else { return }
            if value == "system" { devices.selectInputMode(.systemDefault) }
            else if value == "prioritized" { devices.selectInputMode(.prioritized) }
            else if let device = devices.availableDevices.first(where: { $0.uid == value }) { devices.selectDeviceAndSwitchToCustomMode(id: device.id) }
        })
    }
    var body: some View {
        SettingsSection(title: "Voice capture") {
            SettingsRow(title: "Microphone", value: isRecording ? "Finish recording to change" : nil) {
                Picker("Microphone", selection: selection) {
                    Text("System default").tag("system")
                    if devices.inputMode == .prioritized { Text("Saved device priorities").tag("prioritized") }
                    if selection.wrappedValue == "unavailable" { Text("Unavailable device").tag("unavailable") }
                    ForEach(devices.availableDevices, id: \.uid) { device in Text(device.name).tag(device.uid) }
                }.labelsHidden().frame(maxWidth: 250)
                    .disabled(isRecording || devices.isRecordingActive)
            }
            SettingsRowDivider()
            SettingsRow(title: "Recognition language", info: "Automatic follows your speech. Support depends on the dictation model.") {
                Picker("Recognition language", selection: $language) {
                    ForEach(VoiceCapturePreferences.languages) { Text($0.name).tag($0.id) }
                }.labelsHidden()
            }
            if provider == "openAI" {
                SettingsRowDivider()
                SettingsRow(title: "Vocabulary hints", info: "Send saved names and terms from Memory > Vocabulary to OpenAI transcription. Long snippets are excluded.") {
                    Toggle("Vocabulary hints", isOn: $vocabularyHints).labelsHidden().toggleStyle(.switch)
                }
            }
        }.onAppear { devices.loadAvailableDevices() }
    }
}
