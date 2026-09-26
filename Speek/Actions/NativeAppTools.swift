import Foundation
import AppKit
import Carbon

struct NativeAppToolDefinition {
    let name: String
    let description: String
    let inputSchemaJSON: String
    let requiresConfirmation: Bool
    let service: NativeAppService
}

enum NativeAppService: String, CaseIterable, Identifiable {
    case mail, notes, music, spotify
    var id: String { rawValue }
    var title: String {
        switch self { case .mail: return "Apple Mail"; case .notes: return "Apple Notes"; case .music: return "Apple Music"; case .spotify: return "Spotify" }
    }
    var bundleID: String {
        switch self { case .mail: return "com.apple.mail"; case .notes: return "com.apple.Notes"; case .music: return "com.apple.Music"; case .spotify: return "com.spotify.client" }
    }
    var symbol: String {
        switch self { case .mail: return "envelope"; case .notes: return "note.text"; case .music, .spotify: return "music.note" }
    }
}

/// Fixed AppleScript handlers receive user input exclusively as Apple event arguments.
/// Per-app opt-in and macOS automation permission are both required before any invocation.
@MainActor
final class NativeAppTools {
    static let shared = NativeAppTools()
    static let catalog: [NativeAppToolDefinition] = {
        func tool(_ name: String, _ description: String, service: NativeAppService, fields: [String: [String: Any]], required: [String] = [], write: Bool = false) -> NativeAppToolDefinition {
            let schema: [String: Any] = ["type": "object", "properties": fields, "required": required, "additionalProperties": false]
            return .init(name: name, description: description, inputSchemaJSON: String(decoding: try! JSONSerialization.data(withJSONObject: schema), as: UTF8.self), requiresConfirmation: write, service: service)
        }
        let text = ["type": "string"]
        let search: [String: [String: Any]] = ["query": text, "limit": ["type": "integer", "minimum": 1, "maximum": 50]]
        return [
            tool("mail.search", "Search the 200 most recent messages in the combined Inbox by subject or sender. Returns at most 50. Not a full mailbox search.", service: .mail, fields: search),
            tool("mail.read", "Read an Inbox message using the exact message ID returned by search, up to 16000 characters.", service: .mail, fields: ["id": text], required: ["id"]),
            tool("mail.draft", "Create a visible Mail draft after approval. Does not send it.", service: .mail, fields: ["to": text, "subject": text, "body": text], required: ["to", "subject", "body"], write: true),
            tool("mail.send", "Send an email from the default Mail account to one address after explicit approval.", service: .mail, fields: ["to": text, "subject": text, "body": text], required: ["to", "subject", "body"], write: true),
            tool("mail.reply", "Create a visible reply draft to an Inbox message after approval. Does not send it.", service: .mail, fields: ["id": text, "body": text], required: ["id", "body"], write: true),
            tool("notes.search", "Search the first 200 notes by title. Returns at most 50 note identifiers.", service: .notes, fields: search),
            tool("notes.read", "Read a note as plain text, up to 16000 characters.", service: .notes, fields: ["id": text], required: ["id"]),
            tool("notes.create", "Create a note in the default Notes folder after approval. Body is plain text.", service: .notes, fields: ["title": text, "body": text], required: ["title", "body"], write: true),
            tool("notes.append", "Append plain text to the exact note after approval.", service: .notes, fields: ["id": text, "body": text], required: ["id", "body"], write: true),
            tool("music.status", "Read Apple Music playback state and current track.", service: .music, fields: [:]),
            tool("music.control", "Control Apple Music playback after approval.", service: .music, fields: ["command": ["type": "string", "enum": ["play", "pause", "next", "previous", "volume"]], "volume": ["type": "integer", "minimum": 0, "maximum": 100]], required: ["command"], write: true),
            tool("spotify.status", "Read Spotify playback state and current track.", service: .spotify, fields: [:]),
            tool("spotify.control", "Control Spotify playback after approval.", service: .spotify, fields: ["command": ["type": "string", "enum": ["play", "pause", "next", "previous", "volume"]], "volume": ["type": "integer", "minimum": 0, "maximum": 100]], required: ["command"], write: true)
        ]
    }()

