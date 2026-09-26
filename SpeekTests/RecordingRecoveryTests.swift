import XCTest
@testable import Speek

@MainActor
final class RecordingRecoveryTests: XCTestCase {
    func testPrivacyDedupRetentionAndExpiry() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "RecordingRecoveryTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var clock = Date()
        let recovery = RecordingRecovery(directory: dir.appendingPathComponent("backups"), defaults: defaults, now: { clock })
        let audio = dir.appendingPathComponent("audio.wav")
        try Data([1, 2, 3]).write(to: audio)
        XCTAssertNil(recovery.save(audioURL: audio, appName: "Mail"))
        defaults.set(true, forKey: "speek.voice.recordingRecovery")
        defaults.set(false, forKey: "speek.assistant.saveHistory")
        XCTAssertNil(recovery.save(audioURL: audio, appName: "Mail"))
        defaults.set(true, forKey: "speek.assistant.saveHistory")
        let id = try XCTUnwrap(recovery.save(audioURL: audio, appName: "Mail"))
        XCTAssertEqual(recovery.save(audioURL: audio, appName: "Mail"), id)
        for index in 0..<6 {
            let file = dir.appendingPathComponent("\(index).wav")
            try Data([1]).write(to: file)
            _ = recovery.save(audioURL: file, appName: "Mail")
        }
        XCTAssertEqual(recovery.recordings.count, 5)
        XCTAssertNil(recovery.audioURL(for: id))
        clock = clock.addingTimeInterval(24 * 60 * 60 + 1)
        recovery.cleanup()
        XCTAssertTrue(recovery.recordings.isEmpty)
    }
}
