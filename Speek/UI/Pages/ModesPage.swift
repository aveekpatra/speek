import SwiftUI
import AppKit

// MARK: - Presets

/// Mode presets. Each maps to a bundled prompt (or no AI at all).
enum ModePreset: String, CaseIterable, Identifiable {
    case voiceToText
    case message
    case email
    case note
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .voiceToText: return "Voice to text"
        case .message: return "Message"
        case .email: return "Email"
        case .note: return "Note"
        case .custom: return "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .voiceToText: return "mic"
        case .message: return "bubble.left"
        case .email: return "envelope"
        case .note: return "note.text"
        case .custom: return "sparkles"
        }
    }

    var promptId: UUID? {
        switch self {
        case .voiceToText: return PromptTemplates.cleanPromptId
        case .message: return PromptTemplates.chatPromptId
        case .email: return PromptTemplates.emailPromptId
        case .note: return PromptTemplates.defaultPromptId
        case .custom: return nil
        }
    }

    /// The preset is the formatting recipe; whether a language model runs is decided by
    /// the Language Model picker (None / S1-mini / Ollama), independently of the preset.
    static func preset(for config: ModeConfig) -> ModePreset {
        guard let raw = config.selectedPrompt, let id = UUID(uuidString: raw) else { return .voiceToText }
        return ModePreset.allCases.first { $0.promptId == id } ?? .custom
    }
}

// MARK: - List page

struct ModesPage: View {
    @ObservedObject private var navigation = SpeekNavigation.shared

    var body: some View {
        ModesListView(onOpen: { id in navigation.push(.modeDetail(id)) })
    }
}

private struct ModesListView: View {
    @ObservedObject private var modeManager = ModeManager.shared
    @Environment(\.colorScheme) private var scheme
    let onOpen: (UUID) -> Void

    var body: some View {
        SpeekPageScroll(spacing: 16) {
            HStack {
                SpeekSectionHeader("Modes", help: "A mode bundles a preset, a voice model, an optional text model and the apps it activates in. Switch modes with ⌥⇧K while recording.")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                SpeekPillButton(title: "Create mode", systemImage: "plus") { createMode() }
            }
            VStack(spacing: 10) {
                ForEach(modeManager.configurations) { config in
                    ModeRowView(config: config, isActive: modeManager.currentEffectiveConfiguration?.id == config.id) {
                        onOpen(config.id)
                    }
                }
            }
            Spacer(minLength: 40)
            HStack(spacing: 6) {
                Spacer()
                SpeekKeycapRow(keys: ShortcutStore.shortcut(for: .changeMode)?.displayTokens ?? ["⌥", "⇧", "K"])
                Text("Change active mode")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .navigationTitle("")
        .toolbar { SpeekStandardToolbar() }
    }

    private func createMode() {
        let config = ModeConfig(
            name: "New mode",
            icon: .symbol("sparkles"),
            isAIEnhancementEnabled: false,
            selectedPrompt: nil,
            isDefault: modeManager.configurations.isEmpty
        )
        modeManager.addConfiguration(config)
        onOpen(config.id)
    }
}

private struct ModeRowView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    let config: ModeConfig
    let isActive: Bool
    let onOpen: () -> Void
    @State private var hovering = false

    private var preset: ModePreset { ModePreset.preset(for: config) }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                ModeIconView(icon: config.icon, size: 15, color: .primary)
                    .frame(width: 20)
                Text(config.name)
                    .font(.system(size: 15))
                if isActive {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                }
                if !config.isEnabled {
                    Text("Off")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    modelChip(symbol: "waveform", title: voiceModelName)
                    if config.isAIEnhancementEnabled {
                        modelChip(symbol: "text.alignleft", title: config.selectedAIModel ?? config.selectedAIProvider ?? "Language model")
                    }
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: SpeekDesign.groupRadius, style: .continuous)
                    .fill(SpeekDesign.groupFill(scheme).opacity(hovering ? 1.4 : 1))
                    .overlay(RoundedRectangle(cornerRadius: SpeekDesign.groupRadius, style: .continuous).strokeBorder(SpeekDesign.groupStroke(scheme), lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var voiceModelName: String {
        if let name = config.selectedTranscriptionModelName,
           let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == name }) {
            return model.displayName
        }
        return transcriptionModelManager.currentTranscriptionModel?.displayName ?? "Voice model"
    }

    private func modelChip(symbol: String, title: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SpeekDesign.controlFill(scheme)))
            .help(title)
    }
}

