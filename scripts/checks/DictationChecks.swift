import Foundation
import ApplicationServices
struct VoiceTarget { let element: AXUIElement; func isStillFocused() -> Bool { true } }
enum ActionCloudProvider { case openAI, openRouter }
enum ActionCredentials { static let voiceProvider = ActionCloudProvider.openRouter; static func key(for: ActionCloudProvider) -> String? { nil } }
enum ActionConnection { case openRouter }
enum AgentDefaults { static func model(for: ActionConnection) -> String { "test" } }
enum ActionClientError: Error { case missingKey, invalidResponse, requestFailed(String) }
@main struct Check {
 @MainActor static func main() async throws {
  let corrections = [DictationVocabularyEntry(term: "OpenAI", heardAs: "open eye"), DictationVocabularyEntry(term: "X", heardAs: "OpenAI"), DictationVocabularyEntry(term: "C++", heardAs: "see plus plus")]
  assert(DictationPipeline.applyCorrections("open eye OPEN EYE open eyesight see plus plus", entries: corrections) == "OpenAI OpenAI open eyesight C++")
  assert(DictationPipeline.applyCorrections("An apple pie and apple.", entries: [.init(term: "dessert", heardAs: "apple pie"), .init(term: "fruit", heardAs: "apple")]) == "An dessert and fruit.")
  let suite = "speek-dictation-test-" + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set(try JSONEncoder().encode(corrections), forKey: "speek.memory.vocabularyDrafts")
  let raw = try await DictationPipeline.process(transcript: "open eye", destination: .init(appName: "Mail"), defaults: defaults, completion: { _, _ in fatalError("Raw must not call model") })
  assert(raw.text == "OpenAI" && raw.warning == nil)
  defaults.set("Polished", forKey: "speek.dictation.polish")
  let failed = try await DictationPipeline.process(transcript: "open eye", destination: .init(appName: "Mail"), defaults: defaults, completion: { _, _ in throw ActionClientError.invalidResponse })
  assert(failed.text == "OpenAI" && failed.warning != nil)
  let polished = try await DictationPipeline.process(transcript: "hello", destination: .init(appName: "Mail"), defaults: defaults, completion: { system, input in
   assert(input.contains("Mail") && system.contains("untrusted")); return "Hello."
  })
  assert(polished.text == "Hello.")
  do {
   _ = try await DictationPipeline.process(transcript: "hello", destination: .init(appName: "Mail"), defaults: defaults, completion: { _, _ in throw CancellationError() })
   fatalError("Cancellation must propagate")
  } catch is CancellationError {}
  print("PASS: whole-word, longest match, non-cascading, raw offline, failure preservation, contextual polish, cancellation")
 }
}
