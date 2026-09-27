import Foundation

/// Storage, migration, and recall quality, using the real on-device embedding model.
@main struct MemoryCheck {
 @MainActor static func main() async throws {
  func expect(_ ok: Bool, _ what: String) { if !ok { print("FAIL: " + what); exit(1) } }
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }
  let suite = "MemoryCheck-" + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }

  // Migration from the version 1 JSON file keeps ids and moves the file aside.
  let legacyID = UUID()
  try JSONEncoder().encode([RememberedFact(id: legacyID, text: "My preferred language is English")]).write(to: dir.appendingPathComponent("memory.json"))
  let memory = AssistantMemory(directory: dir, defaults: defaults)
  expect(memory.facts.count == 1 && memory.facts[0].id == legacyID, "legacy facts migrated with ids")
  expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("memory.json.migrated").path), "legacy file kept aside")

  // Writes, duplicates, locking, editing, deletion, persistence.
  expect(memory.remember("I prefer oat milk in coffee"), "remember")
  expect(!memory.remember("  i prefer OAT milk in coffee "), "duplicate ignored (case and spacing)")
  memory.saveProcedure(title: "Weekly update", instructions: "Summarize project progress in three bullets.")
  memory.recordEpisode(request: "Weekly project report", result: "Report saved to Notes.")
  memory.recordEpisode(request: "Weekly project report", result: "Report saved to Notes.")
  expect(memory.episodes.count == 1, "identical episode stored once")
  let oat = memory.facts.first { $0.text.contains("oat") }!
  memory.setPinned(oat.id, true)
  expect(memory.facts.first { $0.id == oat.id }?.pinned == true, "lock")
  memory.updateFact(legacyID, text: "My preferred language is Czech")
  let reloaded = AssistantMemory(directory: dir, defaults: defaults)
  expect(reloaded.facts.contains { $0.text == "My preferred language is Czech" }, "edit persisted")
  expect(reloaded.facts.first { $0.id == oat.id }?.pinned == true, "lock persisted")
  expect(reloaded.procedures.count == 1 && reloaded.episodes.count == 1, "procedures and episodes persisted")
  expect(await reloaded.context(for: "anything").contains("Always true about the user (locked by the user):\nI prefer oat milk"), "locked fact always in context")
  expect(await reloaded.context(for: "weekly project").contains("Report saved"), "relevant episode recalled")
  reloaded.saveHistory = false
  reloaded.recordEpisode(request: "Private", result: "Private result")
  let privateContext = await reloaded.context(for: "weekly project")
  expect(reloaded.episodes.count == 1 && !privateContext.contains("Report saved"), "history off: no recording or recall")
  reloaded.saveHistory = true
  reloaded.remove(legacyID)
  expect(!AssistantMemory(directory: dir, defaults: defaults).facts.contains { $0.id == legacyID }, "deletion persisted")
  expect(MemoryDatabase.matchExpression("\"; DROP TABLE memories; -- AND OR NEAR(") != nil, "user text is quoted for full-text search")
  _ = await reloaded.recall("\"; DROP TABLE memories; -- AND OR NEAR(", kinds: [.fact], limit: 3)
  expect(reloaded.persistenceError == nil, "odd search text does not break recall")

  // Recall quality: a realistic memory and questions phrased differently from the facts.
  let evalDir = dir.appendingPathComponent("eval")
  // With SPEEK_EVAL_EMBEDDING_KEY (an OpenRouter key) the real embedding model is measured;
  // without it, recall is full-text only and the check never calls a cloud service.
  let evalKey = ProcessInfo.processInfo.environment["SPEEK_EVAL_EMBEDDING_KEY"]
  let embedder: MemoryEmbedder? = evalKey.map { key in
      CloudMemoryEmbedder(credentials: { (URL(string: "https://openrouter.ai/api/v1/embeddings")!, key, "openai/text-embedding-3-small") })
  }
  let eval = AssistantMemory(directory: evalDir, defaults: defaults, embedder: embedder)
  let facts = [
   "My sister's name is Priya and she lives in Bangalore", "I prefer oat milk in my coffee", "I work on Speek, a macOS voice assistant",
   "My flight to Prague leaves Friday at 9am from gate B12", "Never email my landlord without asking me first", "My dentist is Dr. Novak on Vinohradska street",
   "I use Zen as my main browser", "My partner is allergic to peanuts", "Send weekly reports to my manager Tomas every Monday",
   "My car is a 2019 Skoda Octavia", "I go to the gym on Tuesdays and Thursdays at 7am", "My favorite restaurant is Lokal in Prague",
   "My Wi-Fi network is called Nebula", "I am vegetarian", "My passport expires in March 2028", "My son's school is Riverside International",
   "I prefer meetings after 11am", "My bank is Revolut", "I speak English, Hindi, and a little Czech", "My laptop is a 16-inch MacBook Pro",
   "The office door code changes every month", "My mother's birthday is June 14", "I support Arsenal", "My accountant is Jana Svobodova",
   "I usually take the tram 22 to work", "Call me Aveek, not Mr. Patra", "I keep my notes in Apple Notes", "My AWS account is for the Unifocus project",
   "I prefer dark mode everywhere", "My doctor recommended walking 8000 steps a day"
  ]
  for fact in facts { eval.remember(fact) }
  for index in 0..<60 { eval.recordEpisode(request: "Routine request \(index) about the weather", result: "It was \(index % 30) degrees.") }
  await eval.waitForEmbeddings()
  let questions: [(String, String)] = [
   ("what's my sister called", "sister"), ("how do I take my coffee", "oat milk"), ("when is my flight", "flight to Prague"),
   ("can you write to the landlord", "landlord"), ("who is my dentist", "dentist"), ("which browser do I use", "Zen"),
   ("book dinner for my partner, anything to watch out for", "peanuts"), ("what car do I drive", "Skoda"), ("when do I work out", "gym"),
   ("where should we eat tonight", "Lokal"), ("what do I eat", "vegetarian"), ("is my passport still valid", "passport"),
   ("schedule a call with the team", "meetings after 11am"), ("what should you call me", "Call me Aveek"), ("gift idea for my mom's birthday", "mother's birthday"),
   ("who does my taxes", "accountant"), ("how do I commute", "tram"), ("which football team do I like", "Arsenal"),
   ("how many steps should I walk", "8000 steps"), ("what languages do I speak", "Hindi")
  ]
  var hits1 = 0, hits3 = 0, lexical3 = 0
  let db = try MemoryDatabase(url: evalDir.appendingPathComponent("memory.sqlite"))
  for (question, expected) in questions {
   let found = await eval.recall(question, kinds: [.fact], limit: 3).map(\.body)
   if found.first?.contains(expected) == true { hits1 += 1 }
   if found.contains(where: { $0.contains(expected) }) { hits3 += 1 } else { print("  missed:", question, "->", found.first ?? "nothing") }
   let words = try db.search(question, kinds: [.fact], limit: 3)
   if eval.facts.filter({ words.contains($0.id) }).contains(where: { $0.text.contains(expected) }) { lexical3 += 1 }
  }
  print("Recall on \(questions.count) questions over \(facts.count) facts" + (embedder == nil ? " (full-text only)" : " (words + meaning)") + ": top-1 \(hits1), top-3 \(hits3); full-text alone top-3 \(lexical3)")
  expect(hits3 >= lexical3, "combined recall is at least as good as full-text alone")
  if embedder != nil { expect(hits3 >= questions.count * 9 / 10, "combined top-3 recall at least 90%") }
  // Episodes: a matching old request still beats unrelated recent ones.
  expect(await eval.recall("weather request 7", kinds: [.episode], limit: 4).contains { ($0.title ?? "").contains("request 7 ") }, "episode recall")
  print("PASS: JSON migration, duplicates, locking, editing, deletion, persistence, locked context, history privacy, query quoting, hybrid recall")
 }
}
