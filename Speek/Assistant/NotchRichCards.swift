import SwiftUI
import AppKit

/// Approval cards shaped like the thing being made: an email to send, an event to save, a file
/// change, music to play. Fields are edited in place and the main button does the action.
/// Anything without a card falls back to the plain approval card.
enum RichCard {
    struct Message { let to: String?; let cc: String?; let subject: String?; let body: String; let sends: Bool }
    struct Event { let title: String; let start: String; let end: String?; let attendees: String?; let location: String?; let updates: Bool }
    struct FileChange { let action: String; let path: String; let destination: String?; let text: String? }
    struct Music { let uri: String?; let query: String?; let queues: Bool }

    case message(Message)
    case event(Event)
    case file(FileChange)
    case music(Music)

    // MARK: Detection

    private static let toKeys = ["to", "recipient", "recipients", "email", "address"]
    private static let bodyKeys = ["body", "text", "message", "content"]
    private static let titleKeys = ["title", "summary", "name"]
    private static let startKeys = ["start", "startTime", "start_time", "startDateTime", "start_datetime"]
    private static let endKeys = ["end", "endTime", "end_time", "endDateTime", "end_datetime"]
    private static let attendeeKeys = ["attendees", "guests", "invitees"]

    static func key(_ candidates: [String], in arguments: [String: MCPValue]) -> String? { candidates.first { arguments[$0] != nil } }

    static func detect(_ call: RuntimeCall) -> RichCard? {
        let args = call.arguments
        let name = call.tool.split(separator: ":").last.map(String.init)?.lowercased() ?? call.tool
        switch call.tool {
        case "spotify.play", "spotify.queue":
            return .music(Music(uri: args["uri"]?.string, query: nil, queues: call.tool == "spotify.queue"))
        case "music.play":
            return .music(Music(uri: nil, query: [args["query"]?.string, args["kind"]?.string].compactMap { $0 }.joined(separator: ", "), queues: false))
        default: break
        }
        if call.tool.hasPrefix("files."), let path = args["path"]?.string {
            let action = String(call.tool.dropFirst("files.".count))
            guard ["write", "append", "move", "copy", "trash", "create_folder"].contains(action) else { return nil }
            return .file(FileChange(action: action, path: path, destination: args["destination"]?.string, text: args["text"]?.string))
        }
        // Events: a title and a start time, from Calendar or a calendar plugin.
        if let startKey = key(startKeys, in: args), let titleKey = key(titleKeys, in: args),
           ["create", "insert", "add", "update", "schedule", "event"].contains(where: name.contains) {
            return .event(Event(title: text(args[titleKey]), start: time(args[startKey]), end: key(endKeys, in: args).map { time(args[$0]) },
                                attendees: key(attendeeKeys, in: args).map { list(args[$0]) }, location: args["location"]?.string,
                                updates: name.contains("update")))
        }
        // Messages: a body, and a recipient unless it replies in a thread.
        if let bodyKey = key(bodyKeys, in: args), ["send", "draft", "reply", "compose", "message"].contains(where: name.contains) {
            let to = key(toKeys, in: args).map { list(args[$0]) }
            guard to != nil || name.contains("reply") || args["reply_to_id"] != nil else { return nil }
            return .message(Message(to: to, cc: args["cc"].map { list($0) }, subject: args["subject"]?.string,
                                    body: text(args[bodyKey]), sends: name.contains("send")))
        }
        return nil
    }

    static func text(_ value: MCPValue?) -> String {
        switch value {
        case .string(let text)?: return text
        case let other?: return other.jsonString
        case nil: return ""
        }
    }
    /// Comma-separated addresses from a string or a list (of strings or {email: ...}).
    static func list(_ value: MCPValue?) -> String {
        if let items = value?.array {
            return items.compactMap { $0.string ?? $0["email"]?.string }.joined(separator: ", ")
        }
        return value?.string ?? ""
    }
    /// A time from an ISO string or a {dateTime: ...} / {date: ...} object.
    static func time(_ value: MCPValue?) -> String { value?.string ?? value?["dateTime"]?.string ?? value?["date"]?.string ?? "" }

