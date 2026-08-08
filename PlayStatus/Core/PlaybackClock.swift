import Foundation
import SwiftUI
import Combine

/// Holds only the rapidly-changing playback position values.
/// Separated from NowPlayingModel so that the 0.5-second elapsed/duration
/// tick does NOT trigger objectWillChange on NowPlayingModel, which would
/// force the entire NowPlayingPopover view tree to re-render on every tick.
/// On macOS 26, every SwiftUI body re-render inside an NSPopover invokes
/// DesignLibrary.AppKitPlatformGlassDefinition — keeping the tick isolated
/// here prevents the glass compositor from running in a hot loop.
final class PlaybackClock: ObservableObject {
    static let shared = PlaybackClock()
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    private var isAdvancing = false
    private var lastSyncUptime: TimeInterval = ProcessInfo.processInfo.systemUptime

    /// Monotonic clock, injectable so the projection rules can be driven deterministically
    /// rather than in real time. Same seam as `PlaybackSessionTracker`.
    var uptimeProvider: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    var liveElapsed: Double {
        let upperBound = duration > 0 ? duration : .greatestFiniteMagnitude
        let resolvedElapsed: Double
        if isAdvancing {
            let delta = max(0, uptimeProvider() - lastSyncUptime)
            resolvedElapsed = elapsed + delta
        } else {
            resolvedElapsed = elapsed
        }
        return min(max(resolvedElapsed, 0), upperBound)
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(liveElapsed / duration, 0), 1)
    }
    var canSeek: Bool { duration > 0.5 }

    // MARK: Smooth advance between syncs

    /// Bumped on every sync. Views animate off this rather than off `progress`, which changes
    /// continuously with the clock and so can never be a stable `value:` to compare against.
    @Published private(set) var positionEpoch: Int = 0

    /// Where the position will be when the next sync is due.
    private(set) var projectedElapsed: Double = 0
    /// How long that projection covers. Zero means "snap" — a seek, a pause, a track change.
    private(set) var projectionDuration: Double = 0

    /// Measured gap between the last two syncs, which is how far ahead it is safe to project.
    ///
    /// Measured rather than told: the metadata poll runs anywhere from 0.5s to 3s depending on
    /// whether the player is broadcasting its own changes, and this tracks that on its own.
    private var lastSyncInterval: Double = 0
    private let minimumProjection: Double = 0.25
    private let maximumProjection: Double = 3.0
    /// Beyond this, the new reading is a seek or a track change rather than drift, and the bar
    /// should jump to it instead of gliding.
    private let continuityTolerance: Double = 1.0

    var projectedProgress: Double {
        guard duration > 0 else { return 0 }
        return min(max(projectedElapsed / duration, 0), 1)
    }

    /// Linear because playback is linear — any easing would visibly speed up and slow down
    /// against a position that does neither.
    var progressAnimation: Animation? {
        projectionDuration > 0 ? .linear(duration: projectionDuration) : nil
    }

    /// - Parameter sampledAtUptime: when `elapsed` was actually observed. Defaults to now, which
    ///   is correct for a value the caller just produced itself (a seek), but a value read from
    ///   a player must pass the timestamp of the read — otherwise the read's own latency is
    ///   silently added to the playback position.
    func sync(
        elapsed: Double,
        duration: Double,
        isPlaying: Bool,
        sampledAtUptime: TimeInterval? = nil
    ) {
        let now = uptimeProvider()
        let sampledAt = sampledAtUptime ?? now
        let resolvedElapsed = max(0, elapsed)
        let resolvedDuration = max(0, duration)

        // Compare against where the previous sync said we would be by now. A poll that merely
        // confirms the extrapolation is a continuation; anything further off is a real jump.
        let predicted = liveElapsed
        let hadPosition = isAdvancing
        let durationChanged = abs(resolvedDuration - self.duration) > 0.5
        let willAdvance = isPlaying && resolvedDuration > 0.5
        let observedInterval = max(0, sampledAt - lastSyncUptime)
        // A long silence — the machine slept, the app was starved — is a discontinuity even
        // when the position lines up perfectly, because the bar has been stalled at a stale
        // value the whole time. Gliding from there would sweep across the track like a scrub
        // the user never asked for; it has to jump.
        let gapIsPlausible = observedInterval <= maximumProjection

        let isContinuation = willAdvance
            && hadPosition
            && !durationChanged
            && gapIsPlausible
            && abs(resolvedElapsed - predicted) <= continuityTolerance

        self.elapsed = resolvedElapsed
        self.duration = resolvedDuration
        self.isAdvancing = willAdvance
        self.lastSyncUptime = sampledAt

        if isContinuation, lastSyncInterval > 0 {
            // Project exactly one polling interval ahead and glide there over that interval, so
            // the bar tracks the true position instead of standing still and then jumping. Any
            // overshoot would have to be corrected backwards on the next sync, which reads far
            // worse than the brief pause a late poll causes.
            let window = min(max(lastSyncInterval, minimumProjection), maximumProjection)
            projectionDuration = window
            projectedElapsed = min(resolvedElapsed + window, resolvedDuration)
        } else {
            projectionDuration = 0
            projectedElapsed = resolvedElapsed
        }

        // Recorded after use, so the first sync of a run projects nothing and simply snaps.
        lastSyncInterval = observedInterval > 0 ? observedInterval : lastSyncInterval
        positionEpoch &+= 1
    }

    /// Not private: the shared instance is what the app uses, but the projection rules are
    /// worth exercising against a throwaway instance with a controlled clock.
    init() {}
}
