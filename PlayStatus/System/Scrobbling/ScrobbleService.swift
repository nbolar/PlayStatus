import Foundation
import AppKit
import SwiftUI
import Combine

/// Owns the Last.fm account, decides what gets scrobbled, and keeps the queue moving.
///
/// Main-actor isolated because the Settings pane binds to it directly; the network and disk
/// work it kicks off lives on `LastFMClient` and `ScrobbleQueue`, which are actors of their own.
@MainActor
final class ScrobbleService: ObservableObject {
    static let shared = ScrobbleService()

    private static let keychainService = "com.bolar.playstatus.lastfm"

    /// Where the connect flow has got to. Drives the whole Settings card.
    enum ConnectionState: Equatable {
        case notConfigured
        case disconnected
        case awaitingApproval
        case connected(username: String)
        case failed(String)
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var pendingCount: Int = 0

    /// Only ever an error or a progress note. Successes are reported by the counters below —
    /// a success message here would be a claim about one flush dressed up as a running total.
    @Published private(set) var lastStatusMessage: String = ""

    /// Running tally of plays Last.fm has accepted, and when the most recent one landed.
    ///
    /// Persisted rather than per-launch: "how many have I scrobbled" is a question about the
    /// account, and an answer that silently resets every relaunch is worse than none.
    @Published private(set) var acceptedCount: Int
    @Published private(set) var lastAcceptedAt: Date?

    /// When the tally started counting, so the UI can name the window it actually measures.
    ///
    /// Not the same as when the account was connected: an account linked before this counter
    /// existed has scrobbles the counter never saw, and captioning those away as "since you
    /// connected" would understate the account by an unknowable amount.
    @Published private(set) var countingSince: Date?

    private static let acceptedCountKey = "scrobbleAcceptedCount"
    private static let lastAcceptedAtKey = "scrobbleLastAcceptedAt"
    private static let countingSinceKey = "scrobbleCountingSince"

    @AppStorage("scrobblingEnabled") var scrobblingEnabled: Bool = true
    @AppStorage("scrobbleFromMusic") var scrobbleFromMusic: Bool = true
    @AppStorage("scrobbleFromSpotify") var scrobbleFromSpotify: Bool = true
    @AppStorage("scrobbleNowPlaying") var sendNowPlayingUpdates: Bool = true
    /// Last.fm's own floor is 30 seconds; this lets a user raise it to keep jingles and
    /// interstitials off their profile.
    @AppStorage("scrobbleMinimumTrackSeconds") var minimumTrackSeconds: Int = 30

    /// Stored alongside the Keychain item so the app knows which account to look up. The
    /// username is not a secret; the session key it maps to is.
    @AppStorage("lastFMUsername") private var storedUsername: String = ""

    private var authTask: Task<Void, Never>?
    private var flushTimer: Timer?

    var isConfigured: Bool { BuildSecrets.isLastFMConfigured }

    var username: String? {
        if case .connected(let name) = connectionState { return name }
        return nil
    }

    private init() {
        let defaults = UserDefaults.standard
        acceptedCount = defaults.integer(forKey: Self.acceptedCountKey)
        let stamp = defaults.double(forKey: Self.lastAcceptedAtKey)
        lastAcceptedAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        let since = defaults.double(forKey: Self.countingSinceKey)
        countingSince = since > 0 ? Date(timeIntervalSince1970: since) : nil

        #if DEBUG
        // Cheap way to tell a build that shipped without credentials from one that has them,
        // without ever printing the values.
        NSLog("PlayStatus scrobble: Last.fm credentials %@",
              BuildSecrets.isLastFMConfigured ? "present" : "absent")
        #endif

        if !BuildSecrets.isLastFMConfigured {
            connectionState = .notConfigured
        } else if !storedUsername.isEmpty, sessionKey != nil {
            connectionState = .connected(username: storedUsername)
        }

        // An account linked before this counter shipped starts counting from this launch, and
        // the caption will say so rather than implying it covers the whole connection.
        if case .connected = connectionState, countingSince == nil {
            beginCounting()
        }

        refreshPendingCount()
        startFlushTimer()
        // Anything queued while offline last session goes out as soon as we are up.
        flushSoon()
    }

