import SwiftUI

private struct VocabularyDraft: Codable, Identifiable {
    var id = UUID()
    var term: String
    var heardAs: String
}

struct MemoryShellView: View {
    @ObservedObject private var memory = AssistantMemory.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = "Facts"
    @State private var addingFact = false
    @State private var addingWord = false
    @State private var fact = ""
    @State private var query = ""
    @State private var editingFactID: UUID?
    @State private var procedureEditor = false
    @State private var procedureID: UUID?
    @State private var procedureTitle = ""
    @State private var procedureInstructions = ""
    @State private var episodeID: UUID?
    @State private var episodeRequest = ""
    @State private var episodeResult = ""
    @State private var term = ""
    @State private var heardAs = ""
    @FocusState private var focusedField: String?
    @AppStorage("speek.memory.vocabularyDrafts") private var vocabularyData = Data()
    private var vocabulary: [VocabularyDraft] { (try? JSONDecoder().decode([VocabularyDraft].self, from: vocabularyData)) ?? [] }
    private func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// A spoken phrase maps to one entry; a term without a spoken phrase is saved once.
    private var vocabularyConflict: String? {
        let spoken = clean(heardAs)
        if !spoken.isEmpty {
            return vocabulary.contains { $0.heardAs.caseInsensitiveCompare(spoken) == .orderedSame } ? "This spoken phrase is already saved." : nil
        }
        return vocabulary.contains { $0.heardAs.isEmpty && $0.term.caseInsensitiveCompare(clean(term)) == .orderedSame } ? "This term is already saved." : nil
    }

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 340), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Memory").font(.system(size: 25, weight: .semibold))
                    Text("Facts, experiences, and the way you work.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    tabs(vertical: false)
                    tabs(vertical: true)
                }
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 16) {
                            Text(selected).font(.system(size: 15, weight: .semibold))
                            InfoButton(text: sectionDescription, subject: selected)
                            Spacer(minLength: 8)
                            if selected == "Facts" {
                                addButton("Add fact") { editingFactID = nil; fact = ""; addingFact = true; focusedField = "fact" }
                                    .disabled(addingFact)
                            } else if selected == "Procedural" {
                                addButton("Add procedure") { procedureID = nil; procedureTitle = ""; procedureInstructions = ""; procedureEditor = true }
                                    .disabled(procedureEditor)
                            } else if selected == "Vocabulary" {
                                addButton("Add entry") { addingWord = true; focusedField = "term" }
                                    .disabled(addingWord)
                            }
                        }
                    }
                    TextField("Search " + selected.lowercased(), text: $query)
                        .textFieldStyle(.roundedBorder).font(.system(size: 13))
                        .accessibilityLabel("Search " + selected.lowercased())
                    if let error = memory.persistenceError {
                        Label(error, systemImage: "exclamationmark.circle.fill").font(.system(size: 12)).foregroundStyle(.red)
                    }
                    switch selected {
                    case "Facts": facts
                    case "Episodic": episodes
                    case "Procedural": procedures
                    default: words
                    }
                }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.vertical, 12).padding(24).frame(maxWidth: .infinity)
        }
    }

    private var sectionDescription: String {
        switch selected {
        case "Facts": return "Semantic memory: preferences, people, and things you know."
        case "Episodic": return "Completed requests and their results, saved with dates for future context."
        case "Procedural": return "How to do things: reusable instructions and learned workflows."
        default: return "Names, terms, corrections, and spoken shortcuts. Speek writes each entry exactly as saved. Add a spoken phrase to replace what you say, such as a misheard name or your address. Entries without one guide Light and Polished mode."
        }
    }

    private func tabs(vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            ForEach(["Facts", "Episodic", "Procedural", "Vocabulary"], id: \.self) { title in
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { selected = title; query = "" }
                } label: {
                    Text(title).font(.system(size: 13, weight: .medium)).fixedSize()
                        .frame(minWidth: 90, maxWidth: .infinity).padding(.vertical, 8)
                        .background(selected == title ? Color.white.opacity(0.11) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(selected == title ? .isSelected : [])
            }
        }.padding(4).frame(maxWidth: 500)
            .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 22))
    }

    private func infoCard(_ title: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(20).frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading).settingsSurface()
    }

    private func matches(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }

    private var episodes: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !memory.saveHistory { HistoryPausedNotice() }
            if let episodeID {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Edit event").font(.system(size: 13, weight: .medium))
                    TextField("Request", text: $episodeRequest, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                    TextField("Result", text: $episodeResult, axis: .vertical).lineLimit(3...8).textFieldStyle(.roundedBorder)
                    formActions(disabled: clean(episodeRequest).isEmpty || clean(episodeResult).isEmpty, cancel: { self.episodeID = nil }) {
                        memory.updateEpisode(episodeID, request: episodeRequest, result: episodeResult); self.episodeID = nil
                    }
                }.padding(16).settingsSurface()
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                let items = memory.episodes.filter { matches($0.request + " " + $0.result) }.sorted { $0.date > $1.date }
                if items.isEmpty { infoCard(query.isEmpty ? "No saved events" : "No matching events", icon: "clock.fill", detail: query.isEmpty ? "Completed requests and results will appear here while saving is enabled." : "Try a different search.") }
                ForEach(items) { episode in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(episode.date, style: .date).font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            editButton("Edit event") { episodeID = episode.id; episodeRequest = episode.request; episodeResult = episode.result }
                            removeButton("Forget event") { memory.removeEpisode(episode.id) }
                        }
                        Text(episode.request).font(.system(size: 13, weight: .medium)).lineLimit(4).textSelection(.enabled)
                        Text(episode.result).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(8).textSelection(.enabled)
                        DisclosureGroup("Full event") {
                            Text(episode.request + "\n\n" + episode.result).font(.system(size: 12)).textSelection(.enabled)
                        }.font(.system(size: 11))
                        Spacer(minLength: 0)
                    }.padding(20).frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading).settingsSurface()
                }
            }
        }
    }

    private var procedures: some View {
        VStack(alignment: .leading, spacing: 16) {
            if procedureEditor {
                VStack(alignment: .leading, spacing: 12) {
                    Text(procedureID == nil ? "New procedure" : "Edit procedure").font(.system(size: 13, weight: .medium))
                    TextField("Name, such as Weekly project update", text: $procedureTitle).textFieldStyle(.roundedBorder)
                    TextField("Instructions to reuse for this kind of request", text: $procedureInstructions, axis: .vertical).lineLimit(4...12).textFieldStyle(.roundedBorder)
                    Text("Relevant procedures are included with future requests. Actions still require their usual permissions.").font(.system(size: 11)).foregroundStyle(.secondary)
                    formActions(disabled: clean(procedureTitle).isEmpty || clean(procedureInstructions).isEmpty, cancel: { procedureEditor = false }) {
                        memory.saveProcedure(id: procedureID, title: procedureTitle, instructions: procedureInstructions); procedureEditor = false
                    }
                }.padding(16).settingsSurface()
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                let items = memory.procedures.filter { matches($0.title + " " + $0.instructions) }.sorted { $0.date > $1.date }
                if items.isEmpty { infoCard(query.isEmpty ? "No saved procedures" : "No matching procedures", icon: "list.bullet.clipboard.fill", detail: query.isEmpty ? "Add the steps and preferences Speek should use for recurring kinds of work." : "Try a different search.") }
                ForEach(items) { procedure in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(procedure.title).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                            editButton("Edit procedure") { procedureID = procedure.id; procedureTitle = procedure.title; procedureInstructions = procedure.instructions; procedureEditor = true }
                            removeButton("Forget procedure") { memory.removeProcedure(procedure.id) }
                        }
                        Text(procedure.instructions).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(8).textSelection(.enabled)
                        Text(procedure.date, style: .date).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }.padding(20).frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading).settingsSurface()
                }
            }
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 16) {
            if memory.facts.isEmpty {
                emptyState("No saved facts", detail: "Add a preference or say \"Remember that...\" to Speek.")
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(memory.facts.filter { matches($0.text) }) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.text).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                Text(item.date, style: .date).font(.system(size: 11)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            editButton("Edit fact") { editingFactID = item.id; fact = item.text; addingFact = true }
                            removeButton("Forget fact") { memory.remove(item.id) }
                        }.padding(20).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading).settingsSurface()
                    }
                }
            }
            if !memory.facts.isEmpty && memory.facts.filter({ matches($0.text) }).isEmpty {
                Text("No matching facts. Try a different search.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if addingFact {
                VStack(alignment: .leading, spacing: 12) {
                    Text(editingFactID == nil ? "New fact" : "Edit fact").font(.system(size: 12, weight: .medium))
                    TextField("What should Speek remember?", text: $fact, axis: .vertical)
                        .lineLimit(2...6).textFieldStyle(.plain).padding(10)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                        .focused($focusedField, equals: "fact")
                    formActions(disabled: clean(fact).isEmpty, cancel: { addingFact = false; fact = "" }) {
                        if let editingFactID { memory.updateFact(editingFactID, text: fact) } else { memory.remember(fact) }; fact = ""; addingFact = false; editingFactID = nil
                    }
                }.padding(12).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 16) {
            if vocabulary.isEmpty {
                emptyState("No vocabulary yet", detail: "Keep names, abbreviations, specialist terms, and snippets here.")
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(vocabulary.filter { matches($0.term + " " + $0.heardAs) }) { word in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(word.term).font(.system(size: 13)).lineLimit(6).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                if !word.heardAs.isEmpty {
                                    Text("When heard as: " + word.heardAs).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            removeButton("Remove " + word.term) {
                                vocabularyData = (try? JSONEncoder().encode(vocabulary.filter { $0.id != word.id })) ?? vocabularyData
                            }
                        }.padding(20).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading).settingsSurface()
                    }
                }
            }
            if !vocabulary.isEmpty && vocabulary.filter({ matches($0.term + " " + $0.heardAs) }).isEmpty {
                Text("No matching vocabulary. Try a different search.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if addingWord {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Write as").font(.system(size: 12, weight: .medium))
                    TextField("Name, term, or text to insert", text: $term, axis: .vertical).lineLimit(1...5)
                        .textFieldStyle(.roundedBorder).focused($focusedField, equals: "term")
                    Text("When heard as (optional)").font(.system(size: 12, weight: .medium))
                    TextField("Spoken phrase or misspelling", text: $heardAs).textFieldStyle(.roundedBorder)
                    if let vocabularyConflict {
                        Text(vocabularyConflict).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    formActions(disabled: clean(term).isEmpty || vocabularyConflict != nil, cancel: {
                        addingWord = false; term = ""; heardAs = ""
                    }) {
                        var entries = vocabulary
                        entries.append(VocabularyDraft(term: clean(term), heardAs: clean(heardAs)))
                        vocabularyData = (try? JSONEncoder().encode(entries)) ?? vocabularyData
                        term = ""; heardAs = ""; addingWord = false
                    }
                }.padding(12).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            infoCard(title, icon: selected == "Facts" ? "text.book.closed.fill" : "character.book.closed.fill", detail: detail)
        }
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(SpeekActionButtonStyle()).controlSize(.regular)
        .fixedSize()
    }

    private func editButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "pencil").font(.system(size: 13)).frame(width: 32, height: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    private func removeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(.white)
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    private func formActions(disabled: Bool, cancel: @escaping () -> Void, save: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("Cancel", action: cancel).buttonStyle(SpeekActionButtonStyle())
            Button("Save", action: save).buttonStyle(SpeekActionButtonStyle()).disabled(disabled)
        }
    }
}
