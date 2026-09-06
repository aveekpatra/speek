import Testing
import Foundation
import SwiftData
@testable import Speek

@MainActor
struct InsightsLoaderTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SessionMetric.self, configurations: config)
    }

    private func metric(
        words: Int,
        at date: Date,
        app: String?,
        bundle: String?,
        duration: TimeInterval = 60
    ) -> SessionMetric {
        SessionMetric(
            transcriptionId: UUID(),
            timestamp: date,
            source: "recorder",
            appName: app,
            appBundleId: bundle,
            wordCount: words,
            audioDuration: duration,
            transcriptionModelName: nil,
            transcriptionDuration: nil,
            speedFactor: nil,
            modeName: "General",
            aiEnhancementModelName: nil,
            enhancementDuration: nil
        )
    }

    @Test func aggregatesAppsHoursAndStreak() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Use the local calendar so hour-of-day buckets line up with the loader,
        // which intentionally aggregates in the user's local time zone.
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 15))!
        func day(_ offset: Int, hour: Int = 15) -> Date {
            calendar.date(byAdding: .day, value: -offset, to:
                calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!)!
        }

        // Today + yesterday + 2 days ago active → current streak 3.
        context.insert(metric(words: 100, at: day(0), app: "Cursor", bundle: "com.todesktop.cursor"))
        context.insert(metric(words: 50, at: day(0, hour: 9), app: "Cursor", bundle: "com.todesktop.cursor"))
        context.insert(metric(words: 80, at: day(1), app: "Safari", bundle: "com.apple.Safari"))
        context.insert(metric(words: 40, at: day(2), app: "Cursor", bundle: "com.todesktop.cursor"))
        // Gap at day 3, then an older active day.
        context.insert(metric(words: 30, at: day(5), app: "Slack", bundle: "com.tinyspeck.slackmacgap"))
        // A self-dictation that must be excluded from top apps.
        context.insert(metric(words: 999, at: day(0), app: "Speek", bundle: "com.aveekpatra.speek"))
        try context.save()

        let data = try #require(try await InsightsLoader.load(from: container, now: now))

        // Top apps: Cursor (3) > Safari (1) == Slack (1); self excluded.
        #expect(data.topApps.first?.name == "Cursor")
        #expect(data.topApps.first?.count == 3)
        #expect(!data.topApps.contains { $0.name == "Speek" })

        // Hours: words logged at 15:00 and 09:00.
        #expect(data.hourBuckets[15].value > 0)
        #expect(data.hourBuckets[9].value > 0)

        // Streak: today, -1, -2 active (gap at -3) → current 3.
        #expect(data.currentStreak == 3)
        #expect(data.longestStreak >= 3)

        // Day grid ends today with the summed word count (100 + 50 + 999 self).
        #expect(data.days.last?.count == 1149)

        // All-time words stay daily, beginning on the first tracked day and
        // preserving empty calendar days between it and today.
        let allTime = try #require(data.wordsByRange[.total])
        #expect(allTime.count == 6)
        #expect(calendar.isDate(allTime[0].date, inSameDayAs: day(5)))
        #expect(allTime[0].value == 30)
        #expect(allTime[2].value == 0)
        #expect(calendar.isDate(allTime[5].date, inSameDayAs: day(0)))
        #expect(allTime[5].value == 1149)
    }

    @Test func returnsNilWhenEmpty() async throws {
        let container = try makeContainer()
        let data = try await InsightsLoader.load(from: container, now: Date())
        #expect(data == nil)
    }
}
