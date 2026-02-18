import SwiftUI
import AppKit
import Combine
import ServiceManagement
import CoreAudio

final class NowPlayingModel: ObservableObject {
    static let shared = NowPlayingModel()

    // User toggles (didSet is the AppStore-safe way to auto-refresh; avoids CombineLatest Binding errors)
    @AppStorage("enableMusic") var enableMusic: Bool = true { didSet { refresh() } }
    @AppStorage("enableSpotify") var enableSpotify: Bool = true { didSet { refresh() } }
    @AppStorage("providerPriority") private var providerPriorityRaw: String = ProviderPriority.musicFirst.rawValue { didSet { refresh() } }
    @AppStorage("menuBarTextMode") private var menuBarTextModeRaw: String = MenuBarTextMode.artistAndSong.rawValue { didSet { refresh(); configureMarquee(forceRestart: true); bumpStatusBarConfigRevision() } }
    @AppStorage("preferredProvider") private var preferredProviderRaw: String = PreferredProvider.automatic.rawValue { didSet { refresh() } }
    @AppStorage("ignoreParentheses") var ignoreParentheses: Bool = false {
        didSet {
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
    @AppStorage("miniMode") var miniMode: Bool = false {
        didSet {
            bumpStatusBarConfigRevision()
        }
    }

    // UI state
    @Published var provider: NowPlayingProvider = .none
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""
    @Published var isPlaying: Bool = false
    @Published var artwork: NSImage? = nil
    @Published var isPopoverVisible: Bool = false
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var glassTint: Color = .white
    @Published var cardBackgroundPalette: [Color] = [
        Color.white.opacity(0.24),
        Color.white.opacity(0.20),
        Color.white.opacity(0.16),
        Color.white.opacity(0.10),
        Color.clear
    ]
    @Published var statusBarConfigRevision: Int = 0
    @Published var menuBarDisplayTitle: String = "Not Playing"
    @Published var availableOutputDevices: [AudioOutputDevice] = []
    @Published var selectedOutputDeviceID: AudioDeviceID = 0
    @Published var outputVolume: Double = 1.0
    @Published var outputMuted: Bool = false
    private var marqueeTimer: AnyCancellable?
    private var marqueeSignature: String = ""
    private var marqueeTrack: [Character] = []
    private var marqueeTrackDoubled: [Character] = []
    private var marqueeIndex: Int = 0
    private var marqueeWindowLength: Int = 0

    // Internals
    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable?
    private var lastSnapshot: NowPlayingSnapshot?
    private var launchAtLoginSupported: Bool = true
    private var fallbackArtworkTaskKey: String?
    private var pendingFallbackWork: DispatchWorkItem?
    private let refreshQueue = DispatchQueue(label: "com.nikhilbolar.playstatus.refresh", qos: .userInitiated)
    private var refreshInFlight = false
    private var refreshPending = false

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
        CGFloat(min(max(artworkDisplaySizeStorage, 120), 260))
    }

    var miniPopoverWidth: CGFloat { 380 }

    var regularPopoverWidth: CGFloat {
        // Artwork + spacing + readable text/controls column + container padding.
        return max(410, artworkDisplaySize + 330)
    }

    var popoverWidth: CGFloat {
        miniMode ? miniPopoverWidth : regularPopoverWidth
    }

    var miniPopoverHeight: CGFloat { 380 }

    var estimatedRegularPopoverHeight: CGFloat {
        max(220, artworkDisplaySize + 54)
    }

    init() {
        // Adaptive polling: fast while playing, slower when idle.
        $isPlaying
            .removeDuplicates()
            .sink { [weak self] playing in
                self?.startTimer(interval: playing ? 0.5 : 1.0)
            }
            .store(in: &cancellables)

        startTimer(interval: 0.5)
        launchAtLoginSupported = launchAtLoginStatus() != nil
        refresh()
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

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    var canSeek: Bool { duration > 0.5 }
    var statusIcon: String { provider.icon }
    var statusLine: String {
        if provider == .none { return "Idle" }
        return isPlaying ? "Playing" : "Paused"
    }
    var launchAtLoginEnabled: Bool { launchAtLoginStatus() == .enabled }

    private func startTimer(interval: Double) {
        timer?.cancel()
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
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
                let audioState = AudioOutputController.currentState()

                DispatchQueue.main.async { [weak self] in
                    self?.applyFetchedSnapshots(music: music, spotify: spotify)
                    self?.applyAudioState(audioState)
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
            elapsed = snap.elapsed
            duration = snap.duration
            isPlaying = snap.isPlaying
            provider = snap.provider
            configureMarquee()
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
        a.album == b.album
    }

    private func apply(snapshot: NowPlayingSnapshot) {
        lastSnapshot = snapshot
        DispatchQueue.main.async {
            self.provider = snapshot.provider
            self.isPlaying = snapshot.isPlaying
            self.title = snapshot.title
            self.artist = snapshot.artist
            self.album = snapshot.album
            self.elapsed = snapshot.elapsed
            self.duration = snapshot.duration
            self.artwork = snapshot.artwork
            self.updateTint(from: snapshot.artwork)
            self.configureMarquee()
        }

        pendingFallbackWork?.cancel()
        pendingFallbackWork = nil

        guard !snapshot.title.isEmpty else { return }

        switch snapshot.nativeArtworkState {
        case .available:
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
    }

    private func updateTint(from image: NSImage?) {
        let scaleOpacity: (Double) -> Double = { base in
            min(max(base * self.artworkColorIntensity, 0), 0.95)
        }

        guard let image else {
            glassTint = .white
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

    func requestPopoverLayoutRefresh() {
        bumpStatusBarConfigRevision()
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
        switch provider {
        case .music, .none:
            MusicProvider.likeCurrentTrack()
        case .spotify:
            // Spotify AppleScript does not expose a stable "like current track" command.
            break
        }
    }

    func searchAndPlayInMusicLibrary(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        MusicProvider.searchAndPlay(query: trimmed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.refresh()
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
