import AppKit
import ApplicationServices
import NaturalLanguage

/// The text around the cursor when dictation starts. Used to join dictation into what is
/// already written (spacing, capitalization), to give polishing continuity, and to hint
/// names and terms to transcription.
struct SurroundingText {
    let before: String
    let after: String

    @MainActor static func capture(_ target: VoiceTarget) -> SurroundingText? {
        if let textView = target.localTextView {
            return slice(textView.string as NSString, range: textView.selectedRange())
        }
        var value: CFTypeRef?
        var rangeValue: CFTypeRef?
        AXUIElementSetMessagingTimeout(target.element, 0.15)
        guard AXUIElementCopyAttributeValue(target.element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, text.utf16.count <= 2_000_000,
              AXUIElementCopyAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(rangeValue, to: AXValue.self), .cfRange, &range) else { return nil }
        return slice(text as NSString, range: NSRange(location: range.location, length: range.length))
    }

    private static func slice(_ text: NSString, range: NSRange) -> SurroundingText? {
        guard range.location != NSNotFound, range.location <= text.length else { return nil }
        let start = max(0, range.location - 600)
        let end = min(text.length, range.location + range.length)
        let tail = min(text.length - end, 200)
        return SurroundingText(before: text.substring(with: NSRange(location: start, length: range.location - start)),
                               after: text.substring(with: NSRange(location: end, length: tail)))
    }

    /// Fits dictated text into the existing text: a space where words would touch, a capital at
    /// a sentence start, and lowercase when continuing a sentence (names are left alone).
    func joined(_ text: String, preferredTerms: Set<String> = []) -> String {
        guard var output = Optional(text), let first = output.first else { return text }
        let previous = before.last
        if let previous, !previous.isWhitespace, !"([{\"'\u{201C}\u{2018}/-@#".contains(previous), first.isLetter || first.isNumber {
            output = " " + output
        }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasSuffix("\n") || ".!?".contains(trimmed.last!) {
            output = Self.changingFirstLetter(of: output) { $0.uppercased() }
        } else if let last = trimmed.last, last.isLetter || last.isNumber || ",;:".contains(last), Self.canLowercaseFirstWord(of: output, preferredTerms: preferredTerms) {
            output = Self.changingFirstLetter(of: output) { $0.lowercased() }
        }
        if let next = after.first, next.isLetter || next.isNumber, let last = output.last, !last.isWhitespace { output += " " }
        return output
    }

    /// Names, acronyms, and technical terms nearby, as transcription hints.
    var terms: [String] {
        var result: [String] = []
        let words = (before + " " + after).split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "." && $0 != "_" })
        var previousEndsSentence = true
        for raw in words {
            let word = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
            defer { previousEndsSentence = raw.hasSuffix(".") }
            guard word.count >= 2, word.count <= 40 else { continue }
            let letters = word.filter(\.isLetter)
            let inner = word.dropFirst().contains(where: \.isUppercase)
            let acronym = letters.count >= 2 && letters.allSatisfy(\.isUppercase)
            let mixed = word.contains(where: \.isNumber) && word.contains(where: \.isLetter)
            let name = word.first?.isUppercase == true && !previousEndsSentence
            if (inner || acronym || mixed || name), !result.contains(word) { result.append(word) }
            if result.count == 20 { break }
        }
        return result
    }

    private static func changingFirstLetter(of text: String, _ transform: (String) -> String) -> String {
        guard let index = text.firstIndex(where: \.isLetter) else { return text }
        return text.replacingCharacters(in: index...index, with: transform(String(text[index])))
    }

    private static func canLowercaseFirstWord(of text: String, preferredTerms: Set<String>) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let word = trimmed.split(whereSeparator: { !$0.isLetter && $0 != "'" }).first.map(String.init),
              let first = word.first, first.isUppercase, word.dropFirst().allSatisfy({ !$0.isUppercase }) else { return false }
        if word == "I" || word.hasPrefix("I'") || preferredTerms.contains(word) { return false }
        // Only lowercase ordinary words; anything the dictionary does not know is probably a name.
        let lower = word.lowercased()
        guard NSSpellChecker.shared.checkSpelling(of: lower, startingAt: 0).location == NSNotFound else { return false }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = trimmed
        let (tag, _) = tagger.tag(at: trimmed.startIndex, unit: .word, scheme: .nameType)
        return ![NLTag.personalName, .placeName, .organizationName].contains(tag)
    }
}
