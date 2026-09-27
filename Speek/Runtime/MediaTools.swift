import AppKit

/// System-wide media control: the same keys as the keyboard's media row, so they reach whatever
/// is playing (Spotify, Music, a browser tab, a podcast app), plus the system output volume.
/// Reversible and low-risk, so they run without asking by default.
@MainActor
enum MediaTools {
    static let catalog: [RuntimeTool] = [
        RuntimeTool(id: "media.control", title: "Media control",
                    summary: "Play, pause, skip to the next track, or go back, in whatever app is playing media on this Mac (like pressing the keyboard's media keys). Use it for \"pause\", \"next song\", \"resume\" when no specific app is named or the app has no own tool.",
                    schema: ActionRuntime.schema(["command": ["type": "string", "enum": ["play_pause", "next", "previous"]]], required: ["command"]), requiresReview: false),
        RuntimeTool(id: "media.volume", title: "System volume",
                    summary: "Read or set the Mac's output volume: level 0 to 100, or mute and unmute. Without arguments it reports the current volume.",
                    schema: ActionRuntime.schema(["level": ["type": "integer", "minimum": 0, "maximum": 100], "muted": ["type": "boolean"]], required: []), requiresReview: false)
    ]

    static func execute(_ call: RuntimeCall) throws -> String {
        switch call.tool {
        case "media.control":
            let keys: [String: Int32] = ["play_pause": 16, "next": 17, "previous": 18]   // NX_KEYTYPE_PLAY, NEXT, PREVIOUS
            guard let command = call.arguments["command"]?.string, let key = keys[command] else {
                throw ActionClientError.requestFailed("Use play_pause, next, or previous.")
            }
            press(key)
            return command == "play_pause" ? "Toggled play and pause." : command == "next" ? "Skipped to the next track." : "Went back."
        case "media.volume":
            if case .number(let level)? = call.arguments["level"] {
                try script("set volume output volume \(Int(min(100, max(0, level))))")
            }
            if let muted = call.arguments["muted"]?.bool { try script("set volume output muted \(muted)") }
            let state = try script("set s to get volume settings\nreturn ((output volume of s) as text) & \",\" & ((output muted of s) as text)")
            let parts = state.split(separator: ",")
            return "Volume \(parts.first ?? "?")%" + (parts.last == "true" ? ", muted." : ".")
        default:
            throw ActionClientError.requestFailed("Unknown media tool.")
        }
    }

    /// A media key press and release, as the keyboard sends it.
    private static func press(_ key: Int32) {
        for down in [true, false] {
            let state: Int32 = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                           modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
                                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                           data1: Int((key << 16) | (state << 8)), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    @discardableResult
    private static func script(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
            throw ActionClientError.requestFailed("The volume could not be changed: " + ((error?[NSAppleScript.errorMessage] as? String) ?? "unknown error"))
        }
        return result.stringValue ?? ""
    }
}
