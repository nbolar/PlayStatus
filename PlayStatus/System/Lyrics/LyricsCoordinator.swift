import Foundation
import Combine

/// Owns the lyrics pane's fetch state — payload, state, loading progress — and the retry policy
/// that produces them.
///
/// The fetch is two-legged: LRCLIB first (retried once on a hard failure), then the Music app as a
/// fallback when Music is the provider. Both legs report progress while they run, and every
/// callback has to re-check that the track it was started for is still the one playing — a fetch
/// outlives a track change, and a late answer for the previous song must not overwrite the
/// current one.
///
/// `LyricsService` performs the fetching and caching; this owns the sequencing and the state the
/// pane renders.
@MainActor
final class LyricsCoordinator: ObservableObject {
    @Published private(set) var payload: LyricsPayload? {
        didSet {
            guard payload != oldValue else { return }
            onLayoutAffectingChange?()
        }
    }
    @Published private(set) var state: LyricsState = .idle {
        didSet {
            guard state != oldValue else { return }
            onLayoutAffectingChange?()
        }
    }
    @Published private(set) var loadingProgress: LyricsLoadingProgress?
    /// True while the in-flight fetch came from the user tapping retry, which the progress view
    /// uses to skip the grace period it applies to automatic fetches.
    @Published private(set) var fetchIsUserInitiated = false
    /// True when a retry the user asked for came back with the same dead end it started from.
    /// The pane says so, rather than redrawing the original sentence as though nothing ran.
    @Published private(set) var retryFoundNothing = false

    /// Fires when `payload` or `state` changes in a way the popover has to re-lay-out for.
    var onLayoutAffectingChange: (() -> Void)?

    /// Whether the descriptor a fetch was started for still matches what is playing. Supplied by
    /// the owner, because only it knows the live track. A fetch whose descriptor has gone stale
    /// discards its result instead of publishing it.
    var isDescriptorCurrent: ((LyricsTrackDescriptor) -> Bool)?

    private var fetchTask: Task<Void, Never>?
    private var currentTrackKey: String = ""

    /// How long a user-initiated retry keeps the pane in `.loading`, even if the fetch beats it.
    ///
    /// A miss round-trips in about 0.4s, which is faster than the progress view's own grace
    /// period — the retry finished before anything was drawn, so tapping "Look again" changed
    /// nothing on screen and read as a dead button. An automatic fetch wants to stay silent when
    /// it is that quick; an explicit tap has to be acknowledged.
    private let userInitiatedFetchFloor: TimeInterval = 0.75

    // Read from the fetch's progress callbacks, which run off the main actor.
    private nonisolated static let maxAttempts = 2
    private nonisolated static let retryDelayNanos: UInt64 = 350_000_000

    #if DEBUG
    private var metricMusicAppHits: Int = 0
    private var metricLRCLIBHits: Int = 0
    private var metricUnavailable: Int = 0
    private var metricFailures: Int = 0
    #endif

    // MARK: - Lifecycle

    /// Stops any in-flight fetch and returns the pane to its empty state.
    func clear() {
        fetchTask?.cancel()
        Task {
            await LyricsService.shared.cancelAllInflightLyricsFetches()
        }
        currentTrackKey = ""
        DispatchQueue.main.async {
            self.payload = nil
            self.state = .idle
            self.loadingProgress = nil
            self.retryFoundNothing = false
        }
    }

