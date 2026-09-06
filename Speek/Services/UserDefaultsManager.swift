import Foundation

extension UserDefaults {
    enum Keys {
        static let audioInputMode = "audioInputMode"
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
        static let selectedAudioDeviceModelUID = "selectedAudioDeviceModelUID"
        static let prioritizedDevices = "prioritizedDevices"
        static let affiliatePromotionDismissed = "SpeekAffiliatePromotionDismissed"
        static let preferredLanguageHints = "PreferredLanguageHints"
    }

    static let defaultPreferredLanguageHints = ["cs", "en"]

    var audioInputModeRawValue: String? {
        get { string(forKey: Keys.audioInputMode) }
        set { setValue(newValue, forKey: Keys.audioInputMode) }
    }

    var selectedAudioDeviceUID: String? {
        get { string(forKey: Keys.selectedAudioDeviceUID) }
        set { setValue(newValue, forKey: Keys.selectedAudioDeviceUID) }
    }

    var selectedAudioDeviceModelUID: String? {
        get { string(forKey: Keys.selectedAudioDeviceModelUID) }
        set { setValue(newValue, forKey: Keys.selectedAudioDeviceModelUID) }
    }

    var prioritizedDevicesData: Data? {
        get { data(forKey: Keys.prioritizedDevices) }
        set { setValue(newValue, forKey: Keys.prioritizedDevices) }
    }

    var affiliatePromotionDismissed: Bool {
        get { bool(forKey: Keys.affiliatePromotionDismissed) }
        set { setValue(newValue, forKey: Keys.affiliatePromotionDismissed) }
    }

    /// Languages the user dictates in, used as Soniox auto-detect hints. Stored as a
    /// comma-joined string (e.g. "cs,en"). Never empty — falls back to Czech + English.
    var preferredLanguageHints: [String] {
        get {
            let raw = string(forKey: Keys.preferredLanguageHints) ?? ""
            let codes = raw.split(separator: ",").map(String.init)
            return codes.isEmpty ? Self.defaultPreferredLanguageHints : codes
        }
        set {
            let codes = newValue.isEmpty ? Self.defaultPreferredLanguageHints : newValue
            setValue(codes.joined(separator: ","), forKey: Keys.preferredLanguageHints)
        }
    }
}
