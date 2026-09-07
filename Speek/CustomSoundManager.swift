import Foundation
import AVFoundation
import SwiftUI

/// The recording sounds. One setting: a collection, which is a start/stop pair (or
/// Off). Simple and Classic are collections like any other; Custom is two files of the
/// user's own. Nothing else to toggle.
class CustomSoundManager: ObservableObject {
    static let shared = CustomSoundManager()

    enum Collection: String, CaseIterable, Identifiable {
        case off
        case simple
        case classic
        case ticks
        case bells
        case soft
        case glass
        case ping
        case hero
        case blow
        case morse
        case frog
        case custom

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .off: return "Off"
            case .simple: return "Simple"
            case .classic: return "Classic"
            case .ticks: return "Ticks"
            case .bells: return "Bells"
            case .soft: return "Soft"
            case .glass: return "Glass"
            case .ping: return "Ping"
            case .hero: return "Hero"
            case .blow: return "Blow"
            case .morse: return "Morse"
            case .frog: return "Frog"
            case .custom: return "Custom..."
            }
        }

        /// Start and stop files. macOS system sounds by name, Speek's own by resource.
        var pair: (start: URL?, stop: URL?) {
            switch self {
            case .off: return (nil, nil)
            case .simple: return (system("Tink"), system("Pop"))
            case .classic: return (bundled("sound5", "mp3"), bundled("sound6", "mp3"))
            case .ticks: return (bundled("sound8", "wav"), bundled("sound9", "wav"))
            case .bells: return (bundled("sound1", "wav"), bundled("sound2", "wav"))
            case .soft: return (bundled("sound3", "wav"), bundled("sound4", "wav"))
            case .glass: return (system("Glass"), system("Purr"))
            case .ping: return (system("Ping"), system("Bottle"))
            case .hero: return (system("Hero"), system("Submarine"))
            case .blow: return (system("Blow"), system("Funk"))
            case .morse: return (system("Morse"), system("Basso"))
            case .frog: return (system("Frog"), system("Sosumi"))
            case .custom: return (nil, nil)   // resolved from the imported files
            }
        }

        private func system(_ name: String) -> URL {
            URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        }

        private func bundled(_ name: String, _ ext: String) -> URL? {
            Bundle.main.url(forResource: name, withExtension: ext) ??
                Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds")
        }
    }

    enum SoundType: String, CaseIterable {
        case start
        case stop
        var standardName: String { "Custom\(rawValue.capitalized)Sound" }
        var fileKey: String { "speek.sound.custom.\(rawValue)" }
    }

    static let escapeSoundURL: URL? = Bundle.main.url(forResource: "sound7", withExtension: "wav") ??
        Bundle.main.url(forResource: "sound7", withExtension: "wav", subdirectory: "Sounds")

    private static let collectionKey = "speek.sound.collection"
    private let maxSoundDuration: TimeInterval = 3.0

    @Published var collection: Collection {
        didSet {
            UserDefaults.standard.set(collection.rawValue, forKey: Self.collectionKey)
            UserDefaults.standard.set(collection != .off, forKey: "isSoundFeedbackEnabled")
            notifyChanged()
        }
    }

    /// Imported file names for the Custom collection (under Application Support).
    @Published private(set) var customStartFile: String?
    @Published private(set) var customStopFile: String?

    private init() {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Self.collectionKey), let saved = Collection(rawValue: stored) {
            collection = saved
        } else {
            // One-time carry-over from the old Simple / Classic / Off style setting.
            switch defaults.string(forKey: "speek.soundEffects") {
            case "off": collection = .off
            case "simple": collection = .simple
            default: collection = .classic
            }
        }
        customStartFile = defaults.string(forKey: SoundType.start.fileKey)
        customStopFile = defaults.string(forKey: SoundType.stop.fileKey)
        createCustomSoundsDirectoryIfNeeded()
    }

    var isEnabled: Bool { collection != .off }

    var hasAnyRecordingSoundEnabled: Bool { isEnabled }

    /// The file that plays for this slot with the current collection; nil is silence.
    func resolvedURL(for type: SoundType) -> URL? {
        if collection == .custom {
            let file = type == .start ? customStartFile : customStopFile
            return file.flatMap { customSoundsDirectory()?.appendingPathComponent($0) }
        }
        let pair = collection.pair
        return type == .start ? pair.start : pair.stop
    }

    func customFileName(for type: SoundType) -> String? {
        let file = type == .start ? customStartFile : customStopFile
        return file.map { ($0 as NSString).deletingPathExtension }
    }

    // MARK: Imported files

    func setCustomSound(url: URL, for type: SoundType) -> Result<Void, CustomSoundError> {
        if case .failure(let error) = validateAudioFile(url: url) { return .failure(error) }
        switch copySoundFile(from: url, standardName: type.standardName) {
        case .success(let filename):
            if type == .start { customStartFile = filename } else { customStopFile = filename }
            UserDefaults.standard.set(filename, forKey: type.fileKey)
            if collection != .custom { collection = .custom } else { notifyChanged() }
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: NSNotification.Name("CustomSoundsChanged"), object: nil)
    }

    private func customSoundsDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Speek/CustomSounds")
    }

    private func createCustomSoundsDirectoryIfNeeded() {
        guard let directory = customSoundsDirectory() else { return }
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func copySoundFile(from sourceURL: URL, standardName: String) -> Result<String, CustomSoundError> {
        guard let directory = customSoundsDirectory() else { return .failure(.directoryCreationFailed) }
        let newFilename = "\(standardName).\(sourceURL.pathExtension)"
        let destinationURL = directory.appendingPathComponent(newFilename)
        if sourceURL.resolvingSymlinksInPath() == destinationURL.resolvingSymlinksInPath() { return .success(newFilename) }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return .success(newFilename)
        } catch {
            return .failure(.fileCopyFailed)
        }
    }

    private func validateAudioFile(url: URL) -> Result<Void, CustomSoundError> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .failure(.fileNotFound) }
        let duration = AVAsset(url: url).duration.seconds
        guard duration.isFinite && duration > 0 else { return .failure(.invalidAudioFile) }
        if duration > maxSoundDuration {
            return .failure(.durationTooLong(duration: duration, maxDuration: maxSoundDuration))
        }
        do { _ = try AVAudioPlayer(contentsOf: url) } catch { return .failure(.invalidAudioFile) }
        return .success(())
    }
}

enum CustomSoundError: LocalizedError {
    case fileNotFound
    case invalidAudioFile
    case durationTooLong(duration: TimeInterval, maxDuration: TimeInterval)
    case directoryCreationFailed
    case fileCopyFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return String(localized: "Audio file not found")
        case .invalidAudioFile:
            return String(localized: "Invalid audio file format")
        case .durationTooLong(let duration, let maxDuration):
            return String(format: String(localized: "Audio file is %.1f seconds long. Please use an audio file that is %.0f seconds or shorter for start and stop sounds."), duration, maxDuration)
        case .directoryCreationFailed:
            return String(localized: "Failed to create custom sounds directory")
        case .fileCopyFailed:
            return String(localized: "Failed to copy audio file")
        }
    }
}
