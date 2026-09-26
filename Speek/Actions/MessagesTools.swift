import Foundation
import AppKit
import Carbon
import SQLite3

struct MessagesToolDefinition {
    let name: String
    let description: String
    let inputSchemaJSON: String
    let requiresConfirmation: Bool
}

/// Reads only the documented subset this adapter recognizes. It never decodes
/// private attributed-body archives, writes the database, or marks messages read.
final class MessagesDatabase {
    private let url: URL
    init(url: URL) { self.url = url }

    func read(operation: String, query: String? = nil, conversationID: String? = nil, limit: Int = 20) throws -> OrganizerToolResult {
        guard ["messages.recent", "messages.conversation", "messages.search", "messages.unread"].contains(operation) else { throw failure("Unsupported Messages read operation.") }
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard openResult == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw failure("Messages history is unavailable. Grant Speek Full Disk Access in System Settings, then restart Speek. No database permissions were changed.")
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1000)
        let required = ["message": ["ROWID", "text", "date", "is_from_me", "is_read", "handle_id", "service"], "chat": ["ROWID", "guid", "chat_identifier", "display_name"], "chat_message_join": ["chat_id", "message_id"], "handle": ["ROWID", "id"]]
        for (table, columns) in required {
            let found = try rows(database, sql: "PRAGMA table_info(\(table))", bindings: []).compactMap { $0["name"]?.lowercased() }
            guard !found.isEmpty, columns.allSatisfy({ $0 == "ROWID" || found.contains($0.lowercased()) }) else {
                throw failure("This macOS Messages database format is not supported. Sending can still be connected separately.")
            }
        }
        let count = min(50, max(1, limit))
        if operation == "messages.recent" {
            let sql = """
            SELECT c.guid AS conversationID, c.chat_identifier AS identifier, COALESCE(c.display_name,'') AS title,
            MAX(m.date) AS latestDate, SUM(CASE WHEN m.is_from_me=0 AND m.is_read=0 THEN 1 ELSE 0 END) AS unreadCount
            FROM chat c JOIN chat_message_join j ON j.chat_id=c.ROWID JOIN message m ON m.ROWID=j.message_id
            WHERE m.service='iMessage' GROUP BY c.ROWID ORDER BY latestDate DESC LIMIT ?
            """
            let result = try rows(database, sql: sql, bindings: [.integer(count)]).map { value -> [String: String] in
                var value = value
                value["latestDate"] = date(value["latestDate"])
                return value
            }
            return .init(summary: "Recent iMessage conversations. Group identifiers are not individual send recipients.", items: result)
        }
        var predicates = ["m.service='iMessage'"], bindings: [Binding] = []
        if operation == "messages.conversation" {
            guard let conversationID, !conversationID.isEmpty, conversationID.count <= 500 else { throw failure("Use an exact conversationID returned by Recent conversations.") }
            predicates.append("c.guid=?"); bindings.append(.text(conversationID))
        }
        if operation == "messages.search" {
            guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.count <= 200 else { throw failure("Provide search text between 1 and 200 characters.") }
            predicates.append("instr(lower(COALESCE(m.text,'')),lower(?))>0"); bindings.append(.text(query))
        }
        if operation == "messages.unread" { predicates += ["m.is_from_me=0", "m.is_read=0"] }
        bindings.append(.integer(count))
        let sql = """
        SELECT m.ROWID AS messageID, c.guid AS conversationID, COALESCE(h.id,'') AS sender,
        substr(COALESCE(m.text,''),1,8000) AS text, CASE WHEN m.text IS NULL THEN 'false' ELSE 'true' END AS textAvailable,
        m.date AS date, m.is_from_me AS fromMe, m.is_read AS isRead
        FROM message m JOIN chat_message_join j ON j.message_id=m.ROWID JOIN chat c ON c.ROWID=j.chat_id
        LEFT JOIN handle h ON h.ROWID=m.handle_id
        WHERE \(predicates.joined(separator: " AND ")) ORDER BY m.date DESC LIMIT ?
        """
        var result = try rows(database, sql: sql, bindings: bindings).map { value -> [String: String] in
            var value = value
            value["date"] = date(value["date"])
            if value["textAvailable"] == "false" { value["text"] = "Message text is unavailable in the readable database fields. Open Messages to view it." }
            return value
        }
        if operation == "messages.conversation" { result.reverse() }
        return .init(summary: "Returned \(result.count) iMessages. Search covers plain text only; rich or attachment-only messages may not have readable text. Messages were not marked read.", items: result)
    }

    private enum Binding { case text(String), integer(Int) }
    private func rows(_ database: OpaquePointer, sql: String, bindings: [Binding]) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure("Messages could not be queried using the supported schema.") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, binding) in bindings.enumerated() {
            let status: Int32
            switch binding {
            case .text(let value): status = sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
            case .integer(let value): status = sqlite3_bind_int64(statement, Int32(index + 1), Int64(value))
            }
            guard status == SQLITE_OK else { throw failure("The Messages query could not be prepared.") }
        }
        var result: [[String: String]] = []
        var budget = 0
        return try withUnsafeMutablePointer(to: &budget) { counter in
            sqlite3_progress_handler(database, 10000, { pointer in
                guard let pointer else { return 1 }
                let value = pointer.assumingMemoryBound(to: Int.self)
                value.pointee += 1
                return value.pointee > 1000 ? 1 : 0
            }, counter)
            defer { sqlite3_progress_handler(database, 0, nil, nil) }
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { return result }
                guard status == SQLITE_ROW else { throw failure(status == SQLITE_INTERRUPT ? "This Messages query was too large. Open Messages to search the full history." : "Messages history is busy or unavailable. Try again after Messages finishes updating.") }
                var item: [String: String] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    let name = String(cString: sqlite3_column_name(statement, index))
                    if let text = sqlite3_column_text(statement, index) { item[name] = String(cString: text) }
                }
                result.append(item)
                guard result.count <= 200 else { throw failure("Messages returned more rows than the supported limit.") }
            }
        }
    }
    private func date(_ raw: String?) -> String {
        guard let raw, let value = Double(raw) else { return "" }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSinceReferenceDate: abs(value) > 1_000_000_000_000 ? value / 1_000_000_000 : value))
    }
    private func failure(_ value: String) -> NSError { NSError(domain: "MessagesDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: value]) }
}

@MainActor
final class MessagesTools {
    static let shared = MessagesTools()
    static let catalog: [MessagesToolDefinition] = {
        func tool(_ name: String, _ description: String, fields: [String: [String: Any]], required: [String] = [], write: Bool = false) -> MessagesToolDefinition {
            let schema: [String: Any] = ["type": "object", "properties": fields, "required": required, "additionalProperties": false]
            return .init(name: name, description: description, inputSchemaJSON: String(decoding: try! JSONSerialization.data(withJSONObject: schema), as: UTF8.self), requiresConfirmation: write)
        }
        let limit: [String: Any] = ["type": "integer", "minimum": 1, "maximum": 50]
        return [
            tool("messages.recent", "List recent iMessage conversations. Requires explicit history access and Full Disk Access.", fields: ["limit": limit]),
            tool("messages.conversation", "Read recent messages from an exact conversationID. Rich text may be unavailable; never marks messages read.", fields: ["conversationID": ["type": "string"], "limit": limit], required: ["conversationID"]),
            tool("messages.search", "Search readable iMessage plain text only, not attachments or private attributed-body archives.", fields: ["query": ["type": "string"], "limit": limit], required: ["query"]),
            tool("messages.unread", "Read unread incoming iMessages without marking them read. Rich text may be unavailable.", fields: ["limit": limit]),
            tool("messages.send", "Send one iMessage only after reviewing the exact recipient and body. Recipient must be a user-confirmed international phone number or email address, never a guessed contact name or group ID.", fields: ["recipient": ["type": "string"], "body": ["type": "string", "maxLength": 16000]], required: ["recipient", "body"], write: true)
        ]
    }()
    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS") != nil }
    var historyEnabled: Bool { UserDefaults.standard.bool(forKey: "speek.messages.historyEnabled") }
    var sendingEnabled: Bool { UserDefaults.standard.bool(forKey: "speek.messages.sendingEnabled") }
    var isEnabled: Bool { historyEnabled || sendingEnabled }
    var availableCatalog: [MessagesToolDefinition] { Self.catalog.filter { $0.requiresConfirmation ? sendingEnabled : historyEnabled } }
    func disableHistory() { UserDefaults.standard.set(false, forKey: "speek.messages.historyEnabled") }
    func disableSending() { UserDefaults.standard.set(false, forKey: "speek.messages.sendingEnabled") }
    func enableHistory() { UserDefaults.standard.set(true, forKey: "speek.messages.historyEnabled") }

    func connectSending() async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS") else { throw failure("Messages is not installed.") }
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MobileSMS").isEmpty {
            let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        try permission(prompt: true)
        UserDefaults.standard.set(true, forKey: "speek.messages.sendingEnabled")
    }

    func execute(name: String, argumentsJSON: String, approved: Bool = false) async throws -> OrganizerToolResult {
        guard let tool = Self.catalog.first(where: { $0.name == name }) else { throw failure("Unknown Messages tool.") }
        guard !tool.requiresConfirmation || approved else { throw failure("Review the exact recipient and message before sending.") }
        guard tool.requiresConfirmation ? sendingEnabled : historyEnabled else { throw failure("Enable this Messages capability in Integrations first.") }
        let args = try JSONDecoder().decode(Arguments.self, from: Data(argumentsJSON.utf8))
        try Task.checkCancellation()
        if !tool.requiresConfirmation {
            let database = MessagesDatabase(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db"))
            return try database.read(operation: name, query: args.query, conversationID: args.conversationID, limit: args.limit ?? 20)
        }
        guard let target = args.recipient, Self.isValidRecipient(target), let body = args.body,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, body.count <= 16000 else { throw failure("Use one exact international phone number or email and a message between 1 and 16000 characters.") }
        try permission(prompt: false)
        guard let script = NSAppleScript(source: Self.sendScript) else { throw failure("Could not prepare Messages.") }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: "speeksend"), forKeyword: AEKeyword(keyASSubroutineName))
        let arguments = NSAppleEventDescriptor.list()
        arguments.insert(NSAppleEventDescriptor(string: target), at: 1); arguments.insert(NSAppleEventDescriptor(string: body), at: 2)
        let direct = NSAppleEventDescriptor.list(); direct.insert(arguments, at: 1)
        event.setParam(direct, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        _ = script.executeAppleEvent(event, error: &error)
        if let error { throw failure(error[NSAppleScript.errorMessage] as? String ?? "Messages could not submit this message.") }
        return .init(summary: "Submitted to Messages. Delivery is not confirmed.", items: [["recipient": target, "body": body]])
    }
    static func isValidRecipient(_ value: String) -> Bool {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else { return false }
        return value.range(of: #"^\+[1-9][0-9]{6,14}$"#, options: .regularExpression) != nil || value.range(of: #"^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$"#, options: .regularExpression) != nil
    }
    private struct Arguments: Decodable { var query: String?; var conversationID: String?; var limit: Int?; var recipient: String?; var body: String? }
    private func permission(prompt: Bool) throws {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.MobileSMS")
        let result = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), prompt)
        guard result == noErr else { throw failure("Allow Speek to control Messages in System Settings > Privacy & Security > Automation. macOS returned \(result).") }
    }
    private func failure(_ value: String) -> NSError { NSError(domain: "MessagesTools", code: 1, userInfo: [NSLocalizedDescriptionKey: value]) }
    static let sendScript = #"""
    on speeksend(a)
        with timeout of 30 seconds
            tell application id "com.apple.MobileSMS"
                set availableAccounts to every account whose service type is iMessage and enabled is true
                if (count availableAccounts) is not 1 then error "Choose exactly one enabled iMessage account in Messages before sending."
                set targetAccount to item 1 of availableAccounts
                if connection status of targetAccount is not connected then error "Sign in to iMessage before sending."
                set targetParticipant to participant (item 1 of a) of targetAccount
                send (item 2 of a) to targetParticipant
            end tell
        end timeout
    end speeksend
    """#
}
