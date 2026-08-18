import SwiftUI
import AppKit
import Combine
import ServiceManagement
import CoreAudio

final class NowPlayingModel: ObservableObject {
    static let shared = NowPlayingModel()

    private enum MetadataPollingMode {
        case playing
        case pausedTrack
        case idle

        /// What the app polls at when it has to discover changes for itself.
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

        /// What it polls at once the player is broadcasting its own changes.
        ///
        /// Track changes and play/pause arrive as notifications, so polling is left with two
        /// jobs: correcting the locally extrapolated position for drift, and noticing a seek
        /// the user performed inside Music or Spotify — neither of which needs half-second
        /// resolution. Idle is unchanged: with nothing playing there is nothing to broadcast.
        var eventDrivenInterval: TimeInterval {
            switch self {
            case .playing:
                return 2.0
            case .pausedTrack:
                return 3.0
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
    @AppStorage("menuBarTextMode") private var menuBarTextModeRaw: String = MenuBarTextMode.artistAndSong.rawValue { didSet { refresh(); bumpStatusBarConfigRevision() } }
    @AppStorage("preferredProvider") private var preferredProviderRaw: String = PreferredProvider.automatic.rawValue { didSet { refresh() } }
    @AppStorage("themeStyle") private var themeStyleRaw: String = ThemeStyle.artworkAdaptive.rawValue {
        didSet {
            updateTint(from: artwork)
        }
    }
    @AppStorage("themeArtworkBlend") private var themeArtworkBlendStorage: Double = 0.28 {
        didSet {
            updateTint(from: artwork)
        }
    }
    @AppStorage("appAppearanceMode") private var appAppearanceModeRaw: String = AppAppearanceMode.system.rawValue {
        didSet {
            guard oldValue != appAppearanceModeRaw else { return }
            appearanceRevision &+= 1
        }
    }
    @Published var ignoreParentheses: Bool = UserDefaults.standard.bool(forKey: "ignoreParentheses") {
        didSet {
            UserDefaults.standard.set(ignoreParentheses, forKey: "ignoreParentheses")
            refresh()
            bumpStatusBarConfigRevision()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.title = self.title
            }
        }
    }
    @AppStorage("scrollableTitle") var scrollableTitle: Bool = true { didSet { bumpStatusBarConfigRevision() } }
    @AppStorage("menuBarControlsEnabled") var menuBarControlsEnabled: Bool = false { didSet { bumpStatusBarConfigRevision() } }
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
    @AppStorage("cropAnimatedArtworkToSquare") var cropAnimatedArtworkToSquare: Bool = true {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("reduceHiddenMemoryUsage") var reduceHiddenMemoryUsage: Bool = false {
        didSet {
            handleReducedMemoryUsageSettingChanged()
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
    @AppStorage("recordPlayHistory") var recordPlayHistory: Bool = true
    /// Skips are recorded by default: "what did I pass over" is part of what makes a history
    /// worth reading. They are never scrobbled regardless of this setting.
    @AppStorage("recordSkippedTracks") var recordSkippedTracks: Bool = true
    @AppStorage("playHistoryRetentionLimit") var playHistoryRetentionLimit: Int = PlayHistoryStore.maximumRetainedEntries {
        didSet {
            let limit = playHistoryRetentionLimit
            Task { await PlayHistoryStore.shared.setRetentionLimit(limit) }
            reloadPlayHistory()
        }
    }
    @AppStorage("showLyricsPanel") var showLyricsPanel: Bool = true { didSet { requestPopoverLayoutRefresh() } }
    @AppStorage("expandLyricsByDefault") var expandLyricsByDefault: Bool = false {
        didSet {
            if expandLyricsByDefault {
                lyricsPanelExpanded = true
            }
        }
    }
    @AppStorage("lyricsPaneSizePreset") private var lyricsPaneSizePresetRaw: String = LyricsPaneSizePreset.standard.rawValue {
        didSet {
            requestPopoverLayoutRefresh()
        }
    }
    @AppStorage("lyricsFontSizePreset") private var lyricsFontSizePresetRaw: String = LyricsFontSizePreset.standard.rawValue {
        didSet {
            requestPopoverLayoutRefresh()
        }
    }
    @AppStorage("lyricsCustomFontSize") private var lyricsCustomFontSizeStorage: Double = Double(LyricsFontSizePreset.standard.regularInactiveSize) {
        didSet {
            requestPopoverLayoutRefresh()
        }
    }
    @AppStorage("miniMode") var miniMode: Bool = false {
        didSet {
            if oldValue != miniMode {
                // Claimed synchronously, before either notification below is delivered.
                // The layout pass runs off an async hop and would otherwise race ahead
                // and snap the window to its new size with no animation at all.
                modeMorphDeadline = CFAbsoluteTimeGetCurrent() + modeTransitionDuration
            }
            bumpStatusBarConfigRevision()
            notifyPopoverModeTransition()
        }
    }
    /// While this is in the future, the surface frame belongs to the mode morph and the
    /// ordinary layout pass must not touch it. Not @Published — it gates layout rather
    /// than causing it.
    var modeMorphDeadline: CFAbsoluteTime = 0
    @AppStorage("miniLyricsEnabled") var miniLyricsEnabled: Bool = false {
        didSet {
            miniLyricsTransitionToken &+= 1
            requestPopoverLayoutRefresh()
        }
    }
    /// Shows a slim progress rail along the mini card's metadata while the pointer is
    /// away. Hovering still swaps in the full scrubber, so this only governs the resting
    /// state. Default on — it is the one thing the resting card could not tell you.
    @AppStorage("miniRestingProgressEnabled") var miniRestingProgressEnabled: Bool = true
    /// Fills the mini card's resting line with the artwork tint instead of white. Scoped
    /// to that line alone: it is an indicator glanced at from across the desk, where
    /// colour is doing no work a scrubber's white fill needs to do. The tint is
    /// album-derived, so unlike white its contrast is never guaranteed.
    @AppStorage("miniRestingProgressUsesTint") var miniRestingProgressUsesTint: Bool = true
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
    @AppStorage("popoverSizePreset") private var popoverSizePresetRaw: String = PopoverSizePreset.medium.rawValue {
        didSet {
            requestPopoverLayoutRefresh()
        }
    }
    // UI state
    @Published var surfaceMode: NowPlayingSurfaceMode = .popover
    @Published var provider: NowPlayingProvider = .none
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var albumArtist: String = ""
    @Published var album: String = ""
    @Published var isPlaying: Bool = false
    @Published var isShuffleEnabled: Bool = false
    @Published var repeatMode: PlaybackRepeatMode = .off
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
    /// How much of `cardBackgroundPalette` the player surface lets through. Owned by the
    /// theme engine — artwork arrives at full strength, presets at their tuned wash.
    @Published var cardPaletteStrength: Double = 1.0
    @Published var regularControlsContrastBoost: Double = 0
    @Published var statusBarConfigRevision: Int = 0
    @Published var appearanceRevision: Int = 0
    @Published var persistentCacheUsageText: String = "0 MB"
    @Published var isClearingPersistentCache: Bool = false
    @Published var isCurrentTrackFavorited: Bool = false
    @Published var favoriteActionPulseToken: Int = 0
    @Published var popoverModeTransitionToken: Int = 0
    @Published var coachmarkSurfaceRevealRequestToken: Int = 0
    @Published var detachedWindowLevelRevision: Int = 0
    @Published var detachedModeToggleRequestToken: Int = 0
    /// Bumped to ask `StatusBarController` to show or hide the player.
    ///
    /// The controller owns the popover and the detached window; automation entry points —
    /// App Intents and the URL scheme — only have the model, so they go through the same
    /// token pattern the detached-mode controls already use.
    @Published var popoverToggleRequestToken: Int = 0
    @Published var detachedCloseRequestToken: Int = 0
    @Published var miniLyricsTransitionToken: Int = 0
    @Published private(set) var surfaceContentHeightCap: CGFloat?
    @Published var selectedMiniDetailsTab: DetailsPaneTab = .lyrics
    @Published var selectedRegularDetailsTab: DetailsPaneTab = .lyrics
    /// Newest first, **one row per track**. The copy the panes render from, so they never have
    /// to await an actor mid-layout.
    ///
    /// Collapsed rather than raw. Replaying from history records those plays back into
    /// history, so a raw log fills with repeats of whatever you have been replaying —
    /// measured at 22 entries covering 10 tracks, one of them nine times. The queue built from
    /// this list then collapsed to a single track, and Next abandoned history immediately.
    /// Showing each track once keeps the list stable, and keeps what plays next matching what
    /// is on screen. The store still keeps every play; only the presentation collapses.
    @Published private(set) var playHistory: [PlayHistoryEntry] = []
    /// How many times each `collapseIdentity` appears in the full store.
    @Published private(set) var playHistoryPlayCounts: [String: Int] = [:]
    /// Total plays recorded, across all repeats.
    @Published private(set) var playHistoryTotalPlays: Int = 0
    @Published var creditsPayload: CreditsPayload? {
        didSet {
            guard creditsPayload != oldValue else { return }
            requestPopoverLayoutRefresh()
        }
    }
    @Published var lyricsPanelExpanded: Bool = false
    // Internals
    private var cancellables = Set<AnyCancellable>()
    private var metadataRefreshTimer: DispatchSourceTimer?
    private var audioRefreshTimer: DispatchSourceTimer?
    private var currentMetadataPollInterval: TimeInterval = 0
    private var currentAudioPollInterval: TimeInterval = 0
    private var lastSnapshot: NowPlayingSnapshot?
    private let playerEvents = PlayerEventObserver()

    /// Guards the three `scan*` fields below, which are written from the main actor and read on
    /// the refresh queue.
    private let providerScanLock = NSLock()
    private var scanActiveProvider: NowPlayingProvider = .none
    private var scanForcedProviders: Set<NowPlayingProvider> = []
    private var scanLastFetchUptime: [NowPlayingProvider: TimeInterval] = [:]

    /// Longest a player that started on its own can go unnoticed if its broadcast is missed.
    private let idleProviderRescanInterval: TimeInterval = 10

    /// How many polled-but-unannounced changes it takes to stop trusting broadcasts.
    private let unannouncedChangesBeforeDistrust = 2
    /// How recently a broadcast must have landed to be credited with explaining a change.
    private let announcedChangeGrace: TimeInterval = 3
    private var unannouncedChangeCount = 0
    private let audioEvents = AudioOutputObserver()

    /// System audio output state and the resume volume ramp.
    ///
    /// Its changes are relayed through this model's `objectWillChange` so views observing the
    /// model still update when the volume rail changes.
    let audio = AudioOutputCoordinator()

    /// Lyrics fetch state and retry policy. Changes are relayed like `audio`'s.
    let lyrics = LyricsCoordinator()

    /// Animated-artwork stream lookup and the rules for preserving a stream. Relayed like `audio`'s.
    let animated = AnimatedArtworkCoordinator()
    private var lastPlayerEventAt: Date?
    /// How long a broadcast counts as evidence that the players are still announcing changes.
    /// Comfortably longer than a track, so a single long song cannot make the app think the
    /// notifications have stopped.
    private let playerEventFreshnessWindow: TimeInterval = 900
    /// Consecutive polls that came back with nothing playing. The idle state waits for this to
    /// reach `missedFetchesBeforeIdle` so a transient scripting error cannot blank the player.
    private var missedFetchCount = 0
    private let missedFetchesBeforeIdle = 3
    private var cachedIdlePresentation: (value: PlayerIdlePresentation, provider: NowPlayingProvider, timestamp: CFAbsoluteTime)?
    private var launchAtLoginSupported: Bool = true
    private let artworkFallback = ArtworkFallbackLookup()
    private var pendingCarriedArtworkExpiry: DispatchWorkItem?
    /// How long the outgoing cover may stand in for one that is still being looked up.
    ///
    /// Sized against the thing it is covering: the iTunes fallback resolves in ~620ms measured,
    /// so this clears it comfortably. Deliberately not generous — when the lookup is going to
    /// fail, every extra moment here is the *previous* album sitting under the current song's
    /// title, and that is worse than the blank it is standing in for.
    private let carriedArtworkGrace: TimeInterval = 1.5
    private var pendingFallbackWork: DispatchWorkItem?
    #if DEBUG
    #endif
    private let refreshQueue = DispatchQueue(label: "com.nikhilbolar.playstatus.refresh", qos: .utility)
    /// Separate from `refreshQueue` on purpose. The provisional read exists to beat the full
    /// fetch to the screen, and sharing that serial queue means queuing behind the very work it
    /// is racing — under rapid skipping it lost every time, and the fast publish silently never
    /// happened. Higher QoS for the same reason: it is on the path to a visible update.
    private let provisionalQueue = DispatchQueue(label: "com.nikhilbolar.playstatus.provisional", qos: .userInitiated)
    private let pollingTimerQueue = DispatchQueue(label: "com.nikhilbolar.playstatus.polling", qos: .utility)
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

    var themeStyle: ThemeStyle {
        get { ThemeStyle(rawValue: themeStyleRaw) ?? .artworkAdaptive }
        set { themeStyleRaw = newValue.rawValue }
    }

    var themeArtworkBlend: Double {
        get { min(max(themeArtworkBlendStorage, 0), 1) }
        set { themeArtworkBlendStorage = min(max(newValue, 0), 1) }
    }

    var appAppearanceMode: AppAppearanceMode {
        get {
            guard let resolved = AppAppearanceMode(rawValue: appAppearanceModeRaw) else {
                appAppearanceModeRaw = AppAppearanceMode.system.rawValue
                return .system
            }
            return resolved
        }
        set {
            guard appAppearanceModeRaw != newValue.rawValue else { return }
            appAppearanceModeRaw = newValue.rawValue
        }
    }

    var animatedArtworkQualityPolicy: AnimatedArtworkQualityPolicy {
        get { AnimatedArtworkQualityPolicy(rawValue: animatedArtworkQualityPolicyRaw) ?? .adaptive1080 }
        set { animatedArtworkQualityPolicyRaw = newValue.rawValue }
    }

    var lyricsPaneSizePreset: LyricsPaneSizePreset {
        get {
            guard let resolved = LyricsPaneSizePreset(rawValue: lyricsPaneSizePresetRaw) else {
                lyricsPaneSizePresetRaw = LyricsPaneSizePreset.standard.rawValue
                return .standard
            }
            return resolved
        }
        set { lyricsPaneSizePresetRaw = newValue.rawValue }
    }

    var lyricsFontSizePreset: LyricsFontSizePreset {
        get {
            guard let resolved = LyricsFontSizePreset(rawValue: lyricsFontSizePresetRaw) else {
                lyricsFontSizePresetRaw = LyricsFontSizePreset.standard.rawValue
                return .standard
            }
            return resolved
        }
        set {
            guard lyricsFontSizePresetRaw != newValue.rawValue else { return }
            objectWillChange.send()
            lyricsFontSizePresetRaw = newValue.rawValue
            if newValue != .custom {
                lyricsCustomFontSizeStorage = Double(newValue.regularInactiveSize)
            }
        }
    }

    var lyricsCustomFontSize: Double {
        get {
            LyricsFontSizePreset.clampedCustomSize(lyricsCustomFontSizeStorage)
        }
        set {
            let clamped = LyricsFontSizePreset.clampedCustomSize(newValue)
            guard abs(lyricsCustomFontSizeStorage - clamped) >= 0.05 || lyricsFontSizePresetRaw != LyricsFontSizePreset.custom.rawValue else {
                return
            }
            objectWillChange.send()
            lyricsFontSizePresetRaw = LyricsFontSizePreset.custom.rawValue
            lyricsCustomFontSizeStorage = clamped
        }
    }

    var regularLyricsInactiveFontSize: CGFloat {
        LyricsFontSizePreset.regularInactiveSize(for: lyricsCustomFontSize)
    }

    var regularLyricsActiveFontSize: CGFloat {
        LyricsFontSizePreset.regularActiveSize(for: lyricsCustomFontSize)
    }

    var miniLyricsInactiveFontSize: CGFloat {
        LyricsFontSizePreset.miniInactiveSize(for: lyricsCustomFontSize)
    }

    var miniLyricsActiveFontSize: CGFloat {
        LyricsFontSizePreset.miniActiveSize(for: lyricsCustomFontSize)
    }

    var detachedWindowSizePreset: DetachedWindowSizePreset {
        get { DetachedWindowSizePreset(rawValue: detachedWindowSizePresetRaw) ?? .medium }
        set { detachedWindowSizePresetRaw = newValue.rawValue }
    }

    var popoverSizePreset: PopoverSizePreset {
        get { PopoverSizePreset(rawValue: popoverSizePresetRaw) ?? .medium }
        set { popoverSizePresetRaw = newValue.rawValue }
    }

    private var surfaceMiniScaleFactor: CGFloat {
        switch surfaceMode {
        case .popover:
            popoverSizePreset.miniScaleFactor
        case .detached:
            detachedWindowSizePreset.miniScaleFactor
        }
    }

    private var surfaceRegularScaleFactor: CGFloat {
        switch surfaceMode {
        case .popover:
            popoverSizePreset.regularScaleFactor
        case .detached:
            detachedWindowSizePreset.regularScaleFactor
        }
    }

    var regularControlScaleFactor: CGFloat {
        switch surfaceMode {
        case .popover:
            popoverSizePreset.regularControlScaleFactor
        case .detached:
            detachedWindowSizePreset.regularControlScaleFactor
        }
    }

    var miniControlScaleFactor: CGFloat {
        switch surfaceMode {
        case .popover:
            popoverSizePreset.miniControlScaleFactor
        case .detached:
            detachedWindowSizePreset.miniControlScaleFactor
        }
    }

    var statusTextWidth: CGFloat {
        let clamped = min(max(statusTextWidthStorage, 80), 320)
        return CGFloat(clamped)
    }

    /// Must match the font `StatusBarMarqueeView` measures and draws with, or the settings
    /// preview will disagree with the status item about whether a title scrolls.
    var statusBarTitleFont: NSFont {
        NSFont.systemFont(ofSize: 13, weight: .regular)
    }

    var statusTextWidthValue: Double {
        get { min(max(statusTextWidthStorage, 80), 320) }
        set {
            statusTextWidthStorage = min(max(newValue, 80), 320)
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
        let scale = miniMode ? surfaceMiniScaleFactor : surfaceRegularScaleFactor
        return base * scale
    }

    var regularArtworkDisplaySize: CGFloat {
        let base = CGFloat(min(max(artworkDisplaySizeStorage, 120), 260))
        return base * surfaceRegularScaleFactor
    }

    /// Surface metrics are rounded to whole points before they can reach a window.
    ///
    /// A scale factor of 0.85 or 1.10 turns most of these into fractions — 239 × 0.90 = 215.1,
    /// 205 × 0.85 = 174.25. A window can never adopt a fraction, so SwiftUI's ideal size and
    /// the window's real size stay permanently unequal, and every layout pass sees a
    /// difference that no resize can close. `StatusBarController` already rounds the *frame*
    /// for this reason, after fractional sizes were measured walking the detached window 1pt
    /// per track change; these are the same fractions arriving through the content size, where
    /// `NSHostingView.updateAnimatedWindowSize` compares them itself and no app-side
    /// `sizeApproximatelyEqual` guard applies.
    ///
    /// Rounding each component rather than only the totals keeps base + pane == total, so a
    /// pane cannot be off by a point from the space reserved for it.
    private func surfacePoints(_ value: CGFloat) -> CGFloat {
        value.rounded()
    }

    var miniPopoverWidth: CGFloat { surfacePoints(380 * surfaceMiniScaleFactor) }

    var regularPopoverWidth: CGFloat {
        // Artwork + spacing + readable text/controls column + container padding.
        let baseArtwork = CGFloat(min(max(artworkDisplaySizeStorage, 120), 260))
        let base = max(410, baseArtwork + 330)
        return surfacePoints(base * surfaceRegularScaleFactor)
    }

    var popoverWidth: CGFloat {
        miniMode ? miniPopoverWidth : regularPopoverWidth
    }

    var miniBaseHeight: CGFloat { surfacePoints(380 * surfaceMiniScaleFactor) }
    var miniLyricsPaneHeight: CGFloat {
        surfacePoints(lyricsPaneSizePreset.miniContentHeight * surfaceMiniScaleFactor)
    }
    var miniExpandedHeight: CGFloat { miniBaseHeight + miniLyricsPaneHeight }

    var miniPopoverHeight: CGFloat {
        (miniMode && miniLyricsEnabled) ? miniExpandedHeight : miniBaseHeight
    }

    var regularLyricsPaneHeight: CGFloat {
        1 + surfacePoints(lyricsPaneSizePreset.regularContentHeight * surfaceRegularScaleFactor)
    }

    var estimatedRegularPopoverHeight: CGFloat {
        let baseArtwork = CGFloat(min(max(artworkDisplaySizeStorage, 120), 260))
        let base = max(220, baseArtwork + 54)
        return surfacePoints(base * surfaceRegularScaleFactor)
    }

    var regularPopoverHeight: CGFloat {
        let base = estimatedRegularPopoverHeight
        guard lyricsPanelExpanded && !miniMode else { return base }
        return base + regularLyricsPaneHeight
    }

    init() {
        surfaceMode = .popover
        lyricsPanelExpanded = expandLyricsByDefault
        $isPopoverVisible
            .removeDuplicates()
            .sink { [weak self] isVisible in
                self?.handleSurfaceVisibilityChanged(isVisible)
            }
            .store(in: &cancellables)

        playerEvents.start { [weak self] provider, payload in
            self?.handlePlayerEvent(from: provider, payload: payload)
        }

        // Volume, mute and device changes are published by Core Audio, so the rail can track
        // the media keys and Control Center immediately instead of catching up on the next
        // ten-second poll.
        audioEvents.start { [weak self] in
            self?.refreshAudioState()
        }

        audio.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        lyrics.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        lyrics.onLayoutAffectingChange = { [weak self] in
            self?.requestPopoverLayoutRefresh()
        }

        // A fetch outlives a track change, so the coordinator re-checks the live track before
        // publishing anything. Only this model knows what that is.
        animated.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // A resolve outlives the snapshot it was started for, so the coordinator re-checks the
        // live track before publishing. Only this model holds it.
        animated.isSnapshotCurrent = { [weak self] snapshot in
            guard let self, let current = self.lastSnapshot else { return false }
            return self.trackIdentityMatches(current, snapshot)
        }
        animated.liveTrackIsAbsent = { [weak self] in
            guard let self else { return false }
            return self.provider == .none && self.title.isEmpty
        }

        lyrics.isDescriptorCurrent = { [weak self] descriptor in
            guard let self else { return false }
            return self.provider == descriptor.provider &&
                self.title == descriptor.title &&
                self.artist == descriptor.artist &&
                self.album == descriptor.album
        }

        MainActor.assumeIsolated {
            PlaybackSessionTracker.shared.onPlayFinished = { [weak self] play in
                self?.handlePlayFinished(play)
            }
            PlaybackSessionTracker.shared.onPlayStarted = { track in
                ScrobbleService.shared.handlePlayStarted(track)
            }
            PlaybackSessionTracker.shared.onPlayReachedThreshold = { track, startedAt in
                ScrobbleService.shared.handleThresholdReached(track, startedAt: startedAt)
            }
        }
        let retention = playHistoryRetentionLimit
        Task { await PlayHistoryStore.shared.setRetentionLimit(retention) }
        reloadPlayHistory()

        updateMetadataPollingTimerIfNeeded()
        updateAudioPollingTimerIfNeeded()
        launchAtLoginSupported = launchAtLoginStatus() != nil
        refresh()
        refreshAudioState()
        refreshPersistentCacheStats()
    }

    var menuBarTitle: String {
        let parts = menuBarTitleParts
        guard let secondary = parts.secondary else { return parts.primary }
        return parts.primary + menuBarTitleSeparator + secondary
    }

    /// What the status item draws, split into the half that identifies the track and the
    /// half that qualifies it.
    ///
    /// In `artistAndSong` the song now leads. You recognise a track by its name faster
    /// than by its artist, and the menu bar truncates from the right — so putting the
    /// artist first meant the identifying half was the half that got cut. The secondary
    /// part is rendered at reduced alpha, which halves its visual weight without giving up
    /// the information.
    var menuBarTitleParts: (primary: String, secondary: String?) {
        let cleanTitle = displayTitle
        let cleanArtist = artist

        if cleanTitle.isEmpty, cleanArtist.isEmpty {
            return ("Not Playing", nil)
        }

        switch menuBarTextMode {
        case .artist:
            return (cleanArtist.isEmpty ? cleanTitle : cleanArtist, nil)
        case .song:
            return (cleanTitle.isEmpty ? cleanArtist : cleanTitle, nil)
        case .artistAndSong:
            if cleanTitle.isEmpty { return (cleanArtist, nil) }
            if cleanArtist.isEmpty { return (cleanTitle, nil) }
            return (cleanTitle, cleanArtist)
        case .iconOnly:
            return (" ", nil)
        }
    }

    var menuBarTitleSeparator: String { " · " }

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

    /// The artist on its own line. The player gives the album its own, quieter line rather
    /// than running both together behind a bullet, so `artistAlbumLine` is only the
    /// fallback for surfaces with a single line to spend.
    var metadataArtistLine: String {
        if !artist.isEmpty { return artist }
        if !album.isEmpty { return album }
        return "Music"
    }

    var progress: Double { PlaybackClock.shared.progress }
    var elapsed: Double { PlaybackClock.shared.liveElapsed }
    var duration: Double { PlaybackClock.shared.duration }
    var canSeek: Bool { PlaybackClock.shared.canSeek }
    private var shouldReduceTransientMemoryWhileHidden: Bool {
        reduceHiddenMemoryUsage && !isPopoverVisible
    }
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
    /// Bumped when something outside the player view asks for the search field — currently
    /// ⌘F. The popover owns the field's focus state, so it watches this rather than exposing
    /// its `@FocusState` upward.
    @Published var searchFocusRequestToken: Int = 0
    /// Bumped to ask the field to close — Escape, from the keyboard monitor.
    @Published var searchDismissRequestToken: Int = 0
    /// Published upward by the popover so the keyboard monitor knows whether Escape should
    /// close the field or the whole surface.
    @Published var searchFieldIsOpen: Bool = false

    func requestSearchFocus() {
        searchFocusRequestToken &+= 1
    }

    func requestSearchDismiss() {
        searchDismissRequestToken &+= 1
    }

    /// Identifies the current track for view identity and transitions.
    ///
    /// Only the fields that arrive together and identify the song: provider, title, artist.
    /// Album and album artist are deliberately excluded — they can land on a later poll than
    /// the title does, and any field in here re-runs the track-change transition when it
    /// changes, which would show as the details refreshing a second time.
    var trackIdentity: String {
        "\(provider.rawValue)|\(title)|\(artist)"
    }

    /// True whenever there is no track to show or control.
    ///
    /// A menu bar player spends much of its life here, so this is a state to design rather
    /// than a layout to disable — see `PlayerIdleView`.
    var isIdle: Bool { !canControlPlayback }

    /// The provider the idle state should talk about: whichever one is actually reporting,
    /// or the user's preference when none is. Mirrors `openProviderApp`'s own resolution so
    /// the copy and the button can never disagree about which app they mean.
    var idleTargetProvider: NowPlayingProvider {
        guard provider == .none else { return provider }
        return preferredProvider == .spotify ? .spotify : .music
    }

    /// What the player says when nothing is playing, and what its one button does.
    ///
    /// Read from a SwiftUI body, which can evaluate many times a second, so the answer is
    /// memoised briefly: resolving it enumerates running applications, and that has no
    /// business happening once per render.
    var idlePresentation: PlayerIdlePresentation {
        let target = idleTargetProvider
        let now = CFAbsoluteTimeGetCurrent()

        if let cached = cachedIdlePresentation,
           cached.provider == target,
           now - cached.timestamp < 2.0 {
            return cached.value
        }

        let resolved = resolveIdlePresentation(for: target)
        cachedIdlePresentation = (resolved, target, now)
        return resolved
    }

    private func resolveIdlePresentation(for target: NowPlayingProvider) -> PlayerIdlePresentation {
        let name = target.displayName
        let inspector = ProviderConnectionInspector.shared

        guard inspector.isInstalled(target) else {
            return PlayerIdlePresentation(
                headline: "Nothing playing",
                detail: "\(name) isn’t installed on this Mac.",
                action: nil
            )
        }

        guard inspector.isRunning(target) else {
            return PlayerIdlePresentation(
                headline: "Nothing playing",
                detail: "\(name) isn’t running.",
                action: .init(title: "Open \(name)", systemImage: "arrow.up.forward.app", kind: .openApp)
            )
        }

        return PlayerIdlePresentation(
            headline: "Nothing playing",
            detail: "\(name) is open but idle.",
            action: .init(title: "Play in \(name)", systemImage: "play.fill", kind: .play)
        )
    }

    var statusIcon: ProviderIconKind { provider.iconKind }
    var statusLine: String {
        if provider == .none { return "Idle" }
        return isPlaying ? "Playing" : "Paused"
    }
    var launchAtLoginEnabled: Bool { launchAtLoginStatus() == .enabled }
    var canControlPlayback: Bool { provider != .none && !title.isEmpty }
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

    private func cancelPollingTimer(_ timer: inout DispatchSourceTimer?) {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    private func makePollingTimer(
        interval: TimeInterval,
        handler: @escaping @Sendable () -> Void
    ) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: pollingTimerQueue)
        let leewayMilliseconds = max(50, Int((interval * 100).rounded()))
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(leewayMilliseconds)
        )
        timer.setEventHandler(handler: handler)
        timer.resume()
        return timer
    }

    /// True while the players are demonstrably broadcasting their changes.
    ///
    /// Whether playback changes can be expected to announce themselves.
    ///
    /// This used to require having *seen* a broadcast, which meant every launch began at the
    /// half-second cadence and stayed there until the track happened to turn over — measured at
    /// 66 seconds in one session, but unbounded in principle, because a paused player and a
    /// long track both broadcast nothing. The startup cost was real: at 0.5s with both apps
    /// open the refresh could not physically keep up with its own timer.
    ///
    /// So the assumption is inverted. Broadcasts are presumed to work, because on every macOS
    /// this app supports they do, and the app polls at the relaxed cadence from launch. What
    /// earns distrust is not silence — silence is the normal state of a playing track — but a
    /// change discovered by polling that *should* have been announced and wasn't. Two of those
    /// in a row and the app returns to full-rate polling on its own.
    ///
    /// Two rather than one because a poll can legitimately beat an in-flight notification by a
    /// few milliseconds; one such race should not cost the user the relaxed cadence.
    private var playerEventsAreLive: Bool {
        guard unannouncedChangeCount < unannouncedChangesBeforeDistrust else { return false }
        guard let lastPlayerEventAt else { return true }
        return Date().timeIntervalSince(lastPlayerEventAt) < playerEventFreshnessWindow
    }

    /// Notices a change that arrived without the player announcing it.
    ///
    /// Deliberately narrow: only track identity and play/pause, the two things both players
    /// reliably broadcast. Shuffle, repeat and favourite are excluded because toggling them
    /// inside the player broadcasts nothing by design, so counting them would condemn a
    /// perfectly healthy notification path.
    private func noteChangeAnnouncement(previous: NowPlayingSnapshot, current: NowPlayingSnapshot) {
        // Discovering a player that was already going when the app launched is not a missed
        // broadcast — there was nothing to miss.
        guard !previous.title.isEmpty, previous.provider != .none else { return }

        let changed = !trackIdentityMatches(previous, current) || previous.isPlaying != current.isPlaying
        guard changed else { return }

        if let lastPlayerEventAt,
           Date().timeIntervalSince(lastPlayerEventAt) < announcedChangeGrace {
            unannouncedChangeCount = 0
            return
        }

        unannouncedChangeCount += 1
        #if DEBUG
        NSLog(
            "PlayStatus events: unannounced change %d/%d (live=%@)",
            unannouncedChangeCount,
            unannouncedChangesBeforeDistrust,
            playerEventsAreLive ? "yes" : "no"
        )
        #endif
    }

    /// Which players are worth asking on this pass.
    ///
    /// Both apps used to be read every cycle regardless of what they were doing, so a Music
    /// window left open and stopped cost a full metadata read every poll forever while
    /// contributing nothing. The player the user is actually listening to is always read; the
    /// other one is read when it has something to say (it broadcast), when nothing is playing
    /// at all (we have no idea who to trust yet), or when its rescan falls due.
    ///
    /// The rescan is the safety net, not the mechanism. Detection normally rides on the
    /// broadcast and is immediate; this only bounds how long a *missed* broadcast can hide a
    /// player that started up on its own.
    private func providersToScan() -> Set<NowPlayingProvider> {
        let now = ProcessInfo.processInfo.systemUptime

        providerScanLock.lock()
        defer { providerScanLock.unlock() }

        var scan = scanForcedProviders
        scanForcedProviders.removeAll()

        // No active player means no basis for skipping either of them.
        if scanActiveProvider == .none {
            scan.insert(.music)
            scan.insert(.spotify)
        } else {
            scan.insert(scanActiveProvider)
        }

        for provider in [NowPlayingProvider.music, .spotify] where !scan.contains(provider) {
            let last = scanLastFetchUptime[provider] ?? 0
            if now - last >= idleProviderRescanInterval {
                scan.insert(provider)
            }
        }

        for provider in scan {
            scanLastFetchUptime[provider] = now
        }
        return scan
    }

    /// Records who the user is actually listening to, for `providersToScan`.
    private func noteActiveProvider(_ provider: NowPlayingProvider) {
        providerScanLock.lock()
        scanActiveProvider = provider
        providerScanLock.unlock()
    }

    private func handlePlayerEvent(from provider: NowPlayingProvider, payload: PlayerEventPayload?) {
        lastPlayerEventAt = Date()
        // Proof the path works, so any earlier suspicion is retired.
        unannouncedChangeCount = 0

        // A broadcast is the player saying something changed, so it gets read on the next pass
        // even if it is the one we would otherwise be skipping. This is what makes a handover
        // between Music and Spotify land immediately rather than at the rescan.
        providerScanLock.lock()
        scanForcedProviders.insert(provider)
        providerScanLock.unlock()

        // Hand the broadcast to the provider before triggering the read, so the refresh this
        // schedules is the one that gets to use it rather than the one after.
        if let payload {
            switch provider {
            case .music: MusicProvider.noteEvent(payload)
            case .spotify: SpotifyProvider.noteEvent(payload)
            case .none: break
            }
        }

        #if DEBUG
        NSLog(
            "PlayStatus events: %@ broadcast a change payload=%@",
            provider.rawValue,
            payload == nil ? "none" : "parsed"
        )
        #endif

        if let payload {
            scheduleProvisionalPublish(from: payload, provider: provider)
        }

        // The notification means the change has already happened, so this read lands on a
        // settled track rather than mid-flip.
        refresh()
        updateMetadataPollingTimerIfNeeded()
    }

    /// Publishes the new track ahead of the authoritative read — text *and* artwork together.
    ///
    /// A track change costs roughly 320ms before the full snapshot exists: ~50ms to ask where
    /// playback is, ~117ms for the seven fields the broadcast omits, then the artwork and the
    /// decode. The broadcast already knows the song's name, so almost all of that is spent
    /// waiting for information we are not missing.
    ///
    /// The first version of this published the text alone and left the artwork to arrive with
    /// the snapshot. That was wrong to look at: the new title appeared over the *previous*
    /// song's cover for a third of a second, which reads as a glitch rather than as speed. The
    /// artwork read is only ~19ms, so it is worth waiting for — everything visible on the card
    /// changes in one step, just far sooner than it used to.
    ///
    /// Music only. Spotify's cover is fetched from a URL through `ArtworkCache`, which cannot
    /// answer synchronously for a track it has not seen, so there is nothing to publish
    /// atomically and Spotify keeps the ordinary path.
    private func scheduleProvisionalPublish(from payload: PlayerEventPayload, provider: NowPlayingProvider) {
        guard provider == .music else { return }
        guard shouldPublishProvisionally(payload: payload, provider: provider) else {
            #if DEBUG
            NSLog("PlayStatus provisional: skip reason=notNewTrackOrProviderMismatch id=%@", payload.trackIdentity)
            #endif
            return
        }
        // Nothing is on screen to keep consistent, and this is exactly the state where the app
        // is trying not to hold decoded images.
        guard !shouldReduceTransientMemoryWhileHidden else {
            #if DEBUG
            NSLog("PlayStatus provisional: skip reason=memoryReduced")
            #endif
            return
        }

        provisionalQueue.async { [weak self] in
            guard let self else { return }
            #if DEBUG
            let queued = CFAbsoluteTimeGetCurrent()
            #endif
            guard let artwork = MusicProvider.provisionalArtwork(forTrackIdentity: payload.trackIdentity) else {
                #if DEBUG
                NSLog("PlayStatus provisional: skip reason=noArtwork id=%@", payload.trackIdentity)
                #endif
                return
            }
            #if DEBUG
            NSLog("PlayStatus provisional: artwork ready after %.0fms", (CFAbsoluteTimeGetCurrent() - queued) * 1000)
            #endif
            let normalized = artwork.normalizedArtworkForDisplay()
            DispatchQueue.main.async {
                self.publishProvisionalTrack(from: payload, provider: provider, artwork: normalized)
            }
        }
    }

    private func shouldPublishProvisionally(payload: PlayerEventPayload, provider: NowPlayingProvider) -> Bool {
        // Only the player already on screen may paint ahead of arbitration. If the other app
        // broadcasts — it might be idling in the background — deciding who wins is
        // `chooseSnapshot`'s job, and guessing here would let a background player seize the
        // display for a couple of hundred milliseconds.
        guard let current = lastSnapshot,
              current.provider == provider,
              !current.title.isEmpty,
              !payload.title.isEmpty else { return false }

        // Same track means a play/pause or a seek, where the expensive fields are all cached
        // and the normal path is already ~50ms. The win here is specific to a new track.
        return current.title != payload.title
            || current.artist != payload.artist
            || current.album != payload.album
    }

    private func publishProvisionalTrack(
        from payload: PlayerEventPayload,
        provider: NowPlayingProvider,
        artwork: NSImage
    ) {
        // Re-checked because the artwork read happened on another queue: the authoritative
        // snapshot may have landed meanwhile, in which case there is nothing left to pre-empt
        // and publishing again would only re-run the crossfade.
        guard shouldPublishProvisionally(payload: payload, provider: provider) else {
            #if DEBUG
            NSLog("PlayStatus provisional: skip reason=snapshotAlreadyLanded")
            #endif
            return
        }

        self.provider = provider
        self.isPlaying = payload.isPlaying
        self.title = payload.title
        self.artist = payload.artist
        self.album = payload.album
        self.albumArtist = payload.albumArtist ?? ""
        // These describe the track being replaced. Clearing beats showing the previous song's
        // personnel under the new song's title; the real values follow with the snapshot.
        self.creditsPayload = nil

        setDisplayedArtwork(artwork, source: "provisional")

        // A newly started track is at the beginning. Worst case this is wrong by the couple of
        // hundred milliseconds it takes the real read to land and correct it — against a
        // progress bar that would otherwise sit at the *previous* track's end position for
        // just as long, which is the more obviously wrong of the two.
        PlaybackClock.shared.sync(elapsed: 0, duration: payload.duration, isPlaying: payload.isPlaying)

        #if DEBUG
        NSLog("PlayStatus events: provisional publish (with artwork) title=%@", payload.title)
        #endif
    }

    private func updateMetadataPollingTimerIfNeeded(using snapshot: NowPlayingSnapshot? = nil) {
        let mode = metadataPollingMode(for: snapshot)
        let interval = playerEventsAreLive ? mode.eventDrivenInterval : mode.interval
        guard abs(currentMetadataPollInterval - interval) > 0.001 else { return }

        cancelPollingTimer(&metadataRefreshTimer)
        currentMetadataPollInterval = interval
        metadataRefreshTimer = makePollingTimer(interval: interval) { [weak self] in
            #if DEBUG
            self?.recordMetadataPollTick()
            #endif
            self?.refresh()
        }

        #if DEBUG
        NSLog(
            "PlayStatus polling: metadata interval=%.2fs mode=%@ events=%@",
            interval,
            mode.debugLabel,
            playerEventsAreLive ? "live" : "none"
        )
        #endif
    }

    private func desiredAudioPollingInterval() -> TimeInterval {
        isPopoverVisible ? 10.0 : 30.0
    }

    private func updateAudioPollingTimerIfNeeded() {
        let interval = desiredAudioPollingInterval()
        guard abs(currentAudioPollInterval - interval) > 0.001 else { return }

        cancelPollingTimer(&audioRefreshTimer)
        currentAudioPollInterval = interval
        audioRefreshTimer = makePollingTimer(interval: interval) { [weak self] in
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
        cancelPollingTimer(&metadataRefreshTimer)
        cancelPollingTimer(&audioRefreshTimer)
        #if DEBUG
        flushDebugPollMetricsIfNeeded(force: true)
        #endif
    }

    func refresh() {
        refreshQueue.async { [weak self] in
            guard let self else { return }
            let includeArtwork = !self.shouldReduceTransientMemoryWhileHidden

            if self.refreshInFlight {
                self.refreshPending = true
                return
            }

            self.refreshInFlight = true
            repeat {
                self.refreshPending = false

                let scan = self.providersToScan()
                var spotify = (self.enableSpotify && scan.contains(.spotify))
                    ? SpotifyProvider.fetch(includeArtwork: includeArtwork)
                    : nil
                var music = (self.enableMusic && scan.contains(.music))
                    ? MusicProvider.fetch(includeArtwork: includeArtwork)
                    : nil

                // Everything we agreed to look at came up empty, so the provider we skipped is
                // the only remaining explanation for what the user might be hearing. Look at it
                // now: reporting idle without checking is how the surface goes blank on a
                // handover between the two apps.
                if music == nil, spotify == nil {
                    if self.enableSpotify, !scan.contains(.spotify) {
                        spotify = SpotifyProvider.fetch(includeArtwork: includeArtwork)
                    }
                    if self.enableMusic, !scan.contains(.music) {
                        music = MusicProvider.fetch(includeArtwork: includeArtwork)
                    }
                }

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
            missedFetchCount += 1
            // Going idle needs confirmation. `runAppleScript` returns nil for *any* scripting
            // error, and errors are most likely exactly when the track is flipping — so a
            // single empty poll is far more often a hiccup than the user stopping playback.
            // Tearing the player down on one miss is what made skipping tracks blank the
            // whole surface.
            if let last = lastSnapshot,
               !last.title.isEmpty,
               missedFetchCount < missedFetchesBeforeIdle {
                return
            }
            // A staged history queue that runs out on its own just stops Music, and by this
            // point there is no current playlist left to ask about — so this is the one place
            // the armed flag is needed. Confirmed idle, not a transient miss, because the
            // early return above has already been passed.
            if historyQueueHandoffArmed {
                historyQueueHandoffArmed = false
                MusicProvider.shuffleLibrary()
                refresh()
                return
            }

            noteActiveProvider(.none)
            // Only now — a transient empty poll returned above, and ending the play on one of
            // those would cut every track short at the first scripting hiccup.
            observePlaybackSession(nil)
            apply(snapshot: NowPlayingSnapshot(provider: .none, isPlaying: false, title: "", artist: "", album: "", artwork: nil, nativeArtworkState: .none, elapsed: 0, duration: 0, canSeek: false))
            return
        }

        missedFetchCount = 0
        // Feed the tracker before the fast-path return below, so it sees every position sample
        // and not just the polls that change something structural.
        observePlaybackSession(snap)
        // Only a *playing* provider earns the right to have the other one skipped. If what we
        // are showing is paused, the other app may well be the one making sound — and it would
        // have broadcast nothing, because from its side nothing changed.
        noteActiveProvider(snap.isPlaying ? snap.provider : .none)

        if let last = lastSnapshot {
            noteChangeAnnouncement(previous: last, current: snap)
        }

        // Keep progress smooth without re-tinting unless track/provider changed
        if let last = lastSnapshot, snapshotsSimilar(last, snap) {
            PlaybackClock.shared.sync(
                elapsed: snap.elapsed,
                duration: snap.duration,
                isPlaying: snap.isPlaying,
                sampledAtUptime: snap.elapsedSampledAtUptime
            )
            lastSnapshot = snap
            // Same track: if native provider artwork arrives later (e.g. Spotify URL fetch),
            // promote it over any previously shown fallback art without forcing a full apply().
            let lastArtworkIdentity = last.artwork?.artworkTransitionIdentity
            let currentArtworkIdentity = snap.artwork?.artworkTransitionIdentity
            let shouldPromoteNativeArtwork =
                snap.nativeArtworkState == .available &&
                (last.nativeArtworkState != .available || lastArtworkIdentity != currentArtworkIdentity)

            if shouldPromoteNativeArtwork, let artwork = snap.artwork?.normalizedArtworkForDisplay() {
                // Written before the hop, as it always has been — the snapshot is read off the
                // main actor by the next poll, which must not race the display update.
                lastSnapshot?.artwork = artwork
                DispatchQueue.main.async {
                    self.setDisplayedArtwork(artwork, source: "promoteNative")
                }
            }
            return
        }

        apply(snapshot: snap)
    }

    /// Hands one observation to `PlaybackSessionTracker`.
    ///
    /// `applyFetchedSnapshots` is always dispatched onto the main queue by `refresh()`, but the
    /// model itself is not `@MainActor`, so the isolation has to be asserted rather than
    /// inferred. Same pattern as `PlayerEventObserver`.
    private func observePlaybackSession(_ snapshot: NowPlayingSnapshot?) {
        MainActor.assumeIsolated {
            PlaybackSessionTracker.shared.observe(snapshot)
        }
    }

    /// Ends any in-flight play and gets it onto disk before the process exits.
    ///
    /// `applicationWillTerminate` returns straight into exit, so the write cannot be left to a
    /// detached task and the store's two-second debounce would never fire. This blocks the main
    /// thread on the outstanding history work — bounded, because a hung write must not stop the
    /// app from quitting.
    ///
    /// Nothing awaited here touches the main actor: `recordPlayFinished` hands its UI update to
    /// a separate unawaited task precisely so this wait cannot deadlock against it.
    func flushPlaybackSession() {
        MainActor.assumeIsolated {
            PlaybackSessionTracker.shared.flush()
        }

        let outstanding = historyWriteChain
        let completed = DispatchSemaphore(value: 0)
        Task.detached {
            await outstanding?.value
            await PlayHistoryStore.shared.flush()
            completed.signal()
        }
        if completed.wait(timeout: .now() + 2) == .timedOut {
            #if DEBUG
            NSLog("PlayStatus history: flush timed out on terminate")
            #endif
        }
    }

    // MARK: Play history

    /// Serializes history writes.
    ///
    /// Each finished play is a read-modify-write of the whole store, and termination needs a
    /// single handle to wait on. Chaining keeps both properties without a lock.
    private var historyWriteChain: Task<Void, Never>?

    /// `Task.detached`, not `Task`, and the distinction is load-bearing.
    ///
    /// `handlePlayFinished` is reached through `MainActor.assumeIsolated`, so a plain `Task`
    /// inherits main-actor isolation. Termination then blocks the main thread waiting for this
    /// chain, which can never be scheduled — the flush times out and the last play is lost.
    /// Detaching keeps history writes on the global executor, where the wait can actually be
    /// satisfied.
    private func enqueueHistoryWork(_ work: @escaping @Sendable () async -> Void) {
        let previous = historyWriteChain
        historyWriteChain = Task.detached {
            await previous?.value
            await work()
        }
    }

    /// History records a play once it has ended, because only then is the listened time final.
    /// Scrobbling does not wait — see `onPlayReachedThreshold`.
    private func handlePlayFinished(_ play: CompletedPlay) {
        recordPlayInHistory(play)
    }

    private func recordPlayInHistory(_ play: CompletedPlay) {
        guard recordPlayHistory else { return }
        guard play.reachedScrobbleThreshold || recordSkippedTracks else { return }

        // The artwork on screen right now still belongs to the play that just ended: the
        // tracker is fed at the top of `applyFetchedSnapshots`, before `apply` swaps in the
        // incoming track. The identity check makes that ordering fail-safe rather than
        // load-bearing — if it ever stops holding, the row loses its thumbnail instead of
        // showing the wrong one.
        let artworkKey = PlayHistoryArtwork.cacheKey(for: play.track)
        var thumbnail: NSImage?
        if let current = lastSnapshot,
           current.title == play.track.title,
           current.artist == play.track.artist,
           current.album == play.track.album,
           let artwork = current.artwork {
            thumbnail = PlayHistoryArtwork.thumbnail(from: artwork)
        }

        let storedKey = thumbnail == nil ? "" : artworkKey
        let capturedThumbnail = thumbnail
        enqueueHistoryWork { [weak self] in
            if let capturedThumbnail {
                await PersistentMediaCache.shared.storeArtworkImage(capturedThumbnail, forKey: artworkKey)
            }
            let entries = await PlayHistoryStore.shared.record(play, artworkKey: storedKey)
            self?.publishHistory(entries)
        }
    }

    /// Pushes a new list to the panes without the caller awaiting the main actor.
    ///
    /// Deliberately fire-and-forget: `flushPlaybackSession` blocks the main thread while
    /// draining the write chain, so chained work that awaited a main-actor hop would deadlock
    /// against it.
    private nonisolated func publishHistory(_ entries: [PlayHistoryEntry]) {
        // Collapsed once here rather than in the view: `body` runs on every hover and layout
        // pass, and the store holds up to 5,000 entries.
        var counts: [String: Int] = [:]
        var collapsed: [PlayHistoryEntry] = []
        for entry in entries {
            let identity = entry.collapseIdentity
            counts[identity, default: 0] += 1
            if counts[identity] == 1 {
                collapsed.append(entry)
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.playHistory = collapsed
            self.playHistoryPlayCounts = counts
            self.playHistoryTotalPlays = entries.count
        }
    }

    /// Provenance line for the History tab, in the same slot the other tabs use to credit a
    /// source. Here the useful fact is how much there is.
    var playHistoryBadgeText: String {
        playHistory.count == 1 ? "1 track" : "\(playHistory.count) tracks"
    }

    static let playHistoryRetentionChoices = [200, 500, 1000, 2500, PlayHistoryStore.maximumRetainedEntries]

    var playHistoryUsageText: String {
        let plays = playHistoryTotalPlays
        if plays == 0 { return "No plays recorded" }
        let tracks = playHistory.count
        let playsText = plays == 1 ? "1 play" : "\(plays) plays"
        let tracksText = tracks == 1 ? "1 track" : "\(tracks) tracks"
        return "\(playsText) across \(tracksText)"
    }

    private func reloadPlayHistory() {
        enqueueHistoryWork { [weak self] in
            let entries = await PlayHistoryStore.shared.allEntries()
            self?.publishHistory(entries)
        }
    }

    func removeHistoryEntry(_ entry: PlayHistoryEntry) {
        enqueueHistoryWork { [weak self] in
            let entries = await PlayHistoryStore.shared.remove(id: entry.id)
            self?.publishHistory(entries)
        }
    }

    func clearPlayHistory() {
        // Thumbnails outlive the records in the media cache, and the keys are derived from
        // track metadata rather than entry IDs. Without this, replaying a cleared track would
        // surface a thumbnail the user thought they had deleted.
        HistoryArtworkProvider.shared.reset()
        enqueueHistoryWork { [weak self] in
            let entries = await PlayHistoryStore.shared.clear()
            self?.publishHistory(entries)
        }
    }

    /// True while a staged history queue may still be playing.
    ///
    /// Only needed for the case where the queue runs out on its own — Music simply stops, and
    /// by then there is no current playlist left to interrogate. The Next button does not rely
    /// on this: it reads the queue's position from Music directly.
    private var historyQueueHandoffArmed = false

    /// The clicked entry, then everything above it in the list, oldest of those first.
    ///
    /// "Above" is more recent, so the queue replays the listening session forward in time
    /// towards now. Repeats are collapsed — the same track logged three times in a row should
    /// not be queued three times — and only tracks from the same provider are included, since
    /// a Music playlist cannot hold a Spotify track.
    private func historyQueueTracks(startingAt entry: PlayHistoryEntry) -> [MusicProvider.HistoryQueueTrack] {
        // ~40ms per track to stage, so this is a responsiveness cap, not a semantic one. Past
        // it the queue simply runs out sooner and hands off to the shuffled library.
        let maximumQueuedTracks = 50

        var ordered: [PlayHistoryEntry] = [entry]
        if let index = playHistory.firstIndex(where: { $0.id == entry.id }) {
            ordered.append(contentsOf: playHistory[playHistory.startIndex..<index].reversed())
        }

        var seen: Set<String> = []
        var result: [MusicProvider.HistoryQueueTrack] = []
        for candidate in ordered {
            guard candidate.provider == entry.provider else { continue }
            let identity = candidate.track.trackIdentity.isEmpty
                ? "\(candidate.track.title)|\(candidate.track.artist)"
                : candidate.track.trackIdentity
            guard seen.insert(identity).inserted else { continue }
            result.append(
                MusicProvider.HistoryQueueTrack(
                    persistentID: candidate.track.trackIdentity,
                    title: candidate.track.title
                )
            )
            if result.count >= maximumQueuedTracks { break }
        }
        return result
    }

    /// Plays a history entry again, through whichever door its provider offers.
    ///
    /// Spotify's own track URI is exact when the provider reported one; Music has no
    /// equivalent addressable handle from outside, so it goes through the same library search
    /// the player's search field already uses.
    func replayHistoryEntry(_ entry: PlayHistoryEntry) {
        let query = [entry.track.title, entry.track.artist]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        switch entry.provider {
        case .music:
            // Not `searchAndPlayInMusicLibrary`: that plays a bare track, which leaves Music
            // with a one-entry queue and a dead Next button.
            MusicProvider.playHistoryQueue(historyQueueTracks(startingAt: entry))
            historyQueueHandoffArmed = true
            refresh()
        case .spotify:
            if entry.track.trackIdentity.hasPrefix("spotify:track:"),
               let url = URL(string: entry.track.trackIdentity) {
                NSWorkspace.shared.open(url)
            } else {
                openSpotifySearch(query: query)
            }
        case .none:
            break
        }
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
        trackIdentityMatches(a, b) &&
        a.isPlaying == b.isPlaying &&
        a.isShuffleEnabled == b.isShuffleEnabled &&
        a.repeatMode == b.repeatMode &&
        a.isFavorited == b.isFavorited
    }

    private func trackIdentityMatches(_ a: NowPlayingSnapshot, _ b: NowPlayingSnapshot) -> Bool {
        a.provider == b.provider &&
        a.title == b.title &&
        a.artist == b.artist &&
        a.albumArtist == b.albumArtist &&
        a.album == b.album
    }

    private func apply(snapshot: NowPlayingSnapshot) {
        var resolvedSnapshot = snapshot
        resolvedSnapshot.artwork = snapshot.artwork?.normalizedArtworkForDisplay()

        let previousSnapshot = lastSnapshot
        let trackChanged = !isSameTrack(previousSnapshot, resolvedSnapshot)

        // Carry artwork across a re-apply of the same track.
        //
        // `apply` runs whenever anything in `snapshotsSimilar` changes — including
        // `isPlaying` — and the Music provider only reads artwork data when the player is
        // actually playing. Between tracks Music reports a beat of not-playing, so the first
        // poll for a new song frequently arrives with no artwork at all. That produced two
        // visible refreshes: the art cleared and the tint fell back to neutral, then the next
        // poll (or the iTunes fallback) brought art back and re-tinted everything.
        //
        // Keeping the previous image for a track we are already showing collapses that back
        // into one refresh, and stops a pointless fallback lookup for art we already have.
        var carriedAcrossTrackChange = false
        if resolvedSnapshot.artwork == nil,
           let previousSnapshot,
           let carriedArtwork = previousSnapshot.artwork {
            if trackIdentityMatches(previousSnapshot, resolvedSnapshot) {
                resolvedSnapshot.artwork = carriedArtwork
                resolvedSnapshot.nativeArtworkState = previousSnapshot.nativeArtworkState
            } else if resolvedSnapshot.nativeArtworkState == .none {
                // A new track that Music has no embedded artwork for — a streaming track,
                // typically. `fetchFallbackArtwork` below will go and find one, but it takes a
                // network round trip: measured at ~620ms.
                //
                // Publishing nil in the meantime is what made skipping flicker. The card went
                // old cover → blank → new cover, two visible transitions where the user is
                // expecting one. Holding the outgoing image until the replacement is ready
                // collapses that back to a single crossfade.
                //
                // The state stays `.none` so the lookup still runs; this only affects what is
                // on screen while it does.
                resolvedSnapshot.artwork = carriedArtwork
                carriedAcrossTrackChange = true
            }
        }

        lastSnapshot = resolvedSnapshot

        DispatchQueue.main.async {
            self.provider = resolvedSnapshot.provider
            self.isPlaying = resolvedSnapshot.isPlaying
            self.title = resolvedSnapshot.title
            self.artist = resolvedSnapshot.artist
            self.albumArtist = resolvedSnapshot.albumArtist
            self.album = resolvedSnapshot.album
            self.isShuffleEnabled = resolvedSnapshot.isShuffleEnabled
            self.repeatMode = resolvedSnapshot.repeatMode
            self.isCurrentTrackFavorited = resolvedSnapshot.provider == .music ? resolvedSnapshot.isFavorited : false
            self.creditsPayload = resolvedSnapshot.credits
            PlaybackClock.shared.sync(
                elapsed: resolvedSnapshot.elapsed,
                duration: resolvedSnapshot.duration,
                isPlaying: resolvedSnapshot.isPlaying,
                sampledAtUptime: resolvedSnapshot.elapsedSampledAtUptime
            )
            // Only touch the artwork when the image actually differs. Assigning an equivalent
            // image re-triggers the crossfade and re-derives the tint, which is the second
            // half of the double refresh — the identity is content-based, so this compares
            // what is on screen rather than which object it came from.
            let displayedArtworkIdentity = self.artwork?.artworkTransitionIdentity
            let incomingArtworkIdentity = resolvedSnapshot.artwork?.artworkTransitionIdentity
            if displayedArtworkIdentity != incomingArtworkIdentity {
                self.setDisplayedArtwork(resolvedSnapshot.artwork, source: "apply")
            }
            self.updateMetadataPollingTimerIfNeeded(using: resolvedSnapshot)
        }

        if resolvedSnapshot.provider != .none, !resolvedSnapshot.title.isEmpty {
            if trackChanged {
                startLyricsFetch(for: resolvedSnapshot, forceRefresh: false, resetState: true)
            }
        } else {
            lyrics.clear()
            DispatchQueue.main.async {
                self.creditsPayload = nil
            }
        }

        pendingFallbackWork?.cancel()
        pendingFallbackWork = nil

        guard !resolvedSnapshot.title.isEmpty else {
            updateAnimatedArtwork(for: resolvedSnapshot)
            return
        }

        if shouldReduceTransientMemoryWhileHidden {
            updateAnimatedArtwork(for: resolvedSnapshot)
            return
        }

        switch resolvedSnapshot.nativeArtworkState {
        case .available:
            updateAnimatedArtwork(for: resolvedSnapshot)
            return
        case .none:
            if carriedAcrossTrackChange {
                scheduleCarriedArtworkExpiry(for: resolvedSnapshot)
            }
            fetchFallbackArtwork(for: resolvedSnapshot)
        case .pending:
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard let current = self.lastSnapshot,
                      self.trackIdentityMatches(current, resolvedSnapshot) else { return }
                if current.artwork == nil {
                    self.fetchFallbackArtwork(for: resolvedSnapshot)
                }
            }
            pendingFallbackWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }

        updateAnimatedArtwork(for: resolvedSnapshot)
    }

    private func isSameTrack(_ a: NowPlayingSnapshot?, _ b: NowPlayingSnapshot) -> Bool {
        guard let a else { return false }
        return trackIdentityMatches(a, b) &&
            Int(a.duration.rounded()) == Int(b.duration.rounded())
    }

    /// Re-asks for lyrics, ignoring the cache.
    ///
    /// A miss is cached for 24 hours, and LRCLIB is community-contributed — a track with no
    /// lyrics today often has them next week, and a transient network failure would otherwise
    /// stick for the rest of the day. This gives the dead-end states something to do.
    func retryLyricsFetch() {
        guard let snapshot = lastSnapshot, !snapshot.title.isEmpty else { return }
        startLyricsFetch(for: snapshot, forceRefresh: true, resetState: true, userInitiated: true)
    }

    private func startLyricsFetch(
        for snapshot: NowPlayingSnapshot,
        forceRefresh: Bool,
        resetState: Bool,
        userInitiated: Bool = false
    ) {
        let descriptor = LyricsTrackDescriptor(
            provider: snapshot.provider,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            duration: snapshot.duration
        )
        lyrics.start(
            for: descriptor,
            forceRefresh: forceRefresh,
            resetState: resetState,
            userInitiated: userInitiated
        )
    }

    private func updateTint(from image: NSImage?) {
        let resolvedSpec = NowPlayingThemeEngine.resolveTheme(
            style: themeStyle,
            image: image,
            artworkColorIntensity: artworkColorIntensity,
            artworkBlend: themeArtworkBlend
        )

        glassTint = Color(resolvedSpec.tint)
        regularControlsContrastBoost = resolvedSpec.contrastBoost
        cardBackgroundPalette = resolvedSpec.palette.map { Color($0) } + [Color.clear]
        cardPaletteStrength = resolvedSpec.paletteStrength
    }

    private func bumpStatusBarConfigRevision() {
        statusBarConfigRevision &+= 1
    }

    func notifyPopoverModeTransition() {
        popoverModeTransitionToken &+= 1
    }

    func requestCoachmarkSurfaceReveal() {
        coachmarkSurfaceRevealRequestToken &+= 1
    }

    func requestPopoverLayoutRefresh() {
        bumpStatusBarConfigRevision()
    }

    func setSurfaceContentHeightCap(_ height: CGFloat?) {
        switch (surfaceContentHeightCap, height) {
        case (nil, nil):
            return
        case let (current?, next?) where abs(current - next) < 0.5:
            return
        default:
            surfaceContentHeightCap = height
        }
    }

    func requestToggleDetachedMode() {
        detachedModeToggleRequestToken &+= 1
    }

    /// Shows or hides the player, whichever surface is current.
    func requestTogglePlayerSurface() {
        popoverToggleRequestToken &+= 1
    }

    func requestCloseDetachedWindow() {
        detachedCloseRequestToken &+= 1
    }

    func setLyricsPanelExpanded(_ expanded: Bool) {
        guard lyricsPanelExpanded != expanded else { return }
        lyricsPanelExpanded = expanded
        requestPopoverLayoutRefresh()
    }

    func selectRegularDetailsTab(_ tab: DetailsPaneTab) {
        guard selectedRegularDetailsTab != tab else { return }
        selectedRegularDetailsTab = tab
    }

    func selectMiniDetailsTab(_ tab: DetailsPaneTab) {
        guard selectedMiniDetailsTab != tab else { return }
        selectedMiniDetailsTab = tab
    }

    func toggleMiniDetailsTab(_ tab: DetailsPaneTab) {
        if miniLyricsEnabled, selectedMiniDetailsTab == tab {
            miniLyricsEnabled = false
            return
        }

        selectMiniDetailsTab(tab)
        if !miniLyricsEnabled {
            miniLyricsEnabled = true
        }
    }

    func toggleRegularDetailsTab(_ tab: DetailsPaneTab) {
        if lyricsPanelExpanded, selectedRegularDetailsTab == tab {
            setLyricsPanelExpanded(false)
            return
        }

        selectRegularDetailsTab(tab)
        if !lyricsPanelExpanded {
            setLyricsPanelExpanded(true)
        }
    }

    // MARK: - Controls

    func playPause() {
        // A ramp in flight means the last press started playback, so this press is the pause:
        // hand the user's volume back before the player stops.
        if audio.isRamping {
            audio.cancelResumeRamp(restoreTargetVolume: true)
            sendPlayPauseCommand()
            return
        }

        let audioState = AudioOutputController.currentState()
        audio.apply(audioState)

        if shouldApplyResumeVolumeRamp(using: audioState) {
            audio.startResumeRamp(using: audioState) { [weak self] in
                self?.sendPlayPauseCommand()
            }
            return
        }

        sendPlayPauseCommand()
    }

    func nextTrack() {
        switch provider {
        case .spotify:
            SpotifyProvider.next()
        case .music, .none:
            // Music makes `next track` a no-op on the last track of a playlist, so at the end
            // of a staged history queue this hands off to the shuffled library instead of
            // sitting on the final track. Reading the queue position from Music means a queue
            // the user has since navigated away from cannot trigger a spurious handoff.
            if MusicProvider.advanceOrShuffleLibrary() {
                historyQueueHandoffArmed = false
            }
        }
    }

    func previousTrack() {
        switch provider {
        case .spotify: SpotifyProvider.previous()
        case .music, .none: MusicProvider.previous()
        }
    }

    func toggleShuffle() {
        guard canControlPlayback else { return }
        let targetState = !isShuffleEnabled
        let confirmedState: Bool?

        switch provider {
        case .spotify:
            confirmedState = SpotifyProvider.setShuffleEnabled(targetState)
        case .music:
            confirmedState = MusicProvider.setShuffleEnabled(targetState)
        case .none:
            confirmedState = nil
        }

        guard let confirmedState else {
            refresh()
            return
        }

        isShuffleEnabled = confirmedState
        refreshPlaybackModeStateAfterCommand()
    }

    func cycleRepeatMode() {
        guard canControlPlayback else { return }
        let targetMode = repeatMode.next(for: provider)
        let confirmedMode: PlaybackRepeatMode?

        switch provider {
        case .spotify:
            confirmedMode = SpotifyProvider.setRepeatMode(targetMode)
        case .music:
            confirmedMode = MusicProvider.setRepeatMode(targetMode)
        case .none:
            confirmedMode = nil
        }

        guard let confirmedMode else {
            refresh()
            return
        }

        repeatMode = confirmedMode
        refreshPlaybackModeStateAfterCommand()
    }

    func seek(to progress: Double) {
        let p = min(max(progress, 0), 1)
        let target = duration * p
        switch provider {
        case .spotify: SpotifyProvider.seek(to: target)
        case .music, .none: MusicProvider.seek(to: target)
        }
        // The player is authoritative, but its next read is up to a poll away. Moving the clock
        // now means the rail and the active lyric line land on the new position immediately
        // instead of sitting on the old one until the poll catches up.
        PlaybackClock.shared.sync(elapsed: target, duration: duration, isPlaying: isPlaying)
    }

    /// Seeking in the units lyrics are expressed in, so callers do not each re-derive a fraction.
    func seek(toSeconds seconds: Double) {
        guard duration > 0 else { return }
        seek(to: seconds / duration)
    }

    private func refreshPlaybackModeStateAfterCommand() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Animated artwork (forwarded to `animated`)

    var animatedArtworkHLSURL: URL? { animated.hlsURL }
    var animatedArtworkState: AnimatedArtworkState { animated.state }
    var animatedArtworkStatusMessage: String { animated.statusMessage }
    var animatedArtworkLastError: String { animated.lastError }

    // MARK: - Lyrics (forwarded to `lyrics`)

    var lyricsPayload: LyricsPayload? { lyrics.payload }
    var lyricsState: LyricsState { lyrics.state }
    var lyricsLoadingProgress: LyricsLoadingProgress? { lyrics.loadingProgress }
    var lyricsFetchIsUserInitiated: Bool { lyrics.fetchIsUserInitiated }
    var lyricsRetryFoundNothing: Bool { lyrics.retryFoundNothing }

    // MARK: - Audio output (forwarded to `audio`)

    var availableOutputDevices: [AudioOutputDevice] { audio.availableOutputDevices }
    var selectedOutputDeviceID: AudioDeviceID { audio.selectedOutputDeviceID }
    var outputVolume: Double { audio.outputVolume }
    var outputMuted: Bool { audio.outputMuted }

    func refreshAudioState() { audio.refreshState() }
    func setOutputDevice(_ id: AudioDeviceID) { audio.setOutputDevice(id) }
    func setOutputVolume(_ value: Double) { audio.setOutputVolume(value) }
    func toggleOutputMute() { audio.toggleOutputMute() }

    private func sendPlayPauseCommand() {
        switch provider {
        case .spotify:
            SpotifyProvider.playPause()
        case .music, .none:
            MusicProvider.playPause()
        }
    }

    /// Playback-side gating for the resume ramp: only ramp when this press is actually resuming
    /// a real track. The audio-side conditions live on the coordinator.
    private func shouldApplyResumeVolumeRamp(using audioState: AudioOutputState) -> Bool {
        provider != .none &&
        !isPlaying &&
        !title.isEmpty &&
        audio.canRamp(using: audioState)
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
        // Starting something else retires any staged history queue, so its ending cannot
        // later hand off to a shuffled library the user never asked for.
        historyQueueHandoffArmed = false
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

    private func handleSurfaceVisibilityChanged(_ isVisible: Bool) {
        updateAudioPollingTimerIfNeeded()
        guard reduceHiddenMemoryUsage else { return }

        if isVisible {
            refresh()
            refreshAnimatedArtworkForCurrentTrack(force: true)
        } else {
            releaseTransientMediaForHiddenSurface()
        }
    }

    private func handleReducedMemoryUsageSettingChanged() {
        guard reduceHiddenMemoryUsage else { return }
        guard !isPopoverVisible else { return }
        releaseTransientMediaForHiddenSurface()
    }

    private func releaseTransientMediaForHiddenSurface() {
        pendingFallbackWork?.cancel()
        pendingFallbackWork = nil
        artworkFallback.reset()

        animated.reset(
            statusMessage: "Released while hidden to reduce memory",
            clearLookupKey: true,
            resetLastValidMusicSnapshotAt: true
        )

        if artwork != nil {
            setDisplayedArtwork(nil, source: "releasedWhileHidden")
        }

        if var cachedSnapshot = lastSnapshot {
            cachedSnapshot.artwork = nil
            cachedSnapshot.nativeArtworkState = .none
            lastSnapshot = cachedSnapshot
        }

        MusicProvider.clearTransientArtworkCache()
        ArtworkCache.shared.clearMemory()
        ITunesArtworkLookup.shared.clearMemory()
        Task {
            await ITunesMetadataLookup.shared.clearInMemoryCache()
        }
    }

    private func handleAnimatedArtworkSettingChanged() {
        if !animatedArtworkEnabled || !animatedArtworkStreamsEnabled {
            animated.reset(statusMessage: "Animated streams disabled")
            return
        }
        refreshAnimatedArtworkForCurrentTrack(force: true)
    }

    private func refreshAnimatedArtworkForCurrentTrack(force: Bool) {
        guard let snapshot = lastSnapshot else {
            animated.reset(statusMessage: "Idle")
            return
        }

        updateAnimatedArtwork(for: snapshot, force: force)
    }

    private func updateAnimatedArtwork(for snapshot: NowPlayingSnapshot, force: Bool = false) {
        animated.update(
            for: snapshot,
            policy: AnimatedArtworkCoordinator.Policy(
                enabled: animatedArtworkEnabled,
                streamsEnabled: animatedArtworkStreamsEnabled,
                quality: animatedArtworkQualityPolicy,
                reduceMemoryWhileHidden: shouldReduceTransientMemoryWhileHidden
            ),
            force: force
        )
    }

    /// Stops a held-over cover from outliving the lookup it was covering for.
    ///
    /// Carrying the previous image across a track change is a bet that a replacement is coming.
    /// When the lookup finds nothing — an obscure track, no network — that bet has to be
    /// settled, or the card would show the wrong album for as long as the song plays. Blank is
    /// the honest answer at that point; it is only the *flicker* on the way to a real cover
    /// that was worth avoiding.
    private func scheduleCarriedArtworkExpiry(for snapshot: NowPlayingSnapshot) {
        let carriedIdentity = snapshot.artwork?.artworkTransitionIdentity
        pendingCarriedArtworkExpiry?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let current = self.lastSnapshot,
                  self.trackIdentityMatches(current, snapshot) else { return }
            // Something replaced it in the meantime, which is the good outcome.
            guard self.artwork?.artworkTransitionIdentity == carriedIdentity else { return }

            self.setDisplayedArtwork(nil, source: "carriedCoverExpired", syncSnapshot: true)
        }
        pendingCarriedArtworkExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + carriedArtworkGrace, execute: work)
    }

    private func fetchFallbackArtwork(for snapshot: NowPlayingSnapshot) {
        artworkFallback.lookup(for: snapshot) { [weak self] image in
            guard let self else { return }
            guard let current = self.lastSnapshot,
                  self.trackIdentityMatches(current, snapshot) else { return }
            // Recorded on the snapshot too, not just on screen. `apply` carries artwork forward
            // across a re-apply of the same track by reading the last snapshot — without that
            // write-back the carry finds nil and the art we just faded in gets cleared by the
            // next poll.
            self.setDisplayedArtwork(image, source: "fallbackLookup", syncSnapshot: true)
        }
    }

    /// The single place `artwork` changes.
    ///
    /// Every write has to re-derive the tint, and most have to mirror the image onto
    /// `lastSnapshot` so the next poll's carry-forward finds it. Those pairings were repeated at
    /// four call sites and drifted; `source` is the label the DEBUG log uses to say which path
    /// produced the change.
    private func setDisplayedArtwork(
        _ image: NSImage?,
        source: String,
        syncSnapshot: Bool = false
    ) {
        artwork = image
        #if DEBUG
        NSLog("PlayStatus artwork: set from=%@ id=%@", source, artwork?.artworkTransitionIdentity ?? "nil")
        #endif
        updateTint(from: image)
        if syncSnapshot {
            lastSnapshot?.artwork = image
        }
    }
}
