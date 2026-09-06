import Foundation
import SwiftData
import os

/// Sendable source that bridges audio chunks from any thread into an AsyncStream.
private final class AudioChunkSource: @unchecked Sendable {
    private struct DropStats {
        var chunks = 0
        var bytes = 0
    }

    private static let targetChunkBytes = 3_200 // 100ms of 16kHz PCM16 mono
    // Must cover a slow WebSocket connect (seconds of audio arrive before the send
    // loop starts) plus network hiccups. Dropping here forces the slow whole-file
    // batch fallback at stop, so the cap is generous: 60s of audio ≈ 1.9 MB.
    private static let maxQueuedChunks = 600

    let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var pendingChunk = Data()
    private var queuedChunks: [Data] = []
    private var isFinished = false
    private var dropStats = DropStats()

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        self.stream = stream
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    func send(_ data: Data) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }

        pendingChunk.append(data)
        let shouldFlush = pendingChunk.count >= Self.targetChunkBytes
        if shouldFlush {
            enqueuePendingChunkLocked()
        }
        lock.unlock()

        if shouldFlush {
            continuation.yield(())
        }
    }

    func finish() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let hasPendingChunk = !pendingChunk.isEmpty
        if hasPendingChunk {
            enqueuePendingChunkLocked()
        }
        lock.unlock()

        if hasPendingChunk {
            continuation.yield(())
        }
        continuation.finish()
    }

    func nextChunk() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard !queuedChunks.isEmpty else { return nil }
        return queuedChunks.removeFirst()
    }

    var hasDroppedAudio: Bool {
        lock.lock()
        defer { lock.unlock() }
        return dropStats.chunks > 0
    }

    func dropSnapshot() -> (chunks: Int, bytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (dropStats.chunks, dropStats.bytes)
    }

    private func enqueuePendingChunkLocked() {
        guard !pendingChunk.isEmpty else { return }
        queuedChunks.append(pendingChunk)
        pendingChunk.removeAll(keepingCapacity: true)

        while queuedChunks.count > Self.maxQueuedChunks {
            let dropped = queuedChunks.removeFirst()
            dropStats.chunks += 1
            dropStats.bytes += dropped.count
        }
    }
}

private final class StreamingMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var receivedChunks = 0
    private var receivedBytes = 0
    private var sentChunks = 0
    private var sentBytes = 0

    func reset() {
        lock.lock()
        receivedChunks = 0
        receivedBytes = 0
        sentChunks = 0
        sentBytes = 0
        lock.unlock()
    }

    func recordReceived(_ byteCount: Int) {
        lock.lock()
        receivedChunks += 1
        receivedBytes += byteCount
        lock.unlock()
    }

    func recordSent(_ byteCount: Int) {
        lock.lock()
        sentChunks += 1
        sentBytes += byteCount
        lock.unlock()
    }

    func snapshot() -> (receivedChunks: Int, receivedBytes: Int, sentChunks: Int, sentBytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (receivedChunks, receivedBytes, sentChunks, sentBytes)
    }
}

/// Lifecycle states for a streaming transcription session.
enum StreamingState {
    case idle
    case connecting
    case streaming
    case committing
    case done
    case failed
    case cancelled
}

