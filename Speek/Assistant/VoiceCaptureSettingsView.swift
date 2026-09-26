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
        VStack(alignment: .leading, spacing: 10) {
            Text("Voice capture").font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
            VStack(spacing: 0) {
                row("Microphone", detail: isRecording ? "Finish recording before changing the microphone." : "Current input: " + (devices.getDeviceName(deviceID: devices.getCurrentDevice()) ?? "No microphone available")) {
                    Picker("Microphone", selection: selection) {
                        Text("System default").tag("system")
                        if devices.inputMode == .prioritized { Text("Saved device priorities").tag("prioritized") }
                        if selection.wrappedValue == "unavailable" { Text("Unavailable device").tag("unavailable") }
                        ForEach(devices.availableDevices, id: \.uid) { device in Text(device.name).tag(device.uid) }
                    }.labelsHidden().fixedSize().frame(maxWidth: 250, alignment: .trailing)
                        .disabled(isRecording || devices.isRecordingActive)
                }
                Divider().padding(.horizontal, 16)
                row("Recognition language", detail: "Automatic follows your speech. Language support depends on the selected transcription model.") {
                    Picker("Recognition language", selection: $language) {
                        ForEach(VoiceCapturePreferences.languages) { Text($0.name).tag($0.id) }
                    }.labelsHidden().fixedSize()
                }
                if provider == "openAI" {
                    Divider().padding(.horizontal, 16)
                    row("Vocabulary hints", detail: "Send saved names and specialist terms to supported OpenAI transcription models. Long snippets are excluded.") {
                        Toggle("Vocabulary hints", isOn: $vocabularyHints).labelsHidden().toggleStyle(.switch)
                    }
                }
            }.settingsSurface()
            if provider == "openRouter" {
                Text("OpenRouter receives the language hint. Saved corrections are applied after transcription; provider-specific vocabulary hints are not sent.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
        }.onAppear { devices.loadAvailableDevices() }
    }
    private func row<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) { label(title, detail: detail).frame(minWidth: 180, maxWidth: .infinity, alignment: .leading); control() }
            VStack(alignment: .trailing, spacing: 12) { label(title, detail: detail).frame(maxWidth: .infinity, alignment: .leading); control() }
        }.padding(16)
    }
    private func label(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
