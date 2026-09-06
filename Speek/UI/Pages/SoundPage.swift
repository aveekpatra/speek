import SwiftUI

struct SoundPage: View {
    @ObservedObject private var settings = SpeekSettings.shared

    var body: some View {
        SpeekPageScroll {
            VStack(alignment: .leading, spacing: 10) {
                SpeekSectionHeader("Recording")
                SpeekGroup {
                    SpeekRow("Automatically increase microphone volume", help: "Boosts quiet microphones so speech is loud enough for the model.") {
                        Toggle("", isOn: $settings.autoIncreaseMicVolume).labelsHidden().toggleStyle(.switch)
                    }
                    SpeekRow("Silence removal", help: "Trims long pauses before transcription. Speeds up processing and reduces hallucinated words.") {
                        Toggle("", isOn: $settings.silenceRemoval).labelsHidden().toggleStyle(.switch)
                    }
                    SpeekRow("Dynamic normalization", help: "Evens out loud and quiet passages in the recording.") {
                        Toggle("", isOn: $settings.dynamicNormalization).labelsHidden().toggleStyle(.switch)
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
                    SpeekRow("Sound effects") {
                        SpeekSegmentedPicker(selection: $settings.soundEffects, options: SoundEffectsStyle.allCases) { $0.displayName }
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
                        .disabled(settings.soundEffects == .off)
                        .opacity(settings.soundEffects == .off ? 0.5 : 1)
                    }
                }
            }
        }
        .navigationTitle("")
        .toolbar { SpeekStandardToolbar() }
    }
}
