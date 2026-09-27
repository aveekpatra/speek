import Foundation
import AppKit

/// The user's Spotify account through the Web API: search, library, playlists, queue, and
/// devices. Signs in with the user's own Spotify app (PKCE, no secret). Playing a result uses
/// the Spotify app (`spotify.play`), which works without Premium; queue and device control
/// need Premium.
@MainActor
final class SpotifyAccount: ObservableObject {
    static let shared = SpotifyAccount()
    static let clientIDKey = "speek.spotify.clientID"
    /// Spotify's dashboard only accepts loopback redirects with an explicit port.
    static let redirectPort: UInt16 = 43821
    static let redirectURI = "http://127.0.0.1:43821/callback"
    private static let tokenID = UUID(uuidString: "5B0F1F1E-7A1C-4E2B-9F3D-53504F544946")!
    private static let nameKey = "speek.spotify.displayName"
    static let scopes = ["user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing",
                         "user-read-recently-played", "user-top-read", "user-library-read", "user-library-modify",
                         "user-follow-read", "user-follow-modify", "playlist-read-private", "playlist-read-collaborative",
                         "playlist-modify-private", "playlist-modify-public"].joined(separator: " ")

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var displayName: String?
    @Published private(set) var signingIn = false
    private var session: MCPOAuthSession?

    var clientID: String {
        get { UserDefaults.standard.string(forKey: Self.clientIDKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.clientIDKey); objectWillChange.send() }
    }

    private init() {
        session = ServiceTokenStore.load(Self.tokenID)
        isSignedIn = session != nil
        displayName = UserDefaults.standard.string(forKey: Self.nameKey)
    }

    func signIn() async throws {
        guard !clientID.isEmpty else { throw SpotifyError.message("Paste your Spotify app's Client ID first.") }
        signingIn = true
        defer { signingIn = false }
        let new = try await MCPOAuth.signIn(authorizationEndpoint: "https://accounts.spotify.com/authorize",
                                            tokenEndpoint: "https://accounts.spotify.com/api/token", clientID: clientID, scopes: Self.scopes, port: Self.redirectPort)
        try ServiceTokenStore.save(new, id: Self.tokenID)
        session = new
        isSignedIn = true
        if let me = try? await request("GET", "/me") as? [String: Any] {
            displayName = me["display_name"] as? String ?? me["id"] as? String
            UserDefaults.standard.set(displayName, forKey: Self.nameKey)
        }
    }

    func signOut() {
        ServiceTokenStore.remove(Self.tokenID)
        session = nil; isSignedIn = false; displayName = nil
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
    }

    // MARK: Tools

