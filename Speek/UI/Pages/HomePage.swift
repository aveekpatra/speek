import SwiftUI
import SwiftData
import AppKit
import ApplicationServices

struct HomePage: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var recorderUIManager: RecorderUIManager
    @ObservedObject private var settings = SpeekSettings.shared
    @ObservedObject private var navigation = SpeekNavigation.shared
    @State private var stats = HomeStats.empty
    @State private var showTypingSpeedPopover = false
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    var body: some View {
        SpeekPageScroll(spacing: 22) {
            if !accessibilityTrusted {
                accessibilityBanner
            }
            rangePicker
            statsStrip
            getStarted
            whatsNew
        }
        .navigationTitle("")
        .toolbar { SpeekStandardToolbar() }
        .task(id: settings.statsRange) { await reloadStats() }
        .task(id: settings.typingWordsPerMinute) { await reloadStats() }
        .onReceive(NotificationCenter.default.publisher(for: .sessionMetricsDidChange)) { _ in
            Task { await reloadStats() }
        }
        .task {
            while !Task.isCancelled {
                accessibilityTrusted = AXIsProcessTrusted()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Shown when macOS no longer trusts this copy of the app (happens after every
    /// rebuild of an ad-hoc signed app). Without Accessibility the global shortcut and
    /// pasting cannot work.
    private var accessibilityBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility permission is missing")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Shortcuts and pasting need it. Repair drops the stale entry and opens the right pane.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Repair") { PermissionsCenter.shared.showGuide() }
                .buttonStyle(.glassProminent)
            }
            HStack(spacing: 8) {
                Text("Still not listed?")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("Show Speek in Finder") { AccessibilityRepair.revealInFinder() }
                    .help("Drag Speek from Finder into the Accessibility list in System Settings.")
                if !AccessibilityRepair.isInstalledInApplications {
                    Button("Move to Applications") { _ = AccessibilityRepair.moveToApplicationsAndRelaunch() }
                        .help("macOS only remembers permissions reliably for apps in the Applications folder.")
                }
                Button("Open System Settings") { AccessibilityRepair.openSettings() }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.12)))
    }

    // MARK: Range

    private var rangePicker: some View {
        Picker("", selection: $settings.statsRange) {
            ForEach(StatsRange.allCases) { range in
                Text(range.displayName).tag(range)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
        .fixedSize()
    }

    // MARK: Stats

    private var statsStrip: some View {
        SpeekGroup {
            HStack(alignment: .top, spacing: 12) {
                SpeekStatTile(value: "\(stats.averageWPM) WPM", label: "Average speed")
                SpeekStatTile(value: stats.words.formatted(.number.grouping(.automatic)), label: "Words")
                SpeekStatTile(value: "\(stats.appsUsed)", label: "Apps used")
                SpeekStatTile(
                    value: stats.savedText,
                    label: "Saved \(settings.statsRange == .allTime ? "all time" : settings.statsRange.displayName.lowercased())",
                    trailingAccessory: AnyView(typingSpeedGear)
                )
            }
            .padding(.horizontal, SpeekDesign.rowHorizontalPadding)
            .padding(.vertical, 16)
        }
    }

    private var typingSpeedGear: some View {
        Button {
            showTypingSpeedPopover.toggle()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTypingSpeedPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your typing speed")
                    .font(.headline)
                Text("Time saved compares dictation against typing at this speed.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack {
                    Slider(value: Binding(
                        get: { Double(settings.typingWordsPerMinute) },
                        set: { settings.typingWordsPerMinute = Int($0) }
                    ), in: 20...120, step: 5)
                    Text("\(settings.typingWordsPerMinute) WPM")
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
            }
            .padding(16)
            .frame(width: 300)
        }
    }

    // MARK: Get started

    private var getStarted: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpeekSectionHeader("Get started")
            VStack(spacing: 2) {
                GetStartedRow(
                    symbol: "record.circle",
                    title: "Start recording",
                    subtitle: "Turn your voice to text with a single click.",
                    trailing: AnyView(SpeekKeycapRow(keys: ShortcutStore.shortcut(for: .primaryRecording)?.displayTokens ?? ["Record"]))
                ) {
                    Task { await recorderUIManager.toggleRecorderPanel() }
                }
                GetStartedRow(symbol: "hand.tap", title: "Customize your shortcuts", subtitle: "Change the keyboard shortcuts for Speek.") {
                    navigation.open(.configuration)
                }
                GetStartedRow(symbol: "sparkle", title: "Create a mode", subtitle: "Build the perfect mode for your workflow.") {
                    navigation.open(.modes)
                }
                GetStartedRow(symbol: "text.book.closed", title: "Add vocabulary", subtitle: "Teach Speek custom words, names, or industry terms.") {
                    navigation.open(.vocabulary)
                }
            }
        }
    }

    // MARK: What's new

    private var whatsNew: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SpeekSectionHeader("What's new?")
                Spacer()
                Button("View all changes") {
                    NSWorkspace.shared.open(SpeekLinks.releases)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
            }
            SpeekGroup {
                ForEach(WhatsNewEntry.entries) { entry in
                    HStack(alignment: .top, spacing: 22) {
                        Text(entry.date)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.system(size: 15, weight: .semibold))
                            Text(entry.body)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if let action = entry.action {
                                Button(action.title) { navigation.open(action.page) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, SpeekDesign.rowHorizontalPadding)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    // MARK: Data

    private func reloadStats() async {
        let range = settings.statsRange
        let typingWPM = max(settings.typingWordsPerMinute, 1)
        let descriptor: FetchDescriptor<SessionMetric>
        if let start = range.startDate {
            descriptor = FetchDescriptor<SessionMetric>(predicate: #Predicate { $0.timestamp >= start })
        } else {
            descriptor = FetchDescriptor<SessionMetric>()
        }
        let metrics = (try? modelContext.fetch(descriptor)) ?? []
        let words = metrics.reduce(0) { $0 + $1.wordCount }
        let seconds = metrics.reduce(0.0) { $0 + $1.audioDuration }
        let apps = Set(metrics.compactMap { $0.appBundleId ?? $0.appName }.filter { !$0.isEmpty }).count
        let wpm = seconds > 0 ? Int((Double(words) / seconds * 60).rounded()) : 0
        let typingSeconds = Double(words) / Double(typingWPM) * 60
        let saved = max(0, typingSeconds - seconds)
        stats = HomeStats(words: words, averageWPM: wpm, appsUsed: apps, savedSeconds: saved)
    }
}

// MARK: - Supporting types

private struct HomeStats {
    var words: Int
    var averageWPM: Int
    var appsUsed: Int
    var savedSeconds: TimeInterval

    static let empty = HomeStats(words: 0, averageWPM: 0, appsUsed: 0, savedSeconds: 0)

    var savedText: String {
        let minutes = Int(savedSeconds / 60)
        if minutes < 1 { return "0 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rem = minutes % 60
        if hours < 10 && rem >= 5 { return "\(hours) h \(rem) min" }
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}

private struct GetStartedRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var trailing: AnyView? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let trailing { trailing }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .speekHoverHighlight()
    }
}

struct WhatsNewEntry: Identifiable {
    struct Action {
        let title: String
        let page: SpeekPage
    }

    let id = UUID()
    let date: String
    let title: String
    let body: String
    var action: Action? = nil

    static let entries: [WhatsNewEntry] = [
        WhatsNewEntry(
            date: "Sep 6",
            title: "Speek 0.1",
            body: "A free, open-source dictation app for macOS with fully local models and a Liquid Glass design.",
            action: Action(title: "Set up a voice model", page: .modelsLibrary)
        ),
        WhatsNewEntry(
            date: "Sep 6",
            title: "Cohere Transcribe",
            body: "Cohere's open 2B speech model runs fully offline on Apple silicon with 14 languages.",
            action: Action(title: "Download it", page: .modelsLibrary)
        ),
        WhatsNewEntry(
            date: "Sep 6",
            title: "Agent plugins",
            body: "Claude Code and Codex can call you when they need input; answer by voice without switching windows.",
            action: Action(title: "Install plugins", page: .configuration)
        )
    ]
}

enum SpeekLinks {
    static let repository = URL(string: "https://github.com/aveekpatra/speek")!
    static let releases = URL(string: "https://github.com/aveekpatra/speek/releases")!
    static let issues = URL(string: "https://github.com/aveekpatra/speek/issues")!
}
