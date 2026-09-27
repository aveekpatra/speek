#!/usr/bin/env python3
"""Check dictation joining, nearby-term hints, and correction learning with the production sources."""
import pathlib, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[2]
STUB = '''import AppKit
struct VoiceTarget { let pid: pid_t; let element: AXUIElement; weak var localTextView: NSTextView?; func isStillFocused() -> Bool { false } }
struct DictationVocabularyEntry: Codable, Identifiable { var id = UUID(); var term: String; var heardAs: String; var learned: Bool? = nil }
@MainActor enum DictationPipeline { static func vocabulary() -> [DictationVocabularyEntry] { [] } }
'''
MAIN = '''import Foundation
@main struct Checks {
 static func main() {
  func check(_ ok: Bool, _ message: String) { if !ok { print("FAIL: " + message); exit(1) } }
  // Joining
  check(SurroundingText(before: "Hello", after: "").joined("world") == " world", "adds a space and continues mid-sentence")
  check(SurroundingText(before: "Done. ", after: "").joined("next step") == "Next step", "capitalizes after a sentence")
  check(SurroundingText(before: "", after: "").joined("hello") == "Hello", "capitalizes at the start")
  check(SurroundingText(before: "Send it to ", after: "").joined("Aveek today") == "Aveek today", "keeps names")
  check(SurroundingText(before: "I think ", after: "").joined("The plan works") == "the plan works", "lowercases a continuing sentence")
  check(SurroundingText(before: "(", after: "").joined("note") == "Note" || SurroundingText(before: "(", after: "").joined("note") == "note", "no space after an opening bracket")
  check(!SurroundingText(before: "(", after: "").joined("note").hasPrefix(" "), "no space after an opening bracket")
  check(SurroundingText(before: "a ", after: "rest").joined("word") == "word ", "adds a trailing space before following text")
  check(SurroundingText(before: "Ship it,", after: "").joined("I think") == " I think", "keeps I capitalized")
  // Terms
  let terms = SurroundingText(before: "We deploy SpeekCore to the EU cluster with v2 of the API. Ask Aveek about it.", after: "").terms
  check(terms.contains("SpeekCore") && terms.contains("EU") && terms.contains("API") && terms.contains("v2") && terms.contains("Aveek"), "extracts names and terms: \\\\(terms)")
  // Learning
  let inserted = "please ask a turn o about the launch"
  let before = "Notes: " + inserted
  check(CorrectionLearner.learnedPair(before: before, after: "Notes: please ask Aturno about the launch", inserted: inserted).map { $0.heard + "|" + $0.term } == "a turn o|Aturno", "learns a misheard name")
  check(CorrectionLearner.learnedPair(before: before, after: "Notes: please ask a turn o about the release", inserted: inserted) == nil, "ignores a real edit")
  check(CorrectionLearner.learnedPair(before: "x iphone y", after: "x iPhone y", inserted: "iphone").map { $0.term } == "iPhone", "learns a casing fix")
  check(CorrectionLearner.learnedPair(before: "Earlier text. " + inserted, after: "Changed text. " + inserted, inserted: inserted) == nil, "ignores edits outside the dictation")
  check(CorrectionLearner.learnedPair(before: before, after: before + " and more", inserted: inserted) == nil, "ignores added text")
  print("PASS: spacing, sentence capitalization, names kept, trailing space, nearby terms, misheard-name learning, casing fixes, edits and outside changes ignored")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='speek-writing-check-') as tmp:
    folder = pathlib.Path(tmp)
    (folder/'Stub.swift').write_text(STUB); (folder/'Main.swift').write_text(MAIN)
    subprocess.run(['swiftc', '-parse-as-library', str(ROOT/'Speek/Assistant/SurroundingText.swift'), str(ROOT/'Speek/Assistant/CorrectionLearner.swift'),
                    str(folder/'Stub.swift'), str(folder/'Main.swift'), '-o', str(folder/'check')], check=True)
    subprocess.run([str(folder/'check')], check=True)
