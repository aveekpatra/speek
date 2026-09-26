import SwiftUI

struct DictationSettingsView: View {
    @AppStorage("speek.dictation.polish") private var polish = DictationPolish.raw.rawValue
    @AppStorage("speek.dictation.contextual") private var contextual = true
    @AppStorage("speek.dictation.style") private var style = "Natural"
    @AppStorage("speek.dictation.doubleTapHandsFree") private var handsFree = false
    @AppStorage("speek.dictation.editSelectedText") private var editSelectedText = false
    @AppStorage("speek.memory.vocabularyDrafts") private var vocabularyData = Data()
    @State private var addingReplacement = false
    @State private var phrase = ""
    @State private var replacement = ""
    @State private var saveError: String?

    private var entries: [DictationVocabularyEntry] {
        (try? JSONDecoder().decode([DictationVocabularyEntry].self, from: vocabularyData)) ?? []
    }
    private var mode: DictationPolish { DictationPolish(rawValue: polish) ?? .raw }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dictation and editing").font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
            VStack(spacing: 0) {
                row("Double-tap for hands-free", detail: "Double-tap your speak shortcut to keep recording. Press it again to finish. Holding the shortcut still works.") {
                    Toggle("Double-tap for hands-free", isOn: $handsFree).labelsHidden().toggleStyle(.switch)
                }
                divider
                row("Writing mode", detail: mode.detail) {
                    Picker("Writing mode", selection: $polish) {
                        ForEach(DictationPolish.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }.labelsHidden().fixedSize()
                }
                if mode == .polished {
                    divider
                    row("Match the destination", detail: "Use the app name to adapt formatting for mail, messages, and notes.") {
                        Toggle("Match the destination", isOn: $contextual).labelsHidden().toggleStyle(.switch)
                    }
                    divider
                    row("Writing style", detail: "Keep facts and intent while adjusting the tone.") {
                        Picker("Writing style", selection: $style) {
                            ForEach(["Natural", "Concise", "Professional", "Friendly"], id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                }
                divider
                row("Edit selected text by voice", detail: "When text is selected, dictation becomes an editing instruction. Speek replaces it only if the selection stays unchanged.") {
                    Toggle("Edit selected text by voice", isOn: $editSelectedText).labelsHidden().toggleStyle(.switch)
                }
            }.settingsSurface()
            Text("Light, Polished, and Edit Mode use your voice API connection. If polishing fails, Speek keeps the original dictation. Raw applies saved corrections on this Mac.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("Replacements").font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    Button { addingReplacement.toggle() } label: { Label("Add replacement", systemImage: "plus") }
                        .buttonStyle(SpeekActionButtonStyle()).disabled(addingReplacement)
                }
                Text("Turn a spoken phrase into a name, address, or reusable snippet. These entries are shared with Memory > Corrections.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if addingReplacement {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("When I say", text: $phrase).textFieldStyle(.roundedBorder).accessibilityLabel("Spoken phrase")
                        TextField("Replace with", text: $replacement, axis: .vertical).lineLimit(1...5)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("Replacement text")
                        if let saveError { Text(saveError).font(.system(size: 11)).foregroundStyle(.red) }
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            Button("Cancel") { resetForm() }.buttonStyle(SpeekActionButtonStyle())
                            Button("Save") { saveReplacement() }.buttonStyle(SpeekActionButtonStyle())
                                .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }.padding(12).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                if entries.filter({ !$0.heardAs.isEmpty }).isEmpty {
                    Text("No replacements yet").font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ForEach(entries.filter { !$0.heardAs.isEmpty }) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.heardAs).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
                                Text(entry.term).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                vocabularyData = (try? JSONEncoder().encode(entries.filter { $0.id != entry.id })) ?? vocabularyData
                            } label: {
                                Image(systemName: "trash").frame(width: 32, height: 32)
                            }.buttonStyle(.plain).accessibilityLabel("Remove replacement for " + entry.heardAs).help("Remove replacement")
                        }
                        if entry.id != entries.filter({ !$0.heardAs.isEmpty }).last?.id { Divider() }
                    }
                }
            }.padding(16).settingsSurface()
        }
    }

    private var divider: some View { Divider().padding(.horizontal, 16) }

    private func row<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                label(title, detail: detail).frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                control().fixedSize()
            }
            VStack(alignment: .trailing, spacing: 12) {
                label(title, detail: detail).frame(maxWidth: .infinity, alignment: .leading)
                control().fixedSize()
            }
        }.padding(16)
    }

    private func label(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveReplacement() {
        let spoken = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entries.contains(where: { $0.heardAs.caseInsensitiveCompare(spoken) == .orderedSame }) else {
            saveError = "This spoken phrase already has a replacement. Remove it before adding a new one."
            return
        }
        do {
            vocabularyData = try JSONEncoder().encode(entries + [DictationVocabularyEntry(term: value, heardAs: spoken)])
            resetForm()
        } catch { saveError = "Could not save this replacement. Try again." }
    }

    private func resetForm() { addingReplacement = false; phrase = ""; replacement = ""; saveError = nil }
}
