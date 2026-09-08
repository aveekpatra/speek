import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Row model

struct LibraryModel: Identifiable {
    enum Kind {
        case voice
        case text
    }

    enum Availability {
        case builtIn
        case downloaded
        case downloading(fraction: Double, message: String)
        case notDownloaded(size: String)
        case unavailable(reason: String)

        var isRemovable: Bool {
            if case .downloaded = self { return true }
            return false
        }
    }

    enum Provider: String, CaseIterable, Identifiable {
        case all = "All providers"
        case cohere = "Cohere"
        case nvidia = "NVIDIA"
        case openAI = "OpenAI"
        case apple = "Apple"
        case superwhisper = "Superwhisper"
        case ollama = "Ollama"

        var id: String { rawValue }
    }

    let id: String
    let displayName: String
    let provider: Provider
    let kind: Kind
    var badge: String? = nil
    let speed: Double
    let accuracy: Double
    let availability: Availability
    var isExperimental: Bool = false
    var transcriptionModel: (any TranscriptionModel)? = nil
    var description: String = ""

    var isVoice: Bool { kind == .voice }
}

// MARK: - Page

struct ModelsLibraryPage: View {
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @ObservedObject private var cohereModelManager = CohereModelManager.shared
    @ObservedObject private var canaryModelManager = CanaryModelManager.shared
    @ObservedObject private var s1MiniModelManager = S1MiniModelManager.shared
    @ObservedObject private var settings = SpeekSettings.shared
    @StateObject private var ollama = OllamaService()
    @Environment(\.colorScheme) private var scheme

    @State private var searchText = ""
    @State private var sortAscending = true
    @State private var pendingDelete: LibraryModel?
    @State private var appleAssetState: NativeAppleSpeechAssetState = .checking

    var body: some View {
        SpeekPageScroll(spacing: 18) {
            table
        }
        .navigationTitle("")
        .toolbar {
            SpeekSearchToolbar(text: $searchText, prompt: "Search models") {
                Menu {
                    Button("Import Whisper model (.bin)...") { importWhisperModel() }
                    Divider()
                    Button("Refresh") { refresh() }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .menuIndicator(.hidden)
                .help("Import model")
            }
        }
        .task { refresh() }
        .confirmationDialog("Delete \(pendingDelete?.displayName ?? "model")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let model = pendingDelete { delete(model) }
                pendingDelete = nil
            }
        } message: {
            Text("The downloaded files are removed from your Mac. You can download the model again at any time.")
        }
    }

    // MARK: Table

