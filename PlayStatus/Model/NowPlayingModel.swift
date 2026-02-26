import SwiftUI
import AppKit
import Combine
import ServiceManagement
import CoreAudio

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
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }
    var canSeek: Bool { duration > 0.5 }
    private init() {}
}

final class NowPlayingModel: ObservableObject {
    static let shared = NowPlayingModel()

    private enum MetadataPollingMode {
        case playing
        case pausedTrack
        case idle

        var interval: TimeInterval {
            switch self {
            case .playing:
                return 0.5
            case .pausedTrack:
                return 1.0
            case .idle:
                return 5.0
            }
        }

        var debugLabel: String {
            switch self {
            case .playing:
                return "playing"
            case .pausedTrack:
                return "paused"
            case .idle:
                return "idle"
            }
        }
    }

    // User toggles (didSet is the AppStore-safe way to auto-refresh; avoids CombineLatest Binding errors)
    @AppStorage("enableMusic") var enableMusic: Bool = true { didSet { refresh() } }
    @AppStorage("enableSpotify") var enableSpotify: Bool = true { didSet { refresh() } }
    @AppStorage("providerPriority") private var providerPriorityRaw: String = ProviderPriority.musicFirst.rawValue { didSet { refresh() } }
    @AppStorage("menuBarTextMode") private var menuBarTextModeRaw: String = MenuBarTextMode.artistAndSong.rawValue { didSet { refresh(); configureMarquee(forceRestart: true); bumpStatusBarConfigRevision() } }
    @AppStorage("preferredProvider") private var preferredProviderRaw: String = PreferredProvider.automatic.rawValue { didSet { refresh() } }
    @Published var ignoreParentheses: Bool = UserDefaults.standard.bool(forKey: "ignoreParentheses") {
        didSet {
            UserDefaults.standard.set(ignoreParentheses, forKey: "ignoreParentheses")
            refresh()
            configureMarquee(forceRestart: true)
            bumpStatusBarConfigRevision()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.title = self.title
            }
        }
    }
    @AppStorage("scrollableTitle") var scrollableTitle: Bool = true { didSet { configureMarquee(forceRestart: true); bumpStatusBarConfigRevision() } }
    @AppStorage("slideTitleOnChange") var slideTitleOnChange: Bool = false
    @AppStorage("statusTextWidth") private var statusTextWidthStorage: Double = 140
    @AppStorage("artworkColorIntensity") private var artworkColorIntensityStorage: Double = 1.0
    @AppStorage("artworkDisplaySize") private var artworkDisplaySizeStorage: Double = 200
    @AppStorage("animatedArtworkEnabled") var animatedArtworkEnabled: Bool = true {
        didSet {
            handleAnimatedArtworkSettingChanged()
        }
    }
    @AppStorage("animatedArtworkStreamsEnabled") var animatedArtworkStreamsEnabled: Bool = true {
        didSet {
            handleAnimatedArtworkSettingChanged()
        }
    }
    @AppStorage("animatedArtworkQualityPolicy") private var animatedArtworkQualityPolicyRaw: String = AnimatedArtworkQualityPolicy.adaptive1080.rawValue {
        didSet {
            refreshAnimatedArtworkForCurrentTrack(force: true)
        }
    }
    @AppStorage("artworkMotionStyle") private var artworkMotionStyleRaw: String = ArtworkMotionStyle.parallaxByPointer.rawValue {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("showLyricsPanel") var showLyricsPanel: Bool = true { didSet { requestPopoverLayoutRefresh() } }
    @AppStorage("expandLyricsByDefault") var expandLyricsByDefault: Bool = false {
        didSet {
            guard showLyricsPanel else { return }
            if expandLyricsByDefault {
                lyricsPanelExpanded = true
            }
        }
    }
    @AppStorage("miniMode") var miniMode: Bool = false {
        didSet {
            bumpStatusBarConfigRevision()
            notifyPopoverModeTransition()
        }
    }
    @AppStorage("miniLyricsEnabled") var miniLyricsEnabled: Bool = false {
        didSet {
            miniLyricsTransitionToken &+= 1
            requestPopoverLayoutRefresh()
        }
    }
    @AppStorage("detachedWindowAlwaysOnTop") var detachedWindowAlwaysOnTop: Bool = true {
        didSet {
            detachedWindowLevelRevision &+= 1
        }
    }
    @AppStorage("detachedWindowSizePreset") private var detachedWindowSizePresetRaw: String = DetachedWindowSizePreset.medium.rawValue {
        didSet {
            requestPopoverLayoutRefresh()
        }
    }
    // UI state
    @Published var surfaceMode: NowPlayingSurfaceMode = .popover
    @Published var provider: NowPlayingProvider = .none
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""
    @Published var isPlaying: Bool = false
    @Published var artwork: NSImage? = nil
    @Published var isPopoverVisible: Bool = false
    // elapsed and duration are managed by PlaybackClock.shared to avoid
    // triggering NowPlayingModel.objectWillChange on every 0.5s tick.
    @Published var glassTint: Color = .white
    @Published var cardBackgroundPalette: [Color] = [
        Color.white.opacity(0.24),
        Color.white.opacity(0.20),
        Color.white.opacity(0.16),
        Color.white.opacity(0.10),
        Color.clear
    ]
    @Published var regularControlsContrastBoost: Double = 0
    @Published var statusBarConfigRevision: Int = 0
    @Published var menuBarDisplayTitle: String = "Not Playing"
    @Published var availableOutputDevices: [AudioOutputDevice] = []
    @Published var selectedOutputDeviceID: AudioDeviceID = 0
    @Published var outputVolume: Double = 1.0
    @Published var outputMuted: Bool = false
    @Published var persistentCacheUsageText: String = "0 MB"
    @Published var isClearingPersistentCache: Bool = false
    @Published var isCurrentTrackFavorited: Bool = false
    @Published var favoriteActionPulseToken: Int = 0
    @Published var popoverModeTransitionToken: Int = 0
    @Published var detachedWindowLevelRevision: Int = 0
    @Published var detachedModeToggleRequestToken: Int = 0
    @Published var detachedCloseRequestToken: Int = 0
    @Published var miniLyricsTransitionToken: Int = 0
    @Published var lyricsPayload: LyricsPayload? {
        didSet {
            guard lyricsPayload != oldValue else { return }
            requestPopoverLayoutRefresh()
        }
    }
    @Published var lyricsState: LyricsState = .idle {
        didSet {
            guard lyricsState != oldValue else { return }
            requestPopoverLayoutRefresh()
        }
    }
    @Published var lyricsLoadingProgress: LyricsLoadingProgress?
    @Published var lyricsPanelExpanded: Bool = false
    @Published var animatedArtworkHLSURL: URL? = nil
    @Published var animatedArtworkState: AnimatedArtworkState = .none
    @Published var animatedArtworkStatusMessage: String = "Idle"
    @Published var animatedArtworkLastError: String = ""
    private var marqueeTimer: AnyCancellable?
    private var marqueeSignature: String = ""
    private var marqueeTrack: [Character] = []
    private var marqueeTrackDoubled: [Character] = []
    private var marqueeIndex: Int = 0
    private var marqueeWindowLength: Int = 0

    // Internals
    private var cancellables = Set<AnyCancellable>()
    private var metadataRefreshTimer: AnyCancellable?
    private var audioRefreshTimer: AnyCancellable?
    private var currentMetadataPollInterval: TimeInterval = 0
    private var currentAudioPollInterval: TimeInterval = 0
    private var lastSnapshot: NowPlayingSnapshot?
    private var launchAtLoginSupported: Bool = true
    private var fallbackArtworkTaskKey: String?
    private var pendingFallbackWork: DispatchWorkItem?
    private var lyricsFetchTask: Task<Void, Never>?
    private var animatedArtworkResolveTask: Task<Void, Never>?
    private var animatedArtworkResolveRequestID: UUID?
    private var animatedArtworkLookupKey: String = ""
    private var animatedArtworkStreamIdentity: String = ""
    private var lastAnimatedArtworkValidMusicSnapshotAt: Date = .distantPast
    private let animatedArtworkTransientClearGrace: TimeInterval = 2.0
    private var currentLyricsTrackKey: String = ""
    #if DEBUG
    private var lyricsMetricMusicAppHits: Int = 0
    private var lyricsMetricLRCLIBHits: Int = 0
    private var lyricsMetricUnavailable: Int = 0
    private var lyricsMetricFailures: Int = 0
    #endif
    private let refreshQueue = DispatchQueue(label: "com.nikhilbolar.playstatus.refresh", qos: .utility)
    private var refreshInFlight = false
    private var refreshPending = false
    #if DEBUG
    private var debugMetadataPollCount: Int = 0
    private var debugAudioPollCount: Int = 0
    private var debugPollMetricsWindowStart: Date = Date()
    #endif

    var providerPriority: ProviderPriority {
        get { ProviderPriority(rawValue: providerPriorityRaw) ?? .musicFirst }
        set { providerPriorityRaw = newValue.rawValue } // didSet triggers refresh()
    }

    var menuBarTextMode: MenuBarTextMode {
        get { MenuBarTextMode(rawValue: menuBarTextModeRaw) ?? .artistAndSong }
        set { menuBarTextModeRaw = newValue.rawValue }
    }

    var preferredProvider: PreferredProvider {
        get { PreferredProvider(rawValue: preferredProviderRaw) ?? .automatic }
        set { preferredProviderRaw = newValue.rawValue }
    }

    var artworkMotionStyle: ArtworkMotionStyle {
        get {
            if artworkMotionStyleRaw == "editorialLoops" ||
                artworkMotionStyleRaw == "glassSheen" ||
                artworkMotionStyleRaw == "depthPulse" {
                artworkMotionStyleRaw = ArtworkMotionStyle.parallaxByPointer.rawValue
                return .parallaxByPointer
            }
            if artworkMotionStyleRaw == "ambientEdgeBloom" {
                artworkMotionStyleRaw = ArtworkMotionStyle.filmGrainDrift.rawValue
                return .filmGrainDrift
            }
            guard let resolved = ArtworkMotionStyle(rawValue: artworkMotionStyleRaw) else {
                artworkMotionStyleRaw = ArtworkMotionStyle.parallaxByPointer.rawValue
                return .parallaxByPointer
            }
            return resolved
        }
        set { artworkMotionStyleRaw = newValue.rawValue }
    }

    var animatedArtworkQualityPolicy: AnimatedArtworkQualityPolicy {
        get { AnimatedArtworkQualityPolicy(rawValue: animatedArtworkQualityPolicyRaw) ?? .adaptive1080 }
        set { animatedArtworkQualityPolicyRaw = newValue.rawValue }
    }

    var detachedWindowSizePreset: DetachedWindowSizePreset {
        get { DetachedWindowSizePreset(rawValue: detachedWindowSizePresetRaw) ?? .medium }
        set { detachedWindowSizePresetRaw = newValue.rawValue }
    }

    private var detachedMiniScaleFactor: CGFloat {
        guard surfaceMode == .detached else { return 1 }
        return detachedWindowSizePreset.miniScaleFactor
    }

    private var detachedRegularScaleFactor: CGFloat {
        guard surfaceMode == .detached else { return 1 }
        return detachedWindowSizePreset.regularScaleFactor
    }

    var detachedRegularControlScaleFactor: CGFloat {
        guard surfaceMode == .detached else { return 1 }
        return detachedWindowSizePreset.regularControlScaleFactor
    }

    var detachedMiniControlScaleFactor: CGFloat {
        guard surfaceMode == .detached else { return 1 }
        return detachedWindowSizePreset.miniControlScaleFactor
    }

    var statusTextWidth: CGFloat {
        let clamped = min(max(statusTextWidthStorage, 80), 320)
        return CGFloat(clamped)
    }

    var menuBarVisibleCharacters: Int {
        max(10, Int((statusTextWidth / 7.3).rounded(.down)))
    }

    var menuBarLabelWidth: CGFloat {
        if menuBarTextMode == .iconOnly { return 13 }
        return statusTextWidth + 18 // icon + spacing
    }

    var statusTextWidthValue: Double {
        get { min(max(statusTextWidthStorage, 80), 320) }
        set {
            statusTextWidthStorage = min(max(newValue, 80), 320)
            configureMarquee(forceRestart: true)
            bumpStatusBarConfigRevision()
        }
    }

    var artworkColorIntensity: Double {
        get { min(max(artworkColorIntensityStorage, 0.5), 1.8) }
        set {
            artworkColorIntensityStorage = min(max(newValue, 0.5), 1.8)
            updateTint(from: artwork)
        }
    }

    var artworkDisplaySize: CGFloat {
        let base = CGFloat(min(max(artworkDisplaySizeStorage, 120), 260))
        let scale = miniMode ? detachedMiniScaleFactor : detachedRegularScaleFactor
        return base * scale
    }

    var miniPopoverWidth: CGFloat { 380 * detachedMiniScaleFactor }

    var regularPopoverWidth: CGFloat {
        // Artwork + spacing + readable text/controls column + container padding.
        let baseArtwork = CGFloat(min(max(artworkDisplaySizeStorage, 120), 260))
        let base = max(410, baseArtwork + 330)
        return base * detachedRegularScaleFactor
    }

    var popoverWidth: CGFloat {
        miniMode ? miniPopoverWidth : regularPopoverWidth
    }

    var miniBaseHeight: CGFloat { 380 * detachedMiniScaleFactor }
    var miniLyricsPaneHeight: CGFloat { 180 * detachedMiniScaleFactor }
    var miniExpandedHeight: CGFloat { miniBaseHeight + miniLyricsPaneHeight }

    var miniPopoverHeight: CGFloat {
        (miniMode && miniLyricsEnabled) ? miniExpandedHeight : miniBaseHeight
    }

    var regularLyricsPaneHeight: CGFloat { 241 * detachedRegularScaleFactor } // 1pt divider + 240pt pane

    var estimatedRegularPopoverHeight: CGFloat {
        let baseArtwork = CGFloat(min(max(artworkDisplaySizeStorage, 120), 260))
        let base = max(220, baseArtwork + 54)
        return base * detachedRegularScaleFactor
    }

    var regularPopoverHeight: CGFloat {
        let base = estimatedRegularPopoverHeight
        guard showLyricsPanel && lyricsPanelExpanded && !miniMode else { return base }
        return base + regularLyricsPaneHeight
    }

    init() {
        surfaceMode = .popover
        lyricsPanelExpanded = expandLyricsByDefault
        animatedArtworkStatusMessage = "Ready"
        $isPopoverVisible
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateAudioPollingTimerIfNeeded()
            }
            .store(in: &cancellables)

        updateMetadataPollingTimerIfNeeded()
        updateAudioPollingTimerIfNeeded()
        launchAtLoginSupported = launchAtLoginStatus() != nil
        refresh()
        refreshAudioState()
        refreshPersistentCacheStats()
    }

    var menuBarTitle: String {
        let cleanTitle = displayTitle
        let cleanArtist = artist

        if cleanTitle.isEmpty, cleanArtist.isEmpty {
            return "Not Playing"
        }

        switch menuBarTextMode {
        case .artist:
            return cleanArtist.isEmpty ? cleanTitle : cleanArtist
        case .song:
            return cleanTitle.isEmpty ? cleanArtist : cleanTitle
        case .artistAndSong:
            if cleanTitle.isEmpty { return cleanArtist }
            if cleanArtist.isEmpty { return cleanTitle }
            return "\(cleanArtist) - \(cleanTitle)"
        case .iconOnly:
            return " "
        }
    }

    var displayTitle: String {
        sanitizeTitle(title)
    }

    var artistAlbumLine: String {
        switch (artist.isEmpty, album.isEmpty) {
        case (false, false): return "\(artist) • \(album)"
        case (false, true):  return artist
        case (true, false):  return album
        case (true, true):   return "Music"
        }
    }

    var progress: Double { PlaybackClock.shared.progress }
    var elapsed: Double { PlaybackClock.shared.elapsed }
    var duration: Double { PlaybackClock.shared.duration }
    var canSeek: Bool { PlaybackClock.shared.canSeek }
    var effectiveAnimatedArtworkURL: URL? {
        guard animatedArtworkEnabled,
              animatedArtworkStreamsEnabled else {
            return nil
        }
        switch animatedArtworkState {
        case .available:
            return animatedArtworkHLSURL
        case .loading:
            // Keep current stream visible while revalidating same-track metadata.
            return animatedArtworkHLSURL
        case .none, .unavailable, .failed:
            return nil
        }
    }
    var statusIcon: ProviderIconKind { provider.iconKind }
    var statusLine: String {
        if provider == .none { return "Idle" }
        return isPlaying ? "Playing" : "Paused"
    }
    var launchAtLoginEnabled: Bool { launchAtLoginStatus() == .enabled }
    var canFavoriteCurrentTrack: Bool { provider == .music && !title.isEmpty }
    var resolvedSearchProvider: NowPlayingProvider {
        switch provider {
        case .music, .spotify:
            return provider
        case .none:
            switch preferredProvider {
            case .music:
                return .music
            case .spotify:
                return .spotify
            case .automatic:
                return providerPriority == .spotifyFirst ? .spotify : .music
            }
        }
    }

    private func metadataPollingMode(for snapshot: NowPlayingSnapshot? = nil) -> MetadataPollingMode {
        let resolvedSnapshot = snapshot
        let resolvedProvider = resolvedSnapshot?.provider ?? provider
        let resolvedTitle = resolvedSnapshot?.title ?? title
        let resolvedIsPlaying = resolvedSnapshot?.isPlaying ?? isPlaying

        if resolvedIsPlaying {
            return .playing
        }
        if resolvedProvider != .none, !resolvedTitle.isEmpty {
            return .pausedTrack
        }
        return .idle
    }

    private func updateMetadataPollingTimerIfNeeded(using snapshot: NowPlayingSnapshot? = nil) {
        let mode = metadataPollingMode(for: snapshot)
        let interval = mode.interval
        guard abs(currentMetadataPollInterval - interval) > 0.001 else { return }

        metadataRefreshTimer?.cancel()
        currentMetadataPollInterval = interval
        metadataRefreshTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                #if DEBUG
                self?.recordMetadataPollTick()
                #endif
                self?.refresh()
            }

        #if DEBUG
        NSLog("PlayStatus polling: metadata interval=%.2fs mode=%@", interval, mode.debugLabel)
        #endif
    }

    private func desiredAudioPollingInterval() -> TimeInterval {
        isPopoverVisible ? 10.0 : 30.0
    }

    private func updateAudioPollingTimerIfNeeded() {
        let interval = desiredAudioPollingInterval()
        guard abs(currentAudioPollInterval - interval) > 0.001 else { return }

        audioRefreshTimer?.cancel()
        currentAudioPollInterval = interval
        audioRefreshTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                #if DEBUG
                self?.recordAudioPollTick()
                #endif
                self?.refreshAudioState()
            }

        #if DEBUG
        NSLog("PlayStatus polling: audio interval=%.2fs visible=%d", interval, isPopoverVisible ? 1 : 0)
        #endif
    }

    #if DEBUG
    private func recordMetadataPollTick() {
        debugMetadataPollCount += 1
        flushDebugPollMetricsIfNeeded()
    }

    private func recordAudioPollTick() {
        debugAudioPollCount += 1
        flushDebugPollMetricsIfNeeded()
    }

    private func flushDebugPollMetricsIfNeeded(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(debugPollMetricsWindowStart) >= 60 else { return }
        NSLog(
            "PlayStatus polling metrics: metadata=%d/min audio=%d/min",
            debugMetadataPollCount,
            debugAudioPollCount
        )
        debugMetadataPollCount = 0
        debugAudioPollCount = 0
        debugPollMetricsWindowStart = now
    }
    #endif

    deinit {
        metadataRefreshTimer?.cancel()
        audioRefreshTimer?.cancel()
        #if DEBUG
        flushDebugPollMetricsIfNeeded(force: true)
        #endif
    }

    func refresh() {
        refreshQueue.async { [weak self] in
            guard let self else { return }

            if self.refreshInFlight {
                self.refreshPending = true
                return
            }

            self.refreshInFlight = true
            repeat {
                self.refreshPending = false

                let spotify = self.enableSpotify ? SpotifyProvider.fetch() : nil
                let music = self.enableMusic ? MusicProvider.fetch() : nil

                DispatchQueue.main.async { [weak self] in
                    self?.applyFetchedSnapshots(music: music, spotify: spotify)
                }
            } while self.refreshPending
            self.refreshInFlight = false
        }
    }

    private func applyFetchedSnapshots(music: NowPlayingSnapshot?, spotify: NowPlayingSnapshot?) {
        let chosen = chooseSnapshot(music: music, spotify: spotify)

        guard let snap = chosen else {
            apply(snapshot: NowPlayingSnapshot(provider: .none, isPlaying: false, title: "", artist: "", album: "", artwork: nil, nativeArtworkState: .none, elapsed: 0, duration: 0, canSeek: false))
            return
        }

        // Keep progress smooth without re-tinting unless track/provider changed
        if let last = lastSnapshot, snapshotsSimilar(last, snap) {
            PlaybackClock.shared.elapsed = snap.elapsed
            PlaybackClock.shared.duration = snap.duration
            lastSnapshot = snap
            // Same track: if native provider artwork arrives later (e.g. Spotify URL fetch),
            // promote it over any previously shown fallback art without forcing a full apply().
            let shouldPromoteNativeArtwork =
                snap.nativeArtworkState == .available &&
                (last.nativeArtworkState != .available || last.artwork == nil)

            if shouldPromoteNativeArtwork, let artwork = snap.artwork {
                DispatchQueue.main.async {
                    self.artwork = artwork
                    self.updateTint(from: artwork)
                }
            }
            return
        }

        apply(snapshot: snap)
    }

    private func chooseSnapshot(music: NowPlayingSnapshot?, spotify: NowPlayingSnapshot?) -> NowPlayingSnapshot? {
        let ordered: [NowPlayingSnapshot?]
        switch preferredProvider {
        case .music:
            ordered = [music, spotify]
        case .spotify:
            ordered = [spotify, music]
        case .automatic:
            switch providerPriority {
            case .musicFirst: ordered = [music, spotify]
            case .spotifyFirst: ordered = [spotify, music]
            }
        }

        let candidates = ordered.compactMap { $0 }
        if let playing = candidates.first(where: { $0.isPlaying && !$0.title.isEmpty }) { return playing }
        if let paused = candidates.first(where: { !$0.isPlaying && !$0.title.isEmpty }) { return paused }
        return nil
    }

    private func snapshotsSimilar(_ a: NowPlayingSnapshot, _ b: NowPlayingSnapshot) -> Bool {
        a.provider == b.provider &&
        a.isPlaying == b.isPlaying &&
        a.title == b.title &&
        a.artist == b.artist &&
        a.album == b.album &&
        a.isFavorited == b.isFavorited
    }

    private func apply(snapshot: NowPlayingSnapshot) {
        let previousSnapshot = lastSnapshot
        let trackChanged = !isSameTrack(previousSnapshot, snapshot)
        lastSnapshot = snapshot

        DispatchQueue.main.async {
            self.provider = snapshot.provider
            self.isPlaying = snapshot.isPlaying
            self.title = snapshot.title
            self.artist = snapshot.artist
            self.album = snapshot.album
            self.isCurrentTrackFavorited = snapshot.provider == .music ? snapshot.isFavorited : false
            PlaybackClock.shared.elapsed = snapshot.elapsed
            PlaybackClock.shared.duration = snapshot.duration
            self.artwork = snapshot.artwork
            self.updateTint(from: snapshot.artwork)
            self.configureMarquee()
            self.updateMetadataPollingTimerIfNeeded(using: snapshot)
        }

        if snapshot.provider != .none, !snapshot.title.isEmpty {
            if trackChanged {
                startLyricsFetch(for: snapshot, forceRefresh: false, resetState: true)
            }
        } else {
            lyricsFetchTask?.cancel()
            Task {
                await LyricsService.shared.cancelAllInflightLyricsFetches()
            }
            currentLyricsTrackKey = ""
            DispatchQueue.main.async {
                self.lyricsPayload = nil
                self.lyricsState = .idle
                self.lyricsLoadingProgress = nil
            }
        }

        pendingFallbackWork?.cancel()
        pendingFallbackWork = nil

        guard !snapshot.title.isEmpty else {
            updateAnimatedArtwork(for: snapshot)
            return
        }

        switch snapshot.nativeArtworkState {
        case .available:
            updateAnimatedArtwork(for: snapshot)
            return
        case .none:
            fetchFallbackArtwork(for: snapshot)
        case .pending:
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard let current = self.lastSnapshot,
                      current.provider == snapshot.provider,
                      current.title == snapshot.title,
                      current.artist == snapshot.artist,
                      current.album == snapshot.album else { return }
                if current.artwork == nil {
                    self.fetchFallbackArtwork(for: snapshot)
                }
            }
            pendingFallbackWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }

        updateAnimatedArtwork(for: snapshot)
    }

    private func isSameTrack(_ a: NowPlayingSnapshot?, _ b: NowPlayingSnapshot) -> Bool {
        guard let a else { return false }
        return a.provider == b.provider &&
            a.title == b.title &&
            a.artist == b.artist &&
            a.album == b.album &&
            Int(a.duration.rounded()) == Int(b.duration.rounded())
    }

    private func startLyricsFetch(for snapshot: NowPlayingSnapshot, forceRefresh: Bool, resetState: Bool) {
        let descriptor = LyricsTrackDescriptor(
            provider: snapshot.provider,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            duration: snapshot.duration
        )
        let trackKey = descriptor.cacheKey
        currentLyricsTrackKey = trackKey
        lyricsFetchTask?.cancel()
        Task {
            await LyricsService.shared.cancelAllInflightLyricsFetches()
        }

        if resetState {
            DispatchQueue.main.async {
                self.lyricsPayload = nil
                self.lyricsState = .loading
                self.lyricsLoadingProgress = nil
            }
        }

        lyricsFetchTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.fetchLyricsWithRetry(for: descriptor, forceRefresh: forceRefresh)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.currentLyricsTrackKey == trackKey else { return }
                guard self.provider == descriptor.provider,
                      self.title == descriptor.title,
                      self.artist == descriptor.artist,
                      self.album == descriptor.album else { return }

                switch outcome {
                case .available(let payload):
                    self.lyricsPayload = payload
                    self.lyricsState = .available
                    self.lyricsLoadingProgress = nil
                    #if DEBUG
                    if payload.source == .musicApp {
                        self.lyricsMetricMusicAppHits += 1
                    } else if payload.source == .lrclib {
                        self.lyricsMetricLRCLIBHits += 1
                    }
                    NSLog(
                        "PlayStatus lyrics metrics: musicApp=\(self.lyricsMetricMusicAppHits) lrclib=\(self.lyricsMetricLRCLIBHits) unavailable=\(self.lyricsMetricUnavailable) failed=\(self.lyricsMetricFailures)"
                    )
                    #endif
                case .unavailable:
                    self.lyricsPayload = nil
                    self.lyricsState = .unavailable
                    self.lyricsLoadingProgress = nil
                    #if DEBUG
                    self.lyricsMetricUnavailable += 1
                    NSLog(
                        "PlayStatus lyrics metrics: musicApp=\(self.lyricsMetricMusicAppHits) lrclib=\(self.lyricsMetricLRCLIBHits) unavailable=\(self.lyricsMetricUnavailable) failed=\(self.lyricsMetricFailures)"
                    )
                    #endif
                case .failed:
                    self.lyricsPayload = nil
                    self.lyricsState = .failed
                    self.lyricsLoadingProgress = nil
                    #if DEBUG
                    self.lyricsMetricFailures += 1
                    NSLog(
                        "PlayStatus lyrics metrics: musicApp=\(self.lyricsMetricMusicAppHits) lrclib=\(self.lyricsMetricLRCLIBHits) unavailable=\(self.lyricsMetricUnavailable) failed=\(self.lyricsMetricFailures)"
                    )
                    #endif
                }
            }
        }
    }

    private func fetchLyricsWithRetry(for descriptor: LyricsTrackDescriptor, forceRefresh: Bool) async -> LyricsFetchOutcome {
        let maxAttempts = 2
        var attempt = 0
        var lastLRCLIBOutcome: LyricsFetchOutcome = .unavailable
        let trackKey = descriptor.cacheKey
        let retryDelayNanos: UInt64 = 350_000_000

        #if DEBUG
        let totalStartTime = CFAbsoluteTimeGetCurrent()
        let outcomeDescription: (LyricsFetchOutcome) -> String = { outcome in
            switch outcome {
            case .available:
                return "available"
            case .unavailable:
                return "unavailable"
            case .failed:
                return "failed"
            }
        }
        let logTotal: (LyricsFetchOutcome, String) -> Void = { outcome, note in
            let totalDuration = CFAbsoluteTimeGetCurrent() - totalStartTime
            NSLog(
                "PlayStatus lyrics timing: provider=%@ total=%.3fs outcome=%@ note=%@",
                descriptor.provider.rawValue,
                totalDuration,
                outcomeDescription(outcome),
                note
            )
        }
        #endif

        attemptLoop: while attempt < maxAttempts {
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
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.currentLyricsTrackKey == trackKey else { return }
                    guard self.provider == descriptor.provider,
                          self.title == descriptor.title,
                          self.artist == descriptor.artist,
                          self.album == descriptor.album else { return }

                    self.lyricsLoadingProgress = LyricsLoadingProgress(
                        attempt: attemptNumber,
                        maxAttempts: maxAttempts,
                        stage: stage,
                        stageIndex: stage.rawValue,
                        stageCount: LyricsLoadingStage.allCases.count
                    )
                }
            }

            #if DEBUG
            let attemptDuration = CFAbsoluteTimeGetCurrent() - attemptStartTime
            NSLog(
                "PlayStatus lyrics timing: provider=%@ phase=lrclib attempt=%d/%d duration=%.3fs outcome=%@",
                descriptor.provider.rawValue,
                attemptNumber,
                maxAttempts,
                attemptDuration,
                outcomeDescription(outcome)
            )
            #endif

            lastLRCLIBOutcome = outcome

            switch outcome {
            case .available:
                #if DEBUG
                logTotal(outcome, "lrclib_success")
                #endif
                return outcome
            case .failed:
                attempt += 1
                guard attempt < maxAttempts else { break }
                try? await Task.sleep(nanoseconds: retryDelayNanos)
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

        let musicFallbackOutcome = await LyricsService.shared.fetchLyrics(
            for: descriptor,
            forceRefresh: true,
            mode: .musicOnly,
            cacheUnavailableResult: true
        ) { [weak self] stage in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.currentLyricsTrackKey == trackKey else { return }
                guard self.provider == descriptor.provider,
                      self.title == descriptor.title,
                      self.artist == descriptor.artist,
                      self.album == descriptor.album else { return }

                self.lyricsLoadingProgress = LyricsLoadingProgress(
                    attempt: maxAttempts,
                    maxAttempts: maxAttempts,
                    stage: stage,
                    stageIndex: stage.rawValue,
                    stageCount: LyricsLoadingStage.allCases.count
                )
            }
        }

        #if DEBUG
        let fallbackDuration = CFAbsoluteTimeGetCurrent() - fallbackStartTime
        NSLog(
            "PlayStatus lyrics timing: provider=%@ phase=music_fallback duration=%.3fs outcome=%@",
            descriptor.provider.rawValue,
            fallbackDuration,
            outcomeDescription(musicFallbackOutcome)
        )
        #endif

        switch musicFallbackOutcome {
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

    private func updateTint(from image: NSImage?) {
        let scaleOpacity: (Double) -> Double = { base in
            min(max(base * self.artworkColorIntensity, 0), 0.95)
        }

        guard let image else {
            let neutral = NSColor.white
            glassTint = .white
            regularControlsContrastBoost = controlContrastBoost(for: neutral)
            cardBackgroundPalette = [
                Color.white.opacity(scaleOpacity(0.24)),
                Color.white.opacity(scaleOpacity(0.20)),
                Color.white.opacity(scaleOpacity(0.16)),
                Color.white.opacity(scaleOpacity(0.10)),
                Color.clear
            ]
            return
        }

        let average = image.averageColor() ?? NSColor.white
        glassTint = Color(average)
        regularControlsContrastBoost = controlContrastBoost(for: average)

        if let palette = image.artworkPalette() {
            let opacities: [Double] = [0.62, 0.56, 0.48, 0.40, 0.32, 0.24, 0.18]
            cardBackgroundPalette = zip(palette, opacities).map { color, alpha in
                Color(color).opacity(scaleOpacity(alpha))
            } + [Color.clear]
        } else {
            cardBackgroundPalette = [
                Color(average).opacity(scaleOpacity(0.55)),
                Color(average).opacity(scaleOpacity(0.45)),
                Color(average).opacity(scaleOpacity(0.34)),
                Color(average).opacity(scaleOpacity(0.24)),
                Color.clear
            ]
        }
    }

    private func controlContrastBoost(for color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let luminance = (0.2126 * Double(rgb.redComponent))
            + (0.7152 * Double(rgb.greenComponent))
            + (0.0722 * Double(rgb.blueComponent))
        return min(max((luminance - 0.56) / 0.30, 0), 1)
    }

    // MARK: - Menu bar marquee (safe for status items)

    private func configureMarquee(forceRestart: Bool = false) {
        let base = menuBarTitle.isEmpty ? "Not Playing" : menuBarTitle
        marqueeTimer?.cancel()
        marqueeTimer = nil
        marqueeTrack = []
        marqueeTrackDoubled = []
        marqueeIndex = 0
        marqueeWindowLength = 0
        marqueeSignature = "\(base)|\(scrollableTitle)|\(menuBarTextMode.rawValue)|\(Int(statusTextWidth.rounded()))|\(forceRestart)"
        menuBarDisplayTitle = base
    }

    private func bumpStatusBarConfigRevision() {
        statusBarConfigRevision &+= 1
    }

    func notifyPopoverModeTransition() {
        popoverModeTransitionToken &+= 1
    }

    func requestPopoverLayoutRefresh() {
        bumpStatusBarConfigRevision()
    }

    func requestToggleDetachedMode() {
        detachedModeToggleRequestToken &+= 1
    }

    func requestCloseDetachedWindow() {
        detachedCloseRequestToken &+= 1
    }

    func setLyricsPanelExpanded(_ expanded: Bool) {
        guard lyricsPanelExpanded != expanded else { return }
        lyricsPanelExpanded = expanded
        requestPopoverLayoutRefresh()
    }

    private func applyAudioState(_ state: AudioOutputState) {
        availableOutputDevices = state.devices
        selectedOutputDeviceID = state.selectedDeviceID
        outputVolume = state.volume
        outputMuted = state.isMuted
    }

    // MARK: - Controls

    func playPause() {
        switch provider {
        case .spotify: SpotifyProvider.playPause()
        case .music, .none: MusicProvider.playPause()
        }
    }

    func nextTrack() {
        switch provider {
        case .spotify: SpotifyProvider.next()
        case .music, .none: MusicProvider.next()
        }
    }

    func previousTrack() {
        switch provider {
        case .spotify: SpotifyProvider.previous()
        case .music, .none: MusicProvider.previous()
        }
    }

    func seek(to progress: Double) {
        let p = min(max(progress, 0), 1)
        let target = duration * p
        switch provider {
        case .spotify: SpotifyProvider.seek(to: target)
        case .music, .none: MusicProvider.seek(to: target)
        }
    }

    func refreshAudioState() {
        refreshQueue.async { [weak self] in
            guard let self else { return }
            let state = AudioOutputController.currentState()
            DispatchQueue.main.async {
                self.applyAudioState(state)
            }
        }
    }

    func setOutputDevice(_ id: AudioDeviceID) {
        AudioOutputController.setDefaultOutputDevice(id)
        refreshAudioState()
    }

    func setOutputVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        outputVolume = clamped
        AudioOutputController.setVolume(Float32(clamped), for: selectedOutputDeviceID == 0 ? nil : selectedOutputDeviceID)
    }

    func toggleOutputMute() {
        let newMuted = !outputMuted
        outputMuted = newMuted
        AudioOutputController.setMuted(newMuted, for: selectedOutputDeviceID == 0 ? nil : selectedOutputDeviceID)
    }

    func refreshPersistentCacheStats() {
        Task { [weak self] in
            guard let self else { return }
            let usage = await PersistentMediaCache.shared.usageText()
            await MainActor.run {
                self.persistentCacheUsageText = usage
            }
        }
    }

    func clearPersistentCache() {
        guard !isClearingPersistentCache else { return }
        isClearingPersistentCache = true

        Task { [weak self] in
            guard let self else { return }
            await PersistentMediaCache.shared.clearAll()
            let usage = await PersistentMediaCache.shared.usageText()
            await MainActor.run {
                self.persistentCacheUsageText = usage
                self.isClearingPersistentCache = false
            }
        }
    }

    func openProviderApp() {
        let providerName: String
        if provider == .none {
            providerName = preferredProvider == .spotify ? "Spotify" : "Music"
        } else {
            providerName = provider.displayName
        }
        let bundleIdentifier = providerName == "Spotify" ? "com.spotify.client" : "com.apple.Music"
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
        }
    }

    func likeCurrentSong() {
        _ = toggleCurrentTrackFavorite()
    }

    @discardableResult
    func favoriteCurrentTrack() -> Bool {
        toggleCurrentTrackFavorite()
    }

    @discardableResult
    func toggleCurrentTrackFavorite() -> Bool {
        guard canFavoriteCurrentTrack else {
            return false
        }

        guard let updatedState = MusicProvider.toggleCurrentTrackFavorite() else {
            NSLog("PlayStatus favorite toggle failed: Apple Music did not confirm favorite action")
            return false
        }

        isCurrentTrackFavorited = updatedState
        favoriteActionPulseToken &+= 1
        return true
    }

    func searchAndPlayInMusicLibrary(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        MusicProvider.searchAndPlay(query: trimmed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.refresh()
        }
    }

    func runSearchAction(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch resolvedSearchProvider {
        case .music, .none:
            searchAndPlayInMusicLibrary(query: trimmed)
        case .spotify:
            openSpotifySearch(query: trimmed)
        }
    }

    func openSpotifySearch(query: String) {
        let encodedQuery = encodedSearchTerm(query)
        guard !encodedQuery.isEmpty else { return }

        let appSearchURL = URL(string: "spotify:search:\(encodedQuery)")
        if let appSearchURL, NSWorkspace.shared.open(appSearchURL) {
            return
        }

        guard let webSearchURL = URL(string: "https://open.spotify.com/search/\(encodedQuery)") else {
            NSLog("PlayStatusSwiftUI Spotify search failed: unable to build web URL for query")
            return
        }

        if !NSWorkspace.shared.open(webSearchURL) {
            NSLog("PlayStatusSwiftUI Spotify search failed: unable to open app or web search URL")
        }
    }

    func retryLyricsFetch() {
        guard let snapshot = lastSnapshot,
              snapshot.provider == .music,
              !snapshot.title.isEmpty else { return }
        startLyricsFetch(for: snapshot, forceRefresh: true, resetState: true)
    }

    func setLaunchAtLogin(enabled: Bool) {
        guard launchAtLoginSupported else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("PlayStatusSwiftUI launch-at-login update failed: \(error.localizedDescription)")
        }
    }

    private func launchAtLoginStatus() -> SMAppService.Status? {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status
        }
        return nil
    }

    private func sanitizeTitle(_ raw: String) -> String {
        guard ignoreParentheses else { return raw }
        return raw.replacingOccurrences(
            of: "\\([^)]*\\)",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func encodedSearchTerm(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
    }

    private func handleAnimatedArtworkSettingChanged() {
        if !animatedArtworkEnabled || !animatedArtworkStreamsEnabled {
            animatedArtworkResolveTask?.cancel()
            animatedArtworkResolveTask = nil
            animatedArtworkResolveRequestID = nil
            animatedArtworkHLSURL = nil
            animatedArtworkStreamIdentity = ""
            animatedArtworkState = .none
            animatedArtworkStatusMessage = "Animated streams disabled"
            animatedArtworkLastError = ""
            return
        }
        refreshAnimatedArtworkForCurrentTrack(force: true)
    }

    private func refreshAnimatedArtworkForCurrentTrack(force: Bool) {
        guard let snapshot = lastSnapshot else {
            animatedArtworkResolveTask?.cancel()
            animatedArtworkResolveTask = nil
            animatedArtworkResolveRequestID = nil
            animatedArtworkHLSURL = nil
            animatedArtworkStreamIdentity = ""
            animatedArtworkState = .none
            animatedArtworkStatusMessage = "Idle"
            animatedArtworkLastError = ""
            return
        }

        updateAnimatedArtwork(for: snapshot, force: force)
    }

    private func updateAnimatedArtwork(for snapshot: NowPlayingSnapshot, force: Bool = false) {
        let now = Date()
        let isMusicProvider = snapshot.provider == .music
        let isSpotifyProvider = snapshot.provider == .spotify
        let isSupportedProvider = isMusicProvider || isSpotifyProvider

        if isMusicProvider, !snapshot.title.isEmpty {
            lastAnimatedArtworkValidMusicSnapshotAt = now
        }

        guard isSupportedProvider,
              !snapshot.title.isEmpty else {
            // Music AppleScript metadata can occasionally transiently drop to empty;
            // keep current animated artwork briefly to avoid visible teardown/relookup jitter.
            if snapshot.provider == .none,
               now.timeIntervalSince(lastAnimatedArtworkValidMusicSnapshotAt) < animatedArtworkTransientClearGrace {
                return
            }
            animatedArtworkResolveTask?.cancel()
            animatedArtworkResolveTask = nil
            animatedArtworkResolveRequestID = nil
            animatedArtworkHLSURL = nil
            animatedArtworkStreamIdentity = ""
            animatedArtworkState = .none
            animatedArtworkStatusMessage = "Idle"
            animatedArtworkLastError = ""
            animatedArtworkLookupKey = ""
            lastAnimatedArtworkValidMusicSnapshotAt = .distantPast
            return
        }

        guard animatedArtworkEnabled, animatedArtworkStreamsEnabled else {
            animatedArtworkResolveTask?.cancel()
            animatedArtworkResolveTask = nil
            animatedArtworkResolveRequestID = nil
            animatedArtworkHLSURL = nil
            animatedArtworkStreamIdentity = ""
            animatedArtworkState = .none
            animatedArtworkStatusMessage = "Animated streams disabled"
            animatedArtworkLastError = ""
            lastAnimatedArtworkValidMusicSnapshotAt = .distantPast
            return
        }

        let lookupKey = animatedArtworkLookupKey(for: snapshot)
        let sameLookupKey = lookupKey == animatedArtworkLookupKey

        if isSpotifyProvider, !snapshot.isPlaying {
            animatedArtworkResolveTask?.cancel()
            animatedArtworkResolveTask = nil
            animatedArtworkResolveRequestID = nil
            animatedArtworkLookupKey = lookupKey

            if animatedArtworkHLSURL != nil, sameLookupKey {
                animatedArtworkState = .available
                animatedArtworkStatusMessage = "Animated artwork available (Apple Music stream)"
            } else {
                animatedArtworkHLSURL = nil
                animatedArtworkStreamIdentity = ""
                animatedArtworkState = .none
                animatedArtworkStatusMessage = "Spotify paused (static artwork)"
                animatedArtworkLastError = ""
            }
            return
        }

        if !force,
           sameLookupKey,
           (animatedArtworkState != .none &&
            !(animatedArtworkState == .loading && animatedArtworkResolveTask == nil)) {
            return
        }
        let preserveCurrentStream = isMusicProvider && shouldPreserveAnimatedArtworkStream(for: snapshot)
        animatedArtworkLookupKey = lookupKey
        let clearExistingURL: Bool
        if isSpotifyProvider {
            // Spotify always starts static-first for new tracks.
            clearExistingURL = !sameLookupKey
        } else {
            clearExistingURL = !(sameLookupKey || preserveCurrentStream)
        }
        resolveAnimatedArtwork(
            for: snapshot,
            lookupKey: lookupKey,
            clearExistingURL: clearExistingURL
        )
    }

    private func resolveAnimatedArtwork(
        for snapshot: NowPlayingSnapshot,
        lookupKey: String,
        clearExistingURL: Bool
    ) {
        animatedArtworkResolveTask?.cancel()
        animatedArtworkResolveTask = nil
        let requestID = UUID()
        animatedArtworkResolveRequestID = requestID

        animatedArtworkState = .loading
        animatedArtworkStatusMessage = animatedArtworkLoadingStatusMessage(for: snapshot.provider)
        if clearExistingURL {
            animatedArtworkHLSURL = nil
            animatedArtworkStreamIdentity = ""
        }

        let descriptor = AnimatedArtworkTrackDescriptor(
            sourceProvider: snapshot.provider,
            artist: snapshot.artist,
            album: snapshot.album,
            title: snapshot.title,
            appleMusicAlbumURL: snapshot.appleMusicAlbumURL
        )
        let quality = animatedArtworkQualityPolicy

        animatedArtworkResolveTask = Task { [weak self] in
            guard let self else { return }
            let resolution = await AppleMusicAnimatedArtworkService.shared.resolve(
                for: descriptor,
                qualityPolicy: quality
            )
            let wasCancelled = Task.isCancelled

            await MainActor.run {
                guard self.animatedArtworkResolveRequestID == requestID else { return }
                self.animatedArtworkResolveTask = nil
                self.animatedArtworkResolveRequestID = nil

                if wasCancelled {
                    if self.animatedArtworkState == .loading, self.animatedArtworkHLSURL == nil {
                        self.animatedArtworkState = .none
                        self.animatedArtworkStatusMessage = "Idle"
                    }
                    return
                }

                let isCurrentSnapshotMatch =
                    self.provider == snapshot.provider &&
                    self.title == snapshot.title &&
                    self.artist == snapshot.artist &&
                    self.album == snapshot.album
                let isTransientMusicGap =
                    snapshot.provider == .music &&
                    self.provider == .none &&
                    self.title.isEmpty &&
                    Date().timeIntervalSince(self.lastAnimatedArtworkValidMusicSnapshotAt) < self.animatedArtworkTransientClearGrace

                guard isCurrentSnapshotMatch || isTransientMusicGap else {
                    if self.animatedArtworkState == .loading, self.animatedArtworkHLSURL == nil {
                        self.animatedArtworkState = .none
                        self.animatedArtworkStatusMessage = "Idle"
                    }
                    return
                }
                guard self.animatedArtworkLookupKey == lookupKey else {
                    if self.animatedArtworkState == .loading, self.animatedArtworkHLSURL == nil {
                        self.animatedArtworkState = .none
                        self.animatedArtworkStatusMessage = "Idle"
                    }
                    return
                }

                let shouldRetainExistingStream =
                    resolution.state != .available &&
                    self.animatedArtworkHLSURL != nil &&
                    self.shouldPreserveAnimatedArtworkStream(for: snapshot)
                if shouldRetainExistingStream {
                    self.animatedArtworkState = .available
                    self.animatedArtworkStatusMessage = self.animatedArtworkResolvedStatusMessage(
                        for: .available,
                        provider: snapshot.provider,
                        fallback: "Animated artwork available"
                    )
                    self.animatedArtworkLastError = resolution.diagnosticMessage
                    return
                }

                self.animatedArtworkState = resolution.state
                self.animatedArtworkHLSURL = resolution.hlsURL
                self.animatedArtworkStatusMessage = self.animatedArtworkResolvedStatusMessage(
                    for: resolution.state,
                    provider: snapshot.provider,
                    fallback: resolution.statusMessage
                )
                if resolution.state == .available, resolution.hlsURL != nil {
                    self.animatedArtworkStreamIdentity = self.animatedArtworkIdentityKey(
                        title: snapshot.title,
                        artist: snapshot.artist
                    )
                } else if resolution.hlsURL == nil {
                    self.animatedArtworkStreamIdentity = ""
                }
                self.animatedArtworkLastError = resolution.diagnosticMessage
            }
        }
    }

    private func animatedArtworkLookupKey(for snapshot: NowPlayingSnapshot) -> String {
        if let albumURL = snapshot.appleMusicAlbumURL?.absoluteString, !albumURL.isEmpty {
            return "\(snapshot.provider.rawValue)|albumURL|\(albumURL.lowercased())"
        }
        return [
            snapshot.provider.rawValue,
            animatedArtworkLookupComponent(snapshot.artist),
            animatedArtworkLookupComponent(snapshot.album),
            animatedArtworkLookupComponent(snapshot.title)
        ].joined(separator: "|")
    }

    private func animatedArtworkLookupComponent(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func animatedArtworkIdentityKey(title: String, artist: String) -> String {
        [
            animatedArtworkLookupComponent(artist),
            animatedArtworkLookupComponent(title)
        ].joined(separator: "|")
    }

    private func shouldPreserveAnimatedArtworkStream(for snapshot: NowPlayingSnapshot) -> Bool {
        guard snapshot.provider == .music, animatedArtworkHLSURL != nil else { return false }
        let snapshotIdentity = animatedArtworkIdentityKey(title: snapshot.title, artist: snapshot.artist)
        guard !snapshotIdentity.isEmpty else { return false }

        if animatedArtworkStreamIdentity == snapshotIdentity {
            return true
        }

        let currentIdentity = animatedArtworkIdentityKey(title: title, artist: artist)
        if !currentIdentity.isEmpty, currentIdentity == snapshotIdentity {
            return true
        }

        return false
    }

    private func animatedArtworkLoadingStatusMessage(for provider: NowPlayingProvider) -> String {
        switch provider {
        case .spotify:
            return "Looking up animated artwork (Spotify)"
        default:
            return "Looking up animated artwork..."
        }
    }

    private func animatedArtworkResolvedStatusMessage(
        for state: AnimatedArtworkState,
        provider: NowPlayingProvider,
        fallback: String
    ) -> String {
        guard provider == .spotify else { return fallback }
        switch state {
        case .available:
            return "Animated artwork available (Apple Music stream)"
        case .unavailable:
            return "No animated stream found for this Spotify track"
        case .failed:
            return "Animated stream lookup failed for this Spotify track"
        case .loading:
            return "Looking up animated artwork (Spotify)"
        case .none:
            return fallback
        }
    }

    private func fetchFallbackArtwork(for snapshot: NowPlayingSnapshot) {
        let key = "\(snapshot.provider.rawValue)|\(snapshot.artist)|\(snapshot.album)|\(snapshot.title)"
        if fallbackArtworkTaskKey == key { return }
        fallbackArtworkTaskKey = key

        ITunesArtworkLookup.shared.lookup(
            artist: snapshot.artist,
            album: snapshot.album,
            title: snapshot.title
        ) { [weak self] image in
            guard let self, let image else { return }
            DispatchQueue.main.async {
                guard self.provider == snapshot.provider,
                      self.title == snapshot.title,
                      self.artist == snapshot.artist,
                      self.album == snapshot.album else { return }
                self.artwork = image
                self.updateTint(from: image)
            }
        }
    }
}
