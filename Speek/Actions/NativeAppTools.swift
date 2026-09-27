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
        let limit: [String: Any] = ["type": "integer", "minimum": 1, "maximum": 50]
        let flag: [String: Any] = ["type": "boolean"]
        let playback: [String: Any] = ["type": "string", "enum": ["play", "pause", "next", "previous", "volume", "shuffle_on", "shuffle_off", "repeat_all", "repeat_one", "repeat_off"]]
        return [
            tool("mail.search", "Search Mail by subject or sender, optionally message body. Searches all inboxes, or one mailbox by exact name (see mail.mailboxes). Newest first, at most 50. Empty query lists recent messages; unread=true returns only unread. Returns ids for mail.read, mail.reply, mail.move, and mail.mark.", service: .mail,
                 fields: ["query": text, "mailbox": text, "unread": flag, "searchBody": flag, "limit": limit]),
            tool("mail.mailboxes", "List Mail accounts and mailboxes with unread counts.", service: .mail, fields: [:]),
            tool("mail.read", "Read a message by the exact id returned by mail.search, up to 16000 characters.", service: .mail, fields: ["id": text], required: ["id"]),
            tool("mail.draft", "Create a visible Mail draft after approval. Does not send it.", service: .mail, fields: ["to": text, "subject": text, "body": text], required: ["to", "subject", "body"], write: true),
            tool("mail.send", "Send an email from the default Mail account to one address after explicit approval.", service: .mail, fields: ["to": text, "subject": text, "body": text], required: ["to", "subject", "body"], write: true),
            tool("mail.reply", "Create a visible reply draft to a message after approval. Does not send it.", service: .mail, fields: ["id": text, "body": text], required: ["id", "body"], write: true),
            tool("mail.move", "Move a message to a mailbox in the same account (for example Archive or Trash) after approval.", service: .mail, fields: ["id": text, "mailbox": text], required: ["id", "mailbox"], write: true),
            tool("mail.mark", "Mark a message read, unread, flagged, or unflagged.", service: .mail, fields: ["id": text, "action": ["type": "string", "enum": ["read", "unread", "flag", "unflag"]]], required: ["id", "action"], write: true),
            tool("notes.folders", "List Notes folders with their note counts.", service: .notes, fields: [:]),
            tool("notes.search", "Search notes by title and text, in all folders or one folder by exact name. Empty query lists recent notes. At most 50.", service: .notes, fields: ["query": text, "folder": text, "limit": limit]),
            tool("notes.read", "Read a note as plain text, up to 16000 characters.", service: .notes, fields: ["id": text], required: ["id"]),
            tool("notes.create", "Create a note after approval, in the default folder or a folder by exact name. Body is plain text.", service: .notes, fields: ["title": text, "body": text, "folder": text], required: ["title", "body"], write: true),
            tool("notes.append", "Append plain text to the exact note after approval.", service: .notes, fields: ["id": text, "body": text], required: ["id", "body"], write: true),
            tool("music.status", "Read Apple Music playback state and current track.", service: .music, fields: [:]),
            tool("music.control", "Control Apple Music playback after approval: play, pause, skip, volume, shuffle, repeat.", service: .music, fields: ["command": playback, "volume": ["type": "integer", "minimum": 0, "maximum": 100]], required: ["command"], write: true),
            tool("music.play", "Find and play something from the Apple Music library: a song, album, or artist by name, or a playlist by exact name.", service: .music, fields: ["query": text, "kind": ["type": "string", "enum": ["song", "album", "artist", "playlist"]]], required: ["query", "kind"], write: true),
            tool("music.playlists", "List Apple Music playlists.", service: .music, fields: [:]),
            tool("spotify.status", "Read Spotify playback state and current track.", service: .spotify, fields: [:]),
            tool("spotify.control", "Control Spotify playback after approval: play, pause, skip, volume, shuffle, repeat.", service: .spotify, fields: ["command": playback, "volume": ["type": "integer", "minimum": 0, "maximum": 100]], required: ["command"], write: true),
            tool("spotify.play", "Play a Spotify track, album, playlist, or artist by its spotify: URI or open.spotify.com link. Find URIs with spotify.search when the Spotify account is signed in, otherwise with web.search (site:open.spotify.com plus the song and artist).", service: .spotify, fields: ["uri": text], required: ["uri"], write: true)
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
        case "mail.search": keys = ["id", "subject", "sender", "date", "unread"]
        case "mail.mailboxes": keys = ["account", "mailbox", "unread"]
        case "mail.read": keys = ["id", "subject", "sender", "body"]
        case "notes.search": keys = ["id", "title", "folder", "modified"]
        case "notes.folders": keys = ["folder", "account", "notes"]
        case "music.playlists": keys = ["playlist", "tracks"]
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

    /// Decoded leniently: models sometimes send numbers as strings ("20"), booleans as "true",
    /// or text as numbers, which strict decoding rejects with an unhelpful format error.
    private struct Arguments: Decodable {
        var id: String?; var query: String?; var limit: Int?; var to: String?; var subject: String?
        var body: String?; var title: String?; var command: String?; var volume: Int?
        var mailbox: String?; var unread: Bool?; var searchBody: Bool?; var action: String?
        var folder: String?; var kind: String?; var uri: String?

        private struct Key: CodingKey {
            var stringValue: String; var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Key.self)
            func string(_ name: String) -> String? {
                let key = Key(stringValue: name)
                if let text = try? values.decodeIfPresent(String.self, forKey: key) { return text }
                if let number = try? values.decodeIfPresent(Double.self, forKey: key) { return number.rounded() == number ? String(Int(number)) : String(number) }
                if let flag = try? values.decodeIfPresent(Bool.self, forKey: key) { return flag ? "true" : "false" }
                return nil
            }
            func int(_ name: String) -> Int? {
                let key = Key(stringValue: name)
                if let number = try? values.decodeIfPresent(Double.self, forKey: key) { return Int(number) }
                return string(name).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { Int($0) }
            }
            func bool(_ name: String) -> Bool? {
                let key = Key(stringValue: name)
                if let flag = try? values.decodeIfPresent(Bool.self, forKey: key) { return flag }
                switch string(name)?.lowercased() { case "true", "yes", "1": return true; case "false", "no", "0": return false; default: return nil }
            }
            id = string("id"); query = string("query"); limit = int("limit"); to = string("to"); subject = string("subject")
            body = string("body"); title = string("title"); command = string("command"); volume = int("volume")
            mailbox = string("mailbox"); unread = bool("unread"); searchBody = bool("searchBody"); action = string("action")
            folder = string("folder"); kind = string("kind"); uri = string("uri")
        }
    }
    private func argumentValues(_ name: String, _ args: Arguments) throws -> [String] {
        func required(_ value: String?, _ label: String) throws -> String {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 32000 else { throw failure("Provide \(label) between 1 and 32000 characters.") }; return value
        }
        switch name {
        case "mail.search":
            return [args.query ?? "", String(min(50, max(1, args.limit ?? 20))), (args.unread ?? false) ? "true" : "false",
                    (args.searchBody ?? false) ? "true" : "false", args.mailbox ?? ""]
        case "notes.search": return [args.query ?? "", String(min(50, max(1, args.limit ?? 20))), args.folder ?? ""]
        case "mail.mailboxes", "notes.folders", "music.playlists": return []
        case "mail.move": return [try required(args.id, "a message identifier"), try required(args.mailbox, "a mailbox")]
        case "mail.mark":
            let action = try required(args.action, "an action")
            guard ["read", "unread", "flag", "unflag"].contains(action) else { throw failure("Unsupported mark action.") }
            return [try required(args.id, "a message identifier"), action]
        case "music.play":
            let kind = try required(args.kind, "a kind")
            guard ["song", "album", "artist", "playlist"].contains(kind) else { throw failure("Kind must be song, album, artist, or playlist.") }
            return [try required(args.query, "what to play"), kind]
        case "spotify.play": return [try Self.spotifyURI(try required(args.uri, "a Spotify link"))]
        case "mail.read", "notes.read": return [try required(args.id, "an identifier")]
        case "mail.draft", "mail.send":
            let recipient = try required(args.to, "a recipient")
            guard recipient.range(of: #"^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$"#, options: .regularExpression) != nil else { throw failure("Provide one email address.") }
            return [recipient, try required(args.subject, "a subject"), try required(args.body, "a message")]
        case "mail.reply": return [try required(args.id, "a message identifier"), try required(args.body, "a reply")]
        case "notes.create": return [try required(args.title, "a title"), html(try required(args.body, "note text")), args.folder ?? ""]
        case "notes.append": return [try required(args.id, "a note identifier"), html(try required(args.body, "note text"))]
        case "music.control", "spotify.control":
            let command = try required(args.command, "a command")
            guard ["play", "pause", "next", "previous", "volume", "shuffle_on", "shuffle_off", "repeat_all", "repeat_one", "repeat_off"].contains(command) else { throw failure("Unsupported playback command.") }
            if command == "volume", !(0...100).contains(args.volume ?? -1) { throw failure("Volume must be between 0 and 100.") }
            return [command, String(args.volume ?? 0)]
        default: return []
        }
    }
    /// Accepts spotify: URIs and open.spotify.com links; returns a spotify: URI.
    static func spotifyURI(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let kinds = ["track", "album", "playlist", "artist", "episode", "show", "audiobook"]
        func invalid(_ message: String) -> NSError { NSError(domain: "NativeAppTools", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        if trimmed.hasPrefix("spotify:") {
            let parts = trimmed.split(separator: ":")
            guard parts.count == 3, kinds.contains(String(parts[1])), parts[2].allSatisfy({ $0.isLetter || $0.isNumber }) else { throw invalid("That is not a valid Spotify link.") }
            return trimmed
        }
        guard let url = URL(string: trimmed), url.host == "open.spotify.com" else { throw invalid("Use a spotify: URI or an open.spotify.com link.") }
        let path = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
        guard path.count >= 2, kinds.contains(path[0]), path[1].allSatisfy({ $0.isLetter || $0.isNumber }) else { throw invalid("That Spotify link does not point to a track, album, playlist, artist, or episode.") }
        return "spotify:" + path[0] + ":" + path[1]
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
            set q to item 1 of a
            set limitCount to item 2 of a as integer
            set wantUnread to (item 3 of a is "true")
            set searchBody to (item 4 of a is "true")
            set boxName to item 5 of a
            if boxName is "" then
                set sources to {inbox}
            else
                set sources to {}
                repeat with acc in accounts
                    try
                        set end of sources to mailbox boxName of acc
                    end try
                end repeat
                if (count sources) is 0 then error "No mailbox is named " & boxName & ". List mailboxes first."
            end if
            set output to {}
            repeat with src in sources
                if q is "" and wantUnread then
                    set found to (messages of src whose read status is false)
                else if q is "" then
                    set found to messages of src
                else if searchBody then
                    set found to (messages of src whose subject contains q or sender contains q or content contains q)
                else
                    set found to (messages of src whose subject contains q or sender contains q)
                end if
                repeat with m in found
                    if (not wantUnread) or (read status of m is false) then
                        set mb to mailbox of m
                        set end of output to {(name of account of mb) & "|" & (name of mb) & "|" & ((id of m) as text), subject of m, sender of m, (date received of m) as text, (not (read status of m)) as text}
                        if (count output) >= limitCount then return output
                    end if
                end repeat
            end repeat
            return output
        end tell
        """#
        case "mail.mailboxes": body = #"""
        tell application id "com.apple.mail"
            set output to {}
            repeat with acc in accounts
                repeat with mb in mailboxes of acc
                    set end of output to {name of acc, name of mb, (unread count of mb) as text}
                end repeat
            end repeat
            return output
        end tell
        """#
        case "mail.move": body = #"""
        set m to my findMessage(item 1 of a)
        tell application id "com.apple.mail"
            set acc to account of mailbox of m
            set target to mailbox (item 2 of a) of acc
            move m to target
            return {{item 1 of a, "Moved to " & (item 2 of a)}}
        end tell
        """#
        case "mail.mark": body = #"""
        set m to my findMessage(item 1 of a)
        tell application id "com.apple.mail"
            if item 2 of a is "read" then set read status of m to true
            if item 2 of a is "unread" then set read status of m to false
            if item 2 of a is "flag" then set flagged status of m to true
            if item 2 of a is "unflag" then set flagged status of m to false
            return {{item 1 of a, "Marked " & (item 2 of a)}}
        end tell
        """#
        case "mail.read": body = #"""
        set m to my findMessage(item 1 of a)
        tell application id "com.apple.mail"
            set messageText to content of m
            if (count messageText) > 16000 then set messageText to text 1 thru 16000 of messageText
            return {{item 1 of a, subject of m, sender of m, messageText}}
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
        set original to my findMessage(item 1 of a)
        tell application id "com.apple.mail"
            set m to reply original opening window false
            set content of m to (item 2 of a) & return & (content of m)
            set visible of m to true
            return {{(id of m) as text, "Reply draft created"}}
        end tell
        """#
        case "notes.search": body = #"""
        tell application id "com.apple.Notes"
            set q to item 1 of a
            set limitCount to item 2 of a as integer
            if item 3 of a is "" then
                set scope to notes
            else
                set scope to {}
                repeat with f in folders
                    if name of f is (item 3 of a) then set scope to scope & (notes of f)
                end repeat
                if (count scope) is 0 then error "No folder is named " & (item 3 of a) & ". List folders first."
            end if
            set output to {}
            repeat with n in scope
                if q is "" or (name of n contains q) or (plaintext of n contains q) then
                    set end of output to {id of n, name of n, name of container of n, (modification date of n) as text}
                    if (count output) >= limitCount then exit repeat
                end if
            end repeat
            return output
        end tell
        """#
        case "notes.folders": body = #"""
        tell application id "com.apple.Notes"
            set output to {}
            repeat with acc in accounts
                repeat with f in folders of acc
                    set end of output to {name of f, name of acc, (count notes of f) as text}
                end repeat
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
            set destination to default folder of default account
            if item 3 of a is not "" then
                set matches to (folders whose name is (item 3 of a))
                if (count matches) is 0 then error "No folder is named " & (item 3 of a) & ". List folders first."
                set destination to item 1 of matches
            end if
            set n to make new note at destination with properties {name:item 1 of a, body:item 2 of a}
            return {{id of n, "Note created in " & (name of destination)}}
        end tell
        """#
        case "music.playlists": body = #"""
        tell application id "com.apple.Music"
            set output to {}
            repeat with p in user playlists
                set end of output to {name of p, (count tracks of p) as text}
            end repeat
            return output
        end tell
        """#
        case "music.play": body = #"""
        tell application id "com.apple.Music"
            set q to item 1 of a
            set kind to item 2 of a
            if kind is "playlist" then
                set matches to (user playlists whose name is q)
                if (count matches) is 0 then set matches to (user playlists whose name contains q)
                if (count matches) is 0 then error "No playlist matches " & q & "."
                play item 1 of matches
                return {{name of item 1 of matches, "Playing playlist"}}
            end if
            if kind is "album" then
                set matches to (tracks of library playlist 1 whose album contains q)
            else if kind is "artist" then
                set matches to (tracks of library playlist 1 whose artist contains q)
            else
                set matches to (tracks of library playlist 1 whose name contains q)
            end if
            if (count matches) is 0 then error "Nothing in your library matches " & q & "."
            play item 1 of matches
            return {{(name of item 1 of matches) & " - " & (artist of item 1 of matches), "Playing"}}
        end tell
        """#
        case "spotify.play": body = #"""
        tell application id "com.spotify.client"
            play track (item 1 of a)
            return {{item 1 of a, "Playing"}}
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
            else
            """# + "\n" + (name.hasPrefix("music.") ? #"""
                if commandName is "shuffle_on" then set shuffle enabled to true
                if commandName is "shuffle_off" then set shuffle enabled to false
                if commandName is "repeat_all" then set song repeat to all
                if commandName is "repeat_one" then set song repeat to one
                if commandName is "repeat_off" then set song repeat to off
            """# : #"""
                if commandName is "shuffle_on" then set shuffling to true
                if commandName is "shuffle_off" then set shuffling to false
                if commandName is "repeat_all" or commandName is "repeat_one" then set repeating to true
                if commandName is "repeat_off" then set repeating to false
            """#) + "\n" + #"""
            end if
            return {{"", "Playback command completed"}}
            end tell
            """#
        }
        let helpers = name.hasPrefix("mail.") ? "\n" + mailHelpers : ""
        return "on speekrun(a)\nwith timeout of 30 seconds\n" + body + "\nend timeout\nend speekrun" + helpers
    }

    /// Search returns "account|mailbox|id"; older Inbox-only ids are plain numbers.
    static let mailHelpers = #"""
    on findMessage(messageRef)
        set AppleScript's text item delimiters to "|"
        set parts to text items of messageRef
        set AppleScript's text item delimiters to ""
        tell application id "com.apple.mail"
            if (count parts) is 3 then
                set mb to mailbox (item 2 of parts) of account (item 1 of parts)
                set matches to (messages of mb whose id is (item 3 of parts as integer))
            else
                set matches to (messages of inbox whose id is (messageRef as integer))
            end if
            if (count matches) is 0 then error "That message was not found. Search again."
            return item 1 of matches
        end tell
    end findMessage
    """#
}
