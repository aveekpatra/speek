import SwiftUI
import AVFoundation

/// The guided permissions panel: two rows, one button each, live status. Closes on
/// its own once both are granted.
struct PermissionsGuideView: View {
    @ObservedObject var center: PermissionsCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Speek needs two permissions")
                    .font(.system(size: 18, weight: .bold))
                Text(center.allGranted
                     ? "All set. This window closes by itself."
                     : "Each button opens exactly what macOS needs. This window updates as you go.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            SpeekGroup {
                PermissionRow(
                    title: "Microphone",
                    detail: microphoneDetail,
                    granted: center.microphoneGranted,
                    buttonTitle: center.microphoneStatus == .notDetermined ? "Allow" : "Open Settings",
                    action: center.allowMicrophone
                )
                PermissionRow(
                    title: "Accessibility",
                    detail: accessibilityDetail,
                    granted: center.accessibilityTrusted,
                    buttonTitle: center.isRepairingAccessibility ? "Repairing" : "Open Settings",
                    action: center.allowAccessibility
                )
            }
            if !center.accessibilityTrusted {
                Text("macOS does not let apps switch Accessibility on themselves. In the pane that opens, turn on the switch next to Speek. If the switch is already on, turn it off and on again.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .padding(.top, 12)
        .frame(width: 520)
        .onAppear { center.refresh() }
    }

    private var microphoneDetail: String {
        switch center.microphoneStatus {
        case .authorized: return "Records your voice for transcription."
        case .notDetermined: return "Records your voice for transcription. macOS asks once; click Allow."
        default: return "Access was turned off. Switch Speek on in Privacy & Security > Microphone."
        }
    }

    private var accessibilityDetail: String {
        center.accessibilityTrusted
            ? "Pastes text where your cursor is and runs the shortcut from any app."
            : "Pastes text where your cursor is and runs the shortcut from any app. Switch Speek on in Privacy & Security > Accessibility."
    }
}

/// One permission row shared by the guide and onboarding.
struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    var buttonTitle: String = "Allow"
    let action: () -> Void

    var body: some View {
        SpeekRow(LocalizedStringKey(title), subtitle: LocalizedStringKey(detail)) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13, weight: .medium))
            } else {
                Button(buttonTitle, action: action)
                    .buttonStyle(.glassProminent)
            }
        }
    }
}
