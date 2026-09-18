import SwiftUI
import AppKit
import Combine

enum OnboardingMode: String {
    case freshInstall
    case upgrade

    var title: String {
        switch self {
        case .freshInstall:
            return "Welcome to the new PlayStatus"
        case .upgrade:
            return "Welcome back to PlayStatus"
        }
    }

    var subtitle: String {
        switch self {
        case .freshInstall:
            return "Set up your players, learn the redesign, and tune the app to your style."
        case .upgrade:
            return "Catch up on everything that shipped while you were on the previous version."
        }
    }

    var steps: [OnboardingStep] {
        switch self {
        case .freshInstall:
            return [.welcome, .connect, .explore, .personalize, .finish]
        case .upgrade:
            return [.welcomeBack, .explore, .finish]
        }
    }
}

enum OnboardingStep: String, CaseIterable, Identifiable {
    case welcome
    case welcomeBack
    case connect
    case explore
    case personalize
    case finish

    var id: String { rawValue }

    func title(for mode: OnboardingMode) -> String {
        switch self {
        case .welcome:
            return "Choose your players"
        case .welcomeBack:
            return "What changed"
        case .connect:
            return mode == .upgrade ? "Check your connections" : "Connect and verify"
        case .explore:
            return mode == .upgrade ? "See it in motion" : "Tour the new player"
        case .personalize:
            return mode == .upgrade ? "Settings worth a look" : "Make it yours"
        case .finish:
            return mode == .upgrade ? "You are up to date" : "Ready to go"
        }
    }

    func subtitle(for mode: OnboardingMode) -> String {
        switch self {
        case .welcome:
            return "Enable the apps you use and decide which one wins when both are active."
        case .welcomeBack:
            return "Everything that shipped since the version you were running."
        case .connect:
            return mode == .upgrade
                ? "An update can reset macOS Automation access. Confirm PlayStatus can still reach your players."
                : "Trigger macOS Automation access and confirm PlayStatus can talk to your music apps."
        case .explore:
            return mode == .upgrade
                ? "Try the surfaces the new features live on before you meet them on a real track."
                : "Preview the redesign before you use it on a live track."
        case .personalize:
            return mode == .upgrade
                ? "A quick pass over the settings this update touched, in case any of them changed under you."
                : "Pick the defaults that will shape the menu bar player on day one."
        case .finish:
            return "A few habits to remember, plus fast ways back into the walkthrough."
        }
    }
}

enum CoachmarkID: String, CaseIterable, Hashable {
    case modeToggle
    case search
    case detailsToggle
    case detachedMode
    case detachedControls
    case settingsNavigation

    var title: String {
        switch self {
        case .modeToggle:
            return "Mini or full player"
        case .search:
            return "Search from the player"
        case .detailsToggle:
            return "Open lyrics and credits"
        case .detachedMode:
            return "Pop out the player"
        case .detachedControls:
            return "Pinned detached controls"
        case .settingsNavigation:
            return "Everything lives here"
        }
    }

    var message: String {
        switch self {
        case .modeToggle:
            return "Switch between the compact hover-first mini player and the full playback view."
        case .search:
            return "Search routes to the active provider: Music can play from your library, Spotify opens the matching search."
        case .detailsToggle:
            return "Use these buttons to reveal lyrics or credits without leaving the player."
        case .detachedMode:
            return "Detach the player into its own floating window when you want the artwork and controls to stay visible outside the menu bar."
        case .detachedControls:
            return "When detached, pin the window on top or close it and return to the menu bar."
        case .settingsNavigation:
            return "Display, playback, hotkeys, and system controls are grouped here so the redesign stays easy to learn."
        }
    }

}

