import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import os

@MainActor
class SpeekEngine: NSObject, ObservableObject {
    private enum RecordingUseCase {
        case newSession
        case assistantFollowUp

        var isAssistantFollowUp: Bool {
            self == .assistantFollowUp
        }
    }

    @Published var recordingState: RecordingState = .idle
    @Published var shouldCancelRecording = false
    // Escape-to-cancel UI: first Escape arms the in-panel confirm overlay; the second
    // Escape plays the dissolve + shrink-close before the panel is actually torn down.
    @Published var isCancelConfirming = false
    @Published var isCanceling = false
    @Published var partialTranscript: String = ""
    // Stable already-committed text (won't be rewritten) vs the in-progress tail that
    // streaming providers keep revising. Splitting them lets the widget keep committed
    // text steady and only dim the unstable tail, which kills the "jumping" effect.
    @Published var committedTranscript: String = ""
    @Published var partialTail: String = ""
    // "⌘V to paste" hint shown in the panel when the transcript couldn't be
    // auto-inserted (no editable field focused). See RecorderUIManager.
    @Published var pasteHintText: String? = nil
    @Published var resultPreview: String? = nil
    private static let liveTranscriptPublishInterval: TimeInterval = 1.0 / 20.0
    private var lastLiveTranscriptPublishAt = Date.distantPast
    private var pendingLiveTranscriptUpdate: (committed: String, partial: String)?
    private var liveTranscriptPublishTask: Task<Void, Never>?
    // Set when the recording is committed via Return: forces an Enter auto-send
    // after paste for this delivery only (so the hotkey still just pastes).
    var forceAutoSendOnCommit = false
    var currentSession: TranscriptionSession?
    private var currentSessionTranscriptionConfiguration: TranscriptionRuntimeConfiguration?
    private var activeRecordingStartID: UUID?
    private var activePipelineTranscriptionID: UUID?
    private var canceledPipelineTranscriptionIDs = Set<UUID>()
    private var activeRecordingUseCase: RecordingUseCase = .newSession
    private var activePipelineUseCase: RecordingUseCase = .newSession
    private var activeRecordingContextStore: RecordingContextSnapshotStore?
    private var activeRecordingContextTasks: [Task<Void, Never>] = []

    let recorder = Recorder()
    var recordedFile: URL? = nil
    let recordingsDirectory: URL
    // Mirrors the live transcript to disk so it survives a crash/kill mid-dictation.
    private let transcriptRecovery: TranscriptRecoveryStore

    // Injected managers
    let whisperModelManager: WhisperModelManager
    let transcriptionModelManager: TranscriptionModelManager
    weak var recorderUIManager: RecorderPanelPresenting?

    let modelContext: ModelContext
    internal let serviceRegistry: TranscriptionServiceRegistry
    let enhancementService: AIEnhancementService?
    let assistantSession = AssistantSession()
    let assistantChat: AssistantChatService?
    private let pipeline: TranscriptionPipeline

    let logger = Logger(subsystem: "com.aveekpatra.speek", category: "SpeekEngine")

    init(
        modelContext: ModelContext,
        whisperModelManager: WhisperModelManager,
        transcriptionModelManager: TranscriptionModelManager,
        enhancementService: AIEnhancementService? = nil
    ) {
        self.modelContext = modelContext
        self.whisperModelManager = whisperModelManager
        self.transcriptionModelManager = transcriptionModelManager
        self.enhancementService = enhancementService
        if let aiService = enhancementService?.getAIService() {
            self.assistantChat = AssistantChatService(
                modelContext: modelContext,
                aiService: aiService
            )
        } else {
            self.assistantChat = nil
        }

        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.aveekpatra.speek")
        self.recordingsDirectory = appSupportDirectory.appendingPathComponent("Recordings")
        self.transcriptRecovery = TranscriptRecoveryStore(directory: appSupportDirectory)

        self.serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: whisperModelManager,
            modelsDirectory: whisperModelManager.modelsDirectory,
            modelContext: modelContext
        )
        self.pipeline = TranscriptionPipeline(
            modelContext: modelContext,
            serviceRegistry: serviceRegistry,
            enhancementService: enhancementService
        )

