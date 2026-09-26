import Foundation
@main struct Check {
 @MainActor static func main() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }
  let suite = "RecoveryCheck-" + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  var clock = Date()
  let recovery = RecordingRecovery(directory: dir.appendingPathComponent("backups"), defaults: defaults, now: { clock })
  let audio = dir.appendingPathComponent("audio.wav")
  try Data([1,2,3,4]).write(to: audio)
  assert(recovery.save(audioURL: audio, appName: "Mail") == nil)
  defaults.set(true, forKey: "speek.voice.recordingRecovery")
  defaults.set(false, forKey: "speek.assistant.saveHistory")
  assert(recovery.save(audioURL: audio, appName: "Mail") == nil)
  defaults.set(true, forKey: "speek.assistant.saveHistory")
  let id = recovery.save(audioURL: audio, appName: "Mail")!
  assert(recovery.save(audioURL: audio, appName: "Mail") == id && recovery.recordings.count == 1)
  let backup = recovery.audioURL(for: id)!
  let attrs = try FileManager.default.attributesOfItem(atPath: backup.path)
  assert((attrs[.posixPermissions] as! NSNumber).intValue == 0o600)
  for index in 0..<6 {
   let file = dir.appendingPathComponent("\(index).wav"); try Data([1]).write(to: file)
   _ = recovery.save(audioURL: file, appName: "Mail")
  }
  assert(recovery.recordings.count == 5 && !FileManager.default.fileExists(atPath: backup.path))
  let removed = recovery.recordings[0].id
  recovery.complete(removed)
  assert(recovery.audioURL(for: removed) == nil)
  clock = clock.addingTimeInterval(24 * 60 * 60 + 1)
  recovery.cleanup()
  assert(recovery.recordings.isEmpty)
  print("PASS: opt-in, history privacy, dedup, owner permissions, retention, complete, expiry")
 }
}