    static let toolIDs = catalog.map(\.id)
    static let catalog: [RuntimeTool] = {
        func tool(_ id: String, _ summary: String, _ properties: [String: Any], required: [String] = [], changes: Bool = false) -> RuntimeTool {
            RuntimeTool(id: id, title: id.replacingOccurrences(of: ".", with: " ").capitalized, summary: summary,
                        schema: ["type": "object", "properties": properties, "required": required, "additionalProperties": false], requiresReview: changes)
        }
        let text = ["type": "string"]
        let uris: [String: Any] = ["type": "array", "items": ["type": "string"], "maxItems": 40]
        let limit: [String: Any] = ["type": "integer", "minimum": 1, "maximum": 50]
        return [
            tool("spotify.search", "Search the Spotify catalog. Returns names and spotify: URIs to use with spotify.play, spotify.queue, spotify.save, or spotify.add_to_playlist. At most 10 results.",
                 ["query": text, "type": ["type": "string", "enum": ["track", "album", "artist", "playlist", "show", "episode", "audiobook"]],
                  "limit": ["type": "integer", "minimum": 1, "maximum": 10]], required: ["query", "type"]),
            tool("spotify.now_playing", "What is playing on Spotify right now, on which device, and playback progress.", [:]),
            tool("spotify.recently_played", "Tracks the user played recently on Spotify, newest first.", ["limit": limit]),
            tool("spotify.top", "The user's most played artists or tracks over a time range.",
                 ["type": ["type": "string", "enum": ["artists", "tracks"]], "range": ["type": "string", "enum": ["short_term", "medium_term", "long_term"]], "limit": limit], required: ["type"]),
            tool("spotify.library", "The user's saved Spotify items: liked tracks, saved albums, playlists, podcasts (shows), saved episodes, or followed artists.",
                 ["kind": ["type": "string", "enum": ["tracks", "albums", "playlists", "shows", "episodes", "artists"]], "limit": limit, "offset": ["type": "integer", "minimum": 0]], required: ["kind"]),
            tool("spotify.playlist_items", "Tracks and episodes in a playlist, by spotify: URI, open.spotify.com link, or playlist id.",
                 ["playlist": text, "limit": limit, "offset": ["type": "integer", "minimum": 0]], required: ["playlist"]),
            tool("spotify.devices", "Spotify devices the user can play on (computer, phone, speakers), with ids for spotify.transfer.", [:]),
            tool("spotify.queue", "Add a track or episode to the end of the Spotify queue. Needs Premium.", ["uri": text], required: ["uri"], changes: true),
            tool("spotify.transfer", "Move Spotify playback to a device by id from spotify.devices, and optionally start playing. Needs Premium.",
                 ["device_id": text, "play": ["type": "boolean"]], required: ["device_id"], changes: true),
            tool("spotify.save", "Save items to the user's Spotify library: like tracks, save albums, episodes, or shows, follow artists or playlists. Up to 40 spotify: URIs.", ["uris": uris], required: ["uris"], changes: true),
            tool("spotify.unsave", "Remove items from the user's Spotify library (unlike, unsave, or unfollow). Up to 40 spotify: URIs.", ["uris": uris], required: ["uris"], changes: true),
            tool("spotify.create_playlist", "Create a Spotify playlist for the user. Private unless public is true. Returns its URI.",
                 ["name": text, "description": text, "public": ["type": "boolean"]], required: ["name"], changes: true),
            tool("spotify.add_to_playlist", "Add tracks or episodes (spotify: URIs, up to 40) to a playlist the user owns or collaborates on.",
                 ["playlist": text, "uris": uris], required: ["playlist", "uris"], changes: true)
        ]
    }()

    var availableTools: [RuntimeTool] { isSignedIn ? Self.catalog : [] }

