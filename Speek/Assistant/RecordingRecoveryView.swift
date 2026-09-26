import SwiftUI
import AppKit

struct RecordingRecoveryView: View {
    @ObservedObject private var recovery = RecordingRecovery.shared
    @State private var retryID: UUID?
    @State private var resultID: UUID?
    @State private var transcript = ""
    @State private var requestError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Waiting for recovery").font(.system(size: 13, weight: .semibold))
                Text("Failed recordings kept on this Mac. Retry to transcribe, then copy the text.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let error = requestError ?? recovery.error { Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if !transcript.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recovered dictation").font(.system(size: 13, weight: .medium))
                    ScrollView { Text(transcript).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 160)
                    HStack {
                        Spacer(minLength: 0)
                        Button("Copy dictation") {
                            NSPasteboard.general.clearContents()
                            if NSPasteboard.general.setString(transcript, forType: .string) {
                                if let resultID { recovery.complete(resultID) }
                                transcript = ""; resultID = nil
                            } else { requestError = "The transcript could not be copied. Select it and copy manually." }
                        }.buttonStyle(SpeekActionButtonStyle())
                    }
                }.padding(12).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            ForEach(recovery.recordings.sorted { $0.createdAt > $1.createdAt }) { item in
                Divider()
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.appName.isEmpty ? "Recording" : item.appName).font(.system(size: 13, weight: .medium))
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if retryID == item.id { ProgressView().controlSize(.small) }
                    Button("Retry") { requestError = nil; retryID = item.id }.buttonStyle(SpeekActionButtonStyle()).disabled(retryID != nil)
                    Button { recovery.complete(item.id) } label: { Image(systemName: "trash").frame(width: 32, height: 32) }
                        .buttonStyle(.plain).help("Delete recording").accessibilityLabel("Delete recording").disabled(retryID == item.id)
                }
            }
        }.padding(16).settingsSurface()
        .task(id: retryID) {
            guard let id = retryID else { return }
            guard let url = recovery.audioURL(for: id) else { requestError = "This recording has expired or is no longer available."; retryID = nil; return }
            do {
                let text = try await CloudActionClient.transcribe(url)
                try Task.checkCancellation()
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ActionClientError.invalidResponse }
                transcript = text; resultID = id
            } catch is CancellationError { }
            catch { requestError = error.localizedDescription }
            if !Task.isCancelled { retryID = nil }
        }
    }
}