        super.init()

        setupNotifications()
        createRecordingsDirectoryIfNeeded()
        recoverInterruptedTranscriptIfNeeded()
    }

    /// If the previous session was killed/crashed mid-dictation, its live transcript is
    /// still on disk. Recover it into history (and the clipboard) so it's never lost.
    private func recoverInterruptedTranscriptIfNeeded() {
        guard let recovered = transcriptRecovery.recoverPendingText() else { return }

        let transcription = Transcription(
            text: recovered,
            duration: 0,
            modeName: String(localized: "Recovered"),
            modeEmoji: "♻️",
            transcriptionStatus: .completed
        )
        modelContext.insert(transcription)
        try? modelContext.save()
        NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(recovered, forType: .string)

        transcriptRecovery.clear()
        logger.notice("Recovered interrupted transcript (\(recovered.count, privacy: .public) chars) into history + clipboard")
    }

    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("❌ Error creating recordings directory: \(error, privacy: .public)")
        }
    }

    func getEnhancementService() -> AIEnhancementService? {
        return enhancementService
    }

    // MARK: - Toggle Record

    func toggleRecord(modeId: UUID? = nil, isAssistantFollowUp: Bool = false) async {
        if recordingState == .starting {
            await cancelRecording()
            return
        }

        if recordingState == .recording {
            activePipelineUseCase = activeRecordingUseCase
            activeRecordingUseCase = .newSession
            activeRecordingStartID = nil
            cancelPendingLiveTranscriptUpdate()
            partialTranscript = ""
            recordingState = .transcribing
            await recorder.stopRecording()

            if let recordedFile {
                if !shouldCancelRecording {
                    let transcription = makeRecordingTranscription(
                        for: recordedFile,
                        text: "",
                        duration: 0,
                        transcriptionStatus: .pending
                    )
                    modelContext.insert(transcription)
                    try? modelContext.save()
                    NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)

                    await runPipeline(
                        on: transcription,
                        audioURL: recordedFile,
                        contextStore: activeRecordingContextStore
                    )
                } else {
                    await finishActiveRecorderCancellation()
                }
            } else {
                cancelCurrentSession()
                if !shouldCancelRecording {
                    logger.error("❌ No recorded file found after stopping recording")
                }
                recordingState = .idle
                await cleanupResources()
            }
        } else {
            let canContinueAssistantSession = isAssistantFollowUp && assistantSession.canSendFollowUp
            let recordingUseCase: RecordingUseCase = canContinueAssistantSession ? .assistantFollowUp : .newSession

            activePipelineTranscriptionID = nil
            shouldCancelRecording = false
            cancelPendingLiveTranscriptUpdate()
            partialTranscript = ""
            committedTranscript = ""
            partialTail = ""
            activeRecordingUseCase = recordingUseCase
            clearActiveRecordingContext()

            if !recordingUseCase.isAssistantFollowUp {
                assistantSession.reset()
            }

            requestRecordPermission { [self] granted in
                if granted {
                    Task { @MainActor [self] in
                        let startID = UUID()
                        self.activeRecordingStartID = startID
                        let activeModeTask = ActiveWindowService.shared.beginApplyingConfiguration(modeId: modeId) { [weak self] in
                            guard let self else { return false }
                            return self.activeRecordingStartID == startID && !self.shouldCancelRecording
                        }

                        do {
                            let fileName = "\(UUID().uuidString).wav"
                            let permanentURL = self.recordingsDirectory.appendingPathComponent(fileName)
                            self.recordedFile = permanentURL

                            let pendingChunks = OSAllocatedUnfairLock(initialState: [Data]())
                            self.recorder.onAudioChunk = { data in
                                pendingChunks.withLock { $0.append(data) }
                            }

                            self.recordingState = .starting
                            self.recorder.scheduleSystemMute()

                            // Connect to the streaming provider now, in parallel with the
                            // (slower) microphone startup, so the first words appear sooner.
                            // Audio keeps accumulating in pendingChunks until the mode below
                            // is confirmed — if the mode switches the model, a fresh session
                            // gets the full audio from that buffer.
                            var earlyConfiguration: TranscriptionRuntimeConfiguration?
                            var earlyCallback: ((Data) -> Void)?
                            if let configuration = ModeRuntimeResolver.transcriptionConfiguration(
                                transcriptionModelManager: self.transcriptionModelManager
                            ), self.serviceRegistry.shouldUseRealtimeTranscription(for: configuration) {
                                earlyConfiguration = configuration
                                earlyCallback = try await self.makeRealtimeSession(
                                    configuration: configuration,
                                    startID: startID
                                )
                                if let earlyCallback {
                                    self.recorder.onAudioChunk = { data in
                                        pendingChunks.withLock { $0.append(data) }
                                        earlyCallback(data)
                                    }
                                }
                            }

                            try await self.recorder.startRecording(toOutputFile: permanentURL)

                            guard self.activeRecordingStartID == startID,
                                  self.recorderUIManager?.isRecorderPanelVisible ?? false,
                                  !self.shouldCancelRecording else {
                                activeModeTask.cancel()
                                let shouldKeepRecordingFile = self.shouldCancelRecording
                                if self.activeRecordingStartID == startID {
                                    await self.recorder.stopRecording()
                                    self.cancelCurrentSession()
                                    if !shouldKeepRecordingFile {
                                        self.recordedFile = nil
                                    }
                                    self.recordingState = .idle
                                    self.activeRecordingStartID = nil
                                }
                                return
                            }

                            self.recordingState = .recording

                            await activeModeTask.value

                            guard self.recordingState == .recording,
                                  self.activeRecordingStartID == startID,
                                  !self.shouldCancelRecording else {
                                return
                            }

                            self.startRecordingContextCapture()

                            guard let transcriptionConfiguration = ModeRuntimeResolver.transcriptionConfiguration(
                                transcriptionModelManager: self.transcriptionModelManager
                            ) else {
                                NotificationManager.shared.showNotification(title: String(localized: "No AI Model Selected"), type: .error)
                                await self.recorder.stopRecording()
                                self.cancelCurrentSession()
                                try? FileManager.default.removeItem(at: permanentURL)
                                self.recordedFile = nil
                                self.recordingState = .idle
                                self.activeRecordingStartID = nil
                                self.clearActiveRecordingContext()
                                await self.cleanupResources()
                                await self.recorderUIManager?.dismissRecorderPanel()
                                return
                            }

                            if self.serviceRegistry.shouldUseRealtimeTranscription(for: transcriptionConfiguration) {
                                if let earlyConfiguration,
                                   Self.isEquivalentRealtimeConfiguration(earlyConfiguration, transcriptionConfiguration) {
                                    // The early session is already streaming all audio; stop
                                    // keeping the duplicate copy in pendingChunks.
                                    if let earlyCallback {
                                        self.recorder.onAudioChunk = earlyCallback
                                    }
                                    pendingChunks.withLock { $0.removeAll() }
                                } else {
                                    // The applied mode changed the model — replace the early
                                    // session and replay the full audio from the buffer.
                                    self.cancelCurrentSession()
                                    let realCallback = try await self.makeRealtimeSession(
                                        configuration: transcriptionConfiguration,
                                        startID: startID
                                    )

                                    if let realCallback {
                                        self.recorder.onAudioChunk = realCallback
                                        let buffered = pendingChunks.withLock { chunks -> [Data] in
                                            let result = chunks
                                            chunks.removeAll()
                                            return result
                                        }
                                        for chunk in buffered { realCallback(chunk) }
                                    }
                                }
                            } else {
                                self.cancelCurrentSession()
                                self.recorder.onAudioChunk = nil
                                pendingChunks.withLock { $0.removeAll() }
                            }

                            Task { @MainActor [weak self] in
                                guard let self else { return }

                                let currentModel = ModeRuntimeResolver.transcriptionConfiguration(
                                    transcriptionModelManager: self.transcriptionModelManager
                                )?.model

                                if let model = currentModel,
                                   model.provider == .whisper {
                                    if let localWhisperModel = self.whisperModelManager.availableModels.first(where: { $0.name == model.name }),
                                       self.whisperModelManager.whisperContext == nil {
                                        do {
                                            try await self.whisperModelManager.loadModel(localWhisperModel)
                                        } catch {
                                            self.logger.error("❌ Model loading failed: \(error, privacy: .public)")
                                        }
                                    }
                                } else if let fluidAudioModel = currentModel as? FluidAudioModel {
                                    try? await self.serviceRegistry.fluidAudioTranscriptionService.loadModel(for: fluidAudioModel)
                                }

                            }

                        } catch {
                            activeModeTask.cancel()
                            self.logger.error("Recording failed to start: \(error, privacy: .public)")
                            await self.recorder.stopRecording()
                            self.cancelCurrentSession()
                            if let recordedFile = self.recordedFile {
                                try? FileManager.default.removeItem(at: recordedFile)
                            }
                            self.recordingState = .idle
                            self.recordedFile = nil
                            self.activeRecordingStartID = nil
                            self.clearActiveRecordingContext()
                            await self.cleanupResources()
                            NotificationManager.shared.showNotification(title: String(localized: "Recording failed to start"), type: .error)
                            await self.recorderUIManager?.dismissRecorderPanel()
                        }
                    }
                } else {
                    logger.error("Recording permission denied")
                }
            }
        }
    }

    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
        response(true)
    }

    /// Creates + prepares a realtime session and installs it as the current one.
    /// Returns the audio-chunk callback from `prepare` (the socket keeps connecting
    /// in the background).
    private func makeRealtimeSession(
        configuration: TranscriptionRuntimeConfiguration,
        startID: UUID
    ) async throws -> ((Data) -> Void)? {
        let session = serviceRegistry.createSession(
            for: configuration,
            onPartialTranscript: { [weak self] committed, partial in
                Task { @MainActor in
                    guard let self,
                          self.activeRecordingStartID == startID,
                          self.recordingState == .recording else {
                        return
                    }
                    self.scheduleLiveTranscriptUpdate(committed: committed, partial: partial)
                }
            }
        )
        currentSession = session
        currentSessionTranscriptionConfiguration = configuration
        return try await session.prepare(configuration: configuration)
    }

    private static func isEquivalentRealtimeConfiguration(
        _ a: TranscriptionRuntimeConfiguration,
        _ b: TranscriptionRuntimeConfiguration
    ) -> Bool {
        a.model.name == b.model.name &&
        a.model.provider == b.model.provider &&
        a.language == b.language &&
        a.isRealtimeEnabled == b.isRealtimeEnabled
    }

    private func scheduleLiveTranscriptUpdate(committed: String, partial: String) {
        guard recordingState == .recording else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastLiveTranscriptPublishAt)
        if elapsed >= Self.liveTranscriptPublishInterval {
            liveTranscriptPublishTask?.cancel()
            liveTranscriptPublishTask = nil
            pendingLiveTranscriptUpdate = nil
            publishLiveTranscript(committed: committed, partial: partial, now: now)
            return
        }

        pendingLiveTranscriptUpdate = (committed, partial)
        guard liveTranscriptPublishTask == nil else { return }

        let delay = max(0, Self.liveTranscriptPublishInterval - elapsed)
        liveTranscriptPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            self.liveTranscriptPublishTask = nil
            guard let update = self.pendingLiveTranscriptUpdate else { return }
            self.pendingLiveTranscriptUpdate = nil
            self.publishLiveTranscript(committed: update.committed, partial: update.partial, now: Date())
        }
    }

    private func publishLiveTranscript(committed: String, partial: String, now: Date = Date()) {
        guard recordingState == .recording else { return }
        let fullCombined = [committed, partial].filter { !$0.isEmpty }.joined(separator: " ")
        // The panel shows the full text (scrollable) — never a "..."-prefixed window.
        let display = (committed: committed, partial: partial)
        let combined = fullCombined
        transcriptRecovery.update(fullCombined)

        guard committedTranscript != display.committed ||
              partialTail != display.partial ||
              partialTranscript != combined else {
            lastLiveTranscriptPublishAt = now
            return
        }

        committedTranscript = display.committed
        partialTail = display.partial
        partialTranscript = combined
        lastLiveTranscriptPublishAt = now
    }

    private func cancelPendingLiveTranscriptUpdate() {
        liveTranscriptPublishTask?.cancel()
        liveTranscriptPublishTask = nil
        pendingLiveTranscriptUpdate = nil
        lastLiveTranscriptPublishAt = .distantPast
    }

    // MARK: - Recording Context

    private func startRecordingContextCapture() {
        clearActiveRecordingContext()

        let store = RecordingContextSnapshotStore()
        activeRecordingContextStore = store
        activeRecordingContextTasks = RecordingContextCaptureService.startCapture(into: store)
    }

    private func clearActiveRecordingContext() {
        activeRecordingContextTasks.forEach { $0.cancel() }
        activeRecordingContextTasks.removeAll()
        activeRecordingContextStore = nil
    }

    // MARK: - Pipeline Dispatch

    private func runPipeline(
        on transcription: Transcription,
        audioURL: URL,
        contextStore: RecordingContextSnapshotStore?
    ) async {
        guard let transcriptionConfiguration = currentSessionTranscriptionConfiguration ??
            ModeRuntimeResolver.transcriptionConfiguration(transcriptionModelManager: transcriptionModelManager) else {
            transcription.text = String(localized: "Transcription Failed: No model selected")
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
            try? modelContext.save()
            recordingState = .idle
            activePipelineUseCase = .newSession
            return
        }

        let session = currentSession
        let transcriptionID = transcription.id
        activePipelineTranscriptionID = transcriptionID

        await pipeline.run(
            transcription: transcription,
            audioURL: audioURL,
            transcriptionConfiguration: transcriptionConfiguration,
            formattingConfiguration: {
                ModeRuntimeResolver.transcriptionFormattingConfiguration()
            },
            session: session,
            enhancementConfiguration: { [weak self] in
                guard let self,
                      let enhancementService = self.enhancementService,
                      let aiService = enhancementService.getAIService() else {
                    return nil
                }
                return ModeRuntimeResolver.currentEnhancementConfiguration(
                    enhancementService: enhancementService,
                    aiService: aiService
                )
            },
            recordingContextSnapshot: {
                await MainActor.run {
                    contextStore?.snapshot
                }
            },
            outputConfiguration: { [weak self] in
                let config = ModeRuntimeResolver.outputConfiguration()
                // Committed via Return → force Enter auto-send (paste path only).
                if self?.forceAutoSendOnCommit == true, config.outputMode == .paste {
                    return OutputRuntimeConfiguration(
                        mode: config.mode,
                        outputMode: config.outputMode,
                        autoSendKey: .enter,
                        customCommand: config.customCommand
                    )
                }
                return config
            },
            onStateChange: { [weak self] state in
                guard let self, self.activePipelineTranscriptionID == transcriptionID else { return }
                self.recordingState = state
            },
            shouldCancel: { [weak self] in
                guard let self else { return false }
                return self.canceledPipelineTranscriptionIDs.contains(transcriptionID)
                    || (self.activePipelineTranscriptionID == transcriptionID && self.shouldCancelRecording)
            },
            onCancel: { [weak self, session] in
                guard let self else { return }
                self.cancelPipelineSession(transcriptionID: transcriptionID, session: session)
            },
            onDismiss: { [weak self] in
                guard let self, self.activePipelineTranscriptionID == transcriptionID else { return }
                await self.recorderUIManager?.dismissRecorderPanel()
            },
            onPasteHint: { [weak self] text in
                guard let self, self.activePipelineTranscriptionID == transcriptionID else { return }
                await self.recorderUIManager?.dismissRecorderPanelWithPasteHint(text: text)
            },
            assistant: TranscriptionPipeline.AssistantHooks(
                isFollowUp: activePipelineUseCase.isAssistantFollowUp,
                sendFollowUp: { [weak self] text, transcription in
                    guard let self, self.activePipelineTranscriptionID == transcriptionID else { return }
                    await self.sendAssistantFollowUp(text, transcription: transcription)
                },
                startResponse: { [weak self] transcript, configuration in
                    guard let self, self.activePipelineTranscriptionID == transcriptionID else { return }
                    self.assistantSession.beginInitialResponse(
                        transcript: transcript,
                        provider: configuration.provider,
                        modelName: configuration.modelName ?? configuration.provider?.defaultModel,
                        modeName: configuration.mode?.name,
                        modeEmoji: configuration.mode?.icon.value,
                        promptName: configuration.prompt?.title
                    )
                },
                showResponse: { [weak self] response, systemPrompt in
                    guard let self, self.activePipelineTranscriptionID == transcriptionID else { return }
                    await self.completeAssistantResponse(response, systemPrompt: systemPrompt)
                },
                failResponse: { [weak self] message in
                    guard let self, self.activePipelineTranscriptionID == transcriptionID else { return }
                    self.assistantSession.fail(message)
                }
            )
        )

        forceAutoSendOnCommit = false

        let didFinishActivePipeline = activePipelineTranscriptionID == transcriptionID
        if didFinishActivePipeline {
            // Session finished normally — the final text is saved in history, so the
            // crash-recovery copy is no longer needed.
            transcriptRecovery.clear()
            await finishRecorderSession()
            await cleanupResources()
            activePipelineTranscriptionID = nil
            currentSession = nil
            currentSessionTranscriptionConfiguration = nil
            recordedFile = nil
            shouldCancelRecording = false
            activePipelineUseCase = .newSession
            clearActiveRecordingContext()
        }
        canceledPipelineTranscriptionIDs.remove(transcriptionID)

        if didFinishActivePipeline &&
            (recordingState == .transcribing || recordingState == .enhancing || recordingState == .busy) {
            recordingState = .idle
        }
    }

    // MARK: - Cancellation

    func cancelRecording() async {
        // User abandoned the recording — drop the crash-recovery copy too.
        transcriptRecovery.clear()
        let shouldFinishSessionImmediately: Bool
        switch recordingState {
        case .starting, .recording:
            requestRecordingCancellation()
            await finishActiveRecorderCancellation()
            shouldFinishSessionImmediately = true
        case .transcribing, .enhancing:
            requestRecordingCancellation()
            partialTranscript = ""
            committedTranscript = ""
            partialTail = ""
            cancelPendingLiveTranscriptUpdate()
            recordingState = .idle
            shouldFinishSessionImmediately = false
        case .idle, .busy:
            partialTranscript = ""
            committedTranscript = ""
            partialTail = ""
            cancelPendingLiveTranscriptUpdate()
            shouldCancelRecording = false
            recordingState = .idle
            shouldFinishSessionImmediately = true
        }

        if shouldFinishSessionImmediately {
            await finishRecorderSession()
        }
    }

    func resetRecordingSession() async {
        transcriptRecovery.clear()
        cancelCurrentSession()
        activeRecordingStartID = nil
        activePipelineTranscriptionID = nil
        canceledPipelineTranscriptionIDs.removeAll()
        shouldCancelRecording = false
        cancelPendingLiveTranscriptUpdate()
        partialTranscript = ""
        committedTranscript = ""
        partialTail = ""
        assistantSession.reset()
        activeRecordingUseCase = .newSession
        activePipelineUseCase = .newSession
        clearActiveRecordingContext()
        await recorder.stopRecording()
        recordedFile = nil
        recordingState = .idle
        await cleanupResources()
        await finishRecorderSession()
    }

    private func requestRecordingCancellation() {
        shouldCancelRecording = true

        if (recordingState == .transcribing || recordingState == .enhancing),
           let activePipelineTranscriptionID {
            canceledPipelineTranscriptionIDs.insert(activePipelineTranscriptionID)
        }

        cancelCurrentSession()
    }

    private func finishActiveRecorderCancellation() async {
        transcriptRecovery.clear()
        activeRecordingStartID = nil
        clearActiveRecordingContext()
        await recorder.stopRecording()
        await saveCanceledRecording()
        recordedFile = nil
        cancelPendingLiveTranscriptUpdate()
        partialTranscript = ""
        committedTranscript = ""
        partialTail = ""
        recordingState = .idle
        await cleanupResources()
    }

    private func saveCanceledRecording() async {
        guard let recordedFile,
              FileManager.default.fileExists(atPath: recordedFile.path)
        else { return }

        let duration = await AudioFileMetadata.duration(for: recordedFile)
        let transcription = makeRecordingTranscription(
            for: recordedFile,
            text: Transcription.canceledTranscriptionText,
            duration: duration,
            transcriptionStatus: .canceled
        )

        modelContext.insert(transcription)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
        } catch {
            logger.error("Failed to save canceled recording: \(error, privacy: .public)")
        }
    }

    private func makeRecordingTranscription(
        for audioURL: URL,
        text: String,
        duration: TimeInterval,
        transcriptionStatus: TranscriptionStatus
    ) -> Transcription {
        let modeMetadata = currentModeMetadata()

        return Transcription(
            text: text,
            duration: duration,
            audioFileURL: audioURL.absoluteString,
            transcriptionModelName: ModeRuntimeResolver.transcriptionConfiguration(
                transcriptionModelManager: transcriptionModelManager
            )?.model.displayName,
            modeName: modeMetadata.name,
            modeEmoji: modeMetadata.emoji,
            transcriptionStatus: transcriptionStatus
        )
    }

    private func currentModeMetadata() -> (name: String?, emoji: String?) {
        guard let mode = ModeManager.shared.currentEffectiveConfiguration,
              mode.isEnabled else {
            return (nil, nil)
        }

        return (mode.name, mode.icon.value)
    }

    // MARK: - Resource Cleanup

    private func cancelPipelineSession(transcriptionID: UUID, session: TranscriptionSession?) {
        session?.cancel()

        guard activePipelineTranscriptionID == transcriptionID else {
            logger.notice("Skipping stale pipeline cleanup")
            return
        }

        currentSession = nil
        currentSessionTranscriptionConfiguration = nil
    }

    private func cancelCurrentSession() {
        currentSession?.cancel()
        currentSession = nil
        currentSessionTranscriptionConfiguration = nil
    }

    private func finishRecorderSession() async {
        enhancementService?.clearCapturedContexts()
    }

    func cleanupResources() async {
        logger.notice("cleanupResources: releasing model resources")
        activeRecordingStartID = nil
        activeRecordingUseCase = .newSession
        await whisperModelManager.cleanupResources()
        await serviceRegistry.cleanup()
        logger.notice("cleanupResources: completed")
    }

    // MARK: - Notification Handling

    func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePromptChange),
            name: .promptDidChange,
            object: nil
        )
    }

    @objc func handlePromptChange() {
        Task {
            let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt")
                ?? whisperModelManager.whisperPrompt.transcriptionPrompt
            if let context = whisperModelManager.whisperContext {
                await context.setPrompt(currentPrompt)
            }
        }
    }
}

enum AudioFileMetadata {
    static func duration(for url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : 0
    }
}