@MainActor
final class OnboardingCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = OnboardingCoordinator()

    /// The marker value written by every build that shipped the one-shot relaunch
    /// walkthrough. Its presence means the machine has already been told about 3.0.0.
    static let legacyRelaunchExperienceVersion = "2.8-relaunch-v1"
    /// The release whose notes the legacy marker stands for.
    static let legacyRelaunchRelease = ReleaseVersion("3.0.0")!

    @Published private(set) var presentedMode: OnboardingMode?
    /// The releases the current upgrade walkthrough is presenting, newest first.
    @Published private(set) var presentedReleases: [WhatsNewRelease] = []
    /// The steps the current walkthrough is running. Not every upgrade is the same length,
    /// so this — not the mode alone — is what the shell paginates over.
    @Published private(set) var presentedSteps: [OnboardingStep] = []
    @Published var currentStep: OnboardingStep = .welcome
    @Published private(set) var activeCoachmark: CoachmarkID?
    @Published private(set) var debugCoachmarksEnabled = false

    private let defaults = UserDefaults.standard
    /// Written once the walkthrough has been seen, so its presence is the strongest
    /// evidence that PlayStatus has been run here before. `DefaultsMigrations` reads it for
    /// the same reason, which is why it is not private.
    static let completionVersionKey = "playstatus.onboarding.completionVersion"
    /// The newest release this machine has been shown notes for. This, not a single frozen
    /// marker, is what decides whether there is anything to say on launch.
    private let lastSeenReleaseKey = "playstatus.onboarding.lastSeenRelease"
    private let dismissedCoachmarksKey = "playstatus.onboarding.dismissedCoachmarks"
    private let debugCoachmarksEnabledKey = "playstatus.onboarding.debugCoachmarksEnabled"
    private let windowAutosaveName = "PlayStatusOnboardingWindow"
    /// Keys that only land in defaults once someone has actually configured the app.
    static let settingsMarkerKeys = [
        "enableMusic",
        "enableSpotify",
        "providerPriority",
        "menuBarTextMode",
        "preferredProvider",
        "scrollableTitle",
        "statusTextWidth"
    ]

    private var walkthroughWindow: NSWindow?
    private var walkthroughHost: NSHostingController<AnyView>?
    private var walkthroughDraftState: WalkthroughDraftState?
    private var isClosingWalkthroughWindow = false
    private var coachmarkAvailability: [CoachmarkID: Bool] = [:]
    private var persistedDismissedCoachmarks = Set<CoachmarkID>()
    private var debugDismissedCoachmarks = Set<CoachmarkID>()
    private var cancellables = Set<AnyCancellable>()
    private override init() {
        super.init()
        loadPersistedDismissedCoachmarks()
        seedLastSeenReleaseIfNeeded()
        debugCoachmarksEnabled = defaults.bool(forKey: debugCoachmarksEnabledKey)
        NowPlayingModel.shared.$appearanceRevision
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyAppearanceOverride()
            }
            .store(in: &cancellables)
    }

    /// The version this build actually is. Everything the walkthrough offers is bounded by
    /// it, so a downgrade never advertises features that are not present.
    static var currentAppRelease: ReleaseVersion? {
        ReleaseVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    }

    var hasSeenCurrentExperience: Bool {
        unseenReleases.isEmpty && defaults.string(forKey: Self.completionVersionKey) != nil
    }

    /// Releases this machine has not been shown yet, newest first.
    var unseenReleases: [WhatsNewRelease] {
        WhatsNewCatalog.unseenReleases(
            lastSeen: lastSeenRelease,
            currentVersion: Self.currentAppRelease
        )
    }

    private var lastSeenRelease: ReleaseVersion? {
        defaults.string(forKey: lastSeenReleaseKey).flatMap(ReleaseVersion.init)
    }

    /// Existing installs are placed on the timeline rather than replayed at from the start.
    /// A machine that already saw the relaunch walkthrough starts at 3.0.0, so it is caught
    /// up on 3.0.2 onward without being pitched the relaunch a second time. A machine with
    /// settings but no completion marker never finished a walkthrough, so it gets the lot.
    private func seedLastSeenReleaseIfNeeded() {
        guard defaults.string(forKey: lastSeenReleaseKey) == nil else { return }
        guard let completion = defaults.string(forKey: Self.completionVersionKey) else { return }

        // The legacy marker is not a version string — it parses as "2.8", which would put
        // the relaunch back in front of someone who has already sat through it.
        let seed: ReleaseVersion
        if completion == Self.legacyRelaunchExperienceVersion {
            seed = Self.legacyRelaunchRelease
        } else {
            seed = ReleaseVersion(completion).map(\.releaseLine) ?? Self.legacyRelaunchRelease
        }
        defaults.set(seed.description, forKey: lastSeenReleaseKey)
    }

    var resolvedMode: OnboardingMode {
        presentedMode ?? recommendedReplayMode()
    }

    /// An upgrade flow earns its length. One release is a short "here is what's new" pass;
    /// several mean the user has been away long enough that automation access and the
    /// settings that moved in the meantime are worth a second look.
    static func steps(for mode: OnboardingMode, releaseCount: Int) -> [OnboardingStep] {
        guard mode == .upgrade, releaseCount > 1 else { return mode.steps }
        return [.welcomeBack, .connect, .explore, .personalize, .finish]
    }

    /// The steps in play, whether or not the window is currently open.
    var resolvedSteps: [OnboardingStep] {
        if !presentedSteps.isEmpty { return presentedSteps }
        let mode = resolvedMode
        return Self.steps(for: mode, releaseCount: releasesToPresent(for: mode).count)
    }

    func handleAppLaunch() {
        guard let mode = launchMode() else { return }
        switch mode {
        case .freshInstall:
            present(mode: mode)
        case .upgrade:
            // An upgrade announces itself in the What's New sheet now. The tour is still in
            // the app menu and Settings, it just no longer opens uninvited.
            WhatsNewCoordinator.shared.presentSheet(releases: releasesForWhatsNew)
        }
    }

    /// What the What's New surfaces should show: the outstanding releases, or — when a
    /// replay finds nothing outstanding — the release this build actually is.
    var releasesForWhatsNew: [WhatsNewRelease] {
        releasesToPresent(for: .upgrade)
    }

    /// Record that the user has been told about everything up to this build.
    ///
    /// The What's New sheet reaches for this on dismissal for the same reason the
    /// walkthrough does at its last step: the announcement has been made.
    func markReleasesSeen() {
        markExperienceSeen()
    }

    func present(mode: OnboardingMode? = nil, force: Bool = false, preferredStep: OnboardingStep? = nil) {
        let resolvedMode = mode ?? recommendedReplayMode()
        if !force, hasSeenCurrentExperience, presentedMode == nil, launchMode() == nil {
            return
        }

        presentedMode = resolvedMode
        let releases = releasesToPresent(for: resolvedMode)
        presentedReleases = releases
        presentedSteps = Self.steps(for: resolvedMode, releaseCount: releases.count)
        walkthroughDraftState = WalkthroughDraftState(model: .shared)
        WalkthroughPreviewAssets.shared.prewarm()
        let steps = presentedSteps
        currentStep = preferredStep.flatMap { steps.contains($0) ? $0 : nil } ?? steps.first ?? .welcome
        activeCoachmark = nil
        presentWalkthroughWindow()
    }

    func advanceStep() {
        guard presentedMode != nil else { return }
        let steps = presentedSteps
        guard let index = steps.firstIndex(of: currentStep) else { return }
        guard index + 1 < steps.count else {
            finishWalkthrough()
            return
        }

        currentStep = steps[index + 1]
    }

    func goBack() {
        guard presentedMode != nil else { return }
        let steps = presentedSteps
        guard let index = steps.firstIndex(of: currentStep), index > 0 else { return }

        currentStep = steps[index - 1]
    }

    func jump(to step: OnboardingStep) {
        guard presentedMode != nil else { return }
        guard presentedSteps.contains(step), step != currentStep else { return }

        currentStep = step
    }

    func replayFullWalkthrough() {
        present(mode: .freshInstall, force: true)
    }

    func presentUpgradeWalkthrough() {
        present(mode: .upgrade, force: true)
    }

    func skipWalkthrough() {
        markExperienceSeen()
        closeWalkthroughWindow()
    }

    func finishWalkthrough() {
        applyDraftState()
        markExperienceSeen()
        closeWalkthroughWindow()
        updateActiveCoachmark()
    }

    @MainActor
    func openSettingsFromWalkthrough(using openSettings: OpenSettingsAction) {
        applyDraftState()
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    func openAutomationPrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Media",
            "https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func registerCoachmark(_ id: CoachmarkID, available: Bool) {
        coachmarkAvailability[id] = available
        updateActiveCoachmark()
    }

    func dismissCoachmark(_ id: CoachmarkID) {
        if debugCoachmarksEnabled {
            debugDismissedCoachmarks.insert(id)
        } else {
            persistedDismissedCoachmarks.insert(id)
            persistDismissedCoachmarks()
        }
        if activeCoachmark == id {
            activeCoachmark = nil
        }
        updateActiveCoachmark()
    }

    func isCoachmarkActive(_ id: CoachmarkID) -> Bool {
        activeCoachmark == id
    }

    func setDebugCoachmarksEnabled(_ enabled: Bool) {
        guard debugCoachmarksEnabled != enabled else { return }
        debugCoachmarksEnabled = enabled
        defaults.set(enabled, forKey: debugCoachmarksEnabledKey)
        debugDismissedCoachmarks.removeAll()
        activeCoachmark = nil
        if enabled {
            NowPlayingModel.shared.requestCoachmarkSurfaceReveal()
        }
        updateActiveCoachmark()
    }

    func isLastStep(_ step: OnboardingStep) -> Bool {
        resolvedSteps.last == step
    }

    func isFirstStep(_ step: OnboardingStep) -> Bool {
        resolvedSteps.first == step
    }

    func shouldShowCoachmarks() -> Bool {
        (debugCoachmarksEnabled || hasSeenCurrentExperience) && presentedMode == nil
    }

    func providerIsInstalled(_ provider: NowPlayingProvider) -> Bool {
        applicationURL(for: provider) != nil
    }

    func openProvider(_ provider: NowPlayingProvider) {
        guard let url = applicationURL(for: provider) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }

    func shouldForceModeCoachmarkControls() -> Bool {
        isCoachmarkActive(.modeToggle) ||
        isCoachmarkActive(.detailsToggle) ||
        isCoachmarkActive(.detachedMode) ||
        isCoachmarkActive(.detachedControls)
    }

    func nextStepTitle() -> String {
        isLastStep(currentStep) ? "Finish" : "Continue"
    }

    func currentModeTitle() -> String {
        resolvedMode.title
    }

    /// What the "what changed" step should show. Unseen releases are the point of the
    /// upgrade flow; when someone replays it with nothing outstanding, show the release they
    /// are actually running rather than an empty pane.
    private func releasesToPresent(for mode: OnboardingMode) -> [WhatsNewRelease] {
        guard mode == .upgrade else { return [] }
        let unseen = unseenReleases
        if !unseen.isEmpty { return unseen }

        let ceiling = Self.currentAppRelease?.releaseLine
        let running = WhatsNewCatalog.releases.last { release in
            guard let ceiling else { return true }
            return release.version <= ceiling
        }
        guard let running = running ?? WhatsNewCatalog.latest else { return [] }
        return [running]
    }

    private func recommendedReplayMode() -> OnboardingMode {
        hasExistingPreferences ? .upgrade : .freshInstall
    }

    private func launchMode() -> OnboardingMode? {
        guard hasExistingPreferences || defaults.string(forKey: Self.completionVersionKey) != nil else {
            // Nothing on disk: a genuine first run, whether or not the catalog has news.
            return .freshInstall
        }
        return unseenReleases.isEmpty ? nil : .upgrade
    }

    private var hasExistingPreferences: Bool {
        Self.settingsMarkerKeys.contains { defaults.object(forKey: $0) != nil }
    }

    private func markExperienceSeen() {
        let release = Self.currentAppRelease ?? WhatsNewCatalog.latest?.version
        defaults.set(release?.description ?? Self.legacyRelaunchExperienceVersion, forKey: Self.completionVersionKey)
        guard let release else { return }
        // Never walk the marker backwards: a user who ran a newer build once should not be
        // shown its notes again after opening an older one.
        if let lastSeen = lastSeenRelease, lastSeen >= release { return }
        defaults.set(release.description, forKey: lastSeenReleaseKey)
    }

    private func presentWalkthroughWindow() {
        let window = ensureWalkthroughWindow()
        refreshWalkthroughRootView()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func ensureWalkthroughWindow() -> NSWindow {
        if let walkthroughWindow {
            return walkthroughWindow
        }

        let host = NSHostingController(rootView: AnyView(EmptyView()))
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        walkthroughHost = host

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.title = "PlayStatus Walkthrough"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 620)
        window.setFrameAutosaveName(windowAutosaveName)
        window.contentViewController = host
        window.center()
        walkthroughWindow = window
        applyAppearanceOverride()
        return window
    }

    private func refreshWalkthroughRootView() {
        walkthroughHost?.rootView = AnyView(
            OnboardingWalkthroughView(
                coordinator: self,
                draft: currentDraftState
            )
        )
        applyAppearanceOverride()
        walkthroughWindow?.title = currentModeTitle()
    }

    private func applyAppearanceOverride() {
        let appearance = NowPlayingModel.shared.appAppearanceMode.nsAppearance
        walkthroughHost?.view.appearance = appearance
        walkthroughWindow?.appearance = appearance
        walkthroughWindow?.contentView?.appearance = appearance
    }

    private func closeWalkthroughWindow() {
        activeCoachmark = nil
        guard let walkthroughWindow else {
            presentedMode = nil
            presentedReleases = []
            presentedSteps = []
            walkthroughDraftState = nil
            return
        }

        isClosingWalkthroughWindow = true
        walkthroughWindow.close()
        isClosingWalkthroughWindow = false
        self.walkthroughWindow = nil
        walkthroughHost = nil
        walkthroughDraftState = nil
        WalkthroughPreviewAssets.shared.clearMemory()
        presentedMode = nil
        presentedReleases = []
        presentedSteps = []
    }

    private var currentDraftState: WalkthroughDraftState {
        if let walkthroughDraftState {
            return walkthroughDraftState
        }

        let draftState = WalkthroughDraftState(model: .shared)
        walkthroughDraftState = draftState
        return draftState
    }

    private func applyDraftState() {
        walkthroughDraftState?.apply(to: .shared)
    }

    private func updateActiveCoachmark() {
        let dismissedCoachmarks = activeDismissedCoachmarks
        guard shouldShowCoachmarks() else {
            activeCoachmark = nil
            return
        }

        activeCoachmark = CoachmarkID.allCases.first { id in
            !dismissedCoachmarks.contains(id) &&
            shouldIncludeCoachmarkInCurrentSequence(id) &&
            coachmarkAvailability[id] == true
        }
    }

    private func shouldIncludeCoachmarkInCurrentSequence(_ id: CoachmarkID) -> Bool {
        if debugCoachmarksEnabled, id == .settingsNavigation {
            return false
        }
        return true
    }

    private var activeDismissedCoachmarks: Set<CoachmarkID> {
        debugCoachmarksEnabled ? debugDismissedCoachmarks : persistedDismissedCoachmarks
    }

    private func loadPersistedDismissedCoachmarks() {
        let rawValues = defaults.stringArray(forKey: dismissedCoachmarksKey) ?? []
        persistedDismissedCoachmarks = Set(rawValues.compactMap(CoachmarkID.init(rawValue:)))
    }

    private func persistDismissedCoachmarks() {
        defaults.set(persistedDismissedCoachmarks.map(\.rawValue).sorted(), forKey: dismissedCoachmarksKey)
    }

    private func applicationURL(for provider: NowPlayingProvider) -> URL? {
        let bundleIdentifier: String
        switch provider {
        case .music, .none:
            bundleIdentifier = "com.apple.Music"
        case .spotify:
            bundleIdentifier = "com.spotify.client"
        }

        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === walkthroughWindow else { return }
        walkthroughWindow = nil
        walkthroughHost = nil
        walkthroughDraftState = nil
        WalkthroughPreviewAssets.shared.clearMemory()
        if !isClosingWalkthroughWindow {
            markExperienceSeen()
        }
        presentedMode = nil
        presentedReleases = []
        presentedSteps = []
        updateActiveCoachmark()
    }
}
