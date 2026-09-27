import Foundation
import SQLite3
import CryptoKit

/// What a memory is. Profile entries are locked: always recalled, and only the user changes them.
enum MemoryKind: String, CaseIterable, Sendable { case profile, fact, episode, procedure }

/// One stored memory. The same shape is planned for the shared Cloudflare store (D1 is SQLite),
/// so ids are UUIDs, times are Unix milliseconds, and deletions are tombstones that can sync.
struct MemoryRecord: Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: MemoryKind
    /// Procedure title, or the request of an episode.
    var title: String?
    /// Fact text, procedure steps, or the result of an episode.
    var body: String
    /// Where it came from: speek, openclaw, phone, import.
    var source = "speek"
    /// user (said "remember" or wrote it), agent (proposed by the assistant), observed (an episode).
    var origin = "user"
    var threadID: UUID?
    var createdAt = Date()
    var updatedAt = Date()
    var lastRecalledAt: Date?
    var recallCount = 0
}

enum MemoryStoreError: LocalizedError {
    case sqlite(String)
    var errorDescription: String? { if case .sqlite(let message) = self { return "Memory database: " + message }; return nil }
}

/// SQLite storage for memory: one table of memories, a full-text index kept in step by triggers,
/// and one embedding per memory for search by meaning.
final class MemoryDatabase {
    static let schemaVersion = 1
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw MemoryStoreError.sqlite(db.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open")
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try execute("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 2000;")
        try migrate()
    }

    deinit { sqlite3_close_v2(db) }

    private func migrate() throws {
        var version = 0
        try query("PRAGMA user_version") { version = Int(sqlite3_column_int($0, 0)) }
        guard version < Self.schemaVersion else { return }
        try execute("""
        BEGIN;
        CREATE TABLE IF NOT EXISTS memories (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL CHECK (kind IN ('profile', 'fact', 'episode', 'procedure')),
            title TEXT,
            body TEXT NOT NULL CHECK (length(body) > 0),
            source TEXT NOT NULL DEFAULT 'speek',
            origin TEXT NOT NULL DEFAULT 'user' CHECK (origin IN ('user', 'agent', 'observed')),
            thread_id TEXT,
            content_hash TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            last_recalled_at INTEGER,
            recall_count INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER
        );
        CREATE INDEX IF NOT EXISTS memories_live ON memories (kind, updated_at DESC) WHERE deleted_at IS NULL;
        CREATE UNIQUE INDEX IF NOT EXISTS memories_unique ON memories (kind, content_hash) WHERE deleted_at IS NULL;
        CREATE INDEX IF NOT EXISTS memories_changes ON memories (updated_at);
        CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5 (
            title, body, content = 'memories', content_rowid = 'rowid', tokenize = 'porter unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories WHEN new.deleted_at IS NULL BEGIN
            INSERT INTO memories_fts (rowid, title, body) VALUES (new.rowid, new.title, new.body);
        END;
        CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories WHEN old.deleted_at IS NULL BEGIN
            INSERT INTO memories_fts (memories_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body);
        END;
        CREATE TRIGGER IF NOT EXISTS memories_au_old AFTER UPDATE OF title, body, deleted_at ON memories WHEN old.deleted_at IS NULL BEGIN
            INSERT INTO memories_fts (memories_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body);
        END;
        CREATE TRIGGER IF NOT EXISTS memories_au_new AFTER UPDATE OF title, body, deleted_at ON memories WHEN new.deleted_at IS NULL BEGIN
            INSERT INTO memories_fts (rowid, title, body) VALUES (new.rowid, new.title, new.body);
        END;
        CREATE TABLE IF NOT EXISTS embeddings (
            memory_id TEXT PRIMARY KEY REFERENCES memories (id) ON DELETE CASCADE,
            model TEXT NOT NULL,
            dimensions INTEGER NOT NULL,
            content_hash TEXT NOT NULL,
            vector BLOB NOT NULL
        );
        PRAGMA user_version = \(Self.schemaVersion);
        COMMIT;
        """)
    }

    // MARK: Writes

    /// Inserts or updates by id. Returns false when the same text already exists for this kind.
    @discardableResult
    func upsert(_ record: MemoryRecord) throws -> Bool {
        let hash = Self.hash(record.title, record.body)
        var duplicate = false
        try query("SELECT id FROM memories WHERE kind = ? AND content_hash = ? AND deleted_at IS NULL AND id <> ?",
                  [record.kind.rawValue, hash, record.id.uuidString]) { _ in duplicate = true }
        guard !duplicate else { return false }
        try run("""
        INSERT INTO memories (id, kind, title, body, source, origin, thread_id, content_hash, created_at, updated_at, last_recalled_at, recall_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET kind = excluded.kind, title = excluded.title, body = excluded.body,
            content_hash = excluded.content_hash, updated_at = excluded.updated_at, deleted_at = NULL
        """, [record.id.uuidString, record.kind.rawValue, record.title, record.body, record.source, record.origin,
              record.threadID?.uuidString, hash, Self.ms(record.createdAt), Self.ms(record.updatedAt),
              record.lastRecalledAt.map(Self.ms), record.recallCount])
        return true
    }

