import Foundation
import Combine

/// Lets the recorder window tell the user when a voice model is still being loaded
/// (the first load of a CoreML model compiles it for the Neural Engine, which can take
/// minutes) instead of showing a silent "Transcribing...".
@MainActor
final class VoiceModelLoadState: ObservableObject {
    static let shared = VoiceModelLoadState()

    @Published private(set) var loadingModelName: String?
    @Published private(set) var warmModelNames: Set<String> = []

    var isLoading: Bool { loadingModelName != nil }

    private init() {}

    func beginLoading(_ name: String) {
        loadingModelName = name
    }

    func finishLoading(_ name: String, success: Bool) {
        if loadingModelName == name { loadingModelName = nil }
        if success { warmModelNames.insert(name) }
    }

    func isWarm(_ name: String) -> Bool {
        warmModelNames.contains(name)
    }
}
