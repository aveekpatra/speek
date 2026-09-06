import Foundation
import SwiftData

@Model
final class SessionMetric {
    var id: UUID = UUID()
    var transcriptionId: UUID = UUID()
    var timestamp: Date = Date()
    var source: String?
    /// Display name of the app the user dictated into, e.g. "Cursor". Optional —
    /// only populated for sessions recorded after app capture shipped.
    var appName: String?
    /// Bundle identifier of that app, used to filter out Speek itself.
    var appBundleId: String?
    var wordCount: Int = 0
    var audioDuration: TimeInterval = 0
    var transcriptionModelName: String?
    var transcriptionDuration: TimeInterval?
    var speedFactor: Double?
    @Attribute(originalName: "powerModeName")
    var modeName: String?
    var aiEnhancementModelName: String?
    var enhancementDuration: TimeInterval?

    init(
        transcriptionId: UUID,
        timestamp: Date = Date(),
        source: String? = "recorder",
        appName: String? = nil,
        appBundleId: String? = nil,
        wordCount: Int,
        audioDuration: TimeInterval,
        transcriptionModelName: String?,
        transcriptionDuration: TimeInterval?,
        speedFactor: Double?,
        modeName: String?,
        aiEnhancementModelName: String?,
        enhancementDuration: TimeInterval?
    ) {
        self.id = UUID()
        self.transcriptionId = transcriptionId
        self.timestamp = timestamp
        self.source = source
        self.appName = appName
        self.appBundleId = appBundleId
        self.wordCount = wordCount
        self.audioDuration = audioDuration
        self.transcriptionModelName = transcriptionModelName
        self.transcriptionDuration = transcriptionDuration
        self.speedFactor = speedFactor
        self.modeName = modeName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.enhancementDuration = enhancementDuration
    }
}
