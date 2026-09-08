import Foundation
import os

/// What the system's Now Playing slot currently holds.
struct NowPlayingInfo: Equatable {
    let bundleIdentifier: String?
    let processIdentifier: Int32?
    let title: String?
    let playing: Bool
    let playbackRate: Double

    /// Browsers sometimes report playing=false with a non-zero rate while a video runs.
    var isEffectivelyPlaying: Bool { playing || playbackRate > 0 }
}

/// Reads and controls the system Now Playing item through the vendored
/// MediaRemoteAdapter (Vendor/MediaRemoteAdapter). Since macOS 15.4 only
/// Apple-signed binaries may use MediaRemote, so nothing is linked: every call
/// spawns `/usr/bin/perl mediaremote-adapter.pl <framework> ...` and parses its
/// output. `get` prints one JSON object or `null`; `send` prints `true`/`false`.
final class NowPlayingAdapter: Sendable {
    static let shared = NowPlayingAdapter()

    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
    }

    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "NowPlayingAdapter")
    private let scriptURL: URL?
    private let frameworkURL: URL?

    private init() {
        scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")
        frameworkURL = Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework")
        if scriptURL == nil || frameworkURL.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true {
            logger.error("MediaRemoteAdapter is missing from the bundle; pausing playback is unavailable")
        }
    }

    var isAvailable: Bool {
        guard let scriptURL, let frameworkURL else { return false }
        return FileManager.default.fileExists(atPath: scriptURL.path) && FileManager.default.fileExists(atPath: frameworkURL.path)
    }

    /// One-shot, authoritative read. nil when nothing is registered as playing.
    func current() async -> NowPlayingInfo? {
        guard let output = await run(["get", "--no-artwork"]) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "null", let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return NowPlayingInfo(
            bundleIdentifier: object["bundleIdentifier"] as? String,
            processIdentifier: (object["processIdentifier"] as? NSNumber)?.int32Value,
            title: object["title"] as? String,
            playing: (object["playing"] as? Bool) ?? false,
            playbackRate: (object["playbackRate"] as? NSNumber)?.doubleValue ?? 0
        )
    }

    /// Sends a MediaRemote command to the Now Playing app. True when it was accepted.
    @discardableResult
    func send(_ command: Command) async -> Bool {
        guard let output = await run(["send", String(command.rawValue)]) else { return false }
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    private func run(_ arguments: [String], timeout: TimeInterval = 2.0) async -> String? {
        guard let scriptURL, let frameworkURL, isAvailable else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkURL.path] + arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    self.logger.error("Could not start the adapter: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()
                if process.terminationReason != .exit {
                    self.logger.error("Adapter \(arguments.first ?? "", privacy: .public) timed out")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }
}
