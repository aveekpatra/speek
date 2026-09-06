import Foundation
import SwiftUI

@MainActor
class SoundManager: ObservableObject {
    static let shared = SoundManager()

    private let playbackEngine = SoundPlaybackEngine()

    private init() {
        setupSounds()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadCustomSounds),
            name: NSNotification.Name("CustomSoundsChanged"),
            object: nil
        )
    }

    private func setupSounds() {
        let customSoundManager = CustomSoundManager.shared
        playbackEngine.setup(
            defaultStartURL: customSoundManager.builtInSoundURL(for: .start),
            defaultStopURL: customSoundManager.builtInSoundURL(for: .stop),
            defaultEscURL: CustomSoundManager.BuiltInSound.sound7.bundleURL,
            customStartURL: customSoundManager.getCustomSoundURL(for: .start),
            customStopURL: customSoundManager.getCustomSoundURL(for: .stop)
        )
    }

    @objc private func reloadCustomSounds() {
        setupSounds()
    }

    private var isEnabled: Bool {
        SpeekSettings.shared.soundEffects != .off
    }

    private func applyVolume() {
        playbackEngine.volumeMultiplier = Float(SpeekSettings.shared.soundVolume)
    }

    func playStartSound() {
        guard isEnabled else { return }
        applyVolume()
        playbackEngine.playStartSound()
    }

    func playStopSound() {
        guard isEnabled else { return }
        applyVolume()
        playbackEngine.playStopSound()
    }

    func playEscSound() {
        guard isEnabled else { return }
        applyVolume()
        playbackEngine.playEscSound()
    }
}
