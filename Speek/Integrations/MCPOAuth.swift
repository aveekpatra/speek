import Foundation
import Network
import CryptoKit
import AppKit

/// Saved OAuth state for one remote MCP server. Lives in Keychain with the plugin's secrets.
struct MCPOAuthSession: Codable, Equatable, Sendable {
    var clientID: String
    var clientSecret: String?
    var redirectURI: String
    var authorizationEndpoint: String
    var tokenEndpoint: String
    var resource: String
    var scope: String?
    var accessToken = ""
    var refreshToken: String?
    var expiresAt: Date?

    var needsRefresh: Bool { expiresAt.map { $0.addingTimeInterval(-60) < Date() } ?? false }
}

enum MCPOAuthError: LocalizedError {
    case noAuthorizationServer, registrationUnsupported, denied(String), timedOut, stateMismatch, tokenRejected(String), refreshFailed

    var errorDescription: String? {
        switch self {
        case .noAuthorizationServer: return "This server did not describe how to sign in. Add an access token in Edit instead."
        case .registrationUnsupported: return "This server only allows pre-approved apps to sign in. Add an access token or API key in Edit instead."
        case .denied(let reason): return "Sign-in was not completed: \(reason)."
        case .timedOut: return "Sign-in timed out. Click Connect to try again."
        case .stateMismatch: return "The sign-in response did not match this request. Try again."
        case .tokenRejected(let reason): return "The server did not issue a token: \(reason)."
        case .refreshFailed: return "Your sign-in expired. Click Connect to sign in again."
        }
    }
}

/// MCP authorization (OAuth 2.1): protected resource and authorization server discovery,
/// dynamic client registration, PKCE, and a loopback redirect on 127.0.0.1.
enum MCPOAuth {
    /// Opens the authorization page. Replaced in isolated checks.
    @MainActor static var openBrowser: (URL) -> Void = { _ = NSWorkspace.shared.open($0) }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    // MARK: Sign in

    /// `client` is a pre-registered OAuth client (skips dynamic registration); `scopes`
    /// overrides what the server advertises.
    static func signIn(endpoint: URL, previous: MCPOAuthSession?, client preregistered: (id: String, secret: String?)? = nil,
                       scopes requested: String? = nil) async throws -> MCPOAuthSession {
        let challenge = await probe(endpoint)
        let resource = canonicalResource(endpoint)
        var metadata: [String: Any]?
        var scopes = requested ?? challenge.scope
        if let resourceMetadata = try await protectedResourceMetadata(endpoint, hint: challenge.metadataURL),
           let issuer = (resourceMetadata["authorization_servers"] as? [String])?.first, let issuerURL = URL(string: issuer) {
            metadata = try await authorizationServerMetadata(issuerURL)
            if scopes == nil, let supported = resourceMetadata["scopes_supported"] as? [String], !supported.isEmpty { scopes = supported.joined(separator: " ") }
        }
        if metadata == nil, let origin = origin(of: endpoint) {
            // Servers from before protected resource metadata act as their own authorization server.
            metadata = try await authorizationServerMetadata(origin)
        }
        guard let metadata, let authorize = metadata["authorization_endpoint"] as? String, let token = metadata["token_endpoint"] as? String else {
            throw MCPOAuthError.noAuthorizationServer
        }
        let receiver = LoopbackReceiver()
        let reusable = preregistered != nil ? nil : previous.flatMap { old -> MCPOAuthSession? in
            guard old.authorizationEndpoint == authorize, old.tokenEndpoint == token, let port = URL(string: old.redirectURI)?.port else { return nil }
            return (try? receiver.start(port: UInt16(port))) != nil ? old : nil
        }
        var client: MCPOAuthSession
        if let preregistered {
            // Installed-app clients accept any loopback port (RFC 8252).
            let port = try receiver.start(port: 0)
            client = MCPOAuthSession(clientID: preregistered.id, clientSecret: preregistered.secret, redirectURI: "http://127.0.0.1:\(port)/callback",
                                     authorizationEndpoint: authorize, tokenEndpoint: token, resource: resource, scope: scopes)
        } else if let reusable {
            client = reusable
        } else {
            let port = try receiver.start(port: 0)
            let redirect = "http://127.0.0.1:\(port)/callback"
            guard let registration = metadata["registration_endpoint"] as? String, let registrationURL = URL(string: registration) else {
                receiver.stop(); throw MCPOAuthError.registrationUnsupported
            }
            let registered = try await register(at: registrationURL, redirect: redirect)
            client = MCPOAuthSession(clientID: registered.id, clientSecret: registered.secret, redirectURI: redirect,
                                     authorizationEndpoint: authorize, tokenEndpoint: token, resource: resource, scope: scopes)
        }
        defer { receiver.stop() }
        client.resource = resource
        client.scope = scopes ?? client.scope
        return try await Self.authorize(client, receiver: receiver, issuer: metadata["issuer"] as? String)
    }