/// Manages a streaming transcription lifecycle: buffers audio chunks, sends them to the provider, and collects the final text.
@MainActor
class StreamingTranscriptionService {

    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "StreamingTranscriptionService")
    private var provider: StreamingTranscriptionProvider?
    private var sendTask: Task<Void, Never>?
    private var eventConsumerTask: Task<Void, Never>?
    private let chunkSource = AudioChunkSource()
    private var state: StreamingState = .idle
    private var committedSegments: [String] = []
    private var committedTextCache = ""
    // Last cumulative partial within the current (uncommitted) segment, used to
    // detect which words have stabilised so the live preview can show them solid.
    private var lastSegmentPartial: String = ""
    private let modelContext: ModelContext
    private let fluidAudioService: FluidAudioTranscriptionService?
    // (committedText, partialTail): committed stays stable, tail is the revising part.
    private var onPartialTranscript: ((String, String) -> Void)?
    private let metrics = StreamingMetrics()
    private var stopStartedAt: Date?
    private var firstPartialLogged = false
    private var firstCommitLogged = false

    init(modelContext: ModelContext, fluidAudioService: FluidAudioTranscriptionService? = nil, onPartialTranscript: ((String, String) -> Void)? = nil) {
        self.modelContext = modelContext
        self.fluidAudioService = fluidAudioService
        self.onPartialTranscript = onPartialTranscript
    }

    deinit {
        onPartialTranscript = nil
        sendTask?.cancel()
        eventConsumerTask?.cancel()
        chunkSource.finish()
        commitSignal?.finish()
    }

    /// Signal used to notify `waitForFinalCommit` when a new committed segment arrives.
    private var commitSignal: AsyncStream<Void>.Continuation?

    /// Whether the streaming connection is fully established and actively sending.
    var isActive: Bool { state == .streaming || state == .committing }

    var hasDroppedAudio: Bool { chunkSource.hasDroppedAudio }

    /// Start a streaming transcription session for the given model.
    func startStreaming(model: any TranscriptionModel, context: TranscriptionRequestContext) async throws {
        let start = Date()
        state = .connecting
        committedSegments = []
        committedTextCache = ""
        lastSegmentPartial = ""
        metrics.reset()
        firstPartialLogged = false
        firstCommitLogged = false

        let provider = createProvider(for: model)
        self.provider = provider

        let selectedLanguage = context.language ?? "auto"
        logger.notice("Streaming start requested model=\(model.displayName, privacy: .public) language=\(selectedLanguage, privacy: .public)")

        try await provider.connect(model: model, language: selectedLanguage)

        // If cancel() was called while we were awaiting the connection, tear down immediately.
        if state == .cancelled {
            await provider.disconnect()
            self.provider = nil
            return
        }

        state = .streaming
        startSendLoop()
        startEventConsumer()

        logger.notice("Streaming connected model=\(model.displayName, privacy: .public) elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s")
    }

    /// Buffers an audio chunk for sending. Safe to call from the audio callback thread.
    nonisolated func sendAudioChunk(_ data: Data) {
        metrics.recordReceived(data.count)
        chunkSource.send(data)
    }

    /// Stops streaming, commits remaining audio, and returns the final transcribed text.
    func stopAndGetFinalText() async throws -> String {
        guard let provider = provider, state == .streaming else {
            throw StreamingTranscriptionError.notConnected
        }

        state = .committing
        stopStartedAt = Date()
        let beforeDrain = metrics.snapshot()
        logger.notice("Streaming stop requested receivedChunks=\(beforeDrain.receivedChunks, privacy: .public) sentChunks=\(beforeDrain.sentChunks, privacy: .public) receivedBytes=\(beforeDrain.receivedBytes, privacy: .public) sentBytes=\(beforeDrain.sentBytes, privacy: .public)")

        // Finish the chunk source so the send loop drains remaining chunks and exits naturally.
        await drainRemainingChunks()

        // Set up the commit signal BEFORE sending commit to avoid a race with the response.
        let (signalStream, signalContinuation) = AsyncStream.makeStream(of: Void.self)
        self.commitSignal = signalContinuation

        // Send commit to finalize any remaining audio
        do {
            try await provider.commit()
        } catch {
            commitSignal?.finish()
            commitSignal = nil
            logger.error("Failed to send commit: \(error, privacy: .public)")
            state = .failed
            await cleanupStreaming()
            throw error
        }

        // Wait for the server to acknowledge our commit (or timeout)
        let finalText = await waitForFinalCommit(signalStream: signalStream)
        if let stopStartedAt {
            logger.notice("Streaming stop completed elapsed=\(Date().timeIntervalSince(stopStartedAt), format: .fixed(precision: 3), privacy: .public)s finalChars=\(finalText.count, privacy: .public)")
        }

        state = .done
        await cleanupStreaming()

        return finalText
    }

    /// Cancels the streaming session without waiting for results.
    func cancel() {
        state = .cancelled
        onPartialTranscript = nil
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
        sendTask?.cancel()
        sendTask = nil
        chunkSource.finish()

        // Clean up commit signal if waiting
        commitSignal?.finish()
        commitSignal = nil

        let providerToDisconnect = provider
        provider = nil

        Task {
            await providerToDisconnect?.disconnect()
        }

        committedSegments = []
        committedTextCache = ""
        lastSegmentPartial = ""
        logger.notice("Streaming cancelled")
    }

    // MARK: - Private

    /// Longest common prefix of two cumulative partials, cut back to the last
    /// whitespace on a genuine mid-word divergence so a half-formed word stays in
    /// the dim tail instead of flickering solid.
    private static func stableCommonPrefix(_ a: String, _ b: String) -> String {
        var aIndex = a.startIndex
        var bIndex = b.startIndex
        var lastWhitespaceInB = b.startIndex

        while aIndex < a.endIndex, bIndex < b.endIndex, a[aIndex] == b[bIndex] {
            if b[bIndex].isWhitespace {
                lastWhitespaceInB = b.index(after: bIndex)
            }
            a.formIndex(after: &aIndex)
            b.formIndex(after: &bIndex)
        }

        var cut = bIndex
        // Only back off when both strings have a differing character here (mid-word
        // change). If one is simply a prefix of the other, keep the full overlap.
        if aIndex < a.endIndex, bIndex < b.endIndex {
            cut = lastWhitespaceInB
        }
        return String(b[..<cut])
    }

    private func createProvider(for model: any TranscriptionModel) -> StreamingTranscriptionProvider {
        if model.provider == .fluidAudio {
            guard let fluidAudioService else {
                fatalError("FluidAudioTranscriptionService required for FluidAudio streaming. Ensure it is passed to StreamingTranscriptionService.")
            }
            return FluidAudioStreamingProvider(fluidAudioService: fluidAudioService)
        }
        fatalError("Unsupported streaming provider: \(model.provider). Check shouldUseRealtimeTranscription() before calling startStreaming().")
    }

    /// Consumes audio chunks from the AsyncStream and sends them to the provider.
    private func startSendLoop() {
        let source = chunkSource
        let provider = provider
        let metrics = metrics

        sendTask = Task.detached { [weak self] in
            for await _ in source.stream {
                await Self.sendQueuedChunks(from: source, to: provider, metrics: metrics, owner: self)
            }

            await Self.sendQueuedChunks(from: source, to: provider, metrics: metrics, owner: self)
        }
    }

    private nonisolated static func sendQueuedChunks(
        from source: AudioChunkSource,
        to provider: StreamingTranscriptionProvider?,
        metrics: StreamingMetrics,
        owner: StreamingTranscriptionService?
    ) async {
        while let chunk = source.nextChunk() {
            do {
                try await provider?.sendAudioChunk(chunk)
                metrics.recordSent(chunk.count)
            } catch {
                let desc = error.localizedDescription
                await MainActor.run {
                    owner?.logger.error("Failed to send audio chunk: \(desc, privacy: .public)")
                }
            }
        }
    }

    /// Finishes the chunk source and waits for the send loop to process all remaining buffered chunks.
    private func drainRemainingChunks() async {
        let start = Date()
        chunkSource.finish()
        await sendTask?.value
        sendTask = nil
        let snapshot = metrics.snapshot()
        let drops = chunkSource.dropSnapshot()
        logger.notice("Streaming drain finished elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s receivedChunks=\(snapshot.receivedChunks, privacy: .public) sentChunks=\(snapshot.sentChunks, privacy: .public) receivedBytes=\(snapshot.receivedBytes, privacy: .public) sentBytes=\(snapshot.sentBytes, privacy: .public) droppedChunks=\(drops.chunks, privacy: .public) droppedBytes=\(drops.bytes, privacy: .public)")
    }

    /// Consumes transcription events throughout the session, accumulating committed segments.
    private func startEventConsumer() {
        guard let provider = provider else { return }
        let events = provider.transcriptionEvents

        eventConsumerTask = Task.detached { [weak self] in
            for await event in events {
                guard let self = self else { break }
                switch event {
                case .committed(let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        if !self.firstCommitLogged {
                            self.firstCommitLogged = true
                            let elapsed = self.stopStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                            self.logger.notice("Streaming first committed event chars=\(trimmed.count, privacy: .public) stopElapsed=\(elapsed, format: .fixed(precision: 3), privacy: .public)s")
                        }
                        if !trimmed.isEmpty {
                            self.committedSegments.append(trimmed)
                            self.committedTextCache = self.committedTextCache.isEmpty
                                ? trimmed
                                : self.committedTextCache + " " + trimmed
                        }
                        // A segment finalised; the next partial starts a fresh segment.
                        self.lastSegmentPartial = ""
                        // Refresh the live preview so it keeps showing the full running transcript
                        // after a commit (instead of resetting to empty until the next partial).
                        if self.state == .streaming {
                            // Everything just got committed; no unstable tail remains.
                            self.onPartialTranscript?(self.committedTextCache, "")
                        }
                        if self.state == .committing {
                            self.commitSignal?.yield()
                        }
                    }
                case .partial(let text):
                    await MainActor.run {
                        if !self.firstPartialLogged {
                            self.firstPartialLogged = true
                            self.logger.notice("Streaming first partial event chars=\(text.count, privacy: .public)")
                        }
                        if self.state == .committing {
                            // The server keeps transcribing the tail audio after our
                            // finalize request. Track it so a commit-ack timeout still
                            // delivers the words spoken right before stop.
                            self.lastSegmentPartial = text
                        }
                        if self.state == .streaming {
                            // Already-committed whole segments are always stable (solid).
                            let committedPrefix = self.committedTextCache
                            // Within the current segment, the part of the cumulative partial that
                            // stayed identical since the previous partial has stabilised → solid.
                            // The revising remainder is the dim tail. (Soniox keeps finalised
                            // tokens fixed, so this tracks `is_final` without needing the flag.)
                            let stable = Self.stableCommonPrefix(self.lastSegmentPartial, text)
                            self.lastSegmentPartial = text
                            let tail = String(text.dropFirst(stable.count))

                            let committed = [committedPrefix, stable.trimmingCharacters(in: .whitespaces)]
                                .filter { !$0.isEmpty }
                                .joined(separator: " ")
                            // Preserve the tail's LEADING whitespace — it encodes whether the
                            // dim tail continues the current word ("kdy"+"ž" → no space) or
                            // starts a new one ("slovo"+" další" → leading space). Trimming it
                            // glued every word together. Only clean the trailing edge.
                            var cleanTail = tail
                            while let last = cleanTail.last, last.isWhitespace { cleanTail.removeLast() }
                            self.onPartialTranscript?(committed, cleanTail)
                        }
                    }
                case .sessionStarted:
                    break
                case .error(let error):
                    await MainActor.run {
                        self.logger.error("Streaming event error: \(error, privacy: .public)")
                    }
                }
            }  
        }
    }

    /// How long to wait for the server's final-commit ack before delivering the text we
    /// already have. The server needs a moment to finalize the tail audio after commit —
    /// too short a bound truncated the last words when server finalization latency spiked
    /// (observed 0.17s-2s+ in production logs). This is a worst-case ceiling, not a fixed
    /// delay: `waitForFinalCommit` races the ack against this timeout and returns the
    /// instant the ack arrives, so the normal case (ack in well under a second) is
    /// unaffected — only a genuinely slow finalize eats into the full 6s.
    private static let finalCommitTimeout: UInt64 = 6_000_000_000 // 6s

    /// Waits (briefly) for the server to acknowledge our explicit commit, then returns the
    /// best transcript available. On timeout it falls back to the locally-known text
    /// (committed segments + the still-dim partial tail) rather than blocking or dropping
    /// the last word.
    private func waitForFinalCommit(signalStream: AsyncStream<Void>) async -> String {
        // Race: wait for commit acknowledgment vs a short timeout
        let receivedInTime = await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                for await _ in signalStream {
                    return true
                }
                return false
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: Self.finalCommitTimeout)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        logger.notice("Streaming final wait finished received=\(receivedInTime, privacy: .public) segments=\(self.committedSegments.count, privacy: .public)")

        // Clean up the signal
        commitSignal?.finish()
        commitSignal = nil

        // When the server acked in time, committedSegments holds the finalized text.
        // Otherwise include the last partial tail so we don't lose the final word(s).
        var parts = committedSegments
        if !receivedInTime {
            if !lastSegmentPartial.isEmpty {
                parts.append(lastSegmentPartial)
            }
            let fallbackChars = parts.joined(separator: " ").count
            let timeoutSeconds = Double(Self.finalCommitTimeout) / 1_000_000_000
            logger.warning("Streaming commit ack TIMEOUT after \(timeoutSeconds, format: .fixed(precision: 1), privacy: .public)s — delivering partial fallback chars=\(fallbackChars, privacy: .public)")
        }
        if parts.isEmpty {
            logger.warning("No transcript received from streaming")
            return ""
        }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanupStreaming() async {
        onPartialTranscript = nil
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
        sendTask?.cancel()
        sendTask = nil
        chunkSource.finish()
        commitSignal?.finish()
        commitSignal = nil
        await provider?.disconnect()
        provider = nil
        state = .idle
        committedSegments = []
        committedTextCache = ""
        lastSegmentPartial = ""
    }
}