    /// Tombstones the memory so a later sync can delete it elsewhere; its embedding is removed.
    func delete(_ id: UUID) throws {
        try run("UPDATE memories SET deleted_at = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL", [Self.ms(Date()), Self.ms(Date()), id.uuidString])
        try run("DELETE FROM embeddings WHERE memory_id = ?", [id.uuidString])
    }

    func markRecalled(_ ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        for id in ids { try run("UPDATE memories SET last_recalled_at = ?, recall_count = recall_count + 1 WHERE id = ?", [Self.ms(Date()), id.uuidString]) }
    }

    /// Keeps the newest episodes; older ones are tombstoned.
    func pruneEpisodes(keeping limit: Int) throws {
        try run("""
        UPDATE memories SET deleted_at = ?, updated_at = ? WHERE kind = 'episode' AND deleted_at IS NULL AND id NOT IN
            (SELECT id FROM memories WHERE kind = 'episode' AND deleted_at IS NULL ORDER BY created_at DESC LIMIT ?)
        """, [Self.ms(Date()), Self.ms(Date()), limit])
        try run("DELETE FROM embeddings WHERE memory_id IN (SELECT id FROM memories WHERE deleted_at IS NOT NULL)")
    }

    func setEmbedding(_ id: UUID, model: String, hash: String, vector: [Float]) throws {
        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        try run("INSERT OR REPLACE INTO embeddings (memory_id, model, dimensions, content_hash, vector) VALUES (?, ?, ?, ?, ?)",
                [id.uuidString, model, vector.count, hash, data])
    }

    // MARK: Reads

    func all(_ kinds: [MemoryKind]) throws -> [MemoryRecord] {
        var rows: [MemoryRecord] = []
        let marks = kinds.map { _ in "?" }.joined(separator: ",")
        try query("""
        SELECT id, kind, title, body, source, origin, thread_id, created_at, updated_at, last_recalled_at, recall_count
        FROM memories WHERE deleted_at IS NULL AND kind IN (\(marks)) ORDER BY updated_at DESC
        """, kinds.map(\.rawValue)) { rows.append(Self.record($0)) }
        return rows
    }

    /// Full-text matches, best first, with BM25 (the title counts double).
    func search(_ text: String, kinds: [MemoryKind], limit: Int) throws -> [UUID] {
        guard let match = Self.matchExpression(text) else { return [] }
        var ids: [UUID] = []
        let marks = kinds.map { _ in "?" }.joined(separator: ",")
        try query("""
        SELECT m.id FROM memories_fts JOIN memories m ON m.rowid = memories_fts.rowid
        WHERE memories_fts MATCH ? AND m.deleted_at IS NULL AND m.kind IN (\(marks))
        ORDER BY bm25(memories_fts, 2.0, 1.0) LIMIT ?
        """, [match] + kinds.map(\.rawValue) + [limit]) { statement in
            if let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) { ids.append(id) }
        }
        return ids
    }

    /// Stored vectors for live memories of these kinds made by this model.
    func vectors(model: String, kinds: [MemoryKind]) throws -> [(UUID, [Float])] {
        var rows: [(UUID, [Float])] = []
        let marks = kinds.map { _ in "?" }.joined(separator: ",")
        try query("""
        SELECT e.memory_id, e.vector FROM embeddings e JOIN memories m ON m.id = e.memory_id
        WHERE e.model = ? AND e.content_hash = m.content_hash AND m.deleted_at IS NULL AND m.kind IN (\(marks))
        """, [model] + kinds.map(\.rawValue)) { statement in
            guard let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))),
                  let bytes = sqlite3_column_blob(statement, 1) else { return }
            let count = Int(sqlite3_column_bytes(statement, 1)) / MemoryLayout<Float>.size
            rows.append((id, Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: Float.self), count: count))))
        }
        return rows
    }

    /// Live memories that have no current embedding from this model.
    func missingEmbeddings(model: String) throws -> [(UUID, String, String)] {
        var rows: [(UUID, String, String)] = []
        try query("""
        SELECT m.id, coalesce(m.title || '. ', '') || m.body, m.content_hash FROM memories m
        LEFT JOIN embeddings e ON e.memory_id = m.id AND e.model = ? AND e.content_hash = m.content_hash
        WHERE m.deleted_at IS NULL AND e.memory_id IS NULL
        """, [model]) { statement in
            if let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) {
                rows.append((id, String(cString: sqlite3_column_text(statement, 1)), String(cString: sqlite3_column_text(statement, 2))))
            }
        }
        return rows
    }

    // MARK: Helpers

    static func hash(_ title: String?, _ body: String) -> String {
        let normalized = ((title.map { $0 + "\n" } ?? "") + body).lowercased()
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return SHA256.hash(data: Data(normalized.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Words as prefix terms joined by OR, so "coffee" finds "coffee" and "coffees".
    /// Quotes keep FTS5 syntax characters in the user's words from being read as operators.
    static func matchExpression(_ text: String) -> String? {
        let stop: Set<String> = ["the", "and", "for", "you", "your", "that", "this", "with", "from", "have", "what", "when", "where",
                                 "who", "how", "about", "please", "can", "could", "would", "should", "my", "me", "is", "are", "was",
                                 "do", "does", "did", "to", "of", "in", "on", "at", "a", "an", "it", "i"]
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { ($0.count > 1 || $0.allSatisfy(\.isNumber)) && !stop.contains($0) }
        guard !words.isEmpty else { return nil }
        return Array(Set(words)).sorted().prefix(24).map { "\"\($0)\"*" }.joined(separator: " OR ")
    }

    static func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    private static func date(_ statement: OpaquePointer, _ column: Int32) -> Date? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, column)) / 1000)
    }
    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, column))
    }
    private static func record(_ s: OpaquePointer) -> MemoryRecord {
        MemoryRecord(id: UUID(uuidString: text(s, 0) ?? "") ?? UUID(), kind: MemoryKind(rawValue: text(s, 1) ?? "") ?? .fact,
                     title: text(s, 2), body: text(s, 3) ?? "", source: text(s, 4) ?? "speek", origin: text(s, 5) ?? "user",
                     threadID: text(s, 6).flatMap(UUID.init(uuidString:)), createdAt: date(s, 7) ?? Date(), updatedAt: date(s, 8) ?? Date(),
                     lastRecalledAt: date(s, 9), recallCount: Int(sqlite3_column_int(s, 10)))
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw MemoryStoreError.sqlite(message)
        }
    }

    private func prepare(_ sql: String, _ values: [Any?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MemoryStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case nil: sqlite3_bind_null(statement, index)
            case let text as String: sqlite3_bind_text(statement, index, text, -1, transient)
            case let number as Int: sqlite3_bind_int64(statement, index, Int64(number))
            case let number as Int64: sqlite3_bind_int64(statement, index, number)
            case let data as Data: _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
            default: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func run(_ sql: String, _ values: [Any?] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw MemoryStoreError.sqlite(String(cString: sqlite3_errmsg(db))) }
    }

    private func query(_ sql: String, _ values: [Any?] = [], row: (OpaquePointer) -> Void) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW { row(statement) } else if result == SQLITE_DONE { break }
            else { throw MemoryStoreError.sqlite(String(cString: sqlite3_errmsg(db))) }
        }
    }
}

