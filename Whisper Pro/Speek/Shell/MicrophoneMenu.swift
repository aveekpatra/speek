import SwiftUI

/// Toolbar control showing the active input device, with a menu to switch it.
struct MicrophoneToolbarMenu: View {
    @ObservedObject private var audioDeviceManager = AudioDeviceManager.shared

    private var currentDeviceName: String {
        let id = audioDeviceManager.getCurrentDevice()
        let name = audioDeviceManager.getDeviceName(deviceID: id) ?? "No microphone"
        if audioDeviceManager.inputMode == .custom { return name }
        return "\(name) (Default)"
    }

    var body: some View {
        Menu {
            Button {
                audioDeviceManager.selectInputMode(.systemDefault)
            } label: {
                Label("System default", systemImage: audioDeviceManager.inputMode == .systemDefault ? "checkmark" : "")
            }
            Divider()
            ForEach(audioDeviceManager.availableDevices, id: \.id) { device in
                Button {
                    audioDeviceManager.selectDeviceAndSwitchToCustomMode(id: device.id)
                } label: {
                    let isActive = audioDeviceManager.inputMode == .custom && audioDeviceManager.getCurrentDevice() == device.id
                    Label(device.name, systemImage: isActive ? "checkmark" : "")
                }
            }
            if audioDeviceManager.availableDevices.isEmpty {
                Text("No input devices")
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentDeviceName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 13))
            }
        }
        .menuIndicator(.hidden)
        .help("Microphone")
        .task {
            audioDeviceManager.loadAvailableDevices()
        }
    }
}
