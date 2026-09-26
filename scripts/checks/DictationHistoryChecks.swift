import Foundation
@main struct HistoryCheck {
 @MainActor static func main() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: dir) }
  let file = dir.appendingPathComponent("dictation.json")
  let suite = "HistoryCheck-" + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let store = DictationHistory(file: file, defaults: defaults)
  defaults.set(false, forKey: "speek.assistant.saveHistory")
  store.record(text: "private", duration: 5, appName: "Mail")
  assert(store.entries.isEmpty)
  defaults.set(true, forKey: "speek.assistant.saveHistory")
  store.record(text: "one two three four", duration: 2, appName: "Mail")
  assert(store.insights.words == 4 && store.insights.estimatedSecondsSaved == 4)
  assert(DictationHistory(file: file, defaults: defaults).entries.count == 1)
  for index in 0..<501 { store.record(text: "item \(index)", duration: -1, appName: "Mail") }
  assert(store.entries.count == 500 && store.entries.first?.text == "item 1")
  assert(store.entries.allSatisfy { $0.duration >= 0 })
  let export = dir.appendingPathComponent("export.json")
  try store.export(to: export)
  let object = try JSONSerialization.jsonObject(with: Data(contentsOf: export)) as! [[String: Any]]
  assert(object.count == 500 && object[0]["date"] is String)
  store.clear()
  assert(DictationHistory(file: file, defaults: defaults).entries.isEmpty)
  print("PASS: privacy opt-out, persistence, 40wpm estimate, retention, invalid duration, export, clear")
 }
}
