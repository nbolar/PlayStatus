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
            return "See what changed in the rebuilt SwiftUI release and where the best features live now."
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

    var title: String {
        switch self {
        case .welcome:
            return "Choose your players"
        case .welcomeBack:
            return "What changed"
        case .connect:
            return "Connect and verify"
        case .explore:
            return "Tour the new player"
        case .personalize:
            return "Make it yours"
        case .finish:
            return "Ready to go"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "Enable the apps you use and decide which one wins when both are active."
        case .welcomeBack:
            return "The app was rebuilt around SwiftUI, richer visuals, and a more capable player surface."
        case .connect:
            return "Trigger macOS Automation access and confirm PlayStatus can talk to your music apps."
        case .explore:
            return "Preview the redesign before you use it on a live track."
        case .personalize:
            return "Pick the defaults that will shape the menu bar player on day one."
        case .finish:
            return "A few habits to remember, plus fast ways back into the walkthrough."
        }
    }
}

enum CoachmarkID: String, CaseIterable, Hashable {
    case modeToggle
    case search
    case detailsToggle
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
        case .detachedControls:
            return "When detached, pin the window on top or close it and return to the menu bar."
        case .settingsNavigation:
            return "Display, playback, hotkeys, and system controls are grouped here so the redesign stays easy to learn."
        }
    }
}