    /// Sign-in for a service with known endpoints and a public client (PKCE, loopback redirect),
    /// such as Spotify. No discovery, registration, or resource indicator.
    /// `port` 0 picks a free port; services that require a registered redirect URI pass a fixed one.
    static func signIn(authorizationEndpoint: String, tokenEndpoint: String, clientID: String, scopes: String, port fixed: UInt16 = 0) async throws -> MCPOAuthSession {
        let receiver = LoopbackReceiver()
        let port = try receiver.start(port: fixed)
        defer { receiver.stop() }
        let client = MCPOAuthSession(clientID: clientID, clientSecret: nil, redirectURI: "http://127.0.0.1:\(port)/callback",
                                     authorizationEndpoint: authorizationEndpoint, tokenEndpoint: tokenEndpoint, resource: "", scope: scopes)
        return try await authorize(client, receiver: receiver, issuer: nil)
    }

    private static func authorize(_ client: MCPOAuthSession, receiver: LoopbackReceiver, issuer: String?) async throws -> MCPOAuthSession {
        let verifier = randomString(48)
        let state = randomString(24)
        let codeChallenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        guard var components = URLComponents(string: client.authorizationEndpoint) else { throw MCPOAuthError.noAuthorizationServer }
        var items = components.queryItems ?? []
        items += [URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "client_id", value: client.clientID),
                  URLQueryItem(name: "redirect_uri", value: client.redirectURI), URLQueryItem(name: "code_challenge", value: codeChallenge),
                  URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "state", value: state)]
        if sendsResource(client) { items.append(URLQueryItem(name: "resource", value: client.resource)) }
        if isGoogle(client) {
            // Google issues a refresh token only for offline access with explicit consent.
            items += [URLQueryItem(name: "access_type", value: "offline"), URLQueryItem(name: "prompt", value: "consent")]
        }
        if let scope = client.scope { items.append(URLQueryItem(name: "scope", value: scope)) }
        components.queryItems = items
        guard let url = components.url, url.scheme == "https" || url.host == "127.0.0.1" || url.host == "localhost" else { throw MCPOAuthError.noAuthorizationServer }
        await MainActor.run { openBrowser(url) }

        let callback = try await receiver.waitForCallback(timeout: 300)
        if let error = callback["error"] { throw MCPOAuthError.denied(callback["error_description"] ?? error) }
        guard callback["state"] == state else { throw MCPOAuthError.stateMismatch }
        // RFC 9207: a returned issuer must be the server this request went to.
        if let returned = callback["iss"], let issuer, returned != issuer { throw MCPOAuthError.stateMismatch }
        guard let code = callback["code"], !code.isEmpty else { throw MCPOAuthError.denied("no authorization code was returned") }
        return try await exchange(client, form: ["grant_type": "authorization_code", "code": code, "redirect_uri": client.redirectURI, "code_verifier": verifier])
    }

    static func refresh(_ current: MCPOAuthSession) async throws -> MCPOAuthSession {
        guard let refreshToken = current.refreshToken else { throw MCPOAuthError.refreshFailed }
        do { return try await exchange(current, form: ["grant_type": "refresh_token", "refresh_token": refreshToken]) }
        catch { throw MCPOAuthError.refreshFailed }
    }

    // MARK: Token endpoint

    private static func exchange(_ client: MCPOAuthSession, form: [String: String]) async throws -> MCPOAuthSession {
        guard let url = URL(string: client.tokenEndpoint) else { throw MCPOAuthError.noAuthorizationServer }
        var fields = form
        fields["client_id"] = client.clientID
        if sendsResource(client) { fields["resource"] = client.resource }
        if let secret = client.clientSecret { fields["client_secret"] = secret }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = fields.map { $0.key + "=" + formEncode($0.value) }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true, let access = json["access_token"] as? String, !access.isEmpty else {
            throw MCPOAuthError.tokenRejected((json["error_description"] as? String) ?? (json["error"] as? String) ?? "unexpected response")
        }
        var updated = client
        updated.accessToken = access
        updated.refreshToken = (json["refresh_token"] as? String) ?? client.refreshToken
        updated.expiresAt = (json["expires_in"] as? NSNumber).map { Date().addingTimeInterval($0.doubleValue) }
        return updated
    }

    private static func register(at url: URL, redirect: String) async throws -> (id: String, secret: String?) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "Speek", "client_uri": "https://github.com/aveekpatra/speek",
            "redirect_uris": [redirect], "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"], "token_endpoint_auth_method": "none", "application_type": "native"
        ])
        let (data, response) = try await session.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true, let id = json["client_id"] as? String else {
            throw MCPOAuthError.registrationUnsupported
        }
        return (id, json["client_secret"] as? String)
    }

    // MARK: Discovery

    private struct Challenge { var metadataURL: URL?; var scope: String? }

    /// An unauthenticated request; a 401 names the resource metadata and scopes.
    private static func probe(_ endpoint: URL) async -> Challenge {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":"speek-auth-probe","method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"Speek","version":"1"}}}"#.utf8)
        guard let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse,
              let header = http.value(forHTTPHeaderField: "WWW-Authenticate") else { return Challenge() }
        return Challenge(metadataURL: parameter("resource_metadata", in: header).flatMap(URL.init(string:)), scope: parameter("scope", in: header))
    }

    private static func protectedResourceMetadata(_ endpoint: URL, hint: URL?) async throws -> [String: Any]? {
        var candidates = [hint].compactMap { $0 }
        if let origin = origin(of: endpoint) {
            let path = endpoint.path == "/" ? "" : endpoint.path
            if !path.isEmpty { candidates.append(origin.appendingPathComponent(".well-known/oauth-protected-resource" + path)) }
            candidates.append(origin.appendingPathComponent(".well-known/oauth-protected-resource"))
        }
        for url in candidates { if let json = await fetchJSON(url), json["authorization_servers"] != nil { return json } }
        return nil
    }

    private static func authorizationServerMetadata(_ issuer: URL) async throws -> [String: Any]? {
        guard let origin = origin(of: issuer) else { return nil }
        let path = issuer.path == "/" ? "" : issuer.path
        var candidates: [URL] = []
        if path.isEmpty {
            candidates = [origin.appendingPathComponent(".well-known/oauth-authorization-server"), origin.appendingPathComponent(".well-known/openid-configuration")]
        } else {
            candidates = [origin.appendingPathComponent(".well-known/oauth-authorization-server" + path),
                          origin.appendingPathComponent(".well-known/openid-configuration" + path),
                          issuer.appendingPathComponent(".well-known/openid-configuration")]
        }
        for url in candidates { if let json = await fetchJSON(url), json["authorization_endpoint"] != nil { return json } }
        return nil
    }

    private static func fetchJSON(_ url: URL) async -> [String: Any]? {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Helpers

    private static func isGoogle(_ client: MCPOAuthSession) -> Bool {
        URL(string: client.authorizationEndpoint)?.host == "accounts.google.com"
    }

    /// Google's authorization server scopes tokens to the client, not a resource indicator.
    private static func sendsResource(_ client: MCPOAuthSession) -> Bool { !isGoogle(client) && !client.resource.isEmpty }

    private static func origin(of url: URL) -> URL? {
        var components = URLComponents()
        components.scheme = url.scheme; components.host = url.host; components.port = url.port
        return components.url
    }

    /// Scheme and host lowercased, no fragment, no trailing slash (RFC 8707 resource indicator).
    private static func canonicalResource(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = components.scheme?.lowercased(); components.host = components.host?.lowercased(); components.fragment = nil
        var text = components.string ?? url.absoluteString
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }

    private static func parameter(_ name: String, in header: String) -> String? {
        guard let range = header.range(of: name + "=") else { return nil }
        let rest = header[range.upperBound...]
        if rest.hasPrefix("\"") { return rest.dropFirst().split(separator: "\"", maxSplits: 1).first.map(String.init) }
        return rest.split(whereSeparator: { $0 == "," || $0 == " " }).first.map(String.init)
    }

    private static func randomString(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return data.base64URLEncoded
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Receives one OAuth redirect on 127.0.0.1 and answers the browser with a short page.
private final class LoopbackReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.aveekpatra.speek.oauth-loopback")
    private let lock = NSLock()
    private var listener: NWListener?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var result: Result<[String: String], Error>?

    /// Binds synchronously and returns the port (0 picks a free one).
    func start(port: UInt16) throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        var failure: Error?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error): failure = error; ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, failure == nil, let bound = listener.port?.rawValue, bound != 0 else {
            listener.cancel(); throw failure ?? MCPOAuthError.timedOut
        }
        self.listener = listener
        return bound
    }

    func waitForCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result { lock.unlock(); continuation.resume(with: result); return }
            self.continuation = continuation
            lock.unlock()
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finish(.failure(MCPOAuthError.timedOut)) }
        }
    }

    func stop() {
        listener?.cancel(); listener = nil
        finish(.failure(CancellationError()))
    }

    private func finish(_ value: Result<[String: String], Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let pending = continuation; continuation = nil
        lock.unlock()
        pending?.resume(with: value)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            let line = data.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: "\r\n").first.map(String.init) ?? ""
            let parts = line.split(separator: " ")
            let target = parts.count > 1 ? String(parts[1]) : ""
            let isCallback = target.hasPrefix("/callback")
            let body = isCallback
                ? "<html><body style=\"font-family:-apple-system;background:#1c1c1e;color:#fff;display:flex;align-items:center;justify-content:center;height:90vh\"><div><h2>Signed in to Speek</h2><p>You can close this tab.</p></div></body></html>"
                : "Not found"
            let response = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            guard isCallback, let components = URLComponents(string: "http://127.0.0.1" + target) else { return }
            var values: [String: String] = [:]
            for item in components.queryItems ?? [] { values[item.name] = item.value ?? "" }
            self?.finish(.success(values))
        }
    }
}
