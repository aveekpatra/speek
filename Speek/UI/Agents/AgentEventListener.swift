import Foundation
import os

/// Receives agent events over a named pipe instead of a speek:// URL. Opening a URL
/// goes through Launch Services, which also "reopens" the app and lets SwiftUI present
/// a window; both pull the user to another Space. A pipe involves neither: the hook
/// writes one URL per line to `/tmp/speek-agent/events`, Speek reads it here.
@MainActor
final class AgentEventListener {
    static let shared = AgentEventListener()
    static let pipePath = "/tmp/speek-agent/events"

    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "AgentEventListener")
    private var source: DispatchSourceRead?
    private var fd: Int32 = -1
    private var buffer = Data()

    private init() {}

    func start() {
        guard source == nil else { return }
        let dir = (Self.pipePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var info = stat()
        if stat(Self.pipePath, &info) != 0 || (info.st_mode & S_IFMT) != S_IFIFO {
            unlink(Self.pipePath)
            guard mkfifo(Self.pipePath, 0o622) == 0 else {
                logger.error("Could not create the agent event pipe: \(String(cString: strerror(errno)), privacy: .public)")
                return
            }
        }
        chmod(Self.pipePath, 0o622)
        // O_RDWR keeps a writer alive on our side, so the pipe never reports EOF between
        // hook invocations and the read source only fires when a line is waiting.
        fd = open(Self.pipePath, O_RDWR | O_NONBLOCK)
        guard fd >= 0 else {
            logger.error("Could not open the agent event pipe: \(String(cString: strerror(errno)), privacy: .public)")
            return
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.drain() }
        source.resume()
        self.source = source
        logger.notice("Listening for agent events on \(Self.pipePath, privacy: .public)")
    }

    private func drain() {
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count > 0 {
                buffer.append(contentsOf: chunk[0..<count])
            } else {
                break
            }
        }
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty, let url = URL(string: line) else { continue }
            _ = AgentUpdateCenter.shared.handle(url: url)
        }
    }
}
