import Foundation

/// One-time migration: the "dots", "sine line", and "signal ribbon" waveform styles were
/// removed (replaced by "claude"). A prior selection pointing at one of those removed
/// slots falls back to "bars" instead of silently landing on whatever style now occupies
/// that index.
enum WaveformStyleMigration {
    private static let styleKey = "WaveformStyle"
    private static let migratedKey = "hasMigratedWaveformStyleV2"

    static func prepareIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        if defaults.integer(forKey: styleKey) != 0 {
            defaults.set(0, forKey: styleKey)
        }
        defaults.set(true, forKey: migratedKey)
    }
}
