import Foundation

/// Gmail through the Gmail REST API, presented as an MCP server so the Gmail plugin keeps its
/// tile, Google sign-in, tool list, and policies. Google's own Gmail MCP endpoint only serves
/// Cloud projects enrolled in the Workspace Developer Preview; the REST API accepts the same
/// OAuth token for any project with the Gmail API enabled.
actor GmailAPITransport: MCPTransport {
    private let token: String
    private let session: URLSession
    private let base = "https://gmail.googleapis.com/gmail/v1/users/me"

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    func setProtocolVersion(_ version: String) async {}
    func notify(method: String, params: MCPValue) async throws {}
    func close() async {}

    func request(method: String, params: MCPValue) async throws -> MCPValue {
        switch method {
        case "server/discover":
            return .object(["resultType": .string("complete"), "supportedVersions": .array([.string(MCPProtocol.current)]),
                            "capabilities": .object(["tools": .object([:])]), "serverInfo": .object(["name": .string("Gmail"), "version": .string("1")])])
        case "tools/list":
            return .object(["resultType": .string("complete"), "tools": .array(Self.tools)])
        case "tools/call":
            guard let name = params["name"]?.string else { throw MCPError.invalidResponse }
            let arguments = params["arguments"] ?? .object([:])
            do {
                return Self.result(try await call(name, arguments), isError: false)
            } catch let error as GmailError {
                return Self.result(error.message, isError: true)
            }
        default:
            throw MCPError.server(-32601)
        }
    }

    // MARK: Tools

    private static func tool(_ name: String, _ title: String, _ description: String, _ properties: [String: MCPValue], required: [String] = [], readOnly: Bool) -> MCPValue {
        .object(["name": .string(name), "title": .string(title), "description": .string(description),
                 "inputSchema": .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(MCPValue.string))]),
                 "annotations": .object(["readOnlyHint": .bool(readOnly)])])
    }

    private static let tools: [MCPValue] = {
        let text: MCPValue = .object(["type": .string("string")])
        let list: MCPValue = .object(["type": .string("array"), "items": .object(["type": .string("string")])])
        let limit: MCPValue = .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(25)])
        return [
            tool("search_messages", "Search Gmail", "Search Gmail with Gmail search syntax (from:, to:, subject:, is:unread, newer_than:7d, label:, has:attachment). Empty query lists the newest inbox mail. Returns ids for read_message, reply, and modify.",
                 ["query": text, "limit": limit], readOnly: true),
            tool("read_message", "Read an email", "Read one email by id: headers, plain-text body (up to 20000 characters), and attachment names.", ["id": text], required: ["id"], readOnly: true),
            tool("read_thread", "Read a conversation", "Read every message in a Gmail thread by thread id.", ["thread_id": text], required: ["thread_id"], readOnly: true),
            tool("list_labels", "List labels", "List Gmail labels (system and user labels) with their ids.", [:], readOnly: true),
            tool("create_draft", "Create a draft", "Create a Gmail draft. Set reply_to_id to draft a reply in that message's thread. Does not send.",
                 ["to": text, "cc": text, "subject": text, "body": text, "reply_to_id": text], required: ["body"], readOnly: false),
            tool("send_message", "Send an email", "Send an email from the user's Gmail. Set reply_to_id to reply in that message's thread.",
                 ["to": text, "cc": text, "subject": text, "body": text, "reply_to_id": text], required: ["body"], readOnly: false),
            tool("modify_message", "Label, archive, or mark", "Change a message's labels: archive (remove INBOX), mark read (remove UNREAD), mark unread (add UNREAD), star (add STARRED), or any label ids from list_labels.",
                 ["id": text, "add_labels": list, "remove_labels": list], required: ["id"], readOnly: false),
            tool("trash_message", "Move to Trash", "Move a message to Trash (recoverable for 30 days).", ["id": text], required: ["id"], readOnly: false)
        ]
    }()

    private func call(_ name: String, _ arguments: MCPValue) async throws -> String {
        func string(_ key: String) -> String? {
            let value = arguments[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        func required(_ key: String) throws -> String {
            guard let value = string(key) else { throw GmailError("Provide " + key.replacingOccurrences(of: "_", with: " ") + ".") }
            return value
        }
        switch name {
        case "search_messages":
            let limit = arguments["limit"].flatMap { value -> Int? in if case .number(let n) = value { return Int(n) }; return nil } ?? 10
            let query = string("query") ?? "in:inbox"
            let list = try await get("/messages", ["q": query, "maxResults": String(min(25, max(1, limit)))])
            let ids = (list["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            guard !ids.isEmpty else { return "No messages match \"\(query)\"." }
            var rows: [String] = []
            for id in ids {
                let message = try await get("/messages/" + id, ["format": "metadata", "metadataHeaders": "From,To,Subject,Date"])
                let headers = Self.headers(message)
                let labels = message["labelIds"] as? [String] ?? []
                rows.append("id: \(id) | thread: \(message["threadId"] as? String ?? "") | from: \(headers["from"] ?? "") | subject: \(headers["subject"] ?? "(no subject)") | date: \(headers["date"] ?? "")"
                    + (labels.contains("UNREAD") ? " | unread" : "") + "\n  " + Self.decodeEntities(message["snippet"] as? String ?? ""))
            }
            return rows.joined(separator: "\n")
        case "read_message":
            return Self.render(try await get("/messages/" + (try required("id")), ["format": "full"]))
        case "read_thread":
            let thread = try await get("/threads/" + (try required("thread_id")), ["format": "full"])
            let messages = (thread["messages"] as? [[String: Any]] ?? []).map { Self.render($0, limit: 6000) }
            return messages.isEmpty ? "The thread is empty." : messages.joined(separator: "\n\n---\n\n")
        case "list_labels":
            let labels = (try await get("/labels", [:])["labels"] as? [[String: Any]] ?? [])
            return labels.map { "\($0["name"] as? String ?? "") (id: \($0["id"] as? String ?? ""), \($0["type"] as? String ?? ""))" }.joined(separator: "\n")
        case "create_draft", "send_message":
            let (raw, threadID) = try await compose(to: string("to"), cc: string("cc"), subject: string("subject"), body: try required("body"), replyTo: string("reply_to_id"))
            var message: [String: Any] = ["raw": raw]
            if let threadID { message["threadId"] = threadID }
            if name == "create_draft" {
                let draft = try await send("POST", "/drafts", body: ["message": message])
                return "Draft created (id \(draft["id"] as? String ?? "")). It is in Gmail > Drafts."
            }
            let sent = try await send("POST", "/messages/send", body: message)
            return "Sent (id \(sent["id"] as? String ?? ""))."
        case "modify_message":
            let add = arguments["add_labels"]?.array?.compactMap(\.string) ?? []
            let remove = arguments["remove_labels"]?.array?.compactMap(\.string) ?? []
            guard !add.isEmpty || !remove.isEmpty else { throw GmailError("Provide labels to add or remove.") }
            _ = try await send("POST", "/messages/" + (try required("id")) + "/modify", body: ["addLabelIds": add, "removeLabelIds": remove])
            return "Updated."
        case "trash_message":
            _ = try await send("POST", "/messages/" + (try required("id")) + "/trash", body: [:])
            return "Moved to Trash."
        default:
            throw GmailError("Unknown Gmail tool.")
        }
    }

    /// An RFC 2822 message, base64url encoded. A reply takes the original's thread, subject,
    /// sender, and In-Reply-To/References headers.
    private func compose(to: String?, cc: String?, subject: String?, body: String, replyTo: String?) async throws -> (String, String?) {
        var recipient = to, title = subject ?? "", threadID: String?, references: String?
        if let replyTo {
            let original = try await get("/messages/" + replyTo, ["format": "metadata", "metadataHeaders": "From,Reply-To,Subject,Message-ID,References"])
            let headers = Self.headers(original)
            threadID = original["threadId"] as? String
            recipient = recipient ?? headers["reply-to"] ?? headers["from"]
            if title.isEmpty { title = (headers["subject"] ?? "").lowercased().hasPrefix("re:") ? headers["subject"] ?? "" : "Re: " + (headers["subject"] ?? "") }
            if let id = headers["message-id"] {
                let chain = (headers["references"].map { $0 + " " } ?? "") + id
                references = "In-Reply-To: \(id)\r\nReferences: \(chain)"
            }
        }
        guard let recipient, !recipient.isEmpty else { throw GmailError("Provide a recipient.") }
        for value in [recipient, cc ?? "", title] where value.contains("\n") || value.contains("\r") { throw GmailError("Headers cannot contain line breaks.") }
        var lines = ["To: " + recipient]
        if let cc { lines.append("Cc: " + cc) }
        lines.append("Subject: " + Self.encodedHeader(title))
        if let references { lines.append(references) }
        lines += ["MIME-Version: 1.0", "Content-Type: text/plain; charset=UTF-8", "Content-Transfer-Encoding: base64", "",
                  Data(body.utf8).base64EncodedString(options: .lineLength76Characters)]
        let raw = Data(lines.joined(separator: "\r\n").utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return (raw, threadID)
    }

    // MARK: HTTP

    private func get(_ path: String, _ query: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(string: base + path)!
        // metadataHeaders repeats once per header.
        components.queryItems = query.flatMap { key, value in
            key == "metadataHeaders" ? value.split(separator: ",").map { URLQueryItem(name: key, value: String($0)) } : [URLQueryItem(name: key, value: value)]
        }
        return try await perform(URLRequest(url: components.url!))
    }

    private func send(_ method: String, _ path: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: base + path)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request)
    }

    private func perform(_ original: URLRequest) async throws -> [String: Any] {
        var request = original
        request.timeoutInterval = 30
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Expired token: the store refreshes and retries the call once.
        if status == 401 { throw MCPError.http(401) }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            if status == 403 { throw GmailError("Gmail refused this: \(message). If it mentions scopes, sign out of Gmail in Integrations and sign in again.") }
            if status == 404 { throw GmailError("Gmail could not find that message or label.") }
            throw GmailError("Gmail returned an error: \(message)")
        }
        return json
    }

    // MARK: Parsing

    private static func headers(_ message: [String: Any]) -> [String: String] {
        let list = (message["payload"] as? [String: Any])?["headers"] as? [[String: Any]] ?? []
        var result: [String: String] = [:]
        for header in list { if let name = header["name"] as? String, let value = header["value"] as? String { result[name.lowercased()] = value } }
        return result
    }

    private static func render(_ message: [String: Any], limit: Int = 20_000) -> String {
        let headers = headers(message)
        let payload = message["payload"] as? [String: Any] ?? [:]
        var plain = "", html = "", attachments: [String] = []
        func walk(_ part: [String: Any]) {
            let mime = part["mimeType"] as? String ?? ""
            if let filename = part["filename"] as? String, !filename.isEmpty { attachments.append(filename); return }
            if let data = (part["body"] as? [String: Any])?["data"] as? String, let text = decode(data) {
                if mime == "text/plain" { plain += text } else if mime == "text/html" { html += text }
            }
            (part["parts"] as? [[String: Any]] ?? []).forEach(walk)
        }
        walk(payload)
        var body = plain.isEmpty ? stripHTML(html) : plain
        if body.count > limit { body = String(body.prefix(limit)) + "\n[Truncated]" }
        var lines = ["id: \(message["id"] as? String ?? "") | thread: \(message["threadId"] as? String ?? "")"]
        for key in ["from", "to", "cc", "date", "subject"] { if let value = headers[key] { lines.append(key.capitalized + ": " + value) } }
        if !attachments.isEmpty { lines.append("Attachments: " + attachments.joined(separator: ", ")) }
        lines.append("")
        lines.append(body.trimmingCharacters(in: .whitespacesAndNewlines))
        return lines.joined(separator: "\n")
    }

    private static func decode(_ base64url: String) -> String? {
        var value = base64url.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        return Data(base64Encoded: value).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>|</tr>|</li>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)
        return text.replacingOccurrences(of: "\n[ \t]*\n[\\s]*", with: "\n\n", options: .regularExpression)
    }

    private static func decodeEntities(_ text: String) -> String {
        [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'")]
            .reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// Non-ASCII subjects use RFC 2047 encoded words.
    private static func encodedHeader(_ value: String) -> String {
        value.unicodeScalars.allSatisfy(\.isASCII) ? value : "=?UTF-8?B?" + Data(value.utf8).base64EncodedString() + "?="
    }

    private static func result(_ text: String, isError: Bool) -> MCPValue {
        .object(["resultType": .string("complete"), "content": .array([.object(["type": .string("text"), "text": .string(text)])]), "isError": .bool(isError)])
    }
}

private struct GmailError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