// MARK: - Detail page

struct ModeDetailPage: View {
    @ObservedObject private var modeManager = ModeManager.shared
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @ObservedObject private var settings = SpeekSettings.shared
    @ObservedObject private var navigation = SpeekNavigation.shared
    @ObservedObject private var s1MiniModelManager = S1MiniModelManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let modeID: UUID

    @State private var showAdvanced = false
    @State private var showAppPicker = false
    @State private var showDeleteConfirm = false
    @State private var customPromptText = ""

    private var config: ModeConfig? { modeManager.getConfiguration(with: modeID) }

    var body: some View {
        if let config {
            content(config)
        } else {
            Text("This mode no longer exists.")
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ config: ModeConfig) -> some View {
        let preset = ModePreset.preset(for: config)
        return SpeekPageScroll(spacing: 14) {
            SpeekGroup {
                SpeekRow("Preset", help: "Presets decide how the transcript is formatted after the voice model and the language model have run. Voice to text skips the language model.") {
                    Picker("", selection: Binding(get: { preset }, set: { apply(preset: $0) })) {
                        ForEach(ModePreset.allCases) { preset in
                            Label(preset.displayName, systemImage: preset.symbol).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if config.isAIEnhancementEnabled {
                    SpeekRow("Tone", help: "How formal the cleaned-up text reads, from casual chat to formal writing.") {
                        HStack(spacing: 12) {
                            Text("Casual").font(.system(size: 14))
                            Slider(
                                value: Binding(
                                    get: { Double(toneIndex(config)) },
                                    set: { v in update { $0.s1Styling = S1MiniService.Styling.allCases[Int(v.rounded())].rawValue } }
                                ),
                                in: 0...3, step: 1
                            )
                            .frame(width: 200)
                            Text("Formal").font(.system(size: 14))
                        }
                    }
                }
                if preset == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Instructions for the language model")
                            .font(.system(size: 15))
                        TextEditor(text: $customPromptText)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(SpeekDesign.controlFill(scheme).opacity(0.5)))
                            .onChange(of: customPromptText) { _, text in saveCustomPrompt(text, config: config) }
                        Text("Custom instructions need an Ollama model. S1-mini only follows the tone setting.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, SpeekDesign.rowHorizontalPadding)
                    .padding(.vertical, 12)
                }
            }

            SpeekGroup {
                SpeekRow("Language") {
                    Picker("", selection: Binding(
                        get: { config.selectedLanguage ?? "auto" },
                        set: { code in update { $0.selectedLanguage = code == "auto" ? nil : code } }
                    )) {
                        ForEach(languageOptions(config), id: \.code) { option in
                            Text(option.name).tag(option.code)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                SpeekRow("Voice Model", help: "The speech model that turns your audio into text. Download models in Models library.") {
                    SpeekModelPopup(
                        title: voiceModel(config)?.displayName ?? "Default",
                        icon: AnyView(SpeekModelIcon.tile(for: voiceModel(config)?.provider)),
                        options: [SpeekModelPopup.Option(id: "", title: "Default (\(transcriptionModelManager.currentTranscriptionModel?.displayName ?? "none"))", icon: AnyView(SpeekModelIcon.tile(for: transcriptionModelManager.currentTranscriptionModel?.provider)))]
                            + transcriptionModelManager.usableModels.map { model in
                                SpeekModelPopup.Option(id: model.name, title: model.displayName, icon: AnyView(SpeekModelIcon.tile(for: model.provider)))
                            },
                        selectedID: config.selectedTranscriptionModelName ?? ""
                    ) { id in
                        update { $0.selectedTranscriptionModelName = id.isEmpty ? nil : id }
                    }
                }
                SpeekRow("Language Model", help: "Runs after the voice model and rewrites the transcript according to the preset and tone. None pastes the raw transcript. S1-mini is Superwhisper's open-weights normalizer; Ollama models work too.") {
                    let selectedID = textModelSelection(config)
                    let selected = textModelOptions.first { $0.id == selectedID }
                    SpeekModelPopup(
                        title: selected?.title ?? "None",
                        icon: AnyView(selected == nil ? AnyView(SpeekModelIcon.neutralTile(symbol: "minus")) : AnyView(textModelIcon(selected?.provider))),
                        options: [SpeekModelPopup.Option(id: "none", title: "None", icon: AnyView(SpeekModelIcon.neutralTile(symbol: "minus")))]
                            + textModelOptions.map { option in
                                SpeekModelPopup.Option(id: option.id, title: option.title, icon: AnyView(textModelIcon(option.provider)))
                            },
                        selectedID: selectedID
                    ) { id in
                        apply(textModel: id)
                    }
                }
                if config.isAIEnhancementEnabled {
                    if config.selectedAIProvider != AIProvider.ollama.rawValue, !s1MiniModelManager.isDownloaded {
                        SpeekRow("S1-mini is not downloaded", subtitle: "Download it in Models library to use this preset.") {
                            Button("Open Models library") { navigation.open(.modelsLibrary) }
                                .buttonStyle(.glass)
                        }
                    }
                }
            }

            SpeekGroup {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            Text("Activate for apps")
                                .font(.system(size: 15))
                            SpeekHelpButton(text: "Optional. When one of these apps or websites is in front, this mode is used automatically. Leave empty to keep the mode universal.")
                        }
                        Spacer()
                        SpeekPillButton(title: "Add apps and sites") { showAppPicker = true }
                    }
                    if !config.allAppConfigs.isEmpty || !config.allURLConfigs.isEmpty {
                        FlowChips {
                            ForEach(config.allAppConfigs) { app in
                                chip(app.appName, symbol: "app") { modeManager.removeAppConfig(app, from: config) }
                            }
                            ForEach(config.allURLConfigs) { url in
                                chip(url.url, symbol: "globe") { modeManager.removeURLConfig(url, from: config) }
                            }
                        }
                    }
                }
                .padding(.horizontal, SpeekDesign.rowHorizontalPadding)
                .padding(.vertical, 12)
                SpeekRow("Keyboard shortcut", subtitle: "Start a recording in this mode") {
                    ShortcutRecorder(action: .mode(config.id))
                }
            }

            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(spacing: 14) {
                    SpeekGroup {
                        SpeekRow("Playback when recording", help: "What happens to music or video while you dictate. Shared by every mode.") {
                            Picker("", selection: $settings.playbackWhenRecording) {
                                ForEach(PlaybackWhenRecording.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                        SpeekRow("Use selected text as context", help: "Sends the text selected in the front app to the language model along with your dictation.") {
                            Toggle("", isOn: Binding(get: { config.useSelectedTextContext }, set: { v in update { $0.useSelectedTextContext = v } })).labelsHidden().toggleStyle(.switch)
                        }
                        SpeekRow("Use clipboard as context", help: "Sends the clipboard contents to the language model.") {
                            Toggle("", isOn: Binding(get: { config.useClipboardContext }, set: { v in update { $0.useClipboardContext = v } })).labelsHidden().toggleStyle(.switch)
                        }
                    }
                    SpeekGroup {
                        SpeekRow("Autocapitalize Insert", help: "Capitalize the first letter and apply paragraph formatting when inserting the text.") {
                            Toggle("", isOn: Binding(get: { config.isTextFormattingEnabled }, set: { v in update { $0.isTextFormattingEnabled = v } })).labelsHidden().toggleStyle(.switch)
                        }
                        SpeekRow("Auto paste", help: "On pastes the result where your cursor is. Off shows the result in the recording window and copies it to the clipboard.") {
                            Picker("", selection: Binding(get: { config.outputMode == .paste }, set: { v in update { $0.outputMode = v ? .paste : .respond } })) {
                                Text("On (Default)").tag(true)
                                Text("Off").tag(false)
                            }
                            .labelsHidden().fixedSize()
                        }
                        SpeekRow("Auto send", help: "Press a key after pasting, useful for chat apps.") {
                            Picker("", selection: Binding(get: { config.autoSendKey }, set: { v in update { $0.autoSendKey = v } })) {
                                ForEach(AutoSendKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                    SpeekGroup {
                        SpeekRow("Name") {
                            TextField("Mode name", text: Binding(
                                get: { config.name },
                                set: { name in update { $0.name = name } }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                        }
                        SpeekRow("Icon") {
                            Menu {
                                ForEach(Self.iconChoices, id: \.self) { symbol in
                                    Button {
                                        update { $0.icon = .symbol(symbol) }
                                    } label: {
                                        Label(Self.iconTitle(symbol), systemImage: symbol)
                                    }
                                }
                            } label: {
                                ModeIconView(icon: config.icon, size: 14, color: .primary)
                                    .frame(width: 22)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        SpeekRow("Mode enabled") {
                            Toggle("", isOn: Binding(get: { config.isEnabled }, set: { v in v ? modeManager.enableConfiguration(with: config.id) : modeManager.disableConfiguration(with: config.id) })).labelsHidden().toggleStyle(.switch)
                        }
                        SpeekRow("Default mode", help: "Used when no app-specific mode matches.") {
                            Toggle("", isOn: Binding(get: { config.isDefault }, set: { v in if v { modeManager.setAsDefault(configId: config.id) } })).labelsHidden().toggleStyle(.switch)
                                .disabled(config.isDefault)
                        }
                    }
                    SpeekGroup {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            SpeekRow("Delete this mode") {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("Advanced settings")
                    .font(.system(size: 16, weight: .semibold))
            }
            .disclosureGroupStyle(.automatic)
            .padding(.leading, 4)
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    ModeIconView(icon: config.icon, size: 14, color: .primary)
                    Text(config.name)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showAppPicker) {
            AppAndSitePicker { app in
                modeManager.addAppConfig(app, to: config)
            } onAddURL: { url in
                modeManager.addURLConfig(URLConfig(url: url), to: config)
            }
        }
        .confirmationDialog("Delete \"\(config.name)\"?", isPresented: $showDeleteConfirm) {
            Button("Delete mode", role: .destructive) {
                modeManager.removeConfiguration(with: config.id)
                dismiss()
            }
        }
        .onAppear {
            if let raw = config.selectedPrompt, let id = UUID(uuidString: raw),
               let prompt = enhancementService.allPrompts.first(where: { $0.id == id }),
               ModePreset.preset(for: config) == .custom {
                customPromptText = prompt.promptText
            }
        }
    }

    private func toneIndex(_ config: ModeConfig) -> Int {
        let styling = S1MiniService.Styling(rawValue: config.s1Styling ?? "") ?? .semiCasual
        return S1MiniService.Styling.allCases.firstIndex(of: styling) ?? 1
    }

    private func voiceModel(_ config: ModeConfig) -> (any TranscriptionModel)? {
        if let name = config.selectedTranscriptionModelName {
            return transcriptionModelManager.allAvailableModels.first { $0.name == name }
        }
        return transcriptionModelManager.currentTranscriptionModel
    }

    private func textModelIcon(_ provider: AIProvider?) -> some View {
        provider == .ollama
            ? SpeekModelIcon.tile(brand: .ollama)
            : SpeekModelIcon.tile(brand: .superwhisper)
    }

    static let iconChoices = ["mic.fill", "bubble.left.fill", "envelope.fill", "note.text", "sparkles", "terminal.fill", "doc.text.fill", "list.bullet", "globe", "lightbulb.fill", "briefcase.fill", "heart.fill"]

    static func iconTitle(_ symbol: String) -> String {
        symbol.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " ").capitalized
    }

    private func update(_ mutate: (inout ModeConfig) -> Void) {
        guard var config else { return }
        mutate(&config)
        modeManager.updateConfiguration(config)
    }

    private func apply(preset: ModePreset) {
        update { config in
            switch preset {
            case .custom:
                let prompt = enhancementService.addPrompt(title: "\(config.name) prompt", promptText: customPromptText.isEmpty ? "Clean up the dictation and fix mistakes." : customPromptText)
                config.selectedPrompt = prompt.id.uuidString
            default:
                config.selectedPrompt = preset.promptId?.uuidString
            }
            switch preset {
            case .message:
                config.s1Styling = S1MiniService.Styling.casual.rawValue
                config.s1Structure = S1MiniService.Structure.prose.rawValue
            case .email:
                config.s1Styling = S1MiniService.Styling.semiFormal.rawValue
                config.s1Structure = S1MiniService.Structure.prose.rawValue
            case .note:
                config.s1Styling = S1MiniService.Styling.semiCasual.rawValue
                config.s1Structure = S1MiniService.Structure.lists.rawValue
            case .voiceToText:
                config.s1Structure = S1MiniService.Structure.prose.rawValue
            case .custom:
                break
            }
            // Picking a formatting preset other than plain voice-to-text implies a language model.
            if preset != .voiceToText, !config.isAIEnhancementEnabled {
                config.isAIEnhancementEnabled = true
                config.selectedAIProvider = AIProvider.s1Mini.rawValue
                config.selectedAIModel = "S1-mini"
                if config.s1Styling == nil { config.s1Styling = S1MiniService.Styling.semiCasual.rawValue }
            }
        }
    }

    private func saveCustomPrompt(_ text: String, config: ModeConfig) {
        guard let raw = config.selectedPrompt, let id = UUID(uuidString: raw),
              let existing = enhancementService.allPrompts.first(where: { $0.id == id }) else { return }
        enhancementService.updatePrompt(CustomPrompt(id: existing.id, title: existing.title, promptText: text, useSystemInstructions: existing.useSystemInstructions))
    }

    private struct TextModelOption: Identifiable {
        let id: String
        let title: String
        let provider: AIProvider
        let model: String?
    }

    private var textModelOptions: [TextModelOption] {
        var options: [TextModelOption] = []
        options.append(TextModelOption(id: "s1mini", title: "S1-mini", provider: .s1Mini, model: "S1-mini"))
        for model in aiService.availableModels(for: .ollama) {
            options.append(TextModelOption(id: "ollama|\(model)", title: "\(model) (Ollama)", provider: .ollama, model: model))
        }
        return options
    }

    private func textModelSelection(_ config: ModeConfig) -> String {
        guard config.isAIEnhancementEnabled else { return "none" }
        if config.selectedAIProvider == AIProvider.ollama.rawValue, let model = config.selectedAIModel {
            return "ollama|\(model)"
        }
        return "s1mini"
    }

    private func apply(textModel id: String) {
        if id == "none" {
            update { config in
                config.isAIEnhancementEnabled = false
            }
            return
        }
        guard let option = textModelOptions.first(where: { $0.id == id }) else { return }
        update { config in
            config.isAIEnhancementEnabled = true
            config.selectedAIProvider = option.provider.rawValue
            config.selectedAIModel = option.model
            if config.selectedPrompt == nil {
                config.selectedPrompt = PromptTemplates.cleanPromptId.uuidString
            }
            if config.s1Styling == nil {
                config.s1Styling = S1MiniService.Styling.semiCasual.rawValue
            }
        }
    }

    private struct LanguageOption { let code: String; let name: String }

    private func languageOptions(_ config: ModeConfig) -> [LanguageOption] {
        let modelName = config.selectedTranscriptionModelName ?? transcriptionModelManager.currentTranscriptionModel?.name
        let model = transcriptionModelManager.allAvailableModels.first { $0.name == modelName }
        var languages = model?.supportedLanguages ?? LanguageDictionary.forProvider(isMultilingual: true)
        let hasAuto = languages["auto"] != nil
        languages["auto"] = nil
        var options = languages.map { LanguageOption(code: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
        _ = hasAuto
        options.insert(LanguageOption(code: "auto", name: "Auto-detect"), at: 0)
        return options
    }

    private func chip(_ title: String, symbol: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11))
            Text(title).font(.system(size: 13)).lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(SpeekDesign.controlFill(scheme)))
    }
}

// MARK: - App / site picker

private struct AppAndSitePicker: View {
    @Environment(\.dismiss) private var dismiss
    let onAddApp: (AppConfig) -> Void
    let onAddURL: (String) -> Void
    @State private var url = ""
    @State private var search = ""

    private struct RunningApp: Identifiable {
        let id: String
        let name: String
        let icon: NSImage?
    }

    private var apps: [RunningApp] {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let bundle = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return RunningApp(id: bundle, name: name, icon: app.icon)
            }
        let unique = Dictionary(grouping: running, by: \.id).compactMap { $0.value.first }.sorted { $0.name < $1.name }
        return search.isEmpty ? unique : unique.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Add apps and sites").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.glassProminent)
            }
            HStack {
                TextField("https://mail.google.com", text: $url)
                    .textFieldStyle(.roundedBorder)
                Button("Add site") {
                    let trimmed = url.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    onAddURL(trimmed)
                    url = ""
                }
                .buttonStyle(.glass)
                .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            TextField("Search running apps", text: $search)
                .textFieldStyle(.roundedBorder)
            List(apps) { app in
                HStack(spacing: 10) {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    }
                    Text(app.name)
                    Spacer()
                    Button("Add") { onAddApp(AppConfig(bundleIdentifier: app.id, appName: app.name)) }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
            .frame(minHeight: 260)
            Button("Choose an app from Finder...") { chooseFromFinder() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
        }
        .padding(20)
        .frame(width: 460, height: 480)
    }

    private func chooseFromFinder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? url.deletingPathExtension().lastPathComponent
            onAddApp(AppConfig(bundleIdentifier: id, appName: name))
        }
    }
}

// MARK: - Flow layout for chips

struct FlowChips<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        FlowLayout(spacing: 8) { content() }
    }
}
