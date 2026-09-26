import SwiftUI

// Older callers land in the same settings surface; setup has no duplicate wizard.
struct SpeekOnboardingView: View {
    @Binding var hasCompleted: Bool
    var body: some View { AssistantSettingsView() }
}
