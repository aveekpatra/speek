import SwiftUI
import SwiftData

enum VocabularySortMode: String {
    case wordAsc = "wordAsc"
    case wordDesc = "wordDesc"
}

struct VocabularyView: View {
    @Query private var vocabularyWords: [VocabularyWord]
    @Environment(\.modelContext) private var modelContext
    @State private var newWord = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var sortMode: VocabularySortMode = .wordAsc
    @State private var suggestions: [VocabularySuggestionService.Suggestion] = []

    init() {
        if let savedSort = UserDefaults.standard.string(forKey: "vocabularySortMode"),
           let mode = VocabularySortMode(rawValue: savedSort) {
            _sortMode = State(initialValue: mode)
        }
    }

    private var sortedItems: [VocabularyWord] {
        switch sortMode {
        case .wordAsc:
            return vocabularyWords.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        case .wordDesc:
            return vocabularyWords.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedDescending }
        }
    }

    private func toggleSort() {
        sortMode = (sortMode == .wordAsc) ? .wordDesc : .wordAsc
        UserDefaults.standard.set(sortMode.rawValue, forKey: "vocabularySortMode")
    }

    private var shouldShowAddButton: Bool {
        !newWord.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("", text: $newWord, prompt: Text("Add word to vocabulary"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { addWords() }
                    .labelsHidden()

                if shouldShowAddButton {
                    AddIconButton(
                        helpText: "Add word",
                        isDisabled: newWord.isEmpty,
                        action: addWords
                    )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: shouldShowAddButton)

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Suggested"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    FlowLayout(spacing: 8) {
                        ForEach(suggestions) { suggestion in
                            VocabularyWordView(
                                word: suggestion.word,
                                onAdd: { addSuggestion(suggestion) },
                                isDraft: true
                            ) {
                                dismissSuggestion(suggestion)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.top, 4)
            }

            if !vocabularyWords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: toggleSort) {
                        HStack(spacing: 4) {
                            Text(String(localized: "Vocabulary Words (\(vocabularyWords.count))"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            Image(systemName: sortMode == .wordAsc ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Sort alphabetically")

                    FlowLayout(spacing: 8) {
                        ForEach(sortedItems) { item in
                            VocabularyWordView(word: item.word) {
                                removeWord(item)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Vocabulary", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .task {
            suggestions = VocabularySuggestionService.suggestions(context: modelContext, existing: Array(vocabularyWords))
        }
    }

    private func addSuggestion(_ suggestion: VocabularySuggestionService.Suggestion) {
        if let error = DictionaryService.addVocabularyWords(suggestion.word, existing: Array(vocabularyWords), context: modelContext) {
            alertMessage = error
            showAlert = true
            return
        }
        suggestions.removeAll { $0.id == suggestion.id }
    }

    private func dismissSuggestion(_ suggestion: VocabularySuggestionService.Suggestion) {
        VocabularySuggestionService.dismiss(suggestion.word)
        suggestions.removeAll { $0.id == suggestion.id }
    }

    private func addWords() {
        let input = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        if let error = DictionaryService.addVocabularyWords(input, existing: Array(vocabularyWords), context: modelContext) {
            alertMessage = error
            showAlert = true
            return
        }
        newWord = ""
    }

    private func removeWord(_ word: VocabularyWord) {
        modelContext.delete(word)

        do {
            try modelContext.save()
        } catch {
            // Rollback the delete to restore UI consistency
            modelContext.rollback()
            alertMessage = String(format: String(localized: "Failed to remove word: %@"), error.localizedDescription)
            showAlert = true
        }
    }
}

/// Renders one word chip. Used both for saved vocabulary words (solid border,
/// primary text, delete button) and for draft suggestions (`isDraft: true` —
/// dashed border, secondary text, plus an add button before the dismiss button).
struct VocabularyWordView: View {
    let word: String
    var onAdd: (() -> Void)? = nil
    var isDraft: Bool = false
    let onDelete: () -> Void
    @State private var isDeleteHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(word)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundColor(isDraft ? .secondary : .primary)

            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Add to vocabulary")
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isDeleteHovered ? AppTheme.Status.error : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help(isDraft ? "Dismiss suggestion" : "Remove word")
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDeleteHovered = hover
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isDraft ? AppTheme.Surface.subtle : AppTheme.Surface.window.opacity(0.4))
        }
        .overlay {
            if isDraft {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(AppTheme.Border.subtle, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppTheme.Border.subtle, lineWidth: 1)
            }
        }
        .shadow(color: isDraft ? .clear : Color.black.opacity(0.05), radius: isDraft ? 0 : 2, y: isDraft ? 0 : 1)
    }
}