    static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds], [.withFullDate]] {
            formatter.formatOptions = options
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// "Thursday 2:00 - 2:30 PM", or the raw text when it is not a date.
    static func describe(start: String, end: String?) -> String {
        guard let from = date(from: start) else { return start }
        let day = Calendar.current.isDateInToday(from) ? "Today" : Calendar.current.isDateInTomorrow(from) ? "Tomorrow"
            : from.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let clock = from.formatted(date: .omitted, time: .shortened)
        guard let end, let to = date(from: end) else { return day + " " + clock }
        return day + " " + clock + " - " + to.formatted(date: .omitted, time: .shortened)
    }

    /// The arguments with edited values written back under their original keys and shapes.
    static func updated(_ arguments: [String: MCPValue], key: String?, value: String) -> [String: MCPValue] {
        guard let key else { return arguments }
        var result = arguments
        switch arguments[key] {
        case .array(let items)?:
            let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let objects = items.first?.object != nil
            result[key] = .array(parts.map { objects ? .object(["email": .string($0)]) : .string($0) })
        case .object(var object)?:
            if object["dateTime"] != nil { object["dateTime"] = .string(value) } else { object["date"] = .string(value) }
            result[key] = .object(object)
        default:
            result[key] = .string(value)
        }
        return result
    }
}

