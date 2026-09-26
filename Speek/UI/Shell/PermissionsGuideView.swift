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
                AccessibilitySetupHelp()
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
                    .buttonBorderShape(.capsule)
            }
        }
    }
}


/// A real file URL drag source, shared by onboarding and the permissions panel.
struct AccessibilitySetupHelp: View {
    @State private var installFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !AccessibilityRepair.isInstalledInApplications {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Install Speek first").font(.headline)
                        Text("Keep Speek in Applications so macOS can find it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Move to Applications") {
                        installFailed = !AccessibilityRepair.moveToApplicationsAndRelaunch()
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                }
                if installFailed {
                    Text("Finder is open. Move this copy into Applications, then reopen it there.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Turn on Speek in the settings pane that opens.")
                    .font(.system(size: 13, weight: .medium))
            }
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                        .resizable().frame(width: 36, height: 36)
                    Text("Speek.app").font(.system(size: 13, weight: .medium))
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                .accessibilityLabel("Drag Speek into the permission list")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Missing from the list? Drag this app into it.")
                    Text("Or use + and choose Speek from Applications.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                Spacer(minLength: 0)
                Button("Show in Finder", action: AccessibilityRepair.revealInFinder)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            }
            Text("macOS may call this Accessibility or Device Control and Data Access. Only you can enable its switch.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
