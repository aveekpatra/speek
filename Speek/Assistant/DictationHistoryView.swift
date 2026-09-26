import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DictationHistoryView: View {
    @ObservedObject private var history = DictationHistory.shared
    @ObservedObject private var memory = AssistantMemory.shared
    @ObservedObject private var recovery = RecordingRecovery.shared
    @State private var query = ""
    @State private var confirmingClear = false
    @State private var exportError: String?
    @State private var copiedID: UUID?
    private var filtered: [DictationHistoryEntry] {
        history.entries.filter { query.isEmpty || ($0.text + " " + $0.appName).localizedCaseInsensitiveContains(query) }.sorted { $0.date > $1.date }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { heading; Spacer(minLength: 12); actions }
                    VStack(alignment: .leading, spacing: 16) { heading; actions }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                    statistic("Dictations", value: "\(history.insights.sessions)")
                    statistic("Words", value: "\(history.insights.words)")
                    statistic("Recorded", value: minutes(history.insights.audioSeconds))
                    statistic("Estimated time saved", value: minutes(history.insights.estimatedSecondsSaved),
                              info: "Typing at 40 words per minute, minus recording time. Based on saved dictations only; excludes processing time.")
                }
                if !recovery.recordings.isEmpty { RecordingRecoveryView() }
                if !memory.saveHistory { HistoryPausedNotice() }
                if let error = exportError ?? history.error {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(.system(size: 12)).foregroundStyle(.red)
                }
                if filtered.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "waveform").font(.system(size: 22)).frame(width: 44, height: 44)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        Text(query.isEmpty ? "No saved dictations" : "No matching dictations").font(.system(size: 14, weight: .semibold))
                        Text(query.isEmpty ? "Successfully inserted dictations appear here when history is enabled." : "Try a different phrase or application name.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).settingsSurface()
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(filtered) { entry in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .center, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.appName.isEmpty ? "Dictation" : entry.appName).font(.system(size: 13, weight: .medium))
                                        Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        if NSPasteboard.general.setString(entry.text, forType: .string) { copiedID = entry.id }
                                    } label: { Image(systemName: copiedID == entry.id ? "checkmark.circle.fill" : "doc.on.doc").frame(width: 32, height: 32) }
                                    .buttonStyle(.plain).help("Copy dictation").accessibilityLabel(copiedID == entry.id ? "Copied" : "Copy dictation")
                                    Button { history.remove(entry.id) } label: { Image(systemName: "trash").frame(width: 32, height: 32) }
                                        .buttonStyle(.plain).help("Delete dictation").accessibilityLabel("Delete dictation")
                                }
                                Text(entry.text).font(.system(size: 13)).textSelection(.enabled).lineLimit(8).frame(maxWidth: .infinity, alignment: .leading)
                                if entry.text.count > 300 || entry.text.components(separatedBy: "\n").count > 6 {
                                    DisclosureGroup("Full dictation") { Text(entry.text).font(.system(size: 13)).textSelection(.enabled) }.font(.system(size: 11))
                                }
                                Text("\(entry.wordCount) words | " + minutes(entry.duration)).font(.system(size: 11)).foregroundStyle(.secondary)
                            }.padding(20).settingsSurface()
                        }
                    }
                }
            }.frame(maxWidth: 880, alignment: .leading).padding(.vertical, 12).padding(24).frame(maxWidth: .infinity)
        }
        .confirmationDialog("Delete all saved dictations?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Delete all dictations", role: .destructive) { history.clear() }
        } message: { Text("This removes saved transcripts and their statistics from this Mac. Conversations and memory are kept.") }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dictation history").font(.system(size: 25, weight: .semibold))
            Text("Your words and activity, saved locally.").font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
    private var actions: some View {
        HStack(spacing: 8) {
            SpeekSearchField(prompt: "Search dictations or apps", text: $query)
            Group {
                Button("Export") { export() }.buttonStyle(SpeekActionButtonStyle())
                Button("Clear history") { confirmingClear = true }.buttonStyle(SpeekActionButtonStyle())
            }.disabled(history.entries.isEmpty)
        }.fixedSize()
    }
    private func statistic(_ title: String, value: String, info: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value).font(.system(size: 24, weight: .semibold)).monospacedDigit()
            HStack(spacing: 4) {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                if let info { InfoButton(text: info, subject: title) }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).settingsSurface()
    }
    private func minutes(_ seconds: TimeInterval) -> String { String(format: "%.1f min", seconds / 60) }
    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Speek dictation history.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try history.export(to: url); exportError = nil }
        catch { exportError = "Could not export dictation history. " + error.localizedDescription }
    }
}

/// Shown where saved history appears while saving is off. The switch itself lives in Settings > Privacy.
struct HistoryPausedNotice: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pause.circle.fill").font(.system(size: 15)).foregroundStyle(.white)
            Text("History saving is off. New items are not saved.").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Open Privacy settings") { SpeekMainWindow.shared.showSettings(tab: "Privacy") }
                .buttonStyle(SpeekActionButtonStyle()).fixedSize()
        }.padding(12).settingsSurface()
    }
}
