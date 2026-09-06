import Foundation

/// Speek always pastes using simulated Cmd+V key events (see CursorPaster).
/// The old AppleScript paste method and its Settings picker were removed; this is
/// kept as a tiny single-case type only because SystemInfoService's diagnostic
/// dump still reports the paste method by name.
enum PasteMethod {
    static var displayName: String { String(localized: "Default") }
}