    func isInstalled(_ service: NativeAppService) -> Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: service.bundleID) != nil }
    func isEnabled(_ service: NativeAppService) -> Bool { UserDefaults.standard.bool(forKey: "speek.nativeApps.\(service.rawValue).enabled") }
    func disconnect(_ service: NativeAppService) { UserDefaults.standard.set(false, forKey: "speek.nativeApps.\(service.rawValue).enabled") }

    func connect(_ service: NativeAppService) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: service.bundleID) else { throw failure("Install \(service.title) first.") }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: service.bundleID).isEmpty {} else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        try checkPermission(service, prompt: true)
        UserDefaults.standard.set(true, forKey: "speek.nativeApps.\(service.rawValue).enabled")
    }

    func execute(name: String, argumentsJSON: String, approved: Bool = false) async throws -> OrganizerToolResult {
        guard let tool = Self.catalog.first(where: { $0.name == name }) else { throw failure("Unknown app tool.") }
        guard !tool.requiresConfirmation || approved else { throw failure("Review and approve this action before running it.") }
        guard isEnabled(tool.service) else { throw failure("Connect \(tool.service.title) in Integrations first.") }
        guard isInstalled(tool.service) else { throw failure("\(tool.service.title) is not installed.") }
        try checkPermission(tool.service, prompt: false)
        let args = try JSONDecoder().decode(Arguments.self, from: Data(argumentsJSON.utf8))
        try Task.checkCancellation()
        let values = try argumentValues(name, args)
        let descriptor = try invoke(source: Self.script(for: name), arguments: values)
        var items: [[String: String]] = []
        let keys: [String]
        switch name {
        case "mail.search": keys = ["id", "subject", "sender", "date"]
        case "mail.read": keys = ["id", "subject", "sender", "body"]
        case "notes.search": keys = ["id", "title"]
        case "notes.read": keys = ["id", "title", "body"]
        case "music.status", "spotify.status": keys = ["state", "title", "artist"]
        default: keys = ["id", "status"]
        }
        for index in 1...max(1, descriptor.numberOfItems) {
            guard let row = descriptor.atIndex(index) else { continue }
            var item: [String: String] = [:]
            for (offset, key) in keys.enumerated() { item[key] = String((row.atIndex(offset + 1)?.stringValue ?? "").prefix(16000)) }
            items.append(item)
        }
        return .init(summary: "\(tool.service.title): \(items.count) result\(items.count == 1 ? "" : "s").", items: items)
    }

    private struct Arguments: Decodable {
        var id: String?; var query: String?; var limit: Int?; var to: String?; var subject: String?
        var body: String?; var title: String?; var command: String?; var volume: Int?
    }
    private func argumentValues(_ name: String, _ args: Arguments) throws -> [String] {
        func required(_ value: String?, _ label: String) throws -> String {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 32000 else { throw failure("Provide \(label) between 1 and 32000 characters.") }; return value
        }
        switch name {
        case "mail.search", "notes.search": return [args.query ?? "", String(min(50, max(1, args.limit ?? 20)))]
        case "mail.read", "notes.read": return [try required(args.id, "an identifier")]
        case "mail.draft", "mail.send":
            let recipient = try required(args.to, "a recipient")
            guard recipient.range(of: #"^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$"#, options: .regularExpression) != nil else { throw failure("Provide one email address.") }
            return [recipient, try required(args.subject, "a subject"), try required(args.body, "a message")]
        case "mail.reply": return [try required(args.id, "a message identifier"), try required(args.body, "a reply")]
        case "notes.create": return [try required(args.title, "a title"), html(try required(args.body, "note text"))]
        case "notes.append": return [try required(args.id, "a note identifier"), html(try required(args.body, "note text"))]
        case "music.control", "spotify.control":
            let command = try required(args.command, "a command")
            guard ["play", "pause", "next", "previous", "volume"].contains(command) else { throw failure("Unsupported playback command.") }
            if command == "volume", !(0...100).contains(args.volume ?? -1) { throw failure("Volume must be between 0 and 100.") }
            return [command, String(args.volume ?? 0)]
        default: return []
        }
    }
    private func html(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>") }
    private func failure(_ message: String) -> NSError { NSError(domain: "NativeAppTools", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

    private func checkPermission(_ service: NativeAppService, prompt: Bool) throws {
        let target = NSAppleEventDescriptor(bundleIdentifier: service.bundleID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), prompt)
        guard status == noErr else {
            throw failure("Allow Speek to control \(service.title) in System Settings > Privacy & Security > Automation. macOS returned \(status).")
        }
    }

    private func invoke(source: String, arguments: [String]) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw failure("Could not prepare the app command.") }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: "speekrun"), forKeyword: AEKeyword(keyASSubroutineName))
        let argumentList = NSAppleEventDescriptor.list()
        for (index, value) in arguments.enumerated() { argumentList.insert(NSAppleEventDescriptor(string: value), at: index + 1) }
        let direct = NSAppleEventDescriptor.list(); direct.insert(argumentList, at: 1)
        event.setParam(direct, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if let error { throw failure(error[NSAppleScript.errorMessage] as? String ?? "The app could not complete this command.") }
        return result
    }

    static func script(for name: String) -> String {
        let body: String
        switch name {
        case "mail.search": body = #"""
        tell application id "com.apple.mail"
            set output to {}
            set sourceMessages to messages of inbox
            set maxScan to count sourceMessages
            if maxScan > 200 then set maxScan to 200
            repeat with i from 1 to maxScan
                set m to item i of sourceMessages
                if (item 1 of a is "") or (subject of m contains item 1 of a) or (sender of m contains item 1 of a) then
                    set end of output to {(id of m) as text, subject of m, sender of m, (date received of m) as text}
                    if (count output) >= (item 2 of a as integer) then exit repeat
                end if
            end repeat
            return output
        end tell
        """#
        case "mail.read": body = #"""
        tell application id "com.apple.mail"
            set matches to messages of inbox whose id is (item 1 of a as integer)
            if (count matches) is 0 then error "Message is no longer in Inbox. Search again."
            set m to item 1 of matches
            set messageText to content of m
            if (count messageText) > 16000 then set messageText to text 1 thru 16000 of messageText
            return {{(id of m) as text, subject of m, sender of m, messageText}}
        end tell
        """#
        case "mail.draft", "mail.send":
            let completion = name == "mail.send" ? "set messageID to (id of m) as text\nset submitted to send m\nif not submitted then error \"Mail could not submit the message.\"\nreturn {{messageID, \"Submitted to Mail for sending\"}}" : "set visible of m to true\nreturn {{(id of m) as text, \"Draft created\"}}"
            body = #"""
            tell application id "com.apple.mail"
                set m to make new outgoing message with properties {subject:item 2 of a, content:item 3 of a, visible:false}
                tell m to make new to recipient at end of to recipients with properties {address:item 1 of a}
            """# + "\n" + completion + "\nend tell"
        case "mail.reply": body = #"""
        tell application id "com.apple.mail"
            set matches to messages of inbox whose id is (item 1 of a as integer)
            if (count matches) is 0 then error "Message is no longer in Inbox. Search again."
            set m to reply (item 1 of matches) opening window false
            set content of m to (item 2 of a) & return & (content of m)
            set visible of m to true
            return {{(id of m) as text, "Reply draft created"}}
        end tell
        """#
        case "notes.search": body = #"""
        tell application id "com.apple.Notes"
            set output to {}
            set sourceNotes to notes
            set maxScan to count sourceNotes
            if maxScan > 200 then set maxScan to 200
            repeat with i from 1 to maxScan
                set n to item i of sourceNotes
                if (item 1 of a is "") or (name of n contains item 1 of a) then
                    set end of output to {id of n, name of n}
                    if (count output) >= (item 2 of a as integer) then exit repeat
                end if
            end repeat
            return output
        end tell
        """#
        case "notes.read": body = #"""
        tell application id "com.apple.Notes"
            set n to note id (item 1 of a)
            set noteText to plaintext of n
            if (count noteText) > 16000 then set noteText to text 1 thru 16000 of noteText
            return {{id of n, name of n, noteText}}
        end tell
        """#
        case "notes.create": body = #"""
        tell application id "com.apple.Notes"
            set n to make new note at default folder of default account with properties {name:item 1 of a, body:item 2 of a}
            return {{id of n, "Note created"}}
        end tell
        """#
        case "notes.append": body = #"""
        tell application id "com.apple.Notes"
            set n to note id (item 1 of a)
            if (count attachments of n) > 0 then error "This note contains attachments. Append to a plain-text note to preserve its contents."
            set body of n to (body of n) & "<br>" & (item 2 of a)
            return {{id of n, "Text appended"}}
        end tell
        """#
        case "music.status", "spotify.status":
            let application = name.hasPrefix("music.") ? "com.apple.Music" : "com.spotify.client"
            body = "tell application id \"\(application)\"\nset playbackState to player state as text\nif playbackState is \"stopped\" then return {{playbackState, \"\", \"\"}}\nreturn {{playbackState, name of current track, artist of current track}}\nend tell"
        default:
            let application = name.hasPrefix("music.") ? "com.apple.Music" : "com.spotify.client"
            body = "tell application id \"\(application)\"\n" + #"""
            set commandName to item 1 of a
            if commandName is "play" then
                play
            else if commandName is "pause" then
                pause
            else if commandName is "next" then
                next track
            else if commandName is "previous" then
                previous track
            else if commandName is "volume" then
                set sound volume to item 2 of a as integer
            end if
            return {{"", "Playback command completed"}}
            end tell
            """#
        }
        return "on speekrun(a)\nwith timeout of 30 seconds\n" + body + "\nend timeout\nend speekrun"
    }
}
