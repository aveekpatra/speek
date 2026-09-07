import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SoundPage: View {
    @ObservedObject private var settings = SpeekSettings.shared
    @ObservedObject private var sounds = CustomSoundManager.shared
    @State private var importError: String?

    var body: some View {
        SpeekPageScroll {
            VStack(alignment: .leading, spacing: 10) {
                SpeekSectionHeader("Recording")
                SpeekGroup {
                    SpeekRow("Silence removal", help: "Trims long pauses before transcription. Speeds up processing and reduces hallucinated words.") {
                        Toggle("", isOn: $settings.silenceRemoval).labelsHidden().toggleStyle(.switch)
                    }
                    SpeekRow("Playback when recording", help: "Pause sends a real pause to whatever is playing (Music, Spotify, a video in your browser) and resumes it when you stop. Mute only silences the speakers. Do nothing leaves playback alone.") {
                        Picker("", selection: $settings.playbackWhenRecording) {
                            ForEach(PlaybackWhenRecording.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SpeekSectionHeader("Sound Effects")
                SpeekGroup {
                    SpeekRow("Sounds", help: "Each collection is a start and a stop sound. Custom uses two files of your own, 3 seconds or less.") {
                        Picker("", selection: $sounds.collection) {
                            ForEach(CustomSoundManager.Collection.allCases) { collection in
                                Text(collection.displayName).tag(collection)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: sounds.collection) { _, collection in
                            guard collection != .off, collection != .custom else { return }
                            previewPair()
                        }
                    }
                    if sounds.collection == .custom {
                        SpeekRow("Start file", subtitle: sounds.customFileName(for: .start).map { LocalizedStringKey($0) } ?? "No file chosen") {
                            Button("Choose...") { importFile(for: .start) }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)
                        }
                        SpeekRow("Stop file", subtitle: sounds.customFileName(for: .stop).map { LocalizedStringKey($0) } ?? "No file chosen") {
                            Button("Choose...") { importFile(for: .stop) }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)
                        }
                    }
                    SpeekRow("Volume") {
                        HStack(spacing: 10) {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(.secondary)
                            Slider(value: $settings.soundVolume, in: 0...1, step: 0.1)
                                .frame(width: 320)
                                .onChange(of: settings.soundVolume) { _, _ in
                                    SoundManager.shared.playStartSound()
                                }
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.secondary)
                        }
                        .disabled(!sounds.isEnabled)
                        .opacity(sounds.isEnabled ? 1 : 0.5)
                    }
                }
            }
        }
        .navigationTitle("")
        .toolbar { SpeekStandardToolbar() }
        .alert("Could not use that file", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    /// Start, then stop a beat later, so a collection is heard as the pair it is.
    private func previewPair() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { SoundManager.shared.playStartSound() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { SoundManager.shared.playStopSound() }
    }

    private func importFile(for type: CustomSoundManager.SoundType) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a sound of 3 seconds or less."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch sounds.setCustomSound(url: url, for: type) {
        case .success:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                type == .start ? SoundManager.shared.playStartSound() : SoundManager.shared.playStopSound()
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}