    private var table: some View {
        VStack(spacing: 0) {
            headerRow
            ForEach(filteredModels) { model in
                LibraryModelRow(
                    model: model,
                    onPrimary: { primaryAction(for: model) },
                    onDelete: { pendingDelete = model },
                    onReveal: { reveal(model) }
                )
            }
            if filteredModels.isEmpty {
                Text("No models match your search.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 30)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: LibraryColumns.iconSpacing) {
                Color.clear.frame(width: LibraryColumns.iconSize, height: 1)
                Button {
                    sortAscending.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text("Model name")
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Text("Type").frame(width: LibraryColumns.type)
            Text("Speed / Accuracy").frame(width: LibraryColumns.meters, alignment: .leading)
            Text("Offline").frame(width: LibraryColumns.status, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, LibraryColumns.inset)
        .padding(.bottom, 6)
    }

    // MARK: Data

    private var filteredModels: [LibraryModel] {
        var models = allModels
        if !settings.showExperimentalModels { models = models.filter { !$0.isExperimental } }
        if !searchText.isEmpty {
            models = models.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) || $0.provider.rawValue.localizedCaseInsensitiveContains(searchText) }
        }
        return models.sorted { sortAscending ? $0.displayName < $1.displayName : $0.displayName > $1.displayName }
    }

    private var allModels: [LibraryModel] {
        var result: [LibraryModel] = []

        for model in transcriptionModelManager.allAvailableModels {
            switch model {
            case let cohere as CohereModel:
                result.append(LibraryModel(
                    id: cohere.name, displayName: cohere.displayName, provider: .cohere, kind: .voice, badge: "NEW",
                    speed: cohere.speed, accuracy: cohere.accuracy,
                    availability: cohereAvailability(size: cohere.size),
                    transcriptionModel: cohere, description: cohere.description
                ))
            case let canary as CanaryModel:
                result.append(LibraryModel(
                    id: canary.name, displayName: canary.displayName, provider: .nvidia, kind: .voice, badge: "NEW",
                    speed: canary.speed, accuracy: canary.accuracy,
                    availability: canaryAvailability(size: canary.size),
                    transcriptionModel: canary, description: canary.description
                ))
            case let parakeet as FluidAudioModel:
                result.append(LibraryModel(
                    id: parakeet.name, displayName: parakeet.displayName, provider: .nvidia, kind: .voice,
                    badge: parakeet.isMultilingualModel ? nil : "EN",
                    speed: parakeet.speed, accuracy: parakeet.accuracy,
                    availability: parakeetAvailability(parakeet),
                    transcriptionModel: parakeet, description: parakeet.description
                ))
            case let whisper as WhisperModel:
                result.append(LibraryModel(
                    id: whisper.name, displayName: "Whisper \(whisper.displayName)", provider: .openAI, kind: .voice,
                    badge: whisper.isMultilingualModel ? nil : "EN",
                    speed: whisper.speed, accuracy: whisper.accuracy,
                    availability: whisperAvailability(whisper),
                    isExperimental: whisper.name.contains("q5"),
                    transcriptionModel: whisper, description: whisper.description
                ))
            case let imported as ImportedWhisperModel:
                result.append(LibraryModel(
                    id: imported.name, displayName: imported.displayName, provider: .openAI, kind: .voice,
                    speed: 0.6, accuracy: 0.8, availability: .downloaded,
                    transcriptionModel: imported, description: imported.description
                ))
            case let apple as NativeAppleModel:
                result.append(LibraryModel(
                    id: apple.name, displayName: apple.displayName, provider: .apple, kind: .voice,
                    speed: 0.95, accuracy: 0.85, availability: appleAvailability,
                    transcriptionModel: apple, description: apple.description
                ))
            default:
                break
            }
        }

        result.append(LibraryModel(
            id: S1MiniModelManager.modelName, displayName: S1MiniModelManager.displayName, provider: .superwhisper, kind: .text, badge: "EN",
            speed: 0.9, accuracy: 0.95,
            availability: s1MiniAvailability,
            description: "S1-mini by Superwhisper: open-weights text normalizer that turns raw transcripts into clean written text, fully on device."
        ))

        for model in ollama.availableModels {
            result.append(LibraryModel(
                id: "ollama:\(model.name)", displayName: model.name, provider: .ollama, kind: .text,
                speed: 0.7, accuracy: 0.8, availability: .downloaded,
                description: "Local Ollama model"
            ))
        }

        return result
    }

    private func canaryAvailability(size: String) -> LibraryModel.Availability {
        if let status = canaryModelManager.downloadStatus {
            return .downloading(fraction: status.fractionCompleted, message: status.message)
        }
        return canaryModelManager.isDownloaded ? .downloaded : .notDownloaded(size: size)
    }

    private var s1MiniAvailability: LibraryModel.Availability {
        if let status = s1MiniModelManager.downloadStatus {
            return .downloading(fraction: status.fractionCompleted, message: status.message)
        }
        return s1MiniModelManager.isDownloaded ? .downloaded : .notDownloaded(size: S1MiniModelManager.sizeText)
    }

    private func cohereAvailability(size: String) -> LibraryModel.Availability {
        if let status = cohereModelManager.downloadStatus {
            return .downloading(fraction: status.fractionCompleted, message: status.message)
        }
        return cohereModelManager.isDownloaded ? .downloaded : .notDownloaded(size: size)
    }

    private func parakeetAvailability(_ model: FluidAudioModel) -> LibraryModel.Availability {
        if let status = fluidAudioModelManager.downloadStatus(for: model) {
            return .downloading(fraction: status.fractionCompleted, message: status.message)
        }
        return fluidAudioModelManager.isFluidAudioModelDownloaded(model) ? .downloaded : .notDownloaded(size: model.size)
    }

    private func whisperAvailability(_ model: WhisperModel) -> LibraryModel.Availability {
        let main = whisperModelManager.downloadProgress[model.name + "_main"]
        let coreML = whisperModelManager.downloadProgress[model.name + "_coreml"]
        if main != nil || coreML != nil {
            let fraction = ((main ?? 0) + (coreML ?? 0)) / (coreML == nil ? 1 : 2)
            return .downloading(fraction: fraction, message: "Downloading")
        }
        let downloaded = whisperModelManager.availableModels.contains { $0.name == model.name }
        return downloaded ? .downloaded : .notDownloaded(size: model.size)
    }

    /// Apple Speech ships with macOS but its per-language pack is downloaded on demand.
    private var appleAvailability: LibraryModel.Availability {
        switch appleAssetState {
        case .downloaded: return .downloaded
        case .needsDownload: return .notDownloaded(size: appleLanguageName)
        case .downloading: return .downloading(fraction: 0, message: "Downloading \(appleLanguageName) language pack")
        case .checking: return .builtIn
        case .notSupported: return .unavailable(reason: "Unsupported language")
        case .assetManagementUnavailable: return .unavailable(reason: "Requires macOS 26")
        case .reservationLimitReached: return .unavailable(reason: "Language limit reached")
        case .failed: return .notDownloaded(size: appleLanguageName)
        }
    }

    private var appleLocaleIdentifier: String {
        NativeAppleSpeechAssetManager.normalizedLocaleIdentifier(ModeManager.shared.currentEffectiveConfiguration?.selectedLanguage)
    }

    private var appleLanguageName: String {
        NativeAppleSpeechAssetManager.languageDisplayName(for: appleLocaleIdentifier)
    }

    private func refreshAppleAssetState() {
        let locale = appleLocaleIdentifier
        Task {
            let state = await NativeAppleSpeechAssetManager.assetState(for: locale)
            await MainActor.run { appleAssetState = state }
        }
    }

    private func installAppleAsset() {
        let locale = appleLocaleIdentifier
        appleAssetState = .downloading
        Task {
            let state = await NativeAppleSpeechAssetManager.installAsset(for: locale)
            await MainActor.run { appleAssetState = state }
        }
    }

    // MARK: Actions

    private func primaryAction(for model: LibraryModel) {
        switch model.availability {
        case .notDownloaded:
            download(model)
        case .downloaded, .builtIn:
            // Which model a dictation uses is decided per mode, under Modes.
            break
        case .downloading:
            if model.provider == .cohere { cohereModelManager.cancelDownload() }
            if model.id == CanaryModelManager.modelName { canaryModelManager.cancelDownload() }
            if model.id == S1MiniModelManager.modelName { s1MiniModelManager.cancelDownload() }
        case .unavailable:
            break
        }
    }

    private func download(_ model: LibraryModel) {
        if model.id == S1MiniModelManager.modelName { s1MiniModelManager.download(); return }
        if model.provider == .apple { installAppleAsset(); return }
        switch model.transcriptionModel {
        case let cohere as CohereModel where cohere.provider == .cohere:
            cohereModelManager.download()
        case is CanaryModel:
            canaryModelManager.download()
        case let parakeet as FluidAudioModel:
            Task { await fluidAudioModelManager.downloadFluidAudioModel(parakeet) }
        case let whisper as WhisperModel:
            Task { await whisperModelManager.downloadModel(whisper) }
        default:
            break
        }
    }

    private func delete(_ model: LibraryModel) {
        if model.id == S1MiniModelManager.modelName { s1MiniModelManager.delete(); return }
        switch model.transcriptionModel {
        case is CohereModel:
            cohereModelManager.delete()
        case is CanaryModel:
            canaryModelManager.delete()
        case let parakeet as FluidAudioModel:
            fluidAudioModelManager.deleteFluidAudioModel(parakeet)
        case let whisper as WhisperModel:
            if let file = whisperModelManager.availableModels.first(where: { $0.name == whisper.name }) {
                Task { await whisperModelManager.deleteModel(file) }
            }
        case let imported as ImportedWhisperModel:
            if let file = whisperModelManager.availableModels.first(where: { $0.name == imported.name }) {
                Task { await whisperModelManager.deleteModel(file) }
            }
        default:
            break
        }
    }

    private func reveal(_ model: LibraryModel) {
        if model.id == S1MiniModelManager.modelName { s1MiniModelManager.showInFinder(); return }
        switch model.transcriptionModel {
        case is CohereModel:
            cohereModelManager.showInFinder()
        case is CanaryModel:
            canaryModelManager.showInFinder()
        case let parakeet as FluidAudioModel:
            fluidAudioModelManager.showFluidAudioModelInFinder(parakeet)
        case is WhisperModel, is ImportedWhisperModel:
            if let file = whisperModelManager.availableModels.first(where: { $0.name == model.transcriptionModel?.name }) {
                NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "")
            }
        default:
            break
        }
    }

    private func importWhisperModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a whisper.cpp GGML model (.bin)"
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await whisperModelManager.importWhisperModel(from: url)
                transcriptionModelManager.refreshAllAvailableModels()
            }
        }
    }

    private func refresh() {
        transcriptionModelManager.refreshAllAvailableModels()
        refreshAppleAssetState()
        Task { _ = await ollama.refreshConnectionAndModels() }
    }
}

