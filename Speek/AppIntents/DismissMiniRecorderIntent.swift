import AppIntents
import Foundation
import AppKit

struct DismissMiniRecorderIntent: AppIntent {
    static var title: LocalizedStringResource = "Dismiss Speek Recorder"
    static var description = IntentDescription("Dismiss the Speek recorder and cancel any active recording.")
    
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .dismissRecorderPanel, object: nil)
        
        let dialog: IntentDialog = "Speek recorder dismissed"
        return .result(dialog: dialog)
    }
}
