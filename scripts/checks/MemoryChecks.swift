import Foundation
@main struct MemoryCheck {
 @MainActor static func main() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }
  let file = dir.appendingPathComponent("memory.json")
  let suite = "MemoryCheck-" + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  try JSONEncoder().encode([RememberedFact(text: "My preferred language is English")]).write(to: file)
  let memory = AssistantMemory(file: file, defaults: defaults)
  assert(memory.facts.count == 1)
  memory.saveProcedure(title: "Weekly update", instructions: "Summarize project progress in three bullets.")
  memory.recordEpisode(request: "Weekly project report", result: "Report saved.")
  memory.recordEpisode(request: "Weekly project report", result: "Report saved.")
  assert(memory.episodes.count == 1)
  let loaded = AssistantMemory(file: file, defaults: defaults)
  assert(loaded.facts.count == 1 && loaded.procedures.count == 1 && loaded.episodes.count == 1)
  assert(loaded.context(for: "weekly project").contains("Report saved."))
  assert(!loaded.context(for: "recipe baking").contains("Report saved."))
  loaded.saveHistory = false
  loaded.recordEpisode(request: "Private", result: "Private result")
  assert(loaded.episodes.count == 1 && !loaded.context(for: "weekly project").contains("Report saved."))
  loaded.updateFact(loaded.facts[0].id, text: "Edited fact")
  loaded.removeProcedure(loaded.procedures[0].id)
  let reloaded = AssistantMemory(file: file, defaults: defaults)
  assert(reloaded.facts[0].text == "Edited fact" && reloaded.procedures.isEmpty)
  let broken = Data("invalid".utf8)
  try broken.write(to: file)
  let corrupt = AssistantMemory(file: file, defaults: defaults)
  corrupt.remember("Must not overwrite")
  let preserved = try Data(contentsOf: file); assert(preserved == broken)
  assert(corrupt.persistenceError != nil)
  print("PASS: legacy migration, persistence, episode dedup, relevance, history privacy, editing, deletion, corrupt-file preservation")
 }
}
