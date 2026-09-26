import Foundation
import Combine

enum ActionRole: String, Codable {
    case user
    case assistant
    case system
}

struct ActionMessage: Identifiable, Codable {
    var id = UUID()
    var role: ActionRole
    var text: String
    var date = Date()
}

struct ActionThread: Identifiable, Codable {
    var id = UUID()
    var title: String
    var messages: [ActionMessage] = []
    var updatedAt = Date()
    var codexSessionID: String?
    var workingDirectory: String?
    var contextNotes: String?
    var connection: ActionConnection?
    var modelID: String?
    var reasoningEffort: String?
    var isPinned: Bool?
    var isArchived: Bool?
}

@MainActor
final class ActionThreadStore: ObservableObject {
    static let shared = ActionThreadStore()

    @Published private(set) var threads: [ActionThread] = []
    @Published var selectedID: UUID?

    private let fileURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.aveekpatra.speek", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("action-threads.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([ActionThread].self, from: data) {
            threads = saved
            selectedID = saved.first(where: { $0.isArchived != true })?.id
        }
    }

    var selectedThread: ActionThread? {
        threads.first { $0.id == selectedID }
    }

    @discardableResult
    func newThread() -> UUID {
        let connection = ActionConnection.preferred
        let thread = ActionThread(title: "New task", connection: connection, modelID: AgentDefaults.model(for: connection), reasoningEffort: AgentDefaults.reasoning(for: connection))
        threads.insert(thread, at: 0)
        selectedID = thread.id
        save()
        return thread.id
    }

    func append(_ text: String, role: ActionRole, to id: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        if role == .user && threads[index].messages.isEmpty {
            threads[index].title = String(text.prefix(48))
        }
        threads[index].messages.append(ActionMessage(role: role, text: text))
        threads[index].updatedAt = Date()
        threads.sort { $0.updatedAt > $1.updatedAt }
        save()
    }

    func setCodexSession(_ sessionID: String, directory: String, for id: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[index].codexSessionID = sessionID
        threads[index].workingDirectory = directory
        save()
    }

    func setWorkingDirectory(_ directory: String, for id: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        if threads[index].workingDirectory != directory {
            threads[index].codexSessionID = nil
        }
        threads[index].workingDirectory = directory
        save()
    }

    func setConnection(_ connection: ActionConnection, for id: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        guard threads[index].connection != connection else { return }
        threads[index].modelID = nil
        threads[index].connection = connection
        threads[index].codexSessionID = nil
        save()
    }

    func setReasoning(_ effort: String?, for id: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[index].reasoningEffort = effort
        save()
    }

    func setModel(_ modelID: String?, for id: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[index].modelID = modelID
        save()
    }

    func setContextNotes(_ notes: String, for id: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        threads[index].contextNotes = trimmed.isEmpty ? nil : String(trimmed.prefix(4_000))
        save()
    }

    func setPinned(_ pinned: Bool, for id: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[index].isPinned = pinned
        save()
    }

    func setArchived(_ archived: Bool, for id: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[index].isArchived = archived
        if archived && selectedID == id { selectedID = threads.first(where: { $0.isArchived != true })?.id }
        save()
    }

    func delete(_ id: UUID) {
        threads.removeAll { $0.id == id }
        if selectedID == id { selectedID = threads.first(where: { $0.isArchived != true })?.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(threads) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
