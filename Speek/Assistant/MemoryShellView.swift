import SwiftUI

private struct VocabularyDraft: Codable, Identifiable {
    var id = UUID()
    var term: String
    var heardAs: String
}

/// Add and edit forms open as sheets so the page never reflows around an inline editor.
private enum MemoryEditor: Identifiable {
    case fact(RememberedFact?), episode(RememberedEpisode), procedure(RememberedProcedure?), vocabulary
    var id: String {
        switch self {
        case .fact(let item): return "fact-" + (item?.id.uuidString ?? "new")
        case .episode(let item): return "episode-" + item.id.uuidString
        case .procedure(let item): return "procedure-" + (item?.id.uuidString ?? "new")
        case .vocabulary: return "vocabulary"
        }
    }
}

/// Memory follows the shape of each kind of content: short statements, dated events and
/// word pairs are lists to scan; procedures are titled documents, so they are tiles.
struct MemoryShellView: View {
    private static let tabs = ["Facts", "Episodic", "Procedural", "Vocabulary"]
    @ObservedObject private var memory = AssistantMemory.shared
    @State private var selected = "Facts"
    @State private var query = ""
    @State private var editor: MemoryEditor?
    @State private var hovered: UUID?
    @State private var expanded: UUID?
    @AppStorage("speek.memory.vocabularyDrafts") private var vocabularyData = Data()
    private var vocabulary: [VocabularyDraft] { (try? JSONDecoder().decode([VocabularyDraft].self, from: vocabularyData)) ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Memory").font(.system(size: 25, weight: .semibold))
                    Text("Facts, experiences, and the way you work.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                PillTabs(items: Self.tabs, selection: $selected)
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let error = memory.persistenceError {
                        Label(error, systemImage: "exclamationmark.circle.fill").font(.system(size: 12)).foregroundStyle(.red)
                    }
                    switch selected {
                    case "Episodic": episodes
                    case "Procedural": procedures
                    case "Vocabulary": words
                    default: facts
                    }
                }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.vertical, 12).padding(24).frame(maxWidth: .infinity)
        }
        .onChange(of: selected) { _, _ in query = ""; expanded = nil }
        .sheet(item: $editor) { item in
            MemoryEditorSheet(editor: item, vocabulary: vocabulary) { entry in
                vocabularyData = (try? JSONEncoder().encode(vocabulary + [entry])) ?? vocabularyData
            }
        }
    }

    // MARK: Header

    /// Same height on every tab: title and info leading, search and add trailing.
    private var header: some View {
        HStack(spacing: 10) {
            Text(selected).font(.system(size: 13, weight: .semibold))
            InfoButton(text: description, subject: selected)
            Spacer(minLength: 16)
            SpeekSearchField(prompt: "Search " + selected.lowercased(), text: $query)
            if let add = addAction {
                Button(action: add.action) { Label(add.title, systemImage: "plus") }
                    .buttonStyle(SpeekActionButtonStyle()).fixedSize()
            }
        }
        .frame(height: 32).padding(.leading, 4)
    }

    private var description: String {
        switch selected {
        case "Episodic": return "Completed requests and their results, saved with dates for future context."
        case "Procedural": return "How to do things: reusable instructions Speek includes with matching requests. Actions still need their usual permissions."
        case "Vocabulary": return "Names, terms, corrections, and spoken shortcuts. Speek writes each entry exactly as saved. Add a spoken phrase to replace what you say, such as a misheard name or your address. Entries without one guide Light and Polished mode."
        default: return "Semantic memory: preferences, people, and things you know. Say \"Remember that...\" to add one by voice."
        }
    }

    private var addAction: (title: String, action: () -> Void)? {
        switch selected {
        case "Facts": return ("Add fact", { editor = .fact(nil) })
        case "Procedural": return ("Add procedure", { editor = .procedure(nil) })
        case "Vocabulary": return ("Add entry", { editor = .vocabulary })
        default: return nil
        }
    }

    private func matches(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }

    // MARK: Facts

    private var facts: some View {
        let items = memory.facts.filter { matches($0.text) }.sorted { $0.date > $1.date }
        return listSurface(isEmpty: items.isEmpty, empty: empty("text.book.closed.fill", "No saved facts", "Add a preference or tell Speek to remember something.")) {
            ForEach(items) { item in
                if item.id != items.first?.id { SettingsRowDivider() }
                row(item.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text(item.date, style: .date).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } actions: {
                    HoverRowActions(visible: hovered == item.id, subject: "fact", edit: { editor = .fact(item) }) { memory.remove(item.id) }
                }
            }
        }
    }

    // MARK: Episodic

    private var episodes: some View {
        let items = memory.episodes.filter { matches($0.request + " " + $0.result) }.sorted { $0.date > $1.date }
        let days = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.date) }.sorted { $0.key > $1.key }
        return VStack(alignment: .leading, spacing: 28) {
            if !memory.saveHistory { HistoryPausedNotice() }
            if items.isEmpty {
                listSurface(isEmpty: true, empty: empty("clock.fill", "No saved events", "Completed requests appear here while history saving is on.")) { EmptyView() }
            }
            ForEach(days, id: \.key) { day, events in
                SettingsSection(title: dayTitle(day)) {
                    ForEach(events) { event in
                        if event.id != events.first?.id { SettingsRowDivider() }
                        row(event.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.request).font(.system(size: 13, weight: .medium)).lineLimit(expanded == event.id ? nil : 2)
                                Text(event.result).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(expanded == event.id ? nil : 2)
                                    .textSelection(.enabled)
                            }
                        } actions: {
                            HStack(spacing: 8) {
                                Text(event.date, style: .time).font(.system(size: 11)).foregroundStyle(.secondary)
                                HoverRowActions(visible: hovered == event.id, subject: "event", edit: { editor = .episode(event) }) { memory.removeEpisode(event.id) }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { expanded = expanded == event.id ? nil : event.id }
                    }
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = Calendar.current.isDate(day, equalTo: Date(), toGranularity: .year)
        return day.formatted(sameYear ? .dateTime.weekday(.wide).month(.wide).day() : .dateTime.month(.wide).day().year())
    }

    // MARK: Procedural

    private var procedures: some View {
        let items = memory.procedures.filter { matches($0.title + " " + $0.instructions) }.sorted { $0.date > $1.date }
        return Group {
            if items.isEmpty {
                IntegrationEmptyTile(symbol: "list.bullet.clipboard", title: query.isEmpty ? "No procedures yet" : "No matches",
                                     text: query.isEmpty ? "Save the steps Speek should follow for recurring work." : "Try a different search.")
            } else {
                LazyVGrid(columns: IntegrationTile<EmptyView, EmptyView>.columns, alignment: .leading, spacing: 16) {
                    ForEach(items) { procedure in
                        IntegrationTile(symbol: "list.bullet.clipboard", title: procedure.title, subtitle: procedure.instructions,
                                        status: "Updated " + procedure.date.formatted(date: .abbreviated, time: .omitted), statusSymbol: "clock",
                                        open: { editor = .procedure(procedure) }) {
                            EmptyView()
                        } menu: {
                            Button("Edit") { editor = .procedure(procedure) }
                            Divider()
                            Button("Delete", role: .destructive) { memory.removeProcedure(procedure.id) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Vocabulary

    private var words: some View {
        let items = vocabulary.filter { matches($0.term + " " + $0.heardAs) }
            .sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
        return listSurface(isEmpty: items.isEmpty, empty: empty("character.book.closed.fill", "No vocabulary yet", "Keep names, terms, and snippets Speek should write your way.")) {
            ForEach(items) { word in
                if word.id != items.first?.id { SettingsRowDivider() }
                row(word.id) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if !word.heardAs.isEmpty {
                            Text(word.heardAs).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                        }
                        Text(word.term).font(.system(size: 13, weight: .medium)).lineLimit(3).textSelection(.enabled)
                    }
                } actions: {
                    HoverRowActions(visible: hovered == word.id, subject: word.term) {
                        vocabularyData = (try? JSONEncoder().encode(vocabulary.filter { $0.id != word.id })) ?? vocabularyData
                    }
                }
            }
        }
    }

    // MARK: Building blocks

    private func listSurface<Rows: View, Empty: View>(isEmpty: Bool, empty: Empty, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(spacing: 0) {
            if isEmpty { empty } else { rows() }
        }.settingsSurface()
    }

    private func row<Content: View, Actions: View>(_ id: UUID, @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .center, spacing: 16) {
            content().frame(maxWidth: .infinity, alignment: .leading)
            actions()
        }
        .padding(16)
        .onHover { inside in if inside { hovered = id } else if hovered == id { hovered = nil } }
    }

    private func empty(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            IntegrationGlyph(symbol: query.isEmpty ? symbol : "magnifyingglass")
            VStack(alignment: .leading, spacing: 4) {
                Text(query.isEmpty ? title : "No matches").font(.system(size: 14, weight: .semibold))
                Text(query.isEmpty ? text : "Try a different search.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(20)
    }
}

private struct MemoryEditorSheet: View {
    let editor: MemoryEditor
    let vocabulary: [VocabularyDraft]
    let addVocabulary: (VocabularyDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var memory = AssistantMemory.shared
    @State private var first = ""
    @State private var second = ""
    @FocusState private var focused: Bool

    private func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 17, weight: .semibold))
            switch editor {
            case .fact:
                field("Fact") { TextField("What should Speek remember?", text: $first, axis: .vertical).lineLimit(3...8).focused($focused) }
            case .episode:
                field("Request") { TextField("Request", text: $first, axis: .vertical).lineLimit(2...4).focused($focused) }
                field("Result") { TextField("Result", text: $second, axis: .vertical).lineLimit(3...8) }
            case .procedure:
                field("Name") { TextField("Weekly project update", text: $first).focused($focused) }
                field("Instructions") { TextField("Steps and preferences to reuse", text: $second, axis: .vertical).lineLimit(5...12) }
            case .vocabulary:
                field("Write as") { TextField("Name, term, or text to insert", text: $first, axis: .vertical).lineLimit(1...5).focused($focused) }
                field("When heard as (optional)") { TextField("Spoken phrase or misspelling", text: $second) }
                if let conflict { Text(conflict).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save") { save(); dismiss() }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }
        .padding(24).frame(width: 460)
        .onAppear(perform: load)
    }

    private var title: String {
        switch editor {
        case .fact(let item): return item == nil ? "New fact" : "Edit fact"
        case .episode: return "Edit event"
        case .procedure(let item): return item == nil ? "New procedure" : "Edit procedure"
        case .vocabulary: return "New vocabulary entry"
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .medium))
            content().textFieldStyle(.roundedBorder).font(.system(size: 13))
        }
    }

    /// A spoken phrase maps to one entry; a term without a spoken phrase is saved once.
    private var conflict: String? {
        let spoken = clean(second)
        if !spoken.isEmpty {
            return vocabulary.contains { $0.heardAs.caseInsensitiveCompare(spoken) == .orderedSame } ? "This spoken phrase is already saved." : nil
        }
        return vocabulary.contains { $0.heardAs.isEmpty && $0.term.caseInsensitiveCompare(clean(first)) == .orderedSame } ? "This term is already saved." : nil
    }

    private var valid: Bool {
        switch editor {
        case .fact: return !clean(first).isEmpty
        case .episode, .procedure: return !clean(first).isEmpty && !clean(second).isEmpty
        case .vocabulary: return !clean(first).isEmpty && conflict == nil
        }
    }

    private func load() {
        switch editor {
        case .fact(let item): first = item?.text ?? ""
        case .episode(let item): first = item.request; second = item.result
        case .procedure(let item): first = item?.title ?? ""; second = item?.instructions ?? ""
        case .vocabulary: break
        }
        focused = true
    }

    private func save() {
        switch editor {
        case .fact(let item): if let item { memory.updateFact(item.id, text: first) } else { memory.remember(first) }
        case .episode(let item): memory.updateEpisode(item.id, request: first, result: second)
        case .procedure(let item): memory.saveProcedure(id: item?.id, title: first, instructions: second)
        case .vocabulary: addVocabulary(VocabularyDraft(term: clean(first), heardAs: clean(second)))
        }
    }
}
