import AVFoundation
import Combine

@MainActor
final class SpeechPlaybackService: ObservableObject {
    @Published private(set) var playingMessageID: UUID?
    private var player: AVAudioPlayer?
    @Published private(set) var errorMessage: String?

    func toggle(_ message: ActionMessage) async {
        if playingMessageID == message.id {
            stop()
            return
        }
        stop()
        errorMessage = nil
        playingMessageID = message.id
        do {
            let audio = try await CloudActionClient.speak(message.text)
            guard playingMessageID == message.id else { return }
            player = try AVAudioPlayer(data: audio)
            player?.enableRate = true
            let savedRate = UserDefaults.standard.double(forKey: "speek.voice.playbackRate")
            player?.rate = Float(savedRate == 0 ? 1 : min(2, max(0.5, savedRate)))
            guard player?.play() == true else { throw ActionClientError.invalidResponse }
            observeCompletion(of: message.id)
        } catch {
            guard playingMessageID == message.id else { return }
            errorMessage = error.localizedDescription
            stop()
        }
    }

    private func observeCompletion(of id: UUID) {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            while playingMessageID == id && player?.isPlaying == true {
                try? await Task.sleep(for: .milliseconds(300))
            }
            if playingMessageID == id { stop() }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingMessageID = nil
    }
}
