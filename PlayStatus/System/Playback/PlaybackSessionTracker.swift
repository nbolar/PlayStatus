import Foundation

/// A track, reduced to the fields worth keeping after it has stopped playing.
///
/// `NowPlayingSnapshot` carries live playback state and an `NSImage`; neither survives being
/// written to disk or sent to a scrobbling API. This is the durable half.
struct PlayedTrack: Codable, Equatable {
    let provider: String
    let title: String
    let artist: String
    /// The three fields below are `var` because a provisional publish can announce a track
    /// before the follow-up read supplies them. See `mergingLateMetadata`.
    var albumArtist: String
    let album: String
    /// Seconds. Zero when the provider had not reported a duration yet.
    var duration: Double
    /// Music's persistent ID or Spotify's `spotify:track:…` URI. Empty when unknown.
    var trackIdentity: String

    init(snapshot: NowPlayingSnapshot) {
        self.provider = snapshot.provider.rawValue
        self.title = snapshot.title
        self.artist = snapshot.artist
        self.albumArtist = snapshot.albumArtist
        self.album = snapshot.album
        self.duration = snapshot.duration
        self.trackIdentity = snapshot.trackIdentity
    }

    /// Whether two observations describe the same playing track.
    ///
    /// Duration is excluded on purpose: a provisional publish arrives with `duration == 0` and
    /// is filled in a poll later, and Music and Spotify each round the value differently
    /// between their broadcast and script paths. Including it would split one play in two.
    ///
    /// `trackIdentity` is only consulted when both sides have one. It is the strongest signal
    /// available — it distinguishes two different recordings of the same song title — but it is
    /// absent on the provisional path, so it cannot be the sole basis for comparison.
    func matches(_ other: PlayedTrack) -> Bool {
        guard provider == other.provider else { return false }
        if !trackIdentity.isEmpty, !other.trackIdentity.isEmpty {
            return trackIdentity == other.trackIdentity
        }
        return title == other.title && artist == other.artist && album == other.album
    }

    var isPlayable: Bool {
        !title.isEmpty && provider != NowPlayingProvider.none.rawValue
    }
}

/// A play that has ended, whether or not it counted.
struct CompletedPlay: Equatable {
    let track: PlayedTrack
    /// When playback of this track began, in UTC. Back-dated by the position already elapsed
    /// when PlayStatus first saw the track, so a play discovered mid-song is still timestamped
    /// from its real start.
    let startedAt: Date
    /// Actual seconds listened, excluding paused time and skipped-over spans.
    let listenedSeconds: Double
    /// Whether this play met the scrobble threshold. Plays that did not are still reported —
    /// history records skips — but must not be scrobbled.
    let reachedScrobbleThreshold: Bool
    /// Why the play ended. Useful for diagnosing accumulation bugs from a log.
    let reason: EndReason

    enum EndReason: String, Equatable {
        case trackChanged
        case restarted
        case idle
        case appTerminating
    }
}

/// Decides when a play counted.
///
/// Both scrobbling and play history need this judgment, and it is subtle enough — seeking,
/// pausing, repeat-one, short tracks — that having two implementations would guarantee two
/// different answers. This is the only place the rules live.
///
/// Main-actor isolated because its sole feed, `NowPlayingModel.applyFetchedSnapshots`, already
/// runs on the main queue. That buys ordered, lock-free access to the session state.
@MainActor
final class PlaybackSessionTracker {
    static let shared = PlaybackSessionTracker()

    /// Called when any play ends, including skips. Consumers filter on
    /// `reachedScrobbleThreshold` themselves.
    var onPlayFinished: ((CompletedPlay) -> Void)?

    /// Called when a track starts. Distinct from `onPlayFinished` because Last.fm's
    /// "now playing" is announced up front, long before the play has earned a scrobble.
    var onPlayStarted: ((PlayedTrack) -> Void)?

