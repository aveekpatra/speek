import SwiftUI
import SwiftData
import AppKit

/// History: searchable, date-grouped list of transcripts with a detail panel.
struct HistoryPage: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @State private var searchText = ""
    @State private var transcriptions: [Transcription] = []
    @State private var selected: Transcription?
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var confirmClearAll = false
    private let pageSize = 40

    var body: some View {
        ZStack(alignment: .trailing) {
            SpeekPageScroll(spacing: 14) {
                if transcriptions.isEmpty && !isLoading {
                    emptyState
                }
                ForEach(groupedTranscriptions, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                            .padding(.bottom, 2)
                        ForEach(group.items, id: \.id) { transcription in
                            HistoryRow(transcription: transcription, isSelected: selected?.id == transcription.id) {
                                selected = transcription
                            } onDelete: {
                                delete(transcription)
                            }
                        }
                    }
                }
                if hasMore && !transcriptions.isEmpty {
                    Button("Load more") { Task { await loadMore() } }
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            if let selected {
                HistoryDetailPanel(transcription: selected) {
                    self.selected = nil
                } onDelete: {
                    delete(selected)
                    self.selected = nil
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: selected?.id)
        .navigationTitle("")
        .toolbar {
            SpeekSearchToolbar(text: $searchText, prompt: "Search history") {
                Button {
                    confirmClearAll = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear history")
                .disabled(transcriptions.isEmpty)
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $confirmClearAll) {
            Button("Clear History", role: .destructive) { clearAll() }
        } message: {
            Text("Every transcript and its recording will be deleted. This cannot be undone.")
        }
        .task(id: searchText) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionCompleted)) { _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionDeleted)) { _ in Task { await reload() } }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "Your transcripts will show up here." : "No transcripts match your search.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: Grouping

    private struct Group {
        let title: String
        let items: [Transcription]
    }

    private var groupedTranscriptions: [Group] {
        var groups: [(String, [Transcription])] = []
        for transcription in transcriptions {
            let title = Self.relativeTitle(for: transcription.timestamp)
            if let last = groups.last, last.0 == title {
                groups[groups.count - 1].1.append(transcription)
            } else {
                groups.append((title, [transcription]))
            }
        }
        return groups.map { Group(title: $0.0, items: $0.1) }
    }

    static func relativeTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        if days < 7 { return "\(days) days ago" }
        if days < 14 { return "Last week" }
        if days < 31 { return "\(days / 7) weeks ago" }
        return date.formatted(.dateTime.month(.wide).year())
    }

    // MARK: Data

    private func descriptor(after timestamp: Date?) -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)])
        let search = searchText
        if let timestamp {
            if search.isEmpty {
                descriptor.predicate = #Predicate { $0.timestamp < timestamp }
            } else {
                descriptor.predicate = #Predicate {
                    ($0.text.localizedStandardContains(search) || ($0.enhancedText?.localizedStandardContains(search) ?? false)) && $0.timestamp < timestamp
                }
            }
        } else if !search.isEmpty {
            descriptor.predicate = #Predicate {
                $0.text.localizedStandardContains(search) || ($0.enhancedText?.localizedStandardContains(search) ?? false)
            }
        }
        descriptor.fetchLimit = pageSize
        return descriptor
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        let items = (try? modelContext.fetch(descriptor(after: nil))) ?? []
        transcriptions = items
        hasMore = items.count == pageSize
        if let selected, !items.contains(where: { $0.id == selected.id }) { self.selected = nil }
    }

    private func loadMore() async {
        guard let last = transcriptions.last else { return }
        let items = (try? modelContext.fetch(descriptor(after: last.timestamp))) ?? []
        transcriptions.append(contentsOf: items)
        hasMore = items.count == pageSize
    }

    private func clearAll() {
        let all = (try? modelContext.fetch(FetchDescriptor<Transcription>())) ?? []
        for transcription in all {
            if let urlString = transcription.audioFileURL, let url = URL(string: urlString) {
                try? FileManager.default.removeItem(at: url)
            }
            modelContext.delete(transcription)
        }
        try? modelContext.save()
        transcriptions = []
        selected = nil
        hasMore = false
        NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
    }

    private func delete(_ transcription: Transcription) {
        if let urlString = transcription.audioFileURL, let url = URL(string: urlString) {
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(transcription)
        try? modelContext.save()
        transcriptions.removeAll { $0.id == transcription.id }
        NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
    }
}

// MARK: - Row

private struct HistoryRow: View {
    @Environment(\.colorScheme) private var scheme
    let transcription: Transcription
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    private var displayText: String {
        let text = transcription.enhancedText?.isEmpty == false ? transcription.enhancedText! : transcription.text
        return text.isEmpty ? "No voice found in recording" : text
    }

    private var isPlaceholder: Bool {
        transcription.text.isEmpty || transcription.transcriptionStatus == TranscriptionStatus.canceled.rawValue || transcription.transcriptionStatus == TranscriptionStatus.failed.rawValue
    }

    var body: some View {
        Button(action: onSelect) {
            Text(displayText)
                .font(.system(size: 14))
                .italic(isPlaceholder)
                .foregroundStyle(isPlaceholder ? Color.secondary : Color.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Two glass buttons float over the row's trailing edge; glass reads fine
                // over text, so nothing else is needed and the text never reflows.
                .overlay(alignment: .trailing) {
                    if hovering {
                        HStack(spacing: 6) {
                            rowButton("doc.on.doc", help: "Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(displayText, forType: .string)
                            }
                            rowButton("trash", help: "Delete", action: onDelete)
                        }
                        .transition(.opacity)
                    }
                }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected || hovering ? SpeekDesign.controlFill(scheme) : SpeekDesign.groupFill(scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(displayText, forType: .string)
            }
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func rowButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .help(help)
    }
}

// MARK: - Detail panel

private struct HistoryDetailPanel: View {
    @Environment(\.colorScheme) private var scheme
    let transcription: Transcription
    let onClose: () -> Void
    let onDelete: () -> Void

    private var audioURL: URL? {
        guard let urlString = transcription.audioFileURL, let url = URL(string: urlString),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                Spacer()
                Text(transcription.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 18)
            .frame(height: 48)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    bubble(label: transcription.enhancedText == nil ? "Transcript" : "Original", text: transcription.text)
                    if let enhanced = transcription.enhancedText, !enhanced.isEmpty {
                        bubble(label: "Result", text: enhanced)
                    }
                    metadata
                }
                .padding(18)
            }

            if let audioURL {
                AudioPlayerView(url: audioURL, transcription: transcription)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 440)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(SpeekDesign.rowDivider(scheme)).frame(width: 1)
        }
    }

    private func bubble(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Text(text.isEmpty ? "No voice found in recording" : text)
                .font(.system(size: 14))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SpeekDesign.groupFill(scheme)))
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            metadataLine("Duration", value: String(format: "%.1f s", transcription.duration))
            if let model = transcription.transcriptionModelName { metadataLine("Voice model", value: model) }
            if let ai = transcription.aiEnhancementModelName { metadataLine("Text model", value: ai) }
            if let mode = transcription.modeName { metadataLine("Mode", value: mode) }
            if let seconds = transcription.transcriptionDuration { metadataLine("Processing", value: String(format: "%.1f s", seconds)) }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    private func metadataLine(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.primary)
        }
    }
}