/// The card itself: app header, editable fields, and one main action.
struct RichApprovalCard: View {
    let card: RichCard
    let call: RuntimeCall
    let source: String
    @ObservedObject var controller: AssistantController
    @State private var fields: [String: String] = [:]
    @State private var start = Date()
    @State private var end = Date()
    @State private var hasTimes = false
    @State private var artwork: URL?
    @State private var trackTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)
            content.padding(.horizontal, 14).padding(.vertical, 10)
            footer.padding(.horizontal, 14).padding(.bottom, 12)
        }
        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1))
        .shadow(color: Color.accentColor.opacity(0.35), radius: 10)
        .onAppear(perform: load)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 8) {
            icon.frame(width: 18, height: 18)
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                Button("Always allow " + (ActionRuntime.shared.tools.first { $0.id == call.tool }?.title ?? "this")) {
                    commit(); ToolPolicyStore.shared.set(.allow, for: call.tool); controller.runProposal()
                }
                Button("Open in Speek") { controller.reviewInMainWindow() }
            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 20).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        // Square at the bottom, where it meets the fields; only the card's top corners are rounded.
        .background(Color.white.opacity(0.06), in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0,
                                                                          bottomTrailingRadius: 0, topTrailingRadius: 16, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch card {
        case .message(let message):
            VStack(alignment: .leading, spacing: 8) {
                if message.to != nil { field("To", key: "to") }
                if message.cc != nil, !(fields["cc"] ?? "").isEmpty { field("Cc", key: "cc") }
                if message.subject != nil {
                    TextField("Subject", text: binding("subject")).textFieldStyle(.plain).font(.system(size: 13, weight: .medium))
                    Divider().opacity(0.3)
                }
                TextEditor(text: binding("body")).font(.system(size: 13)).scrollContentBackground(.hidden).frame(height: 84)
            }
        case .event(let event):
            VStack(alignment: .leading, spacing: 9) {
                TextField("Title", text: binding("title")).textFieldStyle(.plain).font(.system(size: 15, weight: .semibold))
                Rectangle().fill(Color.accentColor).frame(height: 2)
                row("clock") {
                    if hasTimes {
                        DatePicker("Start", selection: $start).labelsHidden().datePickerStyle(.field).controlSize(.small)
                        if event.end != nil {
                            Text("to").font(.system(size: 12)).foregroundStyle(.secondary)
                            DatePicker("End", selection: $end, displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.field).controlSize(.small)
                        }
                    } else { Text(RichCard.describe(start: event.start, end: event.end)).font(.system(size: 13)) }
                }
                if event.attendees != nil { row("person") { TextField("Guests", text: binding("attendees")).textFieldStyle(.plain).font(.system(size: 13)) } }
                if event.location != nil { row("mappin.and.ellipse") { TextField("Location", text: binding("location")).textFieldStyle(.plain).font(.system(size: 13)) } }
            }
        case .file(let change):
            VStack(alignment: .leading, spacing: 8) {
                row(fileSymbol(change.action)) { Text(change.path).font(.system(size: 13, design: .monospaced)).lineLimit(1).truncationMode(.middle) }
                if change.destination != nil {
                    row("arrow.turn.down.right") { TextField("Destination", text: binding("destination")).textFieldStyle(.plain).font(.system(size: 13, design: .monospaced)) }
                }
                if change.text != nil {
                    TextEditor(text: binding("text")).font(.system(size: 12, design: .monospaced)).scrollContentBackground(.hidden)
                        .frame(height: 70).padding(6).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        case .music(let music):
            HStack(spacing: 12) {
                AsyncImage(url: artwork) { image in image.resizable().scaledToFill() } placeholder: {
                    Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.secondary)
                }
                .frame(width: 48, height: 48).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(trackTitle ?? music.query ?? music.uri ?? "Music").font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    Text(music.queues ? "Add to the Spotify queue" : call.tool.hasPrefix("spotify") ? "Play in Spotify" : "Play in Music")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if case .event = card, source.contains("Google") {
                Label("Google Calendar", systemImage: "calendar").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Cancel") { controller.cancelProposal() }.buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(.secondary)
            Button { commit(); controller.runProposal() } label: {
                Text(primary).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 7)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain).keyboardShortcut(.defaultAction).disabled(controller.busy)
        }
    }

    // MARK: Helpers

    private var title: String {
        switch card {
        case .message(let message): return message.sends ? "New Message" : (message.to == nil ? "Reply" : "New Draft")
        case .event(let event): return event.updates ? "Change Event" : "New Event"
        case .file(let change):
            switch change.action {
            case "write": return "New File"
            case "append": return "Add to File"
            case "move": return "Move File"
            case "copy": return "Copy File"
            case "trash": return "Move to Trash"
            default: return "New Folder"
            }
        case .music(let music): return music.queues ? "Add to Queue" : "Play"
        }
    }

    private var primary: String {
        switch card {
        case .message(let message): return message.sends ? "Send" : "Save Draft"
        case .event: return "Save"
        case .file(let change): return change.action == "trash" ? "Move to Trash" : change.action == "move" ? "Move" : change.action == "copy" ? "Copy" : "Save"
        case .music(let music): return music.queues ? "Add" : "Play"
        }
    }

    @ViewBuilder private var icon: some View {
        if source.hasPrefix("Plugin: Gmail") { Image("mcp-gmail").resizable().renderingMode(.template).scaledToFit() }
        else if source.hasPrefix("Plugin: Google Calendar") { Image("mcp-googlecalendar").resizable().renderingMode(.template).scaledToFit() }
        else if let bundle = bundleID, let image = AppIcon.image(for: bundle) { Image(nsImage: image).resizable().scaledToFit() }
        else { Image(systemName: "sparkles").resizable().scaledToFit() }
    }

    private var bundleID: String? {
        switch card {
        case .message: return call.tool.hasPrefix("messages.") ? "com.apple.MobileSMS" : "com.apple.mail"
        case .event: return "com.apple.iCal"
        case .file: return "com.apple.finder"
        case .music: return call.tool.hasPrefix("spotify") ? "com.spotify.client" : "com.apple.Music"
        }
    }

    private func fileSymbol(_ action: String) -> String {
        ["trash": "trash", "create_folder": "folder.badge.plus", "move": "doc", "copy": "doc.on.doc"][action] ?? "doc.text"
    }

    private func field(_ label: String, key: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(label).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
                TextField(label, text: binding(key)).textFieldStyle(.plain).font(.system(size: 13))
            }
            Divider().opacity(0.3)
        }
    }

    private func row<Content: View>(_ symbol: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 18)
            content()
            Spacer(minLength: 0)
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { fields[key] ?? "" }, set: { fields[key] = $0 })
    }

    /// Fills the fields from the proposed arguments.
    private func load() {
        switch card {
        case .message(let message):
            fields = ["to": message.to ?? "", "cc": message.cc ?? "", "subject": message.subject ?? "", "body": message.body]
        case .event(let event):
            fields = ["title": event.title, "attendees": event.attendees ?? "", "location": event.location ?? ""]
            if let from = RichCard.date(from: event.start) {
                start = from; hasTimes = true
                end = event.end.flatMap(RichCard.date(from:)) ?? from.addingTimeInterval(1800)
            }
        case .file(let change):
            fields = ["destination": change.destination ?? "", "text": change.text ?? ""]
        case .music(let music):
            guard let uri = music.uri, let link = Self.openLink(uri),
                  let url = URL(string: "https://open.spotify.com/oembed?url=" + (link.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? link)) else { return }
            Task {
                // Title and cover art from Spotify's public embed endpoint (no sign-in).
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                trackTitle = json["title"] as? String
                artwork = (json["thumbnail_url"] as? String).flatMap(URL.init(string:))
            }
        }
    }

    /// Writes edited fields back into the proposal before it runs.
    private func commit() {
        var args = call.arguments
        switch card {
        case .message:
            args = RichCard.updated(args, key: RichCard.key(["to", "recipient", "recipients", "email", "address"], in: args), value: fields["to"] ?? "")
            if args["cc"] != nil { args = RichCard.updated(args, key: "cc", value: fields["cc"] ?? "") }
            if args["subject"] != nil { args = RichCard.updated(args, key: "subject", value: fields["subject"] ?? "") }
            args = RichCard.updated(args, key: RichCard.key(["body", "text", "message", "content"], in: args), value: fields["body"] ?? "")
        case .event:
            args = RichCard.updated(args, key: RichCard.key(["title", "summary", "name"], in: args), value: fields["title"] ?? "")
            if hasTimes {
                let formatter = ISO8601DateFormatter()
                formatter.timeZone = .current
                args = RichCard.updated(args, key: RichCard.key(["start", "startTime", "start_time", "startDateTime", "start_datetime"], in: args), value: formatter.string(from: start))
                if let endKey = RichCard.key(["end", "endTime", "end_time", "endDateTime", "end_datetime"], in: args) {
                    // The end picker edits the time; it stays on the start's day.
                    let day = Calendar.current.dateComponents([.year, .month, .day], from: start)
                    let clock = Calendar.current.dateComponents([.hour, .minute], from: end)
                    var parts = day; parts.hour = clock.hour; parts.minute = clock.minute
                    var finish = Calendar.current.date(from: parts) ?? end
                    if finish <= start { finish = start.addingTimeInterval(1800) }
                    args = RichCard.updated(args, key: endKey, value: formatter.string(from: finish))
                }
            }
            if let key = RichCard.key(["attendees", "guests", "invitees"], in: args) { args = RichCard.updated(args, key: key, value: fields["attendees"] ?? "") }
            if args["location"] != nil { args = RichCard.updated(args, key: "location", value: fields["location"] ?? "") }
        case .file:
            if args["destination"] != nil { args = RichCard.updated(args, key: "destination", value: fields["destination"] ?? "") }
            if args["text"] != nil { args = RichCard.updated(args, key: "text", value: fields["text"] ?? "") }
        case .music:
            break
        }
        controller.updateReviewedArguments(args)
    }

    private static func openLink(_ uri: String) -> String? {
        if uri.hasPrefix("https://open.spotify.com/") { return uri }
        let parts = uri.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify" else { return nil }
        return "https://open.spotify.com/\(parts[1])/\(parts[2])"
    }

    /// Height the notch reserves for each card.
    static func height(for card: RichCard) -> Int {
        switch card {
        case .message(let message): return 196 + (message.to == nil ? 0 : 34) + (message.subject == nil ? 0 : 30)
        case .event(let event): return 150 + (event.attendees == nil ? 0 : 28) + (event.location == nil ? 0 : 28)
        case .file(let change): return 120 + (change.destination == nil ? 0 : 28) + (change.text == nil ? 0 : 88)
        case .music: return 136
        }
    }
}
