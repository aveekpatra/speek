import Foundation
@main struct PromptCheck {
 @MainActor static func main() throws {
  assert(PromptTemplate.variables(in: "Hi {{ name }}, {{topic}} {{name}} {{123}}") == ["name", "topic"])
  let rendered = try PromptTemplate.render("{{name}}: {{topic}}. {{name}}", values: ["name": "{{topic}}", "topic": "$\\value"])
  assert(rendered == "{{topic}}: $\\value. {{topic}}")
  do { _ = try PromptTemplate.render("{{missing}}", values: [:]); fatalError("must reject") } catch is PromptTemplateError {}
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: dir) }
  let file = dir.appendingPathComponent("prompts.json")
  let store = PromptLibrary(file: file)
  assert(store.save(name: "My prompt", body: "Research {{topic}}"))
  let id = store.prompts[0].id
  store.toggleFavorite(id)
  assert(store.save(id: id, name: "Renamed", body: "Explain {{topic}}"))
  let loaded = PromptLibrary(file: file)
  assert(loaded.prompts.count == 1 && loaded.prompts[0].isFavorite && loaded.prompts[0].name == "Renamed")
  loaded.remove(id)
  assert(PromptLibrary(file: file).prompts.isEmpty)
  try Data("bad json".utf8).write(to: file)
  let broken = PromptLibrary(file: file)
  assert(!broken.save(name: "Test", body: "Must not overwrite"))
  let data = try Data(contentsOf: file)
  assert(data == Data("bad json".utf8))
  print("PASS: variables, single-pass substitution, missing value rejection, save/edit/favorite/reload/delete, corruption preservation")
 }
}
