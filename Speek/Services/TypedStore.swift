import Foundation
import SwiftData
import OSLog

/// Dedicated, single-store SwiftData container for the typed-words metrics
/// (the gray "Napsáno" line: `TypedDailyMetric`, `ProcessedLog`,
/// `TypedPromptSignature`).
///
/// Why a separate container? Saving these aggregates through the app's main
/// 5-store container from a background `ModelContext` made SwiftData abort with an
/// (uncatchable) dynamic-cast failure inside `save()` — the multi-store routing
/// chokes on the background insert/save. An isolated single-store container writes
/// cleanly. This also matches the original design intent: the typed metrics are
/// derived from the chat logs, additive, and never touch the dictation data.
///
/// The data is safe to rebuild, so it lives in its own file (`typed-v3.store`).
/// Both the ingest (writer) and `InsightsLoader` (reader) use this one container.
enum TypedStore {
    private static let logger = Logger(subsystem: "com.aveekpatra.speek", category: "TypedStore")

    /// Built once, lazily. `nil` only if the store can't be opened — callers then
    /// skip typed work instead of crashing.
    static let container: ModelContainer? = {
        do {
            // Same Application Support location the main stores use.
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.aveekpatra.speek", isDirectory: true)
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            let url = appSupportURL.appendingPathComponent("typed-v3.store")
            let schema = Schema([TypedDailyMetric.self, ProcessedLog.self, TypedPromptSignature.self])
            let config = ModelConfiguration("typed", schema: schema, url: url, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            logger.error("Failed to open dedicated typed store: \(error, privacy: .public)")
            return nil
        }
    }()
}
