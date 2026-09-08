import AppKit
import Combine
import Foundation
import os

/// "Playback when recording: Pause". Pauses whatever holds the system Now Playing
/// slot (Music, Spotify, a video in a browser) when a recording starts and resumes
/// it when the recording stops, if it is still the same item and still paused.
@MainActor
final class PlaybackController: ObservableObject {
    static let shared = PlaybackController()

    private struct PausedItem {
        let bundleIdentifier: String
        let title: String?
    }

    private let adapter = NowPlayingAdapter.shared
    private var pausedItem: PausedItem?
    private var resumeTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "PlaybackController")

    @Published var isPauseMediaEnabled: Bool = UserDefaults.standard.bool(forKey: "isPauseMediaEnabled") {
        didSet { UserDefaults.standard.set(isPauseMediaEnabled, forKey: "isPauseMediaEnabled") }
    }

    private init() {}

    func pauseMedia() async {
        resumeTask?.cancel()
        resumeTask = nil
        pausedItem = nil

        guard isPauseMediaEnabled else { return }
        guard adapter.isAvailable else {
            logger.error("pauseMedia: adapter unavailable")
            return
        }

        guard let info = await adapter.current(), info.isEffectivelyPlaying, let bundleID = info.bundleIdentifier else {
            logger.notice("pauseMedia: nothing playing")
            return
        }
        logger.notice("pauseMedia: pausing \(bundleID, privacy: .public) (\(info.title ?? "", privacy: .public))")

        let accepted = await adapter.send(.pause)
        try? await Task.sleep(nanoseconds: 200_000_000)
        let after = await adapter.current()
        let stillPlaying = after?.bundleIdentifier == bundleID && (after?.isEffectivelyPlaying ?? false)
        if stillPlaying {
            // Some apps ignore the MediaRemote command but honour the hardware key.
            logger.notice("pauseMedia: pause command \(accepted ? "accepted" : "rejected") but still playing; sending the media key")
            Self.sendMediaPlayPauseKey()
        }
        pausedItem = PausedItem(bundleIdentifier: bundleID, title: info.title)
    }

    func resumeMedia() async {
        guard let paused = pausedItem else { return }
        pausedItem = nil
        guard isPauseMediaEnabled, isAppRunning(bundleID: paused.bundleIdentifier) else { return }

        let delay = MediaController.shared.audioResumptionDelay
        let task = Task { [adapter, logger] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }

            // Only resume what we paused: same app, still paused. If the user started
            // something else meanwhile, or resumed it themselves, leave it alone.
            let info = await adapter.current()
            guard let info, info.bundleIdentifier == paused.bundleIdentifier, !info.isEffectivelyPlaying else {
                logger.notice("resumeMedia: not resuming (now playing: \(info?.bundleIdentifier ?? "none", privacy: .public), playing=\(info?.isEffectivelyPlaying ?? false))")
                return
            }
            logger.notice("resumeMedia: resuming \(paused.bundleIdentifier, privacy: .public)")
            let accepted = await adapter.send(.play)
            try? await Task.sleep(nanoseconds: 200_000_000)
            let after = await adapter.current()
            if after?.bundleIdentifier == paused.bundleIdentifier, !(after?.isEffectivelyPlaying ?? false) {
                logger.notice("resumeMedia: play command \(accepted ? "accepted" : "rejected") but still paused; sending the media key")
                Self.sendMediaPlayPauseKey()
            }
        }
        resumeTask = task
        await task.value
    }

    /// Simulate the hardware media Play/Pause key (NX_KEYTYPE_PLAY = 16). Some apps
    /// (Plexamp among them) ignore MediaRemote commands but respond to the key the
    /// physical F8 produces.
    private static func sendMediaPlayPauseKey() {
        func post(down: Bool) {
            let flags: UInt = down ? 0xa00 : 0xb00
            let data1 = Int((16 << 16) | ((down ? 0xa : 0xb) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }

    private func isAppRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }
}