    // MARK: Account

    private var sessionKey: String? {
        guard !storedUsername.isEmpty else { return nil }
        return KeychainStore.get(service: Self.keychainService, account: storedUsername)
    }

    /// Runs Last.fm's desktop auth flow: request a token, send the user to approve it in a
    /// browser, then poll until it is granted.
    func connect() {
        guard BuildSecrets.isLastFMConfigured else {
            connectionState = .notConfigured
            return
        }
        authTask?.cancel()
        connectionState = .awaitingApproval
        lastStatusMessage = "Waiting for approval in your browser…"

        authTask = Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await LastFMClient.shared.requestToken()
                guard let url = await LastFMClient.shared.authorizationURL(for: token) else {
                    throw LastFMError.permanent("Could not build the Last.fm sign-in URL.")
                }
                NSWorkspace.shared.open(url)

                // Poll for roughly two minutes. Until the user clicks Allow, Last.fm answers
                // error 14, which the client reports as transient.
                let deadline = Date().addingTimeInterval(120)
                while Date() < deadline {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .seconds(3))
                    if Task.isCancelled { return }

                    do {
                        let session = try await LastFMClient.shared.session(forToken: token)
                        self.finishConnecting(key: session.key, username: session.username)
                        return
                    } catch let error as LastFMError where error.isTransient {
                        continue
                    }
                }
                self.connectionState = .failed("Sign-in timed out. Try again.")
                self.lastStatusMessage = ""
            } catch let error as LastFMError {
                self.connectionState = .failed(error.message)
                self.lastStatusMessage = ""
            } catch {
                self.connectionState = .failed(error.localizedDescription)
                self.lastStatusMessage = ""
            }
        }
    }

    func cancelConnect() {
        authTask?.cancel()
        authTask = nil
        connectionState = storedUsername.isEmpty ? .disconnected : .connected(username: storedUsername)
        lastStatusMessage = ""
    }

    private func finishConnecting(key: String, username: String) {
        guard KeychainStore.set(key, service: Self.keychainService, account: username) else {
            connectionState = .failed("Could not save the Last.fm session to your Keychain.")
            return
        }
        // Reconnecting the same account (after an expired key, say) keeps its tally; signing in
        // as someone else must not inherit the previous account's number.
        if storedUsername != username {
            acceptedCount = 0
            lastAcceptedAt = nil
            UserDefaults.standard.removeObject(forKey: Self.acceptedCountKey)
            UserDefaults.standard.removeObject(forKey: Self.lastAcceptedAtKey)
            countingSince = nil
        }
        storedUsername = username
        connectionState = .connected(username: username)
        lastStatusMessage = ""
        if countingSince == nil { beginCounting() }
        flushSoon()
    }

    func disconnect() {
        authTask?.cancel()
        authTask = nil
        if !storedUsername.isEmpty {
            KeychainStore.delete(service: Self.keychainService, account: storedUsername)
        }
        storedUsername = ""
        connectionState = BuildSecrets.isLastFMConfigured ? .disconnected : .notConfigured
        lastStatusMessage = ""
        // The tally belongs to the account that earned it. Carrying it onto whichever account
        // connects next would be a wrong number rather than a missing one.
        acceptedCount = 0
        lastAcceptedAt = nil
        countingSince = nil
        UserDefaults.standard.removeObject(forKey: Self.acceptedCountKey)
        UserDefaults.standard.removeObject(forKey: Self.lastAcceptedAtKey)
        UserDefaults.standard.removeObject(forKey: Self.countingSinceKey)
        Task {
            await ScrobbleQueue.shared.clear()
            self.refreshPendingCount()
        }
    }

    // MARK: Playback events

    /// Announces the track as "now playing". Fire-and-forget: this is a nicety, and a failure
    /// here must never affect whether the play is later scrobbled.
    func handlePlayStarted(_ track: PlayedTrack) {
        guard sendNowPlayingUpdates, shouldScrobble(providerRawValue: track.provider) else { return }
        guard let key = sessionKey else { return }

        let submission = ScrobbleSubmission(
            play: CompletedPlay(
                track: track,
                startedAt: Date(),
                listenedSeconds: 0,
                reachedScrobbleThreshold: false,
                reason: .trackChanged
            )
        )
        guard submission.isSubmittable else { return }

        Task {
            try? await LastFMClient.shared.updateNowPlaying(submission, sessionKey: key)
        }
    }

    /// Queues a play the moment it earns a scrobble.
    ///
    /// Deliberately not at track end: the queue is durable, so getting the submission into it
    /// as soon as it is owed means a crash before the track finishes cannot lose it.
    func handleThresholdReached(_ track: PlayedTrack, startedAt: Date) {
        guard shouldScrobble(providerRawValue: track.provider) else { return }
        guard track.duration >= Double(minimumTrackSeconds) else { return }

        let submission = ScrobbleSubmission(track: track, startedAt: startedAt)
        guard submission.isSubmittable else { return }

        Task {
            await ScrobbleQueue.shared.enqueue(submission)
            self.refreshPendingCount()
            await self.flushNow()
        }
    }

    private func shouldScrobble(providerRawValue: String) -> Bool {
        guard scrobblingEnabled, case .connected = connectionState else { return false }
        switch NowPlayingProvider(rawValue: providerRawValue) ?? .none {
        case .music: return scrobbleFromMusic
        case .spotify: return scrobbleFromSpotify
        case .none: return false
        }
    }

    // MARK: Queue

    func retryNow() {
        Task {
            await ScrobbleQueue.shared.clearBackoff()
            await self.flushNow()
        }
    }

    private func flushSoon() {
        Task { await flushNow() }
    }

    private func flushNow() async {
        guard scrobblingEnabled, let key = sessionKey else { return }
        let outcome = await ScrobbleQueue.shared.flush(sessionKey: key)
        refreshPendingCount()

        switch outcome {
        case .sent(let count):
            recordAccepted(count)
            // A successful send clears whatever failure was being shown; leaving a stale error
            // above a rising count is the confusing part.
            lastStatusMessage = ""
        case .failed(let error):
            if case .authenticationRequired = error {
                // The key is dead; make the user reconnect rather than retrying forever.
                connectionState = .failed("Last.fm sign-in expired. Reconnect to keep scrobbling.")
            }
            lastStatusMessage = error.message
        case .waiting, .idle:
            break
        }
    }

    /// Marks where the tally starts measuring.
    ///
    /// Backdated to the earliest play already counted, if there is one: a window that begins
    /// after a play it already includes is a contradiction the UI would print verbatim. This
    /// only bites on the upgrade from a build that counted without recording a start.
    private func beginCounting() {
        let start = min(Date(), lastAcceptedAt ?? .distantFuture)
        countingSince = start
        UserDefaults.standard.set(start.timeIntervalSince1970, forKey: Self.countingSinceKey)
    }

    private func recordAccepted(_ count: Int) {
        guard count > 0 else { return }
        if countingSince == nil { beginCounting() }
        let now = Date()
        acceptedCount += count
        lastAcceptedAt = now
        UserDefaults.standard.set(acceptedCount, forKey: Self.acceptedCountKey)
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastAcceptedAtKey)
    }

    private func refreshPendingCount() {
        Task {
            let count = await ScrobbleQueue.shared.pendingCount()
            self.pendingCount = count
        }
    }

    /// Retries on a slow timer so a queue stranded by a long outage eventually drains without
    /// the user having to touch anything.
    private func startFlushTimer() {
        flushTimer?.invalidate()
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.flushNow() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }
}
