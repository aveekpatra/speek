import SwiftUI
import AppKit

struct MenuBarView: View {
    var body: some View {
        Button("Speak") { AssistantController.shared.toggleVoice() }
        Button("Type a request") { AssistantController.shared.show(typing: true) }
        Button("Circle screen context") { AssistantController.shared.circleContext() }
        Divider()
        Button("Settings...") { AssistantSettingsWindow.shared.show() }
        Button("Quit Speek") { NSApp.terminate(nil) }
    }
}
