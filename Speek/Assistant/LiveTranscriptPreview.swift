import Foundation
import AVFAudio
import Speech

/// Shows words in the notch while the user speaks. Recognized on this Mac with Apple's
/// speech framework and used only for display; the inserted text still comes from the
/// user's cloud dictation model. Silent (no preview) whenever the language or model is unavailable.
@MainActor
final class LiveTranscriptPreview: ObservableObject {
    static let shared = LiveTranscriptPreview()

    @Published private(set) var text = ""

    private var finalized = ""
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var tasks: [Task<Void, Never>] = []
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    private var generation = 0

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: "speek.dictation.livePreview") as? Bool ?? true }

    /// Starts listening and returns a handler for 16 kHz mono Int16 audio chunks.
    func start(languageCode: String?) -> ((Data) -> Void)? {
        stop()
        guard Self.isEnabled else { return nil }
        generation += 1
        let current = generation
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(64))
        input = continuation
        let requested = languageCode.map { Locale(identifier: $0) } ?? Locale.current
        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else { return }
                let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
                // The language model downloads once in the background; the first dictation may have no preview.
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
                guard current == self.generation else { return }
                let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) ?? self.sourceFormat
                self.targetFormat = format
                self.converter = format == self.sourceFormat ? nil : AVAudioConverter(from: self.sourceFormat, to: format)
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                self.analyzer = analyzer
                self.tasks.append(Task { [weak self] in
                    do {
                        for try await result in transcriber.results {
                            guard let self, current == self.generation else { return }
                            let chunk = String(result.text.characters)
                            if result.isFinal { self.finalized += chunk; self.text = self.finalized }
                            else { self.text = self.finalized + chunk }
                        }
                    } catch {}
                })
                try await analyzer.start(inputSequence: stream)
            } catch {}
        })
        return { [weak self] data in
            Task { @MainActor in self?.feed(data, generation: current) }
        }
    }

    func stop() {
        generation += 1
        input?.finish(); input = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        for task in tasks { task.cancel() }
        tasks = []
        converter = nil; targetFormat = nil
        finalized = ""; text = ""
    }

    private func feed(_ data: Data, generation current: Int) {
        guard current == generation, let input, targetFormat != nil else { return }
        let frames = AVAudioFrameCount(data.count / 2)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress, let destination = buffer.int16ChannelData?[0] {
                memcpy(destination, base, Int(frames) * 2)
            }
        }
        guard let converter, let targetFormat else { input.yield(AnalyzerInput(buffer: buffer)); return }
        let capacity = AVAudioFrameCount(Double(frames) * targetFormat.sampleRate / sourceFormat.sampleRate) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return buffer
        }
        if error == nil, output.frameLength > 0 { input.yield(AnalyzerInput(buffer: output)) }
    }
}
