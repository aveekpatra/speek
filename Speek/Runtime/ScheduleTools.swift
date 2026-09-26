import Foundation

@MainActor
enum ScheduleTools {
    static var catalog: [RuntimeTool] {
        [RuntimeTool(id: "schedules.list", title: "List schedules", summary: "List local schedules, including paused requests. Speek must be running for due checks.", schema: ActionRuntime.schema([:], required: []), requiresReview: false),
         RuntimeTool(id: "schedules.create", title: "Schedule a request", summary: "Save a one-time or recurring request. When due it waits for review in Activity; it never silently sends or changes anything.", schema: ActionRuntime.schema([
            "title": ["type": "string", "minLength": 1], "request": ["type": "string", "minLength": 1],
            "date": ["type": "string", "description": "First occurrence as ISO8601 with time zone offset."],
            "recurrence": ["type": "string", "enum": ["once", "daily", "weekly"]],
            "timeZone": ["type": "string", "description": "IANA time zone, for example Europe/Prague."]
         ], required: ["title", "request", "date", "recurrence", "timeZone"]), requiresReview: true),
         RuntimeTool(id: "schedules.pause", title: "Pause or resume schedule", summary: "Pause or resume a schedule using its exact ID from schedules.list.", schema: ActionRuntime.schema(["id": ["type": "string"], "paused": ["type": "boolean"]], required: ["id", "paused"]), requiresReview: true)]
    }
    static func execute(_ name: String, arguments: [String: Any]) throws -> String {
        let store = TaskScheduler.shared
        switch name {
        case "schedules.list": return String(decoding: try JSONEncoder().encode(store.schedules), as: UTF8.self)
        case "schedules.create":
            guard let title = arguments["title"] as? String, let request = arguments["request"] as? String,
                  let rawDate = arguments["date"] as? String, let date = ISO8601DateFormatter().date(from: rawDate),
                  let rawRecurrence = arguments["recurrence"] as? String, let recurrence = TaskSchedule.Recurrence(rawValue: rawRecurrence),
                  let timeZone = arguments["timeZone"] as? String else { throw ActionClientError.invalidResponse }
            try store.addSchedule(title: title, request: request, date: date, recurrence: recurrence, timeZone: timeZone)
            return "Scheduled \(title). Speek will surface it for review when due while the app is running."
        case "schedules.pause":
            guard let raw = arguments["id"] as? String, let id = UUID(uuidString: raw), store.schedules.contains(where: { $0.id == id }),
                  let paused = arguments["paused"] as? Bool else { throw ActionClientError.invalidResponse }
            store.setSchedulePaused(id, paused: paused)
            if let error = store.storageError { throw ActionClientError.requestFailed(error) }
            return paused ? "Schedule paused." : "Schedule resumed."
        default: throw ActionClientError.invalidResponse
        }
    }
}
