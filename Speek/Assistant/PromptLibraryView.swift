import SwiftUI

struct PromptLibraryView: View {
    var usePrompt: (String) -> Void
    @ObservedObject private var library = PromptLibrary.shared
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var editing = false
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var bodyText = ""
    @State private var selectedPrompt: SavedPrompt?
    @State private var values: [String: String] = [:]
    @State private var renderError: String?
    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 16, alignment: .top)]

    private var results: [SavedPrompt] {
        library.prompts.filter {
            (!favoritesOnly || $0.isFavorite) && (search.isEmpty || ($0.name + " " + $0.body).localizedCaseInsensitiveContains(search))
        }.sorted { $0.isFavorite == $1.isFavorite ? $0.updatedAt > $1.updatedAt : $0.isFavorite }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) { heading; Spacer(minLength: 16); addButton }
                    VStack(alignment: .leading, spacing: 16) { heading; addButton }
                }
                HStack(spacing: 12) {
                    TextField("Find a prompt", text: $search).textFieldStyle(.roundedBorder).font(.system(size: 13))
                    Toggle("Favorites", isOn: $favoritesOnly).toggleStyle(.button).buttonStyle(SpeekActionButtonStyle()).fixedSize()
                }
                if let error = library.error {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(.system(size: 12)).foregroundStyle(.red)
                }
                if results.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "text.bubble").font(.system(size: 22)).frame(width: 44, height: 44)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        Text(library.prompts.isEmpty ? "Your reusable prompts" : "No matching prompts").font(.system(size: 14, weight: .semibold))
                        Text(library.prompts.isEmpty ? "Save instructions you use often. Add {{topic}} or {{recipient}} to fill in the details each time." : "Try another search or show all prompts.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).settingsSurface()
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(results) { prompt in card(prompt) }
                    }
                }
            }.frame(maxWidth: 880, alignment: .leading).padding(.vertical, 12).padding(24).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $editing) { editor }
        .sheet(item: $selectedPrompt) { prompt in variableEditor(prompt) }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prompts").font(.system(size: 25, weight: .semibold))
            Text("Reusable instructions, ready for your next chat.").font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
    private var addButton: some View {
        Button { editingID = nil; name = ""; bodyText = ""; editing = true } label: { Label("Add prompt", systemImage: "plus") }
            .buttonStyle(SpeekActionButtonStyle()).fixedSize()
    }
    private func card(_ prompt: SavedPrompt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text(prompt.name).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                Button { library.toggleFavorite(prompt.id) } label: {
                    Image(systemName: prompt.isFavorite ? "star.fill" : "star").frame(width: 28, height: 28)
                }.buttonStyle(.plain).help(prompt.isFavorite ? "Remove from favorites" : "Add to favorites")
                    .accessibilityLabel(prompt.isFavorite ? "Remove from favorites" : "Add to favorites")
                Menu {
                    Button("Edit", systemImage: "pencil") { editingID = prompt.id; name = prompt.name; bodyText = prompt.body; editing = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { library.remove(prompt.id) }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Prompt actions")
            }
            Text(prompt.body).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(6).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            HStack {
                Text(prompt.variables.isEmpty ? "Ready to use" : "\(prompt.variables.count) fields to fill")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Use prompt") {
                    if prompt.variables.isEmpty { usePrompt(prompt.body) }
                    else { values = [:]; renderError = nil; selectedPrompt = prompt }
                }.buttonStyle(SpeekActionButtonStyle())
            }
        }.padding(20).frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading).settingsSurface()
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editingID == nil ? "New prompt" : "Edit prompt").font(.system(size: 20, weight: .semibold))
            TextField("Prompt name", text: $name).textFieldStyle(.roundedBorder).accessibilityLabel("Prompt name")
            TextEditor(text: $bodyText).font(.system(size: 13)).scrollContentBackground(.hidden).padding(8)
                .frame(minHeight: 180, maxHeight: 320).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Prompt instructions")
            Text("Use {{name}} for a field you will fill before inserting. This creates a chat draft; it does not schedule or execute actions.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = library.error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") { editing = false }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save") { if library.save(id: editingID, name: name, body: bodyText) { editing = false } }
                    .buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(minWidth: 400, idealWidth: 520, maxWidth: 640)
    }

    private func variableEditor(_ prompt: SavedPrompt) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt.name).font(.system(size: 20, weight: .semibold))
            Text("Fill in the details, then review the prompt in your chat.").font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(prompt.variables, id: \.self) { variable in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(variable).font(.system(size: 13, weight: .medium))
                            TextField(variable, text: Binding(get: { values[variable] ?? "" }, set: { values[variable] = $0 }), axis: .vertical)
                                .lineLimit(1...5).textFieldStyle(.roundedBorder).accessibilityLabel(variable)
                        }
                    }
                }
            }.frame(maxHeight: 320)
            if let renderError { Text(renderError).font(.system(size: 11)).foregroundStyle(.red) }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") { selectedPrompt = nil }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Insert prompt") {
                    do { let text = try PromptTemplate.render(prompt.body, values: values); selectedPrompt = nil; usePrompt(text) }
                    catch { renderError = error.localizedDescription }
                }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(prompt.variables.contains { (values[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
        }.padding(24).frame(minWidth: 400, idealWidth: 520, maxWidth: 640)
    }
}