    /// Called the moment a play earns a scrobble, which is not the moment it ends.
    ///
    /// Waiting for the end left a window — often minutes on a long track — where the play was
    /// owed but unsent, and only a clean termination flushed it; a crash or force-quit inside
    /// that window lost it. Fires exactly once per session, guarded by `reachedThreshold`.
    var onPlayReachedThreshold: ((PlayedTrack, Date) -> Void)?

    /// Monotonic clock, injectable so the accumulation rules can be driven deterministically
    /// instead of in real time.
    var uptimeProvider: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    // MARK: Thresholds

    /// Last.fm will not accept a scrobble for anything shorter than this.
    private let minimumScrobbleableDuration: Double = 30
    /// A play counts at half the track, or after four minutes, whichever comes first.
    private let scrobbleTimeCap: Double = 240

    /// How far the position may run ahead of the wall clock before the excess is treated as a
    /// seek rather than as listening.
    ///
    /// Polls arrive between 0.5s and 3s apart, and the position read is not perfectly
    /// simultaneous with the sample timestamp, so a little slack is required. Beyond it, the
    /// only explanation for the position advancing faster than time is that the user moved it.
    private let positionDriftTolerance: Double = 1.5
    private let positionDriftGrace: Double = 0.5

    /// A backward jump larger than this, landing near the very start of the track, is a replay
    /// rather than a rewind. This is what repeat-one looks like from out here.
    private let restartBackwardJump: Double = 5.0
    private let restartLandingZone: Double = 5.0

    /// Below this, a play is not reported at all.
    ///
    /// Holding down *next* to get through a playlist opens and closes a session per track, and
    /// a wrap into repeat-one opens one final session that the app may never play. Without a
    /// floor those all become history rows for music nobody heard.
    private let minimumRecordableListening: Double = 3.0

    // MARK: Session state

    private struct Session {
        var track: PlayedTrack
        var startedAt: Date
        var listenedSeconds: Double
        var lastPosition: Double
        var lastSampleUptime: TimeInterval
        var reachedThreshold: Bool
    }

    private var session: Session?

    /// Not private: the shared instance is the one the app uses, but the rules above are worth
    /// exercising against a throwaway instance with a controlled clock.
    init() {}

    // MARK: Feed

    /// Records one observation. Safe to call at any cadence, including on polls where nothing
    /// changed; the accumulator is driven by position deltas, not by call count.
    ///
    /// Pass `nil` when no provider is playing anything.
    func observe(_ snapshot: NowPlayingSnapshot?) {
        let now = uptimeProvider()

        guard let snapshot else {
            finishSession(reason: .idle)
            return
        }

        let incoming = PlayedTrack(snapshot: snapshot)
        guard incoming.isPlayable else {
            finishSession(reason: .idle)
            return
        }

        guard var active = session else {
            session = beginSession(with: incoming, position: snapshot.elapsed, at: now)
            return
        }

        guard active.track.matches(incoming) else {
            finishSession(reason: .trackChanged)
            session = beginSession(with: incoming, position: snapshot.elapsed, at: now)
            return
        }

        // Same track. Late-arriving metadata replaces the placeholders a provisional publish
        // left behind, so what eventually gets scrobbled is the complete record.
        active.track = mergingLateMetadata(into: active.track, from: incoming)

        let position = snapshot.elapsed
        let positionDelta = position - active.lastPosition

        if positionDelta < -restartBackwardJump, position < restartLandingZone {
            // Back to the top of the same track: repeat-one, or the user restarting it. That is
            // a second play, not a continuation of the first.
            session = active
            finishSession(reason: .restarted)
            session = beginSession(with: incoming, position: position, at: now)
            return
        }

        if positionDelta > 0, snapshot.isPlaying {
            // Credit the position delta, but never more than wall-clock time can account for.
            // A forward seek shows up here as a delta far larger than the elapsed interval; only
            // the plausible part of it is listening.
            let wallClockDelta = max(0, now - active.lastSampleUptime)
            let creditable = wallClockDelta * positionDriftTolerance + positionDriftGrace
            active.listenedSeconds += min(positionDelta, creditable)
        }
        // A negative delta that is not a restart is a rewind, and a zero delta is a paused or
        // stalled player. Neither earns credit, and neither ends the play.

        active.lastPosition = position
        active.lastSampleUptime = now

        if !active.reachedThreshold, meetsThreshold(listened: active.listenedSeconds, duration: active.track.duration) {
            active.reachedThreshold = true
            #if DEBUG
            NSLog("PlayStatus scrobble: threshold reached title=%@ listened=%.1f duration=%.1f",
                  active.track.title, active.listenedSeconds, active.track.duration)
            #endif
            // Written back before notifying: the callback is synchronous, and a consumer that
            // re-entered `observe` must not find a session still marked as un-earned.
            session = active
            onPlayReachedThreshold?(active.track, active.startedAt)
            return
        }

        session = active
    }