/// Turns text into vectors for search by meaning. The model name is stored with every vector,
/// so switching models (for example to the shared store's embeddings) re-embeds instead of mixing.
protocol MemoryEmbedder: AnyObject, Sendable {
    var model: String { get }
    func vectors(for texts: [String]) async throws -> [[Float]]
}

/// OpenAI's text-embedding-3-small (768 dimensions), through OpenRouter or OpenAI with the key
/// Speek already uses. Apple's on-device embedding was measured and added nothing over word
/// search (docs/CLAUDE_HANDOFF.md), so meaning-based recall uses this model. The same memory
/// text already goes to that provider in prompts, so this sends nothing new.
final class CloudMemoryEmbedder: MemoryEmbedder, @unchecked Sendable {
    /// Endpoint, key, and model name for the provider in use; nil when none is configured.
    typealias Credentials = @Sendable () -> (endpoint: URL, key: String, model: String)?
    let model = "text-embedding-3-small@768"
    private let credentials: Credentials
    private let session: URLSession

    init(credentials: @escaping Credentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    func vectors(for texts: [String]) async throws -> [[Float]] {
        guard let (endpoint, key, name) = credentials() else { throw MemoryStoreError.sqlite("no embedding provider is configured") }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = texts.count == 1 ? 4 : 30
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": name, "input": texts.map { String($0.prefix(6000)) }, "dimensions": 768])
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            throw MemoryStoreError.sqlite("the embedding request failed")
        }
        let ordered = items.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
        let vectors = ordered.compactMap { ($0["embedding"] as? [NSNumber])?.map(\.floatValue) }
        guard vectors.count == texts.count else { throw MemoryStoreError.sqlite("the embedding response was incomplete") }
        return vectors.map { vector in
            let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
            return norm > 0 ? vector.map { $0 / norm } : vector
        }
    }
}

/// Merges ranked lists by reciprocal rank fusion: robust when one list's scores are not
/// comparable to the other's (BM25 and cosine are on different scales).
enum MemoryRanking {
    static func fuse(_ lists: [[UUID]], weights: [Double]? = nil, k: Double = 60) -> [UUID: Double] {
        var scores: [UUID: Double] = [:]
        for (index, list) in lists.enumerated() {
            let weight = weights?[index] ?? 1
            for (rank, id) in list.enumerated() { scores[id, default: 0] += weight / (k + Double(rank + 1)) }
        }
        return scores
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        for index in 0..<a.count { dot += a[index] * b[index] }
        return dot
    }

    /// Nearest by meaning, above a floor below which matches are unrelated for this model.
    static func nearest(_ query: [Float], in vectors: [(UUID, [Float])], limit: Int, floor: Float = 0.2) -> [UUID] {
        vectors.map { ($0.0, cosine(query, $0.1)) }.filter { $0.1 >= floor }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}
