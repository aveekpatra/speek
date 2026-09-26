import Foundation
import EventKit

struct OrganizerToolDefinition: Sendable {
    let name: String
    let description: String
    let inputSchemaJSON: String
    let requiresConfirmation: Bool
}

struct OrganizerToolResult: Codable, Sendable {
    let summary: String
    let items: [[String: String]]

    func json() throws -> String {
        String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
    }
}

enum OrganizerService: String, CaseIterable, Identifiable {
    case calendar, reminders
    var id: String { rawValue }
    var title: String { self == .calendar ? "Calendar" : "Reminders" }
    var entity: EKEntityType { self == .calendar ? .event : .reminder }
}

enum OrganizerError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

/// EventKit access is requested only by an explicit Connect action in settings.
/// Callers must show and approve the exact arguments before setting approved to true.
@MainActor
final class NativeOrganizerTools {
    static let shared = NativeOrganizerTools()
    private let store = EKEventStore()

    static let catalog: [OrganizerToolDefinition] = {
        let fields = #"""
        "calendarID":{"type":"string","description":"Calendar/list identifier returned by list tools; optional for creation to use default."},
        "id":{"type":"string","description":"Exact event/reminder identifier returned by search."},
        "occurrenceStart":{"type":"string","description":"Original occurrence start returned by search; required for recurring event updates and deletes."},
        "query":{"type":"string","description":"Case-insensitive title or notes search."},
        "title":{"type":"string"},"notes":{"type":"string"},"location":{"type":"string"},
        "start":{"type":"string","description":"ISO 8601 date-time with explicit UTC offset."},
        "end":{"type":"string","description":"ISO 8601 date-time with explicit UTC offset. Exclusive for all-day events."},
        "due":{"type":"string","description":"ISO 8601 reminder due date-time with explicit UTC offset."},
        "timeZone":{"type":"string","description":"IANA time zone identifier, for example Europe/Prague."},
        "allDay":{"type":"boolean"},"completed":{"type":"boolean"},
        "durationMinutes":{"type":"integer","minimum":1,"maximum":1440},
        "limit":{"type":"integer","minimum":1,"maximum":200}
        """#
        func tool(_ name: String, _ description: String, _ required: [String] = [], write: Bool = false) -> OrganizerToolDefinition {
            let requiredJSON = required.map { "\"\($0)\"" }.joined(separator: ",")
            return .init(name: name, description: description, inputSchemaJSON: "{\"type\":\"object\",\"properties\":{\(fields)},\"required\":[\(requiredJSON)],\"additionalProperties\":false}", requiresConfirmation: write)
        }
        return [
            tool("calendar.list", "List accessible calendars and whether they allow changes."),
            tool("calendar.search", "Find events in a time range up to 366 days; returns identifiers and dates.", ["start", "end"]),
            tool("calendar.availability", "Return free intervals within the requested time range. Non-cancelled busy and tentative events block time. This does not check other people's calendars.", ["start", "end"]),
            tool("calendar.create", "Create an event after approval. Does not invite attendees.", ["title", "start", "end"], write: true),
            tool("calendar.update", "Update only the specified event occurrence after approval. Supplied fields replace current values.", ["id"], write: true),
            tool("calendar.delete", "Delete only the specified event occurrence after approval.", ["id"], write: true),
            tool("reminders.lists", "List accessible reminder lists and whether they allow changes."),
            tool("reminders.search", "Search reminders; incomplete by default. Set completed=true to find completed reminders."),
            tool("reminders.create", "Create a reminder after approval. Due date is optional.", ["title"], write: true),
            tool("reminders.complete", "Mark a reminder complete after approval, or reopen it with completed=false.", ["id"], write: true),
            tool("reminders.delete", "Delete a reminder after approval.", ["id"], write: true)
        ]
    }()

    func authorizationStatus(for service: OrganizerService) -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: service.entity)
    }

    /// macOS access plus Speek's own switch. Turning the switch off keeps the macOS grant.
    func isConnected(_ service: OrganizerService) -> Bool {
        authorizationStatus(for: service) == .fullAccess && isEnabled(service)
    }

    func isEnabled(_ service: OrganizerService) -> Bool {
        UserDefaults.standard.object(forKey: "speek.organizer.\(service.rawValue).enabled") as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool, for service: OrganizerService) {
        UserDefaults.standard.set(enabled, forKey: "speek.organizer.\(service.rawValue).enabled")
    }

    func requestAccess(to service: OrganizerService) async throws {
        let granted: Bool
        if service == .calendar { granted = try await store.requestFullAccessToEvents() }
        else { granted = try await store.requestFullAccessToReminders() }
        guard granted else { throw OrganizerError.message("Allow \(service.title) access in System Settings > Privacy & Security to connect.") }
    }

    func execute(name: String, argumentsJSON: String, approved: Bool = false) async throws -> OrganizerToolResult {
        guard let definition = Self.catalog.first(where: { $0.name == name }) else { throw OrganizerError.message("Unknown organizer tool.") }
        guard !definition.requiresConfirmation || approved else { throw OrganizerError.message("Review and approve this change before running it.") }
        let service: OrganizerService = name.hasPrefix("calendar.") ? .calendar : .reminders
        guard isConnected(service) else { throw OrganizerError.message("Connect \(service.title) in Integrations before using this tool.") }
        let args = try JSONDecoder().decode(Arguments.self, from: Data(argumentsJSON.utf8))
        if let zone = args.timeZone, TimeZone(identifier: zone) == nil { throw OrganizerError.message("Use a valid IANA time zone.") }
        if name == "calendar.list" || name == "reminders.lists" {
            let values = store.calendars(for: service.entity).map { calendar in
                ["id": calendar.calendarIdentifier, "title": calendar.title, "source": calendar.source.title, "writable": String(calendar.allowsContentModifications)]
            }
            return .init(summary: "Found \(values.count) \(service == .calendar ? "calendars" : "reminder lists").", items: values)
        }
        if name == "calendar.search" || name == "calendar.availability" {
            let (start, end) = try range(args)
            let calendars = try selectedCalendars(args.calendarID, entity: .event)
            let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars))
                .filter { $0.status != .canceled }
                .sorted { $0.startDate < $1.startDate }
            if name == "calendar.availability" {
                let duration = args.durationMinutes ?? 30
                guard (1...1440).contains(duration) else { throw OrganizerError.message("Duration must be between 1 and 1440 minutes.") }
                var cursor = start
                var slots: [[String: String]] = []
                for event in events where event.availability != .free {
                    let busyStart = max(start, event.startDate)
                    let busyEnd = min(end, event.endDate)
                    if busyStart.timeIntervalSince(cursor) >= Double(duration * 60) { slots.append(["start": iso(cursor), "end": iso(busyStart)]) }
                    cursor = max(cursor, busyEnd)
                }
                if end.timeIntervalSince(cursor) >= Double(duration * 60) { slots.append(["start": iso(cursor), "end": iso(end)]) }
                return .init(summary: "Found \(slots.count) free intervals in your selected calendars.", items: Array(slots.prefix(args.boundedLimit)))
            }
            let matches = events.filter { matchesQuery(args.query, title: $0.title, notes: $0.notes) }
            return .init(summary: "Found \(matches.count) events; showing up to \(args.boundedLimit).", items: matches.prefix(args.boundedLimit).map(eventItem))
        }
        if name.hasPrefix("calendar.") {
            let event: EKEvent
            if name == "calendar.create" {
                event = EKEvent(eventStore: store)
                event.calendar = try writableCalendar(args.calendarID, entity: .event)
            } else {
                guard let id = args.id, let found = store.event(withIdentifier: id) else { throw OrganizerError.message("This event no longer exists. Search again before changing it.") }
                if found.hasRecurrenceRules {
                    guard let originalStart = args.occurrenceStart else { throw OrganizerError.message("Provide the original occurrence start to change a recurring event.") }
                    let occurrenceStart = try date(originalStart)
                    let predicate = store.predicateForEvents(withStart: occurrenceStart.addingTimeInterval(-1), end: occurrenceStart.addingTimeInterval(1), calendars: [found.calendar])
                    guard let occurrence = store.events(matching: predicate).first(where: { $0.calendarItemIdentifier == found.calendarItemIdentifier && abs($0.startDate.timeIntervalSince(occurrenceStart)) < 1 }) else { throw OrganizerError.message("This occurrence changed. Search again before updating it.") }
                    event = occurrence
                } else { event = found }
                guard event.calendar.allowsContentModifications else { throw OrganizerError.message("This calendar is read-only.") }
                if let calendarID = args.calendarID { event.calendar = try writableCalendar(calendarID, entity: .event) }
            }
            if name == "calendar.delete" {
                let item = eventItem(event)
                try store.remove(event, span: .thisEvent, commit: true)
                return .init(summary: "Deleted this event occurrence.", items: [item])
            }
            if let title = args.title { event.title = try validTitle(title) }
            if let value = args.start { event.startDate = try date(value) }
            if let value = args.end { event.endDate = try date(value) }
            if let value = args.notes { event.notes = value }
            if let value = args.location { event.location = value }
            if let value = args.allDay { event.isAllDay = value }
            if let value = args.timeZone { event.timeZone = TimeZone(identifier: value) }
            guard !(event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let start = event.startDate, let end = event.endDate, end > start else { throw OrganizerError.message("An event needs a title and an end after its start.") }
            if name == "calendar.create" && (args.start == nil || args.end == nil) { throw OrganizerError.message("Provide both start and end dates.") }
            try store.save(event, span: .thisEvent, commit: true)
            return .init(summary: name == "calendar.create" ? "Created event." : "Updated this event occurrence.", items: [eventItem(event)])
        }
        if name == "reminders.search" {
            let calendars = try selectedCalendars(args.calendarID, entity: .reminder)
            let predicate = store.predicateForReminders(in: calendars)
            let reminders: [[String: String]] = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { values in
                    let snapshots = (values ?? []).map(Self.snapshotReminder)
                    continuation.resume(returning: snapshots)
                }
            }
            try Task.checkCancellation()
            let matches = reminders.filter { $0["completed"] == String(args.completed ?? false) && matchesQuery(args.query, title: $0["title"], notes: $0["notes"]) }
                .sorted { ($0["title"] ?? "").localizedStandardCompare($1["title"] ?? "") == .orderedAscending }
            return .init(summary: "Found \(matches.count) reminders; showing up to \(args.boundedLimit).", items: Array(matches.prefix(args.boundedLimit)))
        }
        let reminder: EKReminder
        if name == "reminders.create" {
            reminder = EKReminder(eventStore: store)
            reminder.calendar = try writableCalendar(args.calendarID, entity: .reminder)
            reminder.title = try validTitle(args.title ?? "")
            reminder.notes = args.notes
            if let due = args.due {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = args.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: try date(due))
                components.timeZone = calendar.timeZone
                if args.allDay == true { components.hour = nil; components.minute = nil; components.second = nil }
                reminder.dueDateComponents = components
            }
        } else {
            guard let id = args.id, let found = store.calendarItem(withIdentifier: id) as? EKReminder else { throw OrganizerError.message("This reminder no longer exists. Search again before changing it.") }
            reminder = found
            guard reminder.calendar.allowsContentModifications else { throw OrganizerError.message("This reminder list is read-only.") }
        }
        if name == "reminders.delete" {
            let item = reminderItem(reminder)
            try store.remove(reminder, commit: true)
            return .init(summary: "Deleted reminder.", items: [item])
        }
        if name == "reminders.complete" { reminder.isCompleted = args.completed ?? true }
        try store.save(reminder, commit: true)
        return .init(summary: name == "reminders.create" ? "Created reminder." : (reminder.isCompleted ? "Completed reminder." : "Reopened reminder."), items: [reminderItem(reminder)])
    }

    private struct Arguments: Decodable {
        var calendarID: String?; var id: String?; var query: String?; var title: String?
        var occurrenceStart: String?
        var notes: String?; var location: String?; var start: String?; var end: String?
        var due: String?; var timeZone: String?; var allDay: Bool?; var completed: Bool?
        var durationMinutes: Int?; var limit: Int?
        var boundedLimit: Int { min(200, max(1, limit ?? 50)) }
    }

    private func range(_ args: Arguments) throws -> (Date, Date) {
        guard let start = args.start, let end = args.end else { throw OrganizerError.message("Provide a start and end with explicit time zone offsets.") }
        let lower = try date(start), upper = try date(end)
        guard upper > lower, upper.timeIntervalSince(lower) <= 366 * 86400 else { throw OrganizerError.message("Choose a time range between one second and 366 days.") }
        return (lower, upper)
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        if let result = formatter.date(from: value) { return result }
        formatter.formatOptions.insert(.withFractionalSeconds)
        if let result = formatter.date(from: value) { return result }
        throw OrganizerError.message("Dates must use ISO 8601 with a time zone offset.")
    }
    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private func validTitle(_ value: String) throws -> String {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw OrganizerError.message("Enter a title.") }
        return title
    }
    private func selectedCalendars(_ id: String?, entity: EKEntityType) throws -> [EKCalendar]? {
        guard let id else { return nil }
        guard let calendar = store.calendars(for: entity).first(where: { $0.calendarIdentifier == id }) else { throw OrganizerError.message("This calendar or list is unavailable. Refresh the list and try again.") }
        return [calendar]
    }
    private func writableCalendar(_ id: String?, entity: EKEntityType) throws -> EKCalendar {
        let selected = try selectedCalendars(id, entity: entity)?.first
        guard let calendar = selected ?? (entity == .event ? store.defaultCalendarForNewEvents : store.defaultCalendarForNewReminders()), calendar.allowsContentModifications else { throw OrganizerError.message("Choose a writable calendar or reminder list.") }
        return calendar
    }
    private func matchesQuery(_ query: String?, title: String?, notes: String?) -> Bool {
        guard let query, !query.isEmpty else { return true }
        return ((title ?? "") + " " + (notes ?? "")).localizedCaseInsensitiveContains(query)
    }
    private func eventItem(_ event: EKEvent) -> [String: String] {
        ["id": event.eventIdentifier ?? "", "title": event.title ?? "", "start": iso(event.startDate), "end": iso(event.endDate), "timeZone": event.timeZone?.identifier ?? TimeZone.current.identifier, "allDay": String(event.isAllDay), "calendarID": event.calendar.calendarIdentifier, "calendar": event.calendar.title, "location": event.location ?? "", "notes": event.notes ?? "", "recurring": String(event.hasRecurrenceRules)]
    }
    private func reminderItem(_ reminder: EKReminder) -> [String: String] { Self.snapshotReminder(reminder) }
    nonisolated private static func snapshotReminder(_ reminder: EKReminder) -> [String: String] {
        var item = ["id": reminder.calendarItemIdentifier, "title": reminder.title ?? "", "completed": String(reminder.isCompleted), "calendarID": reminder.calendar.calendarIdentifier, "calendar": reminder.calendar.title, "notes": reminder.notes ?? ""]
        if let due = reminder.dueDateComponents {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = due.timeZone ?? .current
            if let date = calendar.date(from: due) { item["due"] = ISO8601DateFormatter().string(from: date) }
            item["allDay"] = String(due.hour == nil)
            item["timeZone"] = calendar.timeZone.identifier
        }
        return item
    }
}
