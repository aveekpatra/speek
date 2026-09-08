import Foundation
import CoreAudio
import AudioToolbox
import os

final class MediaController: ObservableObject {

    static let shared = MediaController()

    private var didMuteAudio = false
    /// Output volume before we silenced a device that has no mute control (many
    /// Bluetooth headphones); restored on unmute.
    private var savedVolume: Float32?
    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "MediaController")
    private var unmuteTask: Task<Void, Never>?
    private var muteGeneration: Int = 0

    @Published var isSystemMuteEnabled: Bool = UserDefaults.standard.bool(forKey: "isSystemMuteEnabled") {
        didSet { UserDefaults.standard.set(isSystemMuteEnabled, forKey: "isSystemMuteEnabled") }
    }

    @Published var audioResumptionDelay: Double = UserDefaults.standard.double(forKey: "audioResumptionDelay") {
        didSet { UserDefaults.standard.set(audioResumptionDelay, forKey: "audioResumptionDelay") }
    }

    private init() {}

    func muteSystemAudio() async -> Bool {
        guard isSystemMuteEnabled else { return false }

        unmuteTask?.cancel()
        unmuteTask = nil
        muteGeneration += 1

        // Fully mute output during recording so background playback can't bleed into the
        // mic at all. (Ducking left it faintly audible, which the mic still picked up.)
        let success = setSystemMuted(true)
        didMuteAudio = success
        return success
    }

    func unmuteSystemAudio() async {
        guard isSystemMuteEnabled else { return }

        let delay = audioResumptionDelay
        let myGeneration = muteGeneration

        let task = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard let self = self else { return }
            guard !Task.isCancelled else { return }
            guard self.muteGeneration == myGeneration else { return }

            // Always force output back on after a recording. We never want playback to
            // stay silenced, so unmute unconditionally rather than tracking who muted —
            // that bookkeeping was what got stuck and left the system permanently muted.
            _ = self.setSystemMuted(false)
            self.didMuteAudio = false
        }

        unmuteTask = task
        await task.value
    }

    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        return status == noErr ? deviceID : nil
    }

    /// Mutes or unmutes the default output device. Prefers the device's own mute
    /// control; devices without one (common over Bluetooth) get their volume set
    /// to zero and restored instead.
    private func setSystemMuted(_ muted: Bool) -> Bool {
        guard let deviceID = getDefaultOutputDevice() else {
            logger.error("No default output device")
            return false
        }

        if setMuteProperty(on: deviceID, muted: muted) {
            return true
        }

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(deviceID, &volumeAddress),
              AudioObjectIsPropertySettable(deviceID, &volumeAddress, &settable) == noErr, settable.boolValue else {
            logger.error("Output device \(deviceID) has neither a mute nor a volume control")
            return false
        }
        let size = UInt32(MemoryLayout<Float32>.size)
        if muted {
            var current: Float32 = 0
            var readSize = size
            if AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &readSize, &current) == noErr {
                savedVolume = current
            }
            var zero: Float32 = 0
            let status = AudioObjectSetPropertyData(deviceID, &volumeAddress, 0, nil, size, &zero)
            if status != noErr { logger.error("Setting volume to zero failed: \(status)") }
            return status == noErr
        } else {
            guard var restore = savedVolume else { return true }
            savedVolume = nil
            let status = AudioObjectSetPropertyData(deviceID, &volumeAddress, 0, nil, size, &restore)
            if status != noErr { logger.error("Restoring volume failed: \(status)") }
            return status == noErr
        }
    }

    private func setMuteProperty(on deviceID: AudioDeviceID, muted: Bool) -> Bool {
        var muteValue: UInt32 = muted ? 1 : 0
        let propertySize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 0
            if !AudioObjectHasProperty(deviceID, &address) { return false }
        }

        var isSettable: DarwinBoolean = false
        var status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        if status != noErr || !isSettable.boolValue { return false }

        status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, propertySize, &muteValue)
        if status != noErr { logger.error("Setting mute=\(muted) failed: \(status)") }
        return status == noErr
    }
}
