import Foundation
@preconcurrency import AVFoundation
import os

final class SoundPlaybackEngine: @unchecked Sendable {
    private enum Sound {
        case start
        case stop
        case esc
    }

    private let queue = DispatchQueue(label: "com.prakashjoshipax.whisperpro.soundPlayback", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.prakashjoshipax.whisperpro", category: "SoundPlaybackEngine")

    private var startSound: AVAudioPlayer?
    private var stopSound: AVAudioPlayer?
    private var escSound: AVAudioPlayer?
    private var customStartSound: AVAudioPlayer?
    private var customStopSound: AVAudioPlayer?
    /// 0...1 user volume from Sound settings, applied on top of each clip's base level.
    var volumeMultiplier: Float = 1

    func setup(
        defaultStartURL: URL?,
        defaultStopURL: URL?,
        defaultEscURL: URL?,
        customStartURL: URL?,
        customStopURL: URL?
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            self.startSound = self.makePlayer(from: defaultStartURL, volume: 0.6)
            self.stopSound = self.makePlayer(from: defaultStopURL, volume: 0.6)
            self.escSound = self.makePlayer(from: defaultEscURL, volume: 0.45)
            self.reloadCustomSoundsOnQueue(startURL: customStartURL, stopURL: customStopURL)
        }
    }

    func reloadCustomSounds(startURL: URL?, stopURL: URL?) {
        queue.async { [weak self] in
            self?.reloadCustomSoundsOnQueue(startURL: startURL, stopURL: stopURL)
        }
    }

    func playStartSound() {
        play(.start)
    }

    func playStopSound() {
        play(.stop)
    }

    func playEscSound() {
        play(.esc)
    }

    private func reloadCustomSoundsOnQueue(startURL: URL?, stopURL: URL?) {
        if customStartSound?.isPlaying == true {
            customStartSound?.stop()
        }
        if customStopSound?.isPlaying == true {
            customStopSound?.stop()
        }

        customStartSound = makePlayer(from: startURL, volume: 0.4)
        customStopSound = makePlayer(from: stopURL, volume: 0.4)
    }

    private func play(_ sound: Sound) {
        queue.async { [weak self] in
            guard let self else { return }

            let player: AVAudioPlayer?
            switch sound {
            case .start:
                player = self.customStartSound ?? self.startSound
            case .stop:
                player = self.customStopSound ?? self.stopSound
            case .esc:
                player = self.escSound
            }

            guard let player else { return }
            player.volume = self.baseVolume(for: sound) * self.volumeMultiplier
            player.currentTime = 0
            player.play()
        }
    }

    private func baseVolume(for sound: Sound) -> Float {
        sound == .esc ? 0.45 : 0.6
    }

    private func makePlayer(from url: URL?, volume: Float) -> AVAudioPlayer? {
        guard let url else { return nil }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            return player
        } catch {
            logger.error("Failed to load sound: \(error, privacy: .public)")
            return nil
        }
    }
}
