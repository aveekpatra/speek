import Foundation
import AVFAudio
import Speech

/// Listens for "Hey <name>" and starts an agent request, like holding the shortcut. Recognition
/// runs on this Mac with Apple's speech framework; nothing is sent anywhere until the phrase is
/// heard and the request itself is recorded. Off by default: while it listens, the microphone
/// stays on (macOS shows its indicator).
@MainActor
final class WakeWordListener: ObservableObject {
    static let shared = WakeWordListener()
    static let enabledKey = "speek.wake.enabled"
    static let nameKey = "speek.wake.name"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var name: String {
        let saved = UserDefaults.standard.string(forKey: nameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? "Speek" : saved
    }

    /// Called on the main actor when the phrase is heard.
    var onWake: (() -> Void)?
    @Published private(set) var listening = false
    @Published private(set) var problem: String?

    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var tasks: [Task<Void, Never>] = []
    private var generation = 0

    func start() {
        guard Self.isEnabled, !listening else { return }
        generation += 1
        let current = generation
        listening = true
        problem = nil
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(32))
        input = continuation
        let name = Self.name
        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
                    throw WakeError.message("English speech recognition is not available on this Mac.")
                }
                let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
                guard current == self.generation else { return }
                let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                self.analyzer = analyzer
                try self.startMicrophone(converting: format, generation: current)
                self.tasks.append(Task { [weak self] in
                    do {
                        for try await result in transcriber.results {
                            guard let self, current == self.generation else { return }
                            if Self.matches(String(result.text.characters), name: name) {
                                self.stop()
                                self.onWake?()
                                return
                            }
                        }
                    } catch {}
                })
                try await analyzer.start(inputSequence: stream)
            } catch {
                guard current == self.generation else { return }
                self.problem = (error as? WakeError)?.message ?? "Listening could not start: " + error.localizedDescription
                self.stop()
            }
        })
    }

    func stop() {
        generation += 1
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        input?.finish(); input = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        tasks.forEach { $0.cancel() }
        tasks = []
        listening = false
    }

    /// Restarts with the current settings (after the name or switch changes).
    func refresh() {
        stop()
        start()
    }

    private func startMicrophone(converting format: AVAudioFormat?, generation current: Int) throws {
        let engine = AVAudioEngine()
        let node = engine.inputNode
        let source = node.outputFormat(forBus: 0)
        guard source.sampleRate > 0 else { throw WakeError.message("No microphone is available.") }
        let target = format ?? source
        let converter = target == source ? nil : AVAudioConverter(from: source, to: target)
        let continuation = input
        node.installTap(onBus: 0, bufferSize: 4096, format: source) { buffer, _ in
            guard let converter else { continuation?.yield(AnalyzerInput(buffer: buffer)); return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / source.sampleRate) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            if error == nil, output.frameLength > 0 { continuation?.yield(AnalyzerInput(buffer: output)) }
        }
        engine.prepare()
        try engine.start()
        guard current == generation else { engine.inputNode.removeTap(onBus: 0); engine.stop(); return }
        self.engine = engine
    }

    /// "Hey Speek", "hi Speek", "okay Speek", tolerant of recognition near-misses of the name
    /// ("hey speak") and of it being split into two words ("hey spee k").
    nonisolated static func matches(_ text: String, name: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let target = name.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !target.isEmpty, words.count >= 2 else { return false }
        let greetings: Set<String> = ["hey", "hi", "hello", "okay", "ok", "yo", "hay"]
        let tolerance = target.count <= 5 ? 1 : 2
        for index in words.indices.dropLast() where greetings.contains(words[index]) {
            let one = words[index + 1]
            let two = index + 2 < words.count ? one + words[index + 2] : one
            if distance(one, target) <= tolerance || distance(two, target) <= tolerance { return true }
        }
        return false
    }

    nonisolated private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]; row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }

    private enum WakeError: Error {
        case message(String)
        var message: String { if case .message(let text) = self { return text }; return "" }
    }
}