// MARK: - Row

/// Shared column metrics so the header lines up with every row.
private enum LibraryColumns {
    static let inset: CGFloat = 12
    static let iconSize: CGFloat = 24
    static let iconSpacing: CGFloat = 10
    static let type: CGFloat = 56
    static let meters: CGFloat = 130
    static let status: CGFloat = 120
}

private struct LibraryModelRow: View {
    @Environment(\.colorScheme) private var scheme
    let model: LibraryModel
    let onPrimary: () -> Void
    let onDelete: () -> Void
    let onReveal: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: LibraryColumns.iconSpacing) {
                SpeekModelIcon.tile(brand: brand, size: LibraryColumns.iconSize)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 7) {
                        Text(model.displayName)
                            .font(.system(size: 14))
                            .lineLimit(1)
                        if let badge = model.badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(RoundedRectangle(cornerRadius: 3.5).fill(SpeekDesign.controlFill(scheme)))
                        }
                    }
                    if case .downloading(_, let message) = model.availability {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            Image(systemName: model.isVoice ? "waveform" : "text.alignleft")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(SpeekDesign.controlFill(scheme)))
                .frame(width: LibraryColumns.type)
                .help(model.isVoice ? "Voice model" : "Text model")
            VStack(alignment: .leading, spacing: 4) {
                SpeekMeter(value: model.speed)
                SpeekMeter(value: model.accuracy)
            }
            .frame(width: LibraryColumns.meters, alignment: .leading)
            .help("Speed \(Int(model.speed * 100))%, accuracy \(Int(model.accuracy * 100))%")
            trailing
                .frame(width: LibraryColumns.status, alignment: .trailing)
        }
        .padding(.horizontal, LibraryColumns.inset)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? SpeekDesign.controlFill(scheme).opacity(0.7) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if case .notDownloaded = model.availability { onPrimary() } }
        .contextMenu {
            if case .downloaded = model.availability {
                if canDelete {
                    Button("Show in Finder") { onReveal() }
                    Divider()
                    Button("Delete", role: .destructive) { onDelete() }
                }
            } else if case .notDownloaded = model.availability {
                Button("Download") { onPrimary() }
            }
        }
        .help(model.description)
    }

    /// Apple's language packs and Ollama models are not files we own.
    private var canDelete: Bool {
        model.availability.isRemovable && model.provider != .apple && model.provider != .ollama
    }

    private var brand: SpeekModelIcon.Brand {
        switch model.provider {
        case .cohere: return .cohere
        case .nvidia: return .nvidia
        case .openAI: return .openAI
        case .apple: return .apple
        case .ollama: return .ollama
        case .superwhisper, .all: return .superwhisper
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch model.availability {
        case .builtIn:
            statusLabel("Built in")
        case .downloaded:
            HStack(spacing: 8) {
                if hovering && canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(SpeekDesign.controlFill(scheme)))
                    }
                    .buttonStyle(.plain)
                    .help("Delete downloaded files")
                    .transition(.opacity)
                }
                statusLabel("Installed")
            }
            .animation(.easeOut(duration: 0.15), value: hovering)
        case .downloading(let fraction, _):
            HStack(spacing: 8) {
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.secondary)
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }
        case .notDownloaded(let size):
            HStack(spacing: 8) {
                Text(size)
                    .font(.system(size: 13, weight: .medium))
                SpeekCircleIconButton(systemName: "arrow.down") { onPrimary() }
            }
        case .unavailable(let reason):
            Text(reason)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
    }

    private func statusLabel(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(color)
    }
}
