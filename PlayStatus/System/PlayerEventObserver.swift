import Foundation
import AppKit

/// The part of a track Music tells us for free when playback changes.
///
/// Music's `playerInfo` payload carries eight of the sixteen fields the metadata script reads,
/// which is what lets `MusicProvider` skip most of its Apple Events on the common path. What it
/// does *not* carry is equally load-bearing, so it is worth naming: player position, album
/// artist, disc number, track number, year, favourited, shuffle and repeat. Those still come
/// from the player, just far less often. See `MusicProvider.fetch`.
///
/// Spotify's payload is the richer of the two — it carries album artist and track number where
/// Music does not — so the optional fields below are populated for Spotify and left nil for
/// Music rather than being faked with empty strings. nil means "this player didn't say",
/// which is the difference between reusing a cached value and overwriting it with a blank.
struct PlayerEventPayload {
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    var genre: String
    var composer: String
    var albumArtist: String?
    var trackNumber: Int?
    var discNumber: Int?
    /// Seconds. Both players report milliseconds; converted at the parse boundary.
    var duration: Double
    /// Whatever string the player's own scripting interface returns for track identity —
    /// Music's 16-digit hex persistent ID, Spotify's `spotify:track:…` URI. Only ever compared
    /// against a value read back from that same player, never across providers.
    var trackIdentity: String
    /// `systemUptime` at receipt, for staleness checks against a wall clock that cannot jump.
    var receivedAt: TimeInterval

    /// Builds a payload from a full read instead of a broadcast.
    ///
    /// Without this the fast path only ever engages *after* a notification, and a player that
    /// was already paused when the app launched never sends one — so it would sit on the
    /// 280ms script forever. Seeding from the first successful read makes one full fetch, not
    /// one broadcast, the thing that unlocks the cheap path.
    init(
        isPlaying: Bool,
        title: String,
        artist: String,
        album: String,
        genre: String = "",
        composer: String = "",
        albumArtist: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        duration: Double,
        trackIdentity: String
    ) {
        self.isPlaying = isPlaying
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.composer = composer
        self.albumArtist = albumArtist
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.duration = duration
        self.trackIdentity = trackIdentity
        self.receivedAt = ProcessInfo.processInfo.systemUptime
    }

    /// Spotify's `PlaybackStateChanged` payload.
    ///
    /// `Playback Position` is deliberately ignored. The one captured sample read 0 (a track
    /// start), which is consistent with both seconds and milliseconds, and a units mistake here
    /// is the same silent 1000x bug as `Total Time`. Position is read from the player instead —
    /// a single Apple Event that the poll needs anyway for drift and seek detection.
    init?(spotifyUserInfo info: [AnyHashable: Any]) {
        guard let title = info["Name"] as? String, !title.isEmpty else { return nil }

        let state = (info["Player State"] as? String ?? "").lowercased()
        self.isPlaying = (state == "playing")
        self.title = title
        self.artist = info["Artist"] as? String ?? ""
        self.album = info["Album"] as? String ?? ""
        self.genre = ""
        self.composer = ""
        self.albumArtist = info["Album Artist"] as? String
        self.trackNumber = (info["Track Number"] as? NSNumber)?.intValue
        self.discNumber = (info["Disc Number"] as? NSNumber)?.intValue

        if let milliseconds = info["Duration"] as? NSNumber {
            self.duration = milliseconds.doubleValue / 1000
        } else {
            self.duration = 0
        }

        self.trackIdentity = info["Track ID"] as? String ?? ""
        self.receivedAt = ProcessInfo.processInfo.systemUptime
    }

    init?(musicUserInfo info: [AnyHashable: Any]) {
        guard let title = info["Name"] as? String, !title.isEmpty else { return nil }

        // "Playing" / "Paused" / "Stopped" — capitalised here, lowercase from AppleScript.
        let state = (info["Player State"] as? String ?? "").lowercased()
        self.isPlaying = (state == "playing")
        self.title = title
        self.artist = info["Artist"] as? String ?? ""
        self.album = info["Album"] as? String ?? ""
        self.genre = info["Genre"] as? String ?? ""
        self.composer = info["Composer"] as? String ?? ""
        // Music's broadcast carries neither; nil keeps them coming from the cold read.
        self.albumArtist = nil
        self.trackNumber = nil
        self.discNumber = nil

        // `Total Time` is milliseconds where AppleScript's `duration` is seconds. Reading it
        // raw is a silent 1000x error in every progress bar and seek, so it converts here and
        // nowhere else.
        if let milliseconds = info["Total Time"] as? NSNumber {
            self.duration = milliseconds.doubleValue / 1000
        } else {
            self.duration = 0
        }

        // `PersistentID` arrives as a *signed* 64-bit number, while every cache key in the app
        // is built from AppleScript's unsigned hex string. Reinterpreting the bit pattern is
        // what makes the two agree — verified against a library lookup, not assumed.
        if let identifier = info["PersistentID"] as? NSNumber {
            self.trackIdentity = String(format: "%016llX", UInt64(bitPattern: identifier.int64Value))
        } else {
            self.trackIdentity = ""
        }

        self.receivedAt = ProcessInfo.processInfo.systemUptime
    }
}

