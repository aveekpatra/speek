import Foundation
import AVFoundation

enum AudioChunks {
    /// Keep each upload below the provider limit while preserving every recorded frame.
    static func splitIfNeeded(_ source: URL) throws -> [URL] {
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size >= 20_000_000 else { return [source] }
        let file = try AVAudioFile(forReading: source)
        let format = file.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0 else { throw ActionClientError.invalidResponse }
        let bytesPerSecond = format.sampleRate * Double(format.channelCount) * 4
        let seconds = min(300, 16_000_000 / bytesPerSecond)
        let frames = AVAudioFrameCount(max(1, seconds * format.sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw ActionClientError.invalidResponse }
        var chunks: [URL] = []
        do {
            while file.framePosition < file.length {
                try Task.checkCancellation()
                try file.read(into: buffer, frameCount: min(frames, AVAudioFrameCount(file.length - file.framePosition)))
                guard buffer.frameLength > 0 else { break }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("speek-audio-\(UUID().uuidString).wav")
                chunks.append(url)
                let output = try AVAudioFile(forWriting: url, settings: file.fileFormat.settings,
                                             commonFormat: format.commonFormat, interleaved: format.isInterleaved)
                try output.write(from: buffer)
            }
            return chunks
        } catch {
            for url in chunks { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }
}