    /// Ends any in-flight play. Call on termination so the last track of a session is not lost.
    func flush() {
        finishSession(reason: .appTerminating)
    }

    // MARK: Internals

    private func beginSession(with track: PlayedTrack, position: Double, at uptime: TimeInterval) -> Session {
        // Back-date the start by however far into the track we came in. Launching PlayStatus
        // 40 seconds into a song should still timestamp the play from where the song began.
        let startedAt = Date().addingTimeInterval(-max(0, position))
        #if DEBUG
        NSLog("PlayStatus scrobble: begin title=%@ artist=%@ position=%.1f duration=%.1f id=%@",
              track.title, track.artist, position, track.duration,
              track.trackIdentity.isEmpty ? "-" : track.trackIdentity)
        #endif
        onPlayStarted?(track)
        return Session(
            track: track,
            startedAt: startedAt,
            listenedSeconds: 0,
            lastPosition: position,
            lastSampleUptime: uptime,
            reachedThreshold: false
        )
    }

    private func finishSession(reason: CompletedPlay.EndReason) {
        guard let active = session else { return }
        session = nil

        // A session that reached the threshold is always reported, floor or not — the threshold
        // cannot be met below it, but keeping the condition explicit means a future change to
        // either constant cannot silently drop a scrobble.
        guard active.reachedThreshold || active.listenedSeconds >= minimumRecordableListening else {
            #if DEBUG
            NSLog("PlayStatus scrobble: discarded title=%@ listened=%.1f reason=%@",
                  active.track.title, active.listenedSeconds, reason.rawValue)
            #endif
            return
        }

        let play = CompletedPlay(
            track: active.track,
            startedAt: active.startedAt,
            listenedSeconds: active.listenedSeconds,
            reachedScrobbleThreshold: active.reachedThreshold,
            reason: reason
        )

        #if DEBUG
        NSLog("PlayStatus scrobble: finished title=%@ listened=%.1f duration=%.1f counted=%@ reason=%@",
              play.track.title, play.listenedSeconds, play.track.duration,
              play.reachedScrobbleThreshold ? "yes" : "no", reason.rawValue)
        #endif

        onPlayFinished?(play)
    }

    private func meetsThreshold(listened: Double, duration: Double) -> Bool {
        guard duration > minimumScrobbleableDuration else { return false }
        return listened >= min(duration / 2, scrobbleTimeCap)
    }

    /// Fills in fields the first observation of a track did not have yet.
    ///
    /// The provisional-publish path announces a track from a broadcast before the follow-up
    /// read supplies duration, album artist, and the provider's own identifier. Whichever
    /// observation happens to start the session should not be the one that decides what gets
    /// recorded.
    private func mergingLateMetadata(into stored: PlayedTrack, from incoming: PlayedTrack) -> PlayedTrack {
        var merged = stored
        if merged.duration <= 0, incoming.duration > 0 {
            merged.duration = incoming.duration
        }
        if merged.albumArtist.isEmpty, !incoming.albumArtist.isEmpty {
            merged.albumArtist = incoming.albumArtist
        }
        if merged.trackIdentity.isEmpty, !incoming.trackIdentity.isEmpty {
            merged.trackIdentity = incoming.trackIdentity
        }
        return merged
    }
}