    func execute(_ name: String, arguments: [String: Any]) async throws -> String {
        guard isSignedIn else { throw SpotifyError.message("Sign in to Spotify in Integrations > Native apps first.") }
        func string(_ key: String) -> String? { (arguments[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        func int(_ key: String, _ fallback: Int, max upper: Int) -> Int { min(upper, Swift.max(1, (arguments[key] as? NSNumber)?.intValue ?? fallback)) }
        func uriList() throws -> [String] {
            let values = (arguments["uris"] as? [Any] ?? []).compactMap { $0 as? String }
            guard !values.isEmpty, values.count <= 40 else { throw SpotifyError.message("Provide 1 to 40 Spotify URIs.") }
            return try values.map { try NativeAppTools.spotifyURI($0) }
        }
        let offset = Swift.max(0, (arguments["offset"] as? NSNumber)?.intValue ?? 0)
        switch name {
        case "spotify.search":
            guard let query = string("query") else { throw SpotifyError.message("Provide what to search for.") }
            let type = string("type") ?? "track"
            let json = try await request("GET", "/search", query: ["q": query, "type": type, "limit": String(int("limit", 5, max: 10))])
            let items = ((json as? [String: Any])?[type + "s"] as? [String: Any])?["items"] as? [Any] ?? []
            return Self.render(items.compactMap { $0 as? [String: Any] }.map(Self.summary), empty: "No results.")
        case "spotify.now_playing":
            guard let json = try await request("GET", "/me/player", query: ["additional_types": "episode"]) as? [String: Any] else { return "Nothing is playing." }
            var line = [String: Any]()
            line["playing"] = json["is_playing"]
            line["device"] = (json["device"] as? [String: Any])?["name"]
            line["shuffle"] = json["shuffle_state"]; line["repeat"] = json["repeat_state"]
            if let item = json["item"] as? [String: Any] {
                line.merge(Self.summary(item)) { a, _ in a }
                if let progress = json["progress_ms"] as? Int, let total = item["duration_ms"] as? Int { line["position"] = Self.time(progress) + " of " + Self.time(total) }
            }
            return Self.render([line], empty: "Nothing is playing.")
        case "spotify.recently_played":
            let json = try await request("GET", "/me/player/recently-played", query: ["limit": String(int("limit", 20, max: 50))])
            let items = (json as? [String: Any])?["items"] as? [[String: Any]] ?? []
            return Self.render(items.map { entry in
                var line = Self.summary(entry["track"] as? [String: Any] ?? [:]); line["played_at"] = entry["played_at"]; return line
            }, empty: "No recent plays.")
        case "spotify.top":
            let type = string("type") == "artists" ? "artists" : "tracks"
            let json = try await request("GET", "/me/top/" + type, query: ["limit": String(int("limit", 20, max: 50)), "time_range": string("range") ?? "medium_term"])
            return Self.render(((json as? [String: Any])?["items"] as? [[String: Any]] ?? []).map(Self.summary), empty: "No listening history yet.")
        case "spotify.library":
            let kind = string("kind") ?? "tracks"
            let limit = String(int("limit", 20, max: 50))
            let json: Any?
            if kind == "artists" { json = ((try await request("GET", "/me/following", query: ["type": "artist", "limit": limit])) as? [String: Any])?["artists"] }
            else {
                guard ["tracks", "albums", "playlists", "shows", "episodes"].contains(kind) else { throw SpotifyError.message("Unknown library kind.") }
                json = try await request("GET", "/me/" + kind, query: ["limit": limit, "offset": String(offset)])
            }
            let items = (json as? [String: Any])?["items"] as? [[String: Any]] ?? []
            // Saved items wrap the object with the date it was saved.
            return Self.render(items.map { entry in
                let object = (entry["track"] ?? entry["album"] ?? entry["show"] ?? entry["episode"]) as? [String: Any] ?? entry
                return Self.summary(object)
            }, empty: "Nothing saved yet.")
        case "spotify.playlist_items":
            let id = try Self.playlistID(string("playlist"))
            let json = try await request("GET", "/playlists/" + id + "/items", query: ["limit": String(int("limit", 50, max: 50)), "offset": String(offset)])
            let items = (json as? [String: Any])?["items"] as? [[String: Any]] ?? []
            return Self.render(items.compactMap { ($0["item"] ?? $0["track"]) as? [String: Any] }.map(Self.summary), empty: "The playlist is empty.")
        case "spotify.devices":
            let devices = ((try await request("GET", "/me/player/devices")) as? [String: Any])?["devices"] as? [[String: Any]] ?? []
            return Self.render(devices.map { ["id": $0["id"] ?? "", "name": $0["name"] ?? "", "type": $0["type"] ?? "", "active": $0["is_active"] ?? false, "volume": $0["volume_percent"] ?? ""] },
                               empty: "No devices. Open Spotify on a computer, phone, or speaker.")
        case "spotify.queue":
            let uri = try NativeAppTools.spotifyURI(string("uri") ?? "")
            _ = try await request("POST", "/me/player/queue", query: ["uri": uri])
            return "Added to the queue."
        case "spotify.transfer":
            guard let device = string("device_id") else { throw SpotifyError.message("Provide a device id from spotify.devices.") }
            _ = try await request("PUT", "/me/player", body: ["device_ids": [device], "play": arguments["play"] as? Bool ?? false])
            return "Playback moved."
        case "spotify.save", "spotify.unsave":
            _ = try await request(name == "spotify.save" ? "PUT" : "DELETE", "/me/library", query: ["uris": try uriList().joined(separator: ",")])
            return name == "spotify.save" ? "Saved." : "Removed."
        case "spotify.create_playlist":
            guard let title = string("name") else { throw SpotifyError.message("Provide a playlist name.") }
            var body: [String: Any] = ["name": title, "public": arguments["public"] as? Bool ?? false]
            if let description = string("description") { body["description"] = description }
            let json = try await request("POST", "/me/playlists", body: body) as? [String: Any] ?? [:]
            return Self.render([Self.summary(json)], empty: "Playlist created.")
        case "spotify.add_to_playlist":
            let id = try Self.playlistID(string("playlist"))
            _ = try await request("POST", "/playlists/" + id + "/items", body: ["uris": try uriList()])
            return "Added to the playlist."
        default:
            throw SpotifyError.message("Unknown Spotify tool.")
        }
    }

    // MARK: HTTP

    private func accessToken() async throws -> String {
        guard var current = session else { throw SpotifyError.message("Sign in to Spotify in Integrations > Native apps first.") }
        if current.needsRefresh {
            do { current = try await MCPOAuth.refresh(current) }
            catch { signOut(); throw SpotifyError.message("Your Spotify sign-in expired. Sign in again in Integrations > Native apps.") }
            session = current
            try? ServiceTokenStore.save(current, id: Self.tokenID)
        }
        return current.accessToken
    }

    private func request(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil, retry: Bool = true) async throws -> Any? {
        var components = URLComponents(string: "https://api.spotify.com/v1" + path)!
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer " + (try await accessToken()), forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if method != "GET" { request.httpBody = Data() }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, retry, var current = session {
            // The token was revoked or expired early: refresh once and retry.
            current.expiresAt = .distantPast; session = current
            return try await self.request(method, path, query: query, body: body, retry: false)
        }
        guard (200..<300).contains(status) else {
            let detail = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]).flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            switch status {
            case 403: throw SpotifyError.message("Spotify refused this" + (detail.map { ": " + $0 } ?? ".") + " Queue and device control need Premium.")
            case 404: throw SpotifyError.message(path.hasPrefix("/me/player") ? "No active Spotify device. Start playing on a device, then try again." : "Spotify could not find that item.")
            case 429: throw SpotifyError.message("Spotify is rate limiting requests. Try again in a minute.")
            default: throw SpotifyError.message("Spotify returned HTTP \(status)" + (detail.map { ": " + $0 } ?? "."))
            }
        }
        guard !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    // MARK: Formatting

    private static func summary(_ item: [String: Any]) -> [String: Any] {
        var line: [String: Any] = ["name": item["name"] ?? "", "uri": item["uri"] ?? ""]
        if let type = item["type"] { line["type"] = type }
        if let artists = item["artists"] as? [[String: Any]] { line["artists"] = artists.compactMap { $0["name"] as? String }.joined(separator: ", ") }
        if let album = item["album"] as? [String: Any] { line["album"] = album["name"] }
        if let show = item["show"] as? [String: Any] { line["show"] = show["name"] }
        if let owner = item["owner"] as? [String: Any] { line["owner"] = owner["display_name"] }
        if let items = item["items"] as? [String: Any], let total = items["total"] { line["items"] = total }
        if let tracks = item["tracks"] as? [String: Any], let total = tracks["total"] { line["items"] = total }
        if let duration = item["duration_ms"] as? Int { line["duration"] = time(duration) }
        if let date = item["release_date"] { line["released"] = date }
        return line
    }

    private static func render(_ items: [[String: Any]], empty: String) -> String {
        guard !items.isEmpty, let data = try? JSONSerialization.data(withJSONObject: items, options: [.sortedKeys]) else { return empty }
        return String(decoding: data, as: UTF8.self)
    }

    private static func time(_ milliseconds: Int) -> String { String(format: "%d:%02d", milliseconds / 60_000, milliseconds / 1000 % 60) }

    private static func playlistID(_ value: String?) throws -> String {
        guard let value, !value.isEmpty else { throw SpotifyError.message("Provide a playlist.") }
        if value.allSatisfy({ $0.isLetter || $0.isNumber }) { return value }
        let uri = try NativeAppTools.spotifyURI(value)
        guard uri.hasPrefix("spotify:playlist:") else { throw SpotifyError.message("That is not a playlist link.") }
        return String(uri.dropFirst("spotify:playlist:".count))
    }
}

enum SpotifyError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
