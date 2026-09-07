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
        // Each slot resolves to exactly one file (style default, bundled, macOS system
        // sound, or an imported file); nil means that slot is silent.
        playbackEngine.setup(
            defaultStartURL: customSoundManager.resolvedURL(for: .start),
            defaultStopURL: customSoundManager.resolvedURL(for: .stop),
            defaultEscURL: CustomSoundManager.escapeSoundURL,
            customStartURL: nil,
            customStopURL: nil
        )
    }

    @objc private func reloadCustomSounds() {
        setupSounds()
    }

    private var isEnabled: Bool {
        CustomSoundManager.shared.isEnabled
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
