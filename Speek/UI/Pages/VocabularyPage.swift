import SwiftUI
import SwiftData
import AppKit

/// Vocabulary: custom words the models should recognize, plus text replacements.
struct VocabularyPage: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \VocabularyWord.dateAdded, order: .reverse) private var words: [VocabularyWord]
    @Query(sort: \WordReplacement.dateAdded, order: .reverse) private var replacements: [WordReplacement]

    @State private var input = ""
    @State private var errorMessage: String?
    @State private var editingReplacement: WordReplacement?
    @State private var isCreatingReplacement = false
    @FocusState private var inputFocused: Bool

    private var entries: [VocabularyEntry] {
        let wordEntries = words.map { VocabularyEntry.word($0) }
        let replacementEntries = replacements.map { VocabularyEntry.replacement($0) }
        return (wordEntries + replacementEntries).sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            SpeekPageScroll(spacing: 18) {
                composer
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                list
            }
            if editingReplacement != nil || isCreatingReplacement {
                ReplacementEditorPanel(
                    replacement: editingReplacement,
                    initialOriginal: isCreatingReplacement ? input : nil,
                    onClose: { editingReplacement = nil; isCreatingReplacement = false; input = "" }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: editingReplacement?.id)
        .animation(.snappy(duration: 0.25), value: isCreatingReplacement)
        .navigationTitle("")
        .toolbar {
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Export vocabulary...") { export() }
                    Button("Import vocabulary...") { importFile() }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .menuIndicator(.hidden)
                .help("Import or export vocabulary")
            }
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("New word or replacement", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($inputFocused)
                .onSubmit { addWord() }
            Spacer(minLength: 0)
            Button {
                addWord()
            } label: {
                HStack(spacing: 6) {
                    Text("Add word")
                    SpeekKeycap(text: "⏎")
                }
                .foregroundStyle(input.isEmpty ? Color.secondary : Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(input.isEmpty)
            Button {
                isCreatingReplacement = true
            } label: {
                HStack(spacing: 6) {
                    Text("Replace with...")
                    SpeekKeycap(text: "⌘")
                    SpeekKeycap(text: "⏎")
                }
                .foregroundStyle(input.isEmpty ? Color.secondary : Color.primary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(input.isEmpty)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SpeekDesign.groupFill(scheme))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(SpeekDesign.rowDivider(scheme), lineWidth: 1))
        )
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("Add names, jargon or acronyms so they are transcribed correctly.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
            ForEach(entries) { entry in
                VocabularyRow(entry: entry) {
                    if case .replacement(let replacement) = entry { editingReplacement = replacement }
                } onDelete: {
                    delete(entry)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Actions

    private func addWord() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = DictionaryService.addVocabularyWords(trimmed, existing: words, context: modelContext)
        if errorMessage == nil { input = "" }
    }

    private func delete(_ entry: VocabularyEntry) {
        switch entry {
        case .word(let word): modelContext.delete(word)
        case .replacement(let replacement): modelContext.delete(replacement)
        }
        try? modelContext.save()
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "speek-vocabulary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let payload: [String: Any] = [
            "words": words.map(\.word),
            "replacements": replacements.map { ["from": $0.originalText, "to": $0.replacementText] }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        for word in payload["words"] as? [String] ?? [] {
            DictionaryService.addVocabularyWords(word, existing: words, context: modelContext)
        }
        for item in payload["replacements"] as? [[String: String]] ?? [] {
            if let from = item["from"], let to = item["to"] {
                DictionaryService.addWordReplacement(original: from, replacement: to, existing: replacements, context: modelContext)
            }
        }
    }
}

// MARK: - Entry

enum VocabularyEntry: Identifiable {
    case word(VocabularyWord)
    case replacement(WordReplacement)

    var id: String {
        switch self {
        case .word(let word): return "word-\(word.persistentModelID.hashValue)"
        case .replacement(let replacement): return "rep-\(replacement.id.uuidString)"
        }
    }

    var date: Date {
        switch self {
        case .word(let word): return word.dateAdded
        case .replacement(let replacement): return replacement.dateAdded
        }
    }
}

private struct VocabularyRow: View {
    @Environment(\.colorScheme) private var scheme
    let entry: VocabularyEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            switch entry {
            case .word(let word):
                Text(word.word)
                    .font(.system(size: 15))
                    .frame(width: 220, alignment: .leading)
            case .replacement(let replacement):
                Text(replacement.originalText)
                    .font(.system(size: 15))
                    .frame(width: 220, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).fill(SpeekDesign.controlFill(scheme)))
                Text(replacement.replacementText)
                    .font(.system(size: 15))
                    .lineLimit(1)
            }
            Spacer()
            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? SpeekDesign.controlFill(scheme).opacity(0.6) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onEdit() }
        .contextMenu {
            if case .replacement = entry { Button("Edit") { onEdit() } }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Editor panel

/// Slide-over "Edit replacement" editor.
private struct ReplacementEditorPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query private var replacements: [WordReplacement]
    let replacement: WordReplacement?
    let initialOriginal: String?
    let onClose: () -> Void

    @State private var original = ""
    @State private var replaceWith = ""
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case original, replacement }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                Spacer()
                Text(replacement == nil ? "New replacement" : "Edit replacement")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if let replacement {
                    Button("Delete", role: .destructive) {
                        modelContext.delete(replacement)
                        try? modelContext.save()
                        onClose()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                } else {
                    Color.clear.frame(width: 44, height: 1)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 48)

            VStack(alignment: .leading, spacing: 8) {
                Text("Replace")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("Spoken text", text: $original)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(SpeekDesign.controlFill(scheme).opacity(0.6)))
                    .focused($focus, equals: .original)

                Text("With")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                TextEditor(text: $replaceWith)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 120)
                    .background(RoundedRectangle(cornerRadius: 10).fill(SpeekDesign.controlFill(scheme).opacity(0.6)))
                    .focused($focus, equals: .replacement)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                Spacer()
                Button(action: save) {
                    Text("Save")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(original.trimmingCharacters(in: .whitespaces).isEmpty || replaceWith.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                Button("Cancel", action: onClose)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            .padding(18)
        }
        .frame(width: 420)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(SpeekDesign.rowDivider(scheme)).frame(width: 1)
        }
        .onAppear {
            original = replacement?.originalText ?? initialOriginal ?? ""
            replaceWith = replacement?.replacementText ?? ""
            focus = replacement == nil && !(initialOriginal ?? "").isEmpty ? .replacement : .original
        }
    }

    private func save() {
        let from = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = replaceWith.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else { return }
        if let replacement {
            replacement.originalText = from
            replacement.replacementText = to
            try? modelContext.save()
            onClose()
        } else {
            errorMessage = DictionaryService.addWordReplacement(original: from, replacement: to, existing: replacements, context: modelContext)
            if errorMessage == nil { onClose() }
        }
    }
}
