import Foundation
import CryptoKit

/// One scrobble, as Last.fm wants it.
struct ScrobbleSubmission: Codable, Equatable, Identifiable {
    let id: UUID
    let artist: String
    let track: String
    let album: String
    let albumArtist: String
    /// Seconds since 1970, UTC, at the moment the track started playing.
    let timestamp: Int
    let durationSeconds: Int

    /// - Parameter startedAt: when playback of the track began, not when it earned the
    ///   scrobble. Last.fm orders a profile by this, so it must be the start.
    init(track: PlayedTrack, startedAt: Date) {
        self.id = UUID()
        self.artist = track.artist
        self.track = track.title
        self.album = track.album
        self.albumArtist = track.albumArtist
        self.timestamp = Int(startedAt.timeIntervalSince1970)
        self.durationSeconds = Int(track.duration.rounded())
    }

    init(play: CompletedPlay) {
        self.init(track: play.track, startedAt: play.startedAt)
    }

    /// Last.fm rejects a scrobble with no artist or no track name, so there is no point
    /// queueing one.
    var isSubmittable: Bool {
        !artist.trimmingCharacters(in: .whitespaces).isEmpty &&
        !track.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Why a Last.fm call failed, split by whether retrying could ever help.
enum LastFMError: Swift.Error, Equatable {
    /// Network down, rate limited, or Last.fm having a bad day. Keep the scrobble and retry.
    case transient(String)
    /// The request will never succeed as-is. Drop the scrobble.
    case permanent(String)
    /// The session key is no longer valid; the user has to reconnect.
    case authenticationRequired
    /// This build shipped without Last.fm credentials.
    case notConfigured

    var isTransient: Bool {
        if case .transient = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .transient(let m), .permanent(let m): return m
        case .authenticationRequired: return "Last.fm sign-in has expired."
        case .notConfigured: return "This build has no Last.fm credentials."
        }
    }
}

/// Talks to the Last.fm 2.0 API.
///
/// An actor, following `LyricsService` — the house pattern for networked services here.
actor LastFMClient {
    static let shared = LastFMClient()

    private let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Authentication

    /// Step one of the desktop auth flow: a request token the user then approves in a browser.
    func requestToken() async throws -> String {
        let response = try await send(["method": "auth.getToken"], signed: true, httpMethod: "GET")
        guard let token = (response["token"] as? String), !token.isEmpty else {
            throw LastFMError.permanent("Last.fm did not return a token.")
        }
        return token
    }

    /// The URL the user visits to approve the token.
    nonisolated func authorizationURL(for token: String) -> URL? {
        var components = URLComponents(string: "https://www.last.fm/api/auth/")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: BuildSecrets.lastFMAPIKey),
            URLQueryItem(name: "token", value: token)
        ]
        return components?.url
    }

    /// Step two: exchange an approved token for a session key that never expires.
    ///
    /// Called on a poll while the user is still in the browser, so "not approved yet" (error
    /// 14) surfaces as `transient` and the caller keeps waiting.
    func session(forToken token: String) async throws -> (key: String, username: String) {
        let response = try await send(
            ["method": "auth.getSession", "token": token],
            signed: true,
            httpMethod: "GET"
        )
        guard let session = response["session"] as? [String: Any],
              let key = session["key"] as? String,
              let name = session["name"] as? String else {
            throw LastFMError.permanent("Last.fm did not return a session.")
        }
        return (key, name)
    }

    // MARK: Scrobbling

    func updateNowPlaying(_ submission: ScrobbleSubmission, sessionKey: String) async throws {
        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "artist": submission.artist,
            "track": submission.track,
            "sk": sessionKey
        ]
        if !submission.album.isEmpty { params["album"] = submission.album }
        if !submission.albumArtist.isEmpty { params["albumArtist"] = submission.albumArtist }
        if submission.durationSeconds > 0 { params["duration"] = String(submission.durationSeconds) }

        _ = try await send(params, signed: true, httpMethod: "POST")
    }

    /// Submits up to 50 scrobbles in one call, which is Last.fm's documented batch ceiling.
    ///
    /// - Returns: the number Last.fm accepted.
    @discardableResult
    func scrobble(_ submissions: [ScrobbleSubmission], sessionKey: String) async throws -> Int {
        guard !submissions.isEmpty else { return 0 }
        precondition(submissions.count <= 50, "Last.fm accepts at most 50 scrobbles per call")

        var params: [String: String] = ["method": "track.scrobble", "sk": sessionKey]
        for (index, submission) in submissions.enumerated() {
            params["artist[\(index)]"] = submission.artist
            params["track[\(index)]"] = submission.track
            params["timestamp[\(index)]"] = String(submission.timestamp)
            if !submission.album.isEmpty { params["album[\(index)]"] = submission.album }
            if !submission.albumArtist.isEmpty { params["albumArtist[\(index)]"] = submission.albumArtist }
            if submission.durationSeconds > 0 { params["duration[\(index)]"] = String(submission.durationSeconds) }
        }

        let response = try await send(params, signed: true, httpMethod: "POST")
        guard let scrobbles = response["scrobbles"] as? [String: Any],
              let attributes = scrobbles["@attr"] as? [String: Any],
              let accepted = attributes["accepted"] as? Int else {
            // Accepted but unparseable is still accepted; re-sending would duplicate plays on
            // the user's profile, which is worse than losing the count.
            return submissions.count
        }
        return accepted
    }

    // MARK: Transport

    private func send(
        _ parameters: [String: String],
        signed: Bool,
        httpMethod: String
    ) async throws -> [String: Any] {
        guard BuildSecrets.isLastFMConfigured else { throw LastFMError.notConfigured }

        var params = parameters
        params["api_key"] = BuildSecrets.lastFMAPIKey
        if signed {
            params["api_sig"] = Self.signature(for: params, secret: BuildSecrets.lastFMSharedSecret)
        }
        // Deliberately after signing: `format` is excluded from the signature base string.
        params["format"] = "json"

        var request = URLRequest(url: endpoint)
        request.httpMethod = httpMethod
        request.timeoutInterval = 20

        if httpMethod == "GET" {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
            components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let url = components?.url else { throw LastFMError.permanent("Bad request URL.") }
            request.url = url
        } else {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formEncoded(params).data(using: .utf8)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LastFMError.transient(error.localizedDescription)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        if let errorCode = json["error"] as? Int {
            throw Self.error(forCode: errorCode, message: json["message"] as? String ?? "Last.fm error \(errorCode)")
        }

        // 5xx and 429 carry no error body of their own.
        if statusCode >= 500 || statusCode == 429 {
            throw LastFMError.transient("Last.fm returned HTTP \(statusCode).")
        }
        guard (200..<300).contains(statusCode) else {
            throw LastFMError.permanent("Last.fm returned HTTP \(statusCode).")
        }

        return json
    }

    /// Maps Last.fm's documented error codes onto retry semantics.
    ///
    /// Getting this split wrong is expensive in both directions: treating a permanent failure
    /// as transient wedges the queue forever, and treating a transient one as permanent throws
    /// away plays the user did listen to.
    private static func error(forCode code: Int, message: String) -> LastFMError {
        switch code {
        case 4, 9, 14:
            // 4 authentication failed, 9 invalid session key, 14 token not authorised.
            // During the auth poll 14 is expected and the caller treats it as "keep waiting".
            return code == 14 ? .transient(message) : .authenticationRequired
        case 8, 11, 16, 29:
            // Operation failed, service offline, temporarily unavailable, rate limit.
            return .transient(message)
        case 26:
            return .permanent("This build's Last.fm API key has been suspended.")
        default:
            return .permanent(message)
        }
    }

    // MARK: Signing

    /// Last.fm's `api_sig`: every parameter except `format` and `callback`, sorted by name,
    /// concatenated as name+value, with the shared secret appended, then MD5 hex.
    ///
    /// MD5 is not a choice — it is what the Last.fm API specifies. `Insecure.MD5` is the
    /// correct API to reach for here despite the name, and this is not a security defect.
    static func signature(for parameters: [String: String], secret: String) -> String {
        let excluded: Set<String> = ["format", "callback", "api_sig"]
        let base = parameters
            .filter { !excluded.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { $0.key + $0.value }
            .joined()

        let digest = Insecure.MD5.hash(data: Data((base + secret).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func formEncoded(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }
}
