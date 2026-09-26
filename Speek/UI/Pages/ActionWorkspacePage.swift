import SwiftUI

// Compatibility for older navigation callers. The assistant is now a floating panel.
struct ActionWorkspacePage: View {
    var body: some View { AssistantSettingsView() }
}

@MainActor
enum ActionWorkspaceTrigger {
    static let notification = Notification.Name("speek.actions.toggleVoice")
    static var pending = false
    static func activate() { AssistantController.shared.toggleVoice() }
}
