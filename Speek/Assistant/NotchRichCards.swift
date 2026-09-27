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
    @State private var guests: [String] = []
    @State private var recipients: [String] = []
    @State private var newAddress = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var hasTimes = false
    @State private var editingTime = false
    @State private var artwork: URL?
    @State private var trackTitle: String?
    @State private var trackArtist: String?

    private static let radius: CGFloat = 20
    private static let inset: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .background(Color(white: 0.115), in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        // A soft accent halo, like a focused window.
        .background(RoundedRectangle(cornerRadius: Self.radius + 4, style: .continuous).fill(Color.accentColor.opacity(0.5)).padding(-4).blur(radius: 8))
        .onAppear(perform: load)
        .onExitCommand { controller.cancelProposal() }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 10) {
            icon.frame(width: 20, height: 20)
            Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                Button("Cancel") { controller.cancelProposal() }
                Divider()
                Button("Always allow " + (ActionRuntime.shared.tools.first { $0.id == call.tool }?.title ?? "this")) {
                    commit(); ToolPolicyStore.shared.set(.allow, for: call.tool); controller.runProposal()
                }
                Button("Open in Speek") { controller.reviewInMainWindow() }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: 26, height: 22).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More, or Escape to cancel")
        }
        .padding(.horizontal, Self.inset).frame(height: 46)
        // Square at the bottom, where it meets the fields; only the card's top corners are rounded.
        .background(Color.white.opacity(0.055), in: UnevenRoundedRectangle(topLeadingRadius: Self.radius, bottomLeadingRadius: 0,
                                                                           bottomTrailingRadius: 0, topTrailingRadius: Self.radius, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch card {
        case .message(let message):
            VStack(alignment: .leading, spacing: 0) {
                if message.to != nil {
                    line { addressRow("To", addresses: $recipients) }
                }
                if message.subject != nil {
                    line { TextField("Subject", text: binding("subject")).textFieldStyle(.plain).font(.system(size: 14)) }
                }
                ZStack(alignment: .bottomTrailing) {
                    TextEditor(text: binding("body")).font(.system(size: 14)).lineSpacing(3).scrollContentBackground(.hidden)
                        .padding(.horizontal, Self.inset - 5).padding(.top, 12).padding(.bottom, 56)
                        .frame(height: 170)
                    primaryButton.padding(Self.inset - 4)
                }
            }
        case .event(let event):
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title", text: binding("title")).textFieldStyle(.plain).font(.system(size: 18, weight: .semibold))
                    Rectangle().fill(Color.accentColor).frame(height: 2)
                }
                row("clock") {
                    Button { editingTime.toggle() } label: {
                        Text(hasTimes ? timeText(hasEnd: event.end != nil) : RichCard.describe(start: event.start, end: event.end))
                            .font(.system(size: 14)).foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain).disabled(!hasTimes).help("Change the time")
                    .popover(isPresented: $editingTime, arrowEdge: .bottom) { timeEditor(hasEnd: event.end != nil) }
                }
                if event.attendees != nil { row("person") { chips($guests, placeholder: "Add guest") } }
                if event.location != nil {
                    row("mappin.and.ellipse") { TextField("Location", text: binding("location")).textFieldStyle(.plain).font(.system(size: 14)) }
                }
                HStack(spacing: 8) {
                    Image(systemName: source.contains("Google") ? "video" : "calendar").font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 18)
                    Text(source.contains("Google") ? "Google Calendar" : "Calendar").font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    primaryButton
                }
            }
            .padding(.horizontal, Self.inset).padding(.top, 16).padding(.bottom, 16)
        case .file(let change):
            VStack(alignment: .leading, spacing: 14) {
                row(fileSymbol(change.action)) {
                    Text(change.path).font(.system(size: 13, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                if change.destination != nil {
                    row("arrow.turn.down.right") {
                        TextField("Destination", text: binding("destination")).textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                    }
                }
                if change.text != nil {
                    TextEditor(text: binding("text")).font(.system(size: 12, design: .monospaced)).scrollContentBackground(.hidden)
                        .padding(8).frame(height: 88)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                HStack(spacing: 8) {
                    Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 18)
                    Text("Working folder").font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    primaryButton
                }
            }
            .padding(.horizontal, Self.inset).padding(.vertical, 16)
        case .music(let music):
            HStack(spacing: 14) {
                AsyncImage(url: artwork) { image in image.resizable().scaledToFill() } placeholder: {
                    Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.secondary)
                }
                .frame(width: 58, height: 58).background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(trackTitle ?? music.query ?? "Music").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(trackArtist ?? (call.tool.hasPrefix("spotify") ? "Spotify" : "Apple Music"))
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                primaryButton
            }
            .padding(.horizontal, Self.inset).padding(.vertical, 16)
        }
    }

    private var primaryButton: some View {
        Button { commit(); controller.runProposal() } label: {
            Text(primary).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 22).frame(height: 34)
                .background(Color.accentColor, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).keyboardShortcut(.defaultAction).disabled(controller.busy)
    }

    /// A full-width row with a hairline below it, as in a compose window.
    private func line<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content().padding(.horizontal, Self.inset).frame(minHeight: 46)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private func addressRow(_ label: String, addresses: Binding<[String]>) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 14)).foregroundStyle(.secondary)
            chips(addresses, placeholder: addresses.wrappedValue.isEmpty ? "Add recipient" : "")
        }
    }

    /// Addresses as removable pills, with a field to add more (Return or comma adds).
    private func chips(_ items: Binding<[String]>, placeholder: String) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(items.wrappedValue.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 4) {
                    Text(item).font(.system(size: 13)).lineLimit(1)
                    Button { items.wrappedValue.remove(at: index) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).help("Remove")
                }
                .padding(.leading, 10).padding(.trailing, 8).frame(height: 26)
                .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
            TextField(placeholder, text: $newAddress).textFieldStyle(.plain).font(.system(size: 13)).frame(minWidth: 60)
                .onSubmit { addAddress(to: items) }
                .onChange(of: newAddress) { _, value in if value.hasSuffix(",") { addAddress(to: items) } }
        }
    }

    private func addAddress(to items: Binding<[String]>) {
        let value = newAddress.trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
        if !value.isEmpty { items.wrappedValue.append(value) }
        newAddress = ""
    }

    /// "Today, 6:00 - 7:00 PM"
    private func timeText(hasEnd: Bool) -> String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(start) ? "Today" : calendar.isDateInTomorrow(start) ? "Tomorrow"
            : start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let from = start.formatted(date: .omitted, time: .shortened)
        guard hasEnd else { return day + ", " + from }
        return day + ", " + from + " - " + end.formatted(date: .omitted, time: .shortened)
    }

    private func timeEditor(hasEnd: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Starts", selection: $start)
            if hasEnd { DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute) }
        }
        .padding(14).frame(width: 280)
        .onChange(of: start) { old, new in end = end.addingTimeInterval(new.timeIntervalSince(old)) }
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

    private func row<Content: View>(_ symbol: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 18)
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
            fields = ["cc": message.cc ?? "", "subject": message.subject ?? "", "body": message.body]
            recipients = Self.split(message.to ?? "")
        case .event(let event):
            fields = ["title": event.title, "location": event.location ?? ""]
            guests = Self.split(event.attendees ?? "")
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
                trackArtist = (json["author_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                artwork = (json["thumbnail_url"] as? String).flatMap(URL.init(string:))
            }
        }
    }

    /// Writes edited fields back into the proposal before it runs.
    private func commit() {
        var args = call.arguments
        switch card {
        case .message:
            args = RichCard.updated(args, key: RichCard.key(["to", "recipient", "recipients", "email", "address"], in: args), value: (recipients + [newAddress]).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: ", "))
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
            if let key = RichCard.key(["attendees", "guests", "invitees"], in: args) {
                args = RichCard.updated(args, key: key, value: (guests + [newAddress]).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: ", "))
            }
            if args["location"] != nil { args = RichCard.updated(args, key: "location", value: fields["location"] ?? "") }
        case .file:
            if args["destination"] != nil { args = RichCard.updated(args, key: "destination", value: fields["destination"] ?? "") }
            if args["text"] != nil { args = RichCard.updated(args, key: "text", value: fields["text"] ?? "") }
        case .music:
            break
        }
        controller.updateReviewedArguments(args)
    }

    private static func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
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
        case .message(let message): return 46 + 170 + (message.to == nil ? 0 : 47) + (message.subject == nil ? 0 : 47) + 8
        case .event(let event): return 46 + 32 + 44 + 30 + 34 + (event.attendees == nil ? 0 : 42) + (event.location == nil ? 0 : 36) + 16
        case .file(let change): return 46 + 32 + 24 + 34 + 14 + (change.destination == nil ? 0 : 38) + (change.text == nil ? 0 : 102) + 8
        case .music: return 46 + 32 + 58 + 8
        }
    }

}
