import SwiftUI
import AVFoundation

private struct RouterAudioModel: Identifiable {
    let id: String
    let name: String
    let voices: [String]
}

struct RouterAudioSettings: View {
    @AppStorage("speek.actions.openRouterSpeechModel") private var dictation = "openai/gpt-transcribe"
    @AppStorage("speek.actions.openRouterVoiceModel") private var speech = "microsoft/mai-voice-2-flash"
    @AppStorage("speek.actions.openRouterVoice") private var voice = "en-US-Harper:MAI-Voice-2"
    @State private var dictationModels: [RouterAudioModel] = []
    @State private var speechModels: [RouterAudioModel] = []
    @State private var loading = false
    @State private var error: String?
    @State private var previewing = false
    @State private var player: AVAudioPlayer?
    @State private var previewTask: Task<Void, Never>?
    private var voices: [String] { speechModels.first { $0.id == speech }?.voices ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("Dictation", detail: "Turn speech into text") {
                AudioOptionPicker(title: "Dictation model", selected: dictation,
                                  options: dictationModels.map { ($0.id, $0.name) }, fallback: display(dictation)) { dictation = $0 }
            }
            row("Spoken replies", detail: "Choose a speech model") {
                AudioOptionPicker(title: "Speech model", selected: speech,
                                  options: speechModels.map { ($0.id, $0.name) }, fallback: display(speech)) { id in
                    player?.stop(); previewTask?.cancel()
                    if let model = speechModels.first(where: { $0.id == id }), let first = model.voices.first {
                        if !model.voices.contains(voice) { voice = first }
                        speech = id
                    }
                }
            }
            row("Voice", detail: "Available for this speech model") {
                AudioOptionPicker(title: "Voice", selected: voice, options: voices.map { ($0, voiceTitle($0)) }, fallback: voiceTitle(voice)) { voice = $0; player?.stop() }
            }
            HStack(spacing: 10) {
                if loading { ProgressView().controlSize(.small) }
                if let error {
                    Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Retry") { Task { await load() } }.buttonStyle(.plain)
                }
                Spacer()
                Button {
                    previewTask?.cancel()
                    previewTask = Task {
                        previewing = true; error = nil
                        defer { previewing = false }
                        do {
                            let data = try await OpenRouterActionClient.shared.speak("Hello, I'm Speek. This is how your spoken replies will sound.", model: speech, voice: voice)
                            try Task.checkCancellation()
                            player = try AVAudioPlayer(data: data)
                            player?.play()
                        } catch is CancellationError {} catch { self.error = "Preview failed. \(error.localizedDescription)" }
                    }
                } label: {
                    Label(previewing ? "Loading..." : "Preview voice", systemImage: "play.fill").foregroundStyle(.white)
                }.buttonStyle(SpeekActionButtonStyle()).disabled(previewing || !voices.contains(voice))
            }
        }
        .task { await load() }
        .onDisappear { previewTask?.cancel(); player?.stop() }
    }

    private func row<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { label(title, detail); Spacer(minLength: 10); content() }
            VStack(alignment: .leading, spacing: 10) {
                label(title, detail)
                content().frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
    private func label(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }.fixedSize()
    }
    private func display(_ id: String) -> String {
        switch id {
        case "openai/gpt-transcribe": return "OpenAI: GPT Transcribe"
        case "microsoft/mai-voice-2-flash": return "Microsoft: MAI Voice 2 Flash"
        default: return String(id.split(separator: "/").last ?? Substring(id)).replacingOccurrences(of: "-", with: " ").capitalized
        }
    }
    private func voiceTitle(_ id: String) -> String {
        id.replacingOccurrences(of: ":MAI-Voice-2", with: "")
            .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
    }
    private func fetch(_ modality: String) async throws -> [RouterAudioModel] {
        let url = URL(string: "https://openrouter.ai/api/v1/models?output_modalities=\(modality)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (root?["data"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
            let voices = item["supported_voices"] as? [String] ?? []
            // Voice-cloning-only models require a different flow, not a typed ID.
            guard modality != "speech" || !voices.isEmpty else { return nil }
            return RouterAudioModel(id: id, name: name, voices: voices)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            async let input = fetch("transcription")
            async let output = fetch("speech")
            (dictationModels, speechModels) = try await (input, output)
            if dictationModels.isEmpty || speechModels.isEmpty { error = "No audio models returned. Retry to refresh." }
        } catch { self.error = "Could not load audio options. Your selections are unchanged." }
    }
}

struct AudioOptionPicker: View {
    let title: String
    let selected: String
    let options: [(String, String)]
    let fallback: String
    let choose: (String) -> Void
    @State private var open = false
    @State private var search = ""
    var body: some View {
        Button { search = ""; open = true } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.0 == selected }?.1 ?? fallback).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(.white)
            }.padding(.horizontal, 10).frame(maxWidth: 250, minHeight: 26, alignment: .trailing).fixedSize(horizontal: true, vertical: false).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).disabled(options.isEmpty)
        .popover(isPresented: $open) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 14, weight: .semibold))
                TextField("Search", text: $search).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(options.filter { search.isEmpty || $0.1.localizedCaseInsensitiveContains(search) }, id: \.0) { option in
                            Button { choose(option.0); open = false } label: {
                                HStack {
                                    Text(option.1).font(.system(size: 12))
                                    Spacer()
                                    if selected == option.0 { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white) }
                                }.padding(8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(height: min(260, CGFloat(options.count) * 36))
            }.padding(16).frame(width: 340)
        }
    }
}
