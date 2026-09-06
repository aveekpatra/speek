import Foundation
import SwiftData

class WordReplacementService {
    static let shared = WordReplacementService()

    private init() {}

    func applyReplacements(to text: String, using context: ModelContext) -> String {
        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let replacements = try? context.fetch(descriptor), !replacements.isEmpty else {
            return text // No replacements to apply
        }

        var modifiedText = text

        // Longest-first so specific triggers match before shorter overlapping ones
        let sortedReplacements = replacements.sorted {
            $0.originalText.count > $1.originalText.count
        }

        // Apply replacements (case-insensitive)
        for replacement in sortedReplacements {
            let originalGroup = replacement.originalText
            let replacementText = replacement.replacementText

            let variants = originalGroup
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }

            for original in variants {
                let usesBoundaries = usesWordBoundaries(for: original)

                if usesBoundaries {
                    // Lookarounds instead of \b so punctuation acts as a word boundary
                    let escaped = NSRegularExpression.escapedPattern(for: original)
                    let pattern = "(?<![a-zA-Z0-9])\(escaped)(?![a-zA-Z0-9])"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                        let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                        modifiedText = regex.stringByReplacingMatches(
                            in: modifiedText,
                            options: [],
                            range: range,
                            withTemplate: replacementText
                        )
                    }
                } else {
                    // Fallback substring replace for non-spaced scripts
                    modifiedText = modifiedText.replacingOccurrences(of: original, with: replacementText, options: .caseInsensitive)
                }
            }
        }

        // Collapse "/ word" → "/word" so a bare "lomeno" before any word
        // produces a clean slash command (e.g. "/ compact" → "/compact").
        if let slashRegex = try? NSRegularExpression(pattern: "/\\s+(?=\\S)") {
            let range = NSRange(modifiedText.startIndex..., in: modifiedText)
            modifiedText = slashRegex.stringByReplacingMatches(
                in: modifiedText, options: [], range: range, withTemplate: "/"
            )
        }

        // Turn a period right after a slash command into a space (e.g. "/compact." → "/compact "),
        // because the trailing dot stops it being recognised as a command, while a trailing
        // space confirms the command so the skill menu appears.
        if let dotRegex = try? NSRegularExpression(pattern: "(/[\\p{L}\\p{N}:_-]+)\\.") {
            let range = NSRange(modifiedText.startIndex..., in: modifiedText)
            modifiedText = dotRegex.stringByReplacingMatches(
                in: modifiedText, options: [], range: range, withTemplate: "$1 "
            )
        }

        return modifiedText
    }

    private func usesWordBoundaries(for text: String) -> Bool {
        // Returns false for languages without spaces (CJK, Thai), true for spaced languages
        let nonSpacedScripts: [ClosedRange<UInt32>] = [
            0x3040...0x309F, // Hiragana
            0x30A0...0x30FF, // Katakana
            0x4E00...0x9FFF, // CJK Unified Ideographs
            0xAC00...0xD7AF, // Hangul Syllables
            0x0E00...0x0E7F, // Thai
        ]

        for scalar in text.unicodeScalars {
            for range in nonSpacedScripts {
                if range.contains(scalar.value) {
                    return false
                }
            }
        }

        return true
    }
}
