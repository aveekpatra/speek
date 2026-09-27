import SwiftUI

struct VoiceCaptureSettingsView: View {
    var isRecording: Bool = false
    @ObservedObject private var devices = AudioDeviceManager.shared
    @State private var enabledLanguages = VoiceCapturePreferences.enabledLanguages()
    @ObservedObject private var sounds = CustomSoundManager.shared
    @ObservedObject private var playback = PlaybackController.shared
    @AppStorage("speek.dictation.livePreview") private var livePreview = true
    @AppStorage(CorrectionLearner.enabledKey) private var learnCorrections = true
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
    private var languageSummary: String {
        enabledLanguages.isEmpty ? "Any language" : enabledLanguages.map(VoiceCapturePreferences.name(for:)).joined(separator: ", ")
    }

    private func setLanguages(_ ids: [String]) {
        enabledLanguages = ids
        VoiceCapturePreferences.setEnabledLanguages(ids)
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
            SettingsRow(title: "Languages", info: "Choose the languages you speak; the first is your main one. One language is always used. With several, Speek listens for any of them and retries if the result comes back in another language. None means any language.") {
                Menu(languageSummary) {
                    Button { setLanguages([]) } label: {
                        if enabledLanguages.isEmpty { Label("Any language", systemImage: "checkmark") } else { Text("Any language") }
                    }
                    Divider()
                    ForEach(VoiceCapturePreferences.languages.filter { !$0.id.isEmpty }) { language in
                        Toggle(language.name, isOn: Binding(get: { enabledLanguages.contains(language.id) }, set: { on in
                            setLanguages(on ? enabledLanguages + [language.id] : enabledLanguages.filter { $0 != language.id })
                        }))
                    }
                }.fixedSize()
            }
            if provider == "openAI" {
                SettingsRowDivider()
                SettingsRow(title: "Vocabulary hints", info: "Send saved names and terms from Memory > Vocabulary to OpenAI transcription. Long snippets are excluded.") {
                    Toggle("Vocabulary hints", isOn: $vocabularyHints).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsRowDivider()
            SettingsRow(title: "Live transcript", info: "Show your words in the notch as you speak. The preview is recognized on this Mac; the text that gets inserted still comes from your dictation model.") {
                Toggle("Live transcript", isOn: $livePreview).labelsHidden().toggleStyle(.switch)
            }
            SettingsRowDivider()
            SettingsRow(title: "Learn from corrections", info: "When you fix a misheard word right after dictating, Speek adds it to Memory > Vocabulary so it comes out right next time. Undo from the notch or menu bar menu.") {
                Toggle("Learn from corrections", isOn: $learnCorrections).labelsHidden().toggleStyle(.switch)
            }
            SettingsRowDivider()
            SettingsRow(title: "Sound cues", info: "Play a sound when recording starts and stops.") {
                Picker("Sound cues", selection: $sounds.collection) {
                    ForEach(CustomSoundManager.Collection.allCases.filter { $0 != .custom || sounds.collection == .custom }) { Text($0.displayName).tag($0) }
                }.labelsHidden()
                    .onChange(of: sounds.collection) { _, value in if value != .off { SoundManager.shared.playStartSound() } }
            }
            SettingsRowDivider()
            SettingsRow(title: "Pause media while recording", info: "Pause music and videos while you speak, then resume them.") {
                Toggle("Pause media while recording", isOn: $playback.isPauseMediaEnabled).labelsHidden().toggleStyle(.switch)
            }
        }.onAppear { devices.loadAvailableDevices() }
    }
}