/// Listens for the notifications Music and Spotify broadcast when playback changes.
///
/// Both apps post a distributed notification on every track change and every play/pause, so
/// the app does not have to discover those by asking twice a second. Polling still has a job —
/// nothing is broadcast while a track simply plays, and neither app announces a user scrubbing
/// — but it drops to a slow drift-correction cadence, because `PlaybackClock` extrapolates the
/// position locally between syncs.
///
/// Two things this buys beyond the wakeups it saves: playback changes show up immediately
/// rather than up to a poll late, and the refresh happens *after* the track has settled instead
/// of potentially landing mid-flip, which is where torn AppleScript reads came from.
///
/// Requires the app to be unsandboxed, which it is (it drives both players over Apple Events).
@MainActor
final class PlayerEventObserver: NSObject {
    /// Music posts under its modern name; older systems and the iTunes-era binary post under
    /// the legacy one. Observing both is still the right call — either could be the only one a
    /// given system sends — but on macOS 26 Music sends *both*, same instant, byte-identical
    /// payloads. Left alone that is two full metadata reads per track change instead of one,
    /// and a metadata read is ~270ms of Apple Events. See `isDuplicate`.
    private static let notificationNames: [(name: String, provider: NowPlayingProvider)] = [
        ("com.apple.Music.playerInfo", .music),
        ("com.apple.iTunes.playerInfo", .music),
        ("com.spotify.client.PlaybackStateChanged", .spotify)
    ]

    /// How long a payload stays "already seen". Only has to outlast the gap between the paired
    /// Music notifications, which land in the same run loop turn; a second under a second is
    /// slack for a loaded machine, not a real debounce interval.
    private static let duplicateWindow: TimeInterval = 1.0

    private var isRegistered = false
    private var handler: ((NowPlayingProvider, PlayerEventPayload?) -> Void)?
    private var lastPayload: [NowPlayingProvider: (signature: String, at: TimeInterval)] = [:]

    var isObserving: Bool { isRegistered }

    /// Registers with `deliverImmediately`, which is the whole reason this uses the selector API.
    ///
    /// The block-based `addObserver` gives no way to set a suspension behaviour, so it takes the
    /// default — `coalesce` — under which the system holds notifications while the process is
    /// suspended and delivers at most one stale summary on resume. A menu bar app with no
    /// visible window is exactly the kind of process macOS suspends via App Nap, so in practice
    /// broadcasts simply stopped arriving after the app had been idle for a while: five track
    /// changes in a row were discovered by polling instead, with not one notification among them.
    ///
    /// Nothing about that failure is loud. The app keeps working, just on the expensive path,
    /// which is why `noteChangeAnnouncement` exists to notice and say so.
    func start(onEvent: @escaping (NowPlayingProvider, PlayerEventPayload?) -> Void) {
        guard !isRegistered else { return }
        handler = onEvent

        let center = DistributedNotificationCenter.default()
        for entry in Self.notificationNames {
            center.addObserver(
                self,
                selector: #selector(handleDistributedNotification(_:)),
                name: Notification.Name(entry.name),
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
        isRegistered = true

        #if DEBUG
        NSLog("PlayStatus events: observing %d player notifications (deliverImmediately)", Self.notificationNames.count)
        #endif
    }

    @objc
    private func handleDistributedNotification(_ note: Notification) {
        guard let entry = Self.notificationNames.first(where: { $0.name == note.name.rawValue }) else { return }

        MainActor.assumeIsolated {
            guard !isDuplicate(note, from: entry.provider) else {
                #if DEBUG
                NSLog("PlayStatus events: dropped duplicate %@ broadcast", entry.name)
                #endif
                return
            }

            let payload: PlayerEventPayload?
            switch entry.provider {
            case .music:
                payload = note.userInfo.flatMap(PlayerEventPayload.init(musicUserInfo:))
            case .spotify:
                payload = note.userInfo.flatMap(PlayerEventPayload.init(spotifyUserInfo:))
            case .none:
                payload = nil
            }
            handler?(entry.provider, payload)
        }
    }

    /// Whether this broadcast repeats one the same player just sent.
    ///
    /// Matching on the payload rather than on arrival time is what keeps this from being a
    /// debounce: a genuine second change — a fast double-skip — carries a different track and
    /// passes straight through with no delay added. Only a byte-identical repeat is dropped,
    /// which is exactly the Music/iTunes pair and nothing else.
    ///
    /// An empty payload is never treated as a duplicate. Two distinct events would both
    /// signature as empty, and silently swallowing a real change to save one read is the wrong
    /// side of that trade.
    private func isDuplicate(_ note: Notification, from provider: NowPlayingProvider) -> Bool {
        let signature = Self.signature(for: note)
        guard !signature.isEmpty else { return false }

        let now = ProcessInfo.processInfo.systemUptime
        if let previous = lastPayload[provider],
           previous.signature == signature,
           now - previous.at < Self.duplicateWindow {
            return true
        }

        lastPayload[provider] = (signature, now)
        return false
    }

    /// Order-independent digest of a notification's payload.
    ///
    /// `userInfo` is a dictionary, so the two Music broadcasts enumerate their identical
    /// contents in different orders — sorting by key is what makes them compare equal.
    private static func signature(for note: Notification) -> String {
        guard let info = note.userInfo, !info.isEmpty else { return "" }
        return info
            .map { "\($0.key)=\(String(describing: $0.value))" }
            .sorted()
            .joined(separator: "\u{1F}")
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        isRegistered = false
        handler = nil
        lastPayload.removeAll()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
