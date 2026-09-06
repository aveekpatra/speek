import Foundation

enum AppDefaults {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            // Onboarding & General
            "hasCompletedOnboardingV2": false,
            "hasPreparedOnboardingV2": false,
            "enableAnnouncements": true,

            // Clipboard
            "restoreClipboardAfterPaste": true,
            "clipboardRestoreDelay": 2.0,

            // Audio & Media
            "isSystemMuteEnabled": false,
            "audioResumptionDelay": 0.0,
            "isPauseMediaEnabled": true,
            CustomSoundManager.SoundType.start.builtInSoundKey: CustomSoundManager.SoundType.start.defaultBuiltInSound.rawValue,
            CustomSoundManager.SoundType.stop.builtInSoundKey: CustomSoundManager.SoundType.stop.defaultBuiltInSound.rawValue,

            // Recording & Transcription
            "IsTextFormattingEnabled": true,
            "IsVADEnabled": true,
            "RemovePunctuation": false,
            "LowercaseTranscription": false,
            // Default only for transcription paths that fall back to
            // TranscriptionRequestContext.currentDefaults (e.g. file transcription); "auto"
            // keeps those language-agnostic, a concrete code would pin them to one language.
            // Live dictation resolves its language from the active mode, not this key.
            "SelectedLanguage": "auto",
            "AppendTrailingSpace": true,
            "RecorderType": "mini",

            // Cleanup
            "IsTranscriptionCleanupEnabled": false,
            "TranscriptionRetentionMinutes": 1440,
            "IsAudioCleanupEnabled": false,
            "AudioRetentionPeriod": 7,

            // UI & Behavior
            "IsMenuBarOnly": false,
            // Shortcuts
            "isMiddleClickToggleEnabled": false,
            "middleClickActivationDelay": 200,

            // Enhancement
            "SkipShortEnhancement": true,
            "ShortEnhancementWordThreshold": 3,
            "EnhancementTimeoutSeconds": 7,
            "EnhancementRetryOnTimeout": true,

            // Model
            "PrewarmModelOnWake": true,

            // English Coach
            "englishCoachEnabled": false,
            "englishCoachNativeLanguage": "cs",

        ])

        // One-time switch to pausing media (instead of muting) while recording.
        // Forces the new behavior once even for users who had the old defaults
        // persisted, then respects any future manual changes.
        if !UserDefaults.standard.bool(forKey: "didMigrateToPauseMediaDefault") {
            UserDefaults.standard.set(true, forKey: "isPauseMediaEnabled")
            UserDefaults.standard.set(false, forKey: "isSystemMuteEnabled")
            UserDefaults.standard.set(true, forKey: "didMigrateToPauseMediaDefault")
        }

        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded()
    }
}