final class OnboardingCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = OnboardingCoordinator()

    static let experienceVersion = "2.8-relaunch-v1"

    @Published private(set) var presentedMode: OnboardingMode?
    @Published var currentStep: OnboardingStep = .welcome
    @Published private(set) var activeCoachmark: CoachmarkID?

    private let defaults = UserDefaults.standard
    private let completionVersionKey = "playstatus.onboarding.completionVersion"
    private let dismissedCoachmarksKey = "playstatus.onboarding.dismissedCoachmarks"
    private let windowAutosaveName = "PlayStatusOnboardingWindow"
    private let settingsMarkerKeys = [
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
    private var dismissedCoachmarks = Set<CoachmarkID>()
    private let walkthroughPreviewAssets = WalkthroughPreviewAssets.shared

    private override init() {
        super.init()
        loadDismissedCoachmarks()
    }

    var hasSeenCurrentExperience: Bool {
        defaults.string(forKey: completionVersionKey) == Self.experienceVersion
    }

    var resolvedMode: OnboardingMode {
        presentedMode ?? recommendedReplayMode()
    }

    func handleAppLaunch() {
        guard let mode = launchMode() else { return }
        present(mode: mode)
    }

    func present(mode: OnboardingMode? = nil, force: Bool = false, preferredStep: OnboardingStep? = nil) {
        let resolvedMode = mode ?? recommendedReplayMode()
        if !force, hasSeenCurrentExperience, presentedMode == nil, launchMode() == nil {
            return
        }

        presentedMode = resolvedMode
        walkthroughDraftState = WalkthroughDraftState(model: .shared)
        _ = walkthroughPreviewAssets
        let steps = resolvedMode.steps
        currentStep = preferredStep.flatMap { steps.contains($0) ? $0 : nil } ?? steps.first ?? .welcome
        activeCoachmark = nil
        presentWalkthroughWindow()
    }

    func advanceStep() {
        guard let mode = presentedMode else { return }
        let steps = mode.steps
        guard let index = steps.firstIndex(of: currentStep) else { return }
        guard index + 1 < steps.count else {
            finishWalkthrough()
            return
        }

        currentStep = steps[index + 1]
    }

    func goBack() {
        guard let mode = presentedMode else { return }
        let steps = mode.steps
        guard let index = steps.firstIndex(of: currentStep), index > 0 else { return }

        currentStep = steps[index - 1]
    }

    func jump(to step: OnboardingStep) {
        guard let mode = presentedMode else { return }
        guard mode.steps.contains(step), step != currentStep else { return }

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
        dismissedCoachmarks.insert(id)
        persistDismissedCoachmarks()
        if activeCoachmark == id {
            activeCoachmark = nil
        }
        updateActiveCoachmark()
    }

    func isCoachmarkActive(_ id: CoachmarkID) -> Bool {
        activeCoachmark == id
    }

    func resetCoachmarkAvailability() {
        coachmarkAvailability.removeAll()
        activeCoachmark = nil
    }

    func steps(for mode: OnboardingMode) -> [OnboardingStep] {
        mode.steps
    }

    func isLastStep(_ step: OnboardingStep) -> Bool {
        let steps = resolvedMode.steps
        return steps.last == step
    }

    func isFirstStep(_ step: OnboardingStep) -> Bool {
        let steps = resolvedMode.steps
        return steps.first == step
    }

    func shouldShowCoachmarks() -> Bool {
        hasSeenCurrentExperience && presentedMode == nil
    }

    func providerIsInstalled(_ provider: NowPlayingProvider) -> Bool {
        applicationURL(for: provider) != nil
    }

    func openProvider(_ provider: NowPlayingProvider) {
        guard let url = applicationURL(for: provider) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }

    func probeAutomation(for provider: NowPlayingProvider) -> Bool {
        let script: String
        switch provider {
        case .music, .none:
            script = #"tell application "Music" to get player state as string"#
        case .spotify:
            script = #"tell application "Spotify" to get player state as string"#
        }

        return runAppleScriptDescriptor(script) != nil
    }

    func shouldForceModeCoachmarkControls() -> Bool {
        isCoachmarkActive(.modeToggle) || isCoachmarkActive(.detailsToggle) || isCoachmarkActive(.detachedControls)
    }

    func nextStepTitle() -> String {
        isLastStep(currentStep) ? "Finish" : "Continue"
    }

    func currentModeTitle() -> String {
        resolvedMode.title
    }

    private func recommendedReplayMode() -> OnboardingMode {
        hasExistingPreferences ? .upgrade : .freshInstall
    }

    private func launchMode() -> OnboardingMode? {
        guard !hasSeenCurrentExperience else { return nil }
        return hasExistingPreferences ? .upgrade : .freshInstall
    }

    private var hasExistingPreferences: Bool {
        settingsMarkerKeys.contains { defaults.object(forKey: $0) != nil }
    }

    private func markExperienceSeen() {
        defaults.set(Self.experienceVersion, forKey: completionVersionKey)
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
        return window
    }

    private func refreshWalkthroughRootView() {
        walkthroughHost?.rootView = AnyView(
            OnboardingWalkthroughView(
                coordinator: self,
                draft: currentDraftState
            )
        )
        walkthroughWindow?.title = currentModeTitle()
    }

    private func closeWalkthroughWindow() {
        activeCoachmark = nil
        guard let walkthroughWindow else {
            presentedMode = nil
            walkthroughDraftState = nil
            return
        }

        isClosingWalkthroughWindow = true
        walkthroughWindow.close()
        isClosingWalkthroughWindow = false
        self.walkthroughWindow = nil
        walkthroughHost = nil
        walkthroughDraftState = nil
        presentedMode = nil
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
        guard shouldShowCoachmarks() else {
            activeCoachmark = nil
            return
        }

        if let activeCoachmark {
            if dismissedCoachmarks.contains(activeCoachmark) || coachmarkAvailability[activeCoachmark] != true {
                self.activeCoachmark = nil
            } else {
                return
            }
        }

        for id in CoachmarkID.allCases where !dismissedCoachmarks.contains(id) {
            if coachmarkAvailability[id] == true {
                activeCoachmark = id
                return
            }
        }

        activeCoachmark = nil
    }

    private func loadDismissedCoachmarks() {
        let rawValues = defaults.stringArray(forKey: dismissedCoachmarksKey) ?? []
        dismissedCoachmarks = Set(rawValues.compactMap(CoachmarkID.init(rawValue:)))
    }

    private func persistDismissedCoachmarks() {
        defaults.set(dismissedCoachmarks.map(\.rawValue).sorted(), forKey: dismissedCoachmarksKey)
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
        if !isClosingWalkthroughWindow {
            markExperienceSeen()
        }
        presentedMode = nil
        updateActiveCoachmark()
    }
}
