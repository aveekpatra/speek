import Foundation
struct DictationVocabularyEntry: Codable { var term: String; var heardAs: String }
@main struct Check {
 static func main() throws {
  let suite = "CaptureCheck-" + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  assert(VoiceCapturePreferences.language(defaults: defaults) == nil)
  defaults.set("wrong", forKey: "speek.voice.recognitionLanguage")
  assert(VoiceCapturePreferences.language(defaults: defaults) == nil)
  defaults.set("cs", forKey: "speek.voice.recognitionLanguage")
  defaults.set(try JSONEncoder().encode([DictationVocabularyEntry(term: "Speek", heardAs: "speak"), .init(term: "bad\nterm", heardAs: ""), .init(term: "<bad>", heardAs: ""), .init(term: "Speek", heardAs: "")]), forKey: "speek.memory.vocabularyDrafts")
  assert(VoiceCapturePreferences.keywords(defaults: defaults) == ["Speek"])
  let newFields = VoiceCapturePreferences.openAIFields(model: "gpt-transcribe", defaults: defaults)
  assert(newFields.map { $0.0 } == ["languages[]", "keywords[]"])
  let oldFields = VoiceCapturePreferences.openAIFields(model: "gpt-4o-transcribe", defaults: defaults)
  assert(oldFields.map { $0.0 } == ["language", "prompt"])
  defaults.set(false, forKey: "speek.voice.vocabularyHints")
  assert(VoiceCapturePreferences.keywords(defaults: defaults).isEmpty)
  print("PASS: automatic omission, language allowlist, keyword sanitation/dedup, model-specific fields, hint opt-out")
 }
}