    func start(
        for descriptor: LyricsTrackDescriptor,
        forceRefresh: Bool,
        resetState: Bool,
        userInitiated: Bool = false
    ) {
        let trackKey = descriptor.cacheKey
        currentTrackKey = trackKey
        fetchTask?.cancel()
        Task {
            await LyricsService.shared.cancelAllInflightLyricsFetches()
        }

        if resetState {
            DispatchQueue.main.async {
                self.payload = nil
                self.state = .loading
                self.loadingProgress = nil
                self.fetchIsUserInitiated = userInitiated
                self.retryFoundNothing = false
            }
        }

        fetchTask = Task { [weak self] in
            guard let self else { return }
            let fetchStart = CFAbsoluteTimeGetCurrent()
            let outcome = await self.fetchWithRetry(for: descriptor, forceRefresh: forceRefresh)
            guard !Task.isCancelled else { return }

            if userInitiated {
                let elapsed = CFAbsoluteTimeGetCurrent() - fetchStart
                let remaining = self.userInitiatedFetchFloor - elapsed
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                }
            }

            await MainActor.run {
                guard self.isStillCurrent(descriptor, trackKey: trackKey) else { return }
                self.publish(outcome, userInitiated: userInitiated)
            }
        }
    }

    /// The staleness gate every late callback goes through: the key guards against a newer fetch
    /// having started, the descriptor check against the track having changed underneath it.
    private func isStillCurrent(_ descriptor: LyricsTrackDescriptor, trackKey: String) -> Bool {
        currentTrackKey == trackKey && (isDescriptorCurrent?(descriptor) ?? false)
    }

    private func publish(_ outcome: LyricsFetchOutcome, userInitiated: Bool) {
        switch outcome {
        case .available(let payload):
            self.payload = payload
            state = .available
            loadingProgress = nil
            #if DEBUG
            if payload.source == .musicApp {
                metricMusicAppHits += 1
            } else if payload.source == .lrclib {
                metricLRCLIBHits += 1
            }
            logMetrics()
            #endif
        case .instrumental:
            payload = nil
            state = .instrumental
            loadingProgress = nil
        case .unavailable:
            payload = nil
            state = .unavailable
            loadingProgress = nil
            retryFoundNothing = userInitiated
            #if DEBUG
            metricUnavailable += 1
            logMetrics()
            #endif
        case .failed:
            payload = nil
            state = .failed
            loadingProgress = nil
            retryFoundNothing = userInitiated
            #if DEBUG
            metricFailures += 1
            logMetrics()
            #endif
        }
    }

    #if DEBUG
    private func logMetrics() {
        NSLog(
            "PlayStatus lyrics metrics: musicApp=\(metricMusicAppHits) lrclib=\(metricLRCLIBHits) unavailable=\(metricUnavailable) failed=\(metricFailures)"
        )
    }
    #endif

    // MARK: - Fetch policy

    private func fetchWithRetry(for descriptor: LyricsTrackDescriptor, forceRefresh: Bool) async -> LyricsFetchOutcome {
        var attempt = 0
        var lastLRCLIBOutcome: LyricsFetchOutcome = .unavailable
        let trackKey = descriptor.cacheKey

        #if DEBUG
        let totalStartTime = CFAbsoluteTimeGetCurrent()
        let logTotal: (LyricsFetchOutcome, String) -> Void = { outcome, note in
            let totalDuration = CFAbsoluteTimeGetCurrent() - totalStartTime
            NSLog(
                "PlayStatus lyrics timing: provider=%@ total=%.3fs outcome=%@ note=%@",
                descriptor.provider.rawValue,
                totalDuration,
                Self.outcomeDescription(outcome),
                note
            )
        }
        #endif

        attemptLoop: while attempt < Self.maxAttempts {
            if Task.isCancelled { return .failed }

            let shouldForceRefresh = forceRefresh || attempt > 0
            let attemptNumber = attempt + 1

            #if DEBUG
            let attemptStartTime = CFAbsoluteTimeGetCurrent()
            #endif

            let outcome = await LyricsService.shared.fetchLyrics(
                for: descriptor,
                forceRefresh: shouldForceRefresh,
                mode: .lrclibOnly,
                cacheUnavailableResult: false
            ) { [weak self] stage in
                self?.reportProgress(
                    stage: stage,
                    attempt: attemptNumber,
                    descriptor: descriptor,
                    trackKey: trackKey
                )
            }

            #if DEBUG
            let attemptDuration = CFAbsoluteTimeGetCurrent() - attemptStartTime
            NSLog(
                "PlayStatus lyrics timing: provider=%@ phase=lrclib attempt=%d/%d duration=%.3fs outcome=%@",
                descriptor.provider.rawValue,
                attemptNumber,
                Self.maxAttempts,
                attemptDuration,
                Self.outcomeDescription(outcome)
            )
            #endif

            lastLRCLIBOutcome = outcome

            switch outcome {
            case .available:
                #if DEBUG
                logTotal(outcome, "lrclib_success")
                #endif
                return outcome
            case .instrumental:
                #if DEBUG
                logTotal(outcome, "lrclib_instrumental")
                #endif
                return outcome
            case .failed:
                attempt += 1
                guard attempt < Self.maxAttempts else { break }
                try? await Task.sleep(nanoseconds: Self.retryDelayNanos)
            case .unavailable:
                break attemptLoop
            }
        }

        if Task.isCancelled { return .failed }

        guard descriptor.provider == .music else {
            #if DEBUG
            logTotal(lastLRCLIBOutcome, "skip_music_fallback_non_music_provider")
            #endif
            return lastLRCLIBOutcome
        }

        #if DEBUG
        let fallbackStartTime = CFAbsoluteTimeGetCurrent()
        #endif

        // A cached "no lyrics" is a 24-hour answer, so only record one when both legs actually
        // answered. If LRCLIB's leg failed — offline, timeout, a 5xx — then a Music app miss says
        // nothing about whether the track has lyrics, and caching it would hide the real lyrics
        // behind "No lyrics found" for the rest of the day. The outcome returned below is already
        // corrected to `.failed` for this case, but that correction happens *after* the service
        // has written its cache entry, which is what made the stale miss stick.
        let lrclibLegAnswered: Bool
        if case .failed = lastLRCLIBOutcome {
            lrclibLegAnswered = false
        } else {
            lrclibLegAnswered = true
        }

        let musicFallbackOutcome = await LyricsService.shared.fetchLyrics(
            for: descriptor,
            forceRefresh: true,
            mode: .musicOnly,
            cacheUnavailableResult: lrclibLegAnswered
        ) { [weak self] stage in
            self?.reportProgress(
                stage: stage,
                attempt: Self.maxAttempts,
                descriptor: descriptor,
                trackKey: trackKey
            )
        }

        #if DEBUG
        let fallbackDuration = CFAbsoluteTimeGetCurrent() - fallbackStartTime
        NSLog(
            "PlayStatus lyrics timing: provider=%@ phase=music_fallback duration=%.3fs outcome=%@",
            descriptor.provider.rawValue,
            fallbackDuration,
            Self.outcomeDescription(musicFallbackOutcome)
        )
        #endif

        switch musicFallbackOutcome {
        case .instrumental:
            return musicFallbackOutcome
        case .available:
            #if DEBUG
            logTotal(musicFallbackOutcome, "music_fallback_success")
            #endif
            return musicFallbackOutcome
        case .failed:
            #if DEBUG
            logTotal(.failed, "music_fallback_failed")
            #endif
            return .failed
        case .unavailable:
            if case .failed = lastLRCLIBOutcome {
                #if DEBUG
                logTotal(.failed, "lrclib_failed_and_music_unavailable")
                #endif
                return .failed
            }
            #if DEBUG
            logTotal(.unavailable, "music_fallback_unavailable")
            #endif
            return .unavailable
        }
    }

    private nonisolated func reportProgress(
        stage: LyricsLoadingStage,
        attempt: Int,
        descriptor: LyricsTrackDescriptor,
        trackKey: String
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isStillCurrent(descriptor, trackKey: trackKey) else { return }

            self.loadingProgress = LyricsLoadingProgress(
                attempt: attempt,
                maxAttempts: Self.maxAttempts,
                stage: stage,
                stageIndex: stage.rawValue,
                stageCount: LyricsLoadingStage.allCases.count
            )
        }
    }

    #if DEBUG
    private nonisolated static func outcomeDescription(_ outcome: LyricsFetchOutcome) -> String {
        switch outcome {
        case .available:
            return "available"
        case .instrumental:
            return "instrumental"
        case .unavailable:
            return "unavailable"
        case .failed:
            return "failed"
        }
    }
    #endif
}
