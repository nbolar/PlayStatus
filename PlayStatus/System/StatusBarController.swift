import SwiftUI
import AppKit
import Combine

final class StatusBarController: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let popoverHost = NSHostingController(rootView: AnyView(EmptyView()))
    private let detachedHost = NSHostingController(rootView: AnyView(EmptyView()))
    private lazy var detachedContainerController = DetachedNowPlayingContainerController(hostController: detachedHost)
    private var detachedWindow: DetachedNowPlayingWindow?
    private var cancellables = Set<AnyCancellable>()
    private let model = NowPlayingModel.shared
    private let iconView = PassthroughImageView()
    private let marqueeView = StatusBarMarqueeView()
    private let transportControlsView = StatusBarTransportControlsView()
    private let iconSize: CGFloat = 13
    private let statusIconLeadingInset: CGFloat = 4
    private let statusIconTextSpacing: CGFloat = 5
    private let statusTextTrailingInset: CGFloat = 4
    private var lastStatusLength: CGFloat = -1
    private let anchorFollowDriver = PopoverAnchorFollowDriver()
    private var pendingAnchorFollow: DispatchWorkItem?
    /// Where the popover was last deliberately placed. AppKit re-centres the popover on its
    /// positioning view the instant that view's bounds change; this is what that jump gets
    /// undone back to.
    private var placedPopoverOrigin: CGPoint?
    /// A collapse lands as two anchor changes roughly 200ms apart. This has to outlast that
    /// gap, or the popover chases the intermediate geometry and swings back — measured at
    /// 0.16s, it moved twice.
    private let anchorFollowSettleDelay: TimeInterval = 0.3
    private var lastStatusIcon: ProviderIconKind?
    private var lastAppliedPopoverSize: NSSize = .zero
    private let morphDriver = ModeMorphDriver()
    private var pendingLyricsResizeAnimation = false
    private var lastMiniModeValue: Bool = false
    private var lastLyricsPaneExpandedValue: Bool = false
    private var lyricsResizeAnimationEndTime: CFAbsoluteTime = 0
    private var popoverLayoutUpdateScheduled = false
    private var surfaceContentLoaded = true
    /// Installed only while a player surface is on screen, so the bindings cannot fire from
    /// Settings or the walkthrough.
    private lazy var keyboardCommands = PlayerKeyboardCommands(
        model: model,
        surfaceWindow: { [weak self] in self?.activeSurfaceWindow() },
        closeSurface: { [weak self] in self?.closeActiveSurface() }
    )
    private let detachedWindowOriginXKey = "detachedWindowOriginX"
    private let detachedWindowOriginYKey = "detachedWindowOriginY"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            // Trigger on mouseDown so toggle logic runs before NSPopover's transient
            // mouseUp close handling; this avoids close-then-immediate-reopen races.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.imagePosition = .noImage
            button.image = nil
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""

            iconView.imageScaling = .scaleProportionallyDown
            iconView.contentTintColor = .labelColor
            button.addSubview(iconView)
            button.addSubview(marqueeView)
            marqueeView.isHidden = true

            transportControlsView.onPrevious = { [weak self] in self?.model.previousTrack() }
            transportControlsView.onPlayPause = { [weak self] in self?.model.playPause() }
            transportControlsView.onNext = { [weak self] in self?.model.nextTrack() }
            button.addSubview(transportControlsView)
            transportControlsView.isHidden = true
        }

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        if #available(macOS 13.0, *) {
            // We drive popover sizing explicitly via updatePopoverLayout().
            // Disable HostingController auto-size propagation to avoid transient
            // intermediate window sizes during rapid SwiftUI tree changes.
            popoverHost.sizingOptions = []
            detachedHost.sizingOptions = []
        }
        popover.contentViewController = popoverHost
        model.surfaceMode = .popover
        model.isPopoverVisible = false
        applyAppearanceOverride()
        lastMiniModeValue = model.miniMode
        lastLyricsPaneExpandedValue = currentLyricsPaneExpandedState()
        updatePopoverLayout()
        _ = SparkleUpdater.shared

        model.$provider
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusButton() }
            .store(in: &cancellables)

        model.$title
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusButton() }
            .store(in: &cancellables)

        model.$artist
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusButton() }
            .store(in: &cancellables)

        model.$isPlaying
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusButton() }
            .store(in: &cancellables)

        model.$isPopoverVisible
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in
                self?.handleSurfaceVisibilityStateChanged(isVisible)
            }
            .store(in: &cancellables)

        model.$statusBarConfigRevision
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let currentMiniMode = self.model.miniMode
                let currentLyricsPaneExpanded = self.currentLyricsPaneExpandedState()
                if currentMiniMode == self.lastMiniModeValue {
                    if currentLyricsPaneExpanded != self.lastLyricsPaneExpandedValue {
                        self.pendingLyricsResizeAnimation = true
                        self.lyricsResizeAnimationEndTime = CFAbsoluteTimeGetCurrent() + miniLyricsTransitionDuration
                        self.lastLyricsPaneExpandedValue = currentLyricsPaneExpanded
                    }
                }
                self.updateStatusButton()
                self.schedulePopoverLayoutUpdate()
            }
            .store(in: &cancellables)

        model.$popoverModeTransitionToken
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let currentMiniMode = self.model.miniMode
                if currentMiniMode != self.lastMiniModeValue {
                    self.pendingLyricsResizeAnimation = false
                    self.lyricsResizeAnimationEndTime = 0
                    self.lastMiniModeValue = currentMiniMode
                    self.lastLyricsPaneExpandedValue = self.currentLyricsPaneExpandedState()
                    // Start the animation here rather than leaving a flag for the layout
                    // pass to notice. That flag was being consumed by whichever of the
                    // two hops ran first, and when the layout pass lost the race the
                    // window simply snapped.
                    self.beginModeMorphResize()
                }
            }
            .store(in: &cancellables)

        model.$detachedModeToggleRequestToken
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.toggleDetachedMode(showImmediately: true)
            }
            .store(in: &cancellables)

        model.$detachedCloseRequestToken
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.closeDetachedWindowAndReturnToPopover()
            }
            .store(in: &cancellables)

        // `dropFirst` because publishing the initial value on subscribe would open the player
        // at launch, which is precisely what a menu bar app must not do.
        model.$popoverToggleRequestToken
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.togglePopover(nil)
            }
            .store(in: &cancellables)

        model.$detachedWindowLevelRevision
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDetachedWindowLevel()
            }
            .store(in: &cancellables)

        model.$appearanceRevision
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyAppearanceOverride()
            }
            .store(in: &cancellables)

        model.$coachmarkSurfaceRevealRequestToken
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.revealCoachmarkSurface()
            }
            .store(in: &cancellables)

        if let button = statusItem.button {
            button.postsFrameChangedNotifications = true
            NotificationCenter.default.publisher(for: NSView.frameDidChangeNotification, object: button)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.updateStatusButton()
                    self?.repositionPopoverIfAnchorMoved()
                }
                .store(in: &cancellables)
        }

        // The status item's own window is what slides when the menu bar re-flows: the
        // button's frame inside it never changes, so frameDidChange alone misses the move.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] notification in
                    guard let self,
                          let window = notification.object as? NSWindow,
                          window === self.statusItem?.button?.window else { return }
                    self.repositionPopoverIfAnchorMoved()
                }
                .store(in: &cancellables)
        }

        updateStatusButton()

        HotkeyManager.shared.configure(callbacks: [
            .playPause: { [weak self] in self?.model.playPause() },
            .nextTrack: { [weak self] in self?.model.nextTrack() },
            .previousTrack: { [weak self] in self?.model.previousTrack() },
            .togglePopover: { [weak self] in self?.togglePopoverFromHotkey() },
            .likeSong: { [weak self] in self?.model.likeCurrentSong() },
            .toggleDetachedMode: { [weak self] in self?.toggleDetachedModeFromHotkey() }
        ])
        HotkeyManager.shared.registerAll()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            OnboardingCoordinator.shared.handleAppLaunch()
        }
    }

    /// Handles `playstatus://` URLs.
    ///
    /// Routes to the same model methods the App Intents use, so the two automation front
    /// doors cannot drift apart. Unknown hosts are ignored rather than reported: these arrive
    /// from scripts and launchers, where a dialog would be worse than a no-op.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "playstatus" {
            handlePlayStatusURL(url)
        }
    }

    private func handlePlayStatusURL(_ url: URL) {
        // `playstatus://next` parses the verb as the host; `playstatus:next` as the path.
        // Scripts and launchers write both, so accept either.
        let command = (url.host?.isEmpty == false ? url.host! : url.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        func value(_ name: String) -> Double? {
            query.first { $0.name.lowercased() == name }
                .flatMap { $0.value }
                .flatMap(Double.init)
        }

        switch command {
        case "playpause", "toggleplay":
            model.playPause()
        case "next":
            model.nextTrack()
        case "previous", "prev":
            model.previousTrack()
        case "favorite", "like":
            _ = model.toggleCurrentTrackFavorite()
        case "toggle", "player":
            model.requestTogglePlayerSurface()
        case "shuffle":
            model.toggleShuffle()
        case "repeat":
            model.cycleRepeatMode()
        case "volume":
            guard let level = value("level") else { return }
            // Accept both 0–1 and 0–100, since both conventions get written by hand.
            let normalized = level > 1 ? level / 100 : level
            model.setOutputVolume(min(max(normalized, 0), 1))
        case "seek":
            guard let seconds = value("seconds") else { return }
            model.seek(toSeconds: seconds)
        default:
            #if DEBUG
            NSLog("PlayStatus url: ignoring unknown command %@", command)
            #endif
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        persistDetachedWindowOrigin()
        HotkeyManager.shared.unregisterAll()
        // Quitting mid-track must not lose the play in progress.
        model.flushPlaybackSession()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if model.surfaceMode == .detached {
            toggleDetachedWindowVisibility()
            return
        }
        togglePopoverVisibility(sender)
    }

    private func togglePopoverVisibility(_ sender: Any?) {
        if popover.isShown {
            hidePopover(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        ensureSurfaceContentLoaded()
        hideDetachedWindow()
        updatePopoverLayout()
        model.isPopoverVisible = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        placedPopoverOrigin = popover.contentViewController?.view.window?.frame.origin
        applyAppearanceOverride()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: false)
            popover.contentViewController?.view.window?.makeKey()
            syncKeyboardCommands()
        }
    }

    private func hidePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        }
        model.isPopoverVisible = false
    }

    private func togglePopoverFromHotkey() {
        togglePopover(nil)
    }

    private func revealCoachmarkSurface() {
        model.miniMode = false
        if model.surfaceMode == .detached {
            exitDetachedMode(openPopoverImmediately: true)
            return
        }

        if popover.isShown {
            ensureSurfaceContentLoaded()
            updatePopoverLayout()
            model.isPopoverVisible = true
            NSApp.activate(ignoringOtherApps: false)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        } else {
            showPopover()
        }
    }

    /// The window a player surface is currently presented in, or nil when none is showing.
    private func activeSurfaceWindow() -> NSWindow? {
        if let detachedWindow, detachedWindow.isVisible {
            return detachedWindow
        }
        guard popover.isShown else { return nil }
        return popover.contentViewController?.view.window
    }

    private func closeActiveSurface() {
        if let detachedWindow, detachedWindow.isVisible {
            closeDetachedWindowAndReturnToPopover()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    private func syncKeyboardCommands() {
        if activeSurfaceWindow() != nil {
            keyboardCommands.install()
        } else {
            keyboardCommands.remove()
        }
    }

    private func toggleDetachedModeFromHotkey() {
        toggleDetachedMode(showImmediately: true)
    }

    private func toggleDetachedMode(showImmediately: Bool) {
        if model.surfaceMode == .detached {
            exitDetachedMode(openPopoverImmediately: showImmediately)
        } else {
            enterDetachedMode(showImmediately: showImmediately)
        }
    }

    private func enterDetachedMode(showImmediately: Bool) {
        model.surfaceMode = .detached
        if popover.isShown {
            popover.performClose(nil)
        }
        if showImmediately {
            showDetachedWindow()
        } else {
            hideDetachedWindow()
        }
    }

    private func exitDetachedMode(openPopoverImmediately: Bool) {
        hideDetachedWindow()
        model.surfaceMode = .popover
        if openPopoverImmediately {
            showPopover()
        } else {
            model.isPopoverVisible = false
        }
    }

    private func closeDetachedWindowAndReturnToPopover() {
        guard model.surfaceMode == .detached else { return }
        hideDetachedWindow()
        model.surfaceMode = .popover
        model.isPopoverVisible = false
    }

    private func toggleDetachedWindowVisibility() {
        if let detachedWindow, detachedWindow.isVisible {
            hideDetachedWindow()
        } else {
            showDetachedWindow()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        syncKeyboardCommands()
        pendingAnchorFollow?.cancel()
        pendingAnchorFollow = nil
        anchorFollowDriver.cancel()
        placedPopoverOrigin = nil
        if model.surfaceMode == .popover {
            model.isPopoverVisible = false
            return
        }
        if detachedWindow?.isVisible != true {
            model.isPopoverVisible = false
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === detachedWindow else { return }
        persistDetachedWindowOrigin(from: window.frame)
        detachedWindow = nil
        syncKeyboardCommands()
        if model.surfaceMode == .detached {
            model.surfaceMode = .popover
            model.isPopoverVisible = false
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === detachedWindow else { return }
        persistDetachedWindowOrigin(from: window.frame)
    }

    private func updateStatusButton() {
        guard let statusItem, let button = statusItem.button else { return }

        let icon = model.statusIcon
        if icon != lastStatusIcon {
            iconView.image = statusImage(for: icon)
            lastStatusIcon = icon
        }

        let showMenuBarText = model.isPlaying && model.menuBarTextMode != .iconOnly
        let showControls = model.menuBarControlsEnabled
        let controlsWidth = showControls ? StatusBarTransportControlsView.totalWidth : 0
        transportControlsView.isHidden = !showControls
        if showControls {
            transportControlsView.apply(isPlaying: model.isPlaying, enabled: model.canControlPlayback)
        }

        if !showMenuBarText {
            let iconLength: CGFloat = 22
            let desiredLength = iconLength + controlsWidth
            if abs(lastStatusLength - desiredLength) > 0.1 {
                statusItem.length = desiredLength
                lastStatusLength = desiredLength
            }
            let iconY = floor((button.bounds.height - iconSize) / 2)
            let iconX = floor((iconLength - iconSize) / 2)
            iconView.frame = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
            layoutTransportControls(in: button, leadingEdge: iconLength, width: controlsWidth)
            marqueeView.suspendScrolling()
            marqueeView.isHidden = true
            button.image = nil
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
            button.toolTip = model.statusLine
            return
        }

        let configuredLaneWidth = model.statusTextWidth
        let actualTextWidth = measuredTextWidth(
            model.menuBarTitle,
            font: .systemFont(ofSize: 13, weight: .regular)
        )
        let effectiveLaneWidth = floor(min(configuredLaneWidth, max(24, actualTextWidth + 2)))
        let laneChrome = statusIconLeadingInset
            + iconSize
            + statusIconTextSpacing
            + statusTextTrailingInset
            + controlsWidth

        // The icon and marquee are custom button subviews, so their complete
        // horizontal layout must fit inside the status item. Reserving only the
        // text lane clips long titles as soon as they reach the configured width.
        let desiredLength = laneChrome + effectiveLaneWidth
        if abs(lastStatusLength - desiredLength) > 0.1 {
            statusItem.length = desiredLength
            lastStatusLength = desiredLength
        }
        let iconY = floor((button.bounds.height - iconSize) / 2)
        iconView.frame = CGRect(x: statusIconLeadingInset, y: iconY, width: iconSize, height: iconSize)
        marqueeView.isHidden = false
        button.image = nil
        button.attributedTitle = NSAttributedString(string: "")
        button.title = ""

        let laneHeight: CGFloat = 16
        let x = floor(iconView.frame.maxX + statusIconTextSpacing)
        let y = floor((button.bounds.height - laneHeight) / 2)
        let targetFrame = CGRect(x: x, y: y, width: effectiveLaneWidth, height: laneHeight)
        if !marqueeView.frame.equalTo(targetFrame) {
            marqueeView.frame = targetFrame
        }
        layoutTransportControls(
            in: button,
            leadingEdge: targetFrame.maxX + statusTextTrailingInset,
            width: controlsWidth
        )
        let titleParts = model.menuBarTitleParts
        marqueeView.update(
            text: model.menuBarTitle,
            secondarySuffix: titleParts.secondary.map { model.menuBarTitleSeparator + $0 },
            enabled: model.scrollableTitle,
            laneWidth: effectiveLaneWidth,
            slideOnChange: model.slideTitleOnChange
        )
        button.toolTip = model.menuBarTitle
    }

    /// Keeps an open popover under its anchor.
    ///
    /// The status item is the popover's positioning view, and its width changes with the
    /// player state (the title lane collapses on pause). macOS re-flows the menu bar but
    /// leaves the popover at its original screen position, so it ends up pointing at
    /// whatever item slid into that spot.
    ///
    /// A collapse arrives as two separate steps roughly 200ms apart — the item first
    /// narrows in place, then the whole bar slides — and those steps pull the anchor in
    /// opposite directions. Chasing each one produces a visible swing left and back, so the
    /// move is debounced and run once against the settled anchor.
    private func repositionPopoverIfAnchorMoved() {
        guard popover.isShown else { return }
        // The button's bounds shrink before the menu bar slides, and AppKit answers the
        // bounds change alone by re-centring the popover — half the width change to the
        // left, landing nowhere the anchor actually is. Undo it and let the settled move
        // below do the travelling.
        if !anchorFollowDriver.isRunning,
           let placed = placedPopoverOrigin,
           let window = popover.contentViewController?.view.window,
           window.frame.origin != placed {
            window.setFrameOrigin(placed)
        }
        pendingAnchorFollow?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingAnchorFollow = nil
            self?.followAnchor()
        }
        pendingAnchorFollow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + anchorFollowSettleDelay, execute: work)
    }

    /// Slides the popover to wherever AppKit would place it against the current anchor.
    ///
    /// `show` is what derives that position, but it teleports. So it runs first to get the
    /// authoritative destination, the window is put straight back, and the gap is animated —
    /// deriving the destination by hand instead would mean re-implementing NSPopover's
    /// placement (arrow centring, screen clamping) and drifting from it.
    private func followAnchor() {
        guard popover.isShown,
              let button = statusItem?.button,
              let before = placedPopoverOrigin ?? popover.contentViewController?.view.window?.frame.origin else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard let window = popover.contentViewController?.view.window else { return }
        let after = window.frame.origin
        placedPopoverOrigin = after
        guard abs(after.x - before.x) > 0.5 || abs(after.y - before.y) > 0.5 else { return }
        // A mode morph is already stepping this window's frame; leave it at the placed
        // position rather than running a second driver against it.
        guard !morphDriver.isRunning else { return }
        window.setFrameOrigin(before)
        anchorFollowDriver.animate(window, to: after)
    }

    private func layoutTransportControls(in button: NSView, leadingEdge: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let targetFrame = CGRect(x: leadingEdge, y: 0, width: width, height: button.bounds.height)
        if !transportControlsView.frame.equalTo(targetFrame) {
            transportControlsView.frame = targetFrame
            transportControlsView.needsLayout = true
        }
    }

    private func statusImage(for icon: ProviderIconKind) -> NSImage? {
        switch icon {
        case .sfSymbol(let symbolName):
            return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: iconSize, weight: .regular))
        case .iconifyAsset(let assetName):
            return statusAssetImage(named: assetName)
        }
    }

    private func statusAssetImage(named assetName: String) -> NSImage? {
        guard let base = NSImage(named: NSImage.Name(assetName)) else { return nil }
        guard let copy = base.copy() as? NSImage else {
            base.isTemplate = true
            base.size = NSSize(width: iconSize, height: iconSize)
            return base
        }
        copy.isTemplate = true
        copy.size = NSSize(width: iconSize, height: iconSize)
        return copy
    }

    private func desiredSurfaceContentSize() -> NSSize {
        let resolvedContentHeight: CGFloat = model.miniMode
            ? model.miniPopoverHeight
            : model.regularPopoverHeight
        return NSSize(width: model.popoverWidth, height: resolvedContentHeight)
    }

    private func currentSurfaceContentSize(anchorWindow: NSWindow? = nil, updatesHeightCap: Bool = true) -> NSSize {
        let desiredSize = desiredSurfaceContentSize()
        let targetSize = constrainedSurfaceContentSize(desiredSize, anchorWindow: anchorWindow)
        if updatesHeightCap {
            model.setSurfaceContentHeightCap(targetSize.height < desiredSize.height - 0.5 ? targetSize.height : nil)
        }
        return targetSize
    }

    private func minimumSurfaceContentHeight() -> CGFloat {
        model.miniMode ? model.miniBaseHeight : model.estimatedRegularPopoverHeight
    }

    private func constrainedSurfaceContentSize(_ desiredSize: NSSize, anchorWindow: NSWindow?) -> NSSize {
        guard let maxContentHeight = maxVisibleSurfaceContentHeight(anchorWindow: anchorWindow, desiredSize: desiredSize) else {
            return desiredSize
        }

        let resolvedHeight = min(
            desiredSize.height,
            max(minimumSurfaceContentHeight(), maxContentHeight)
        )
        return NSSize(width: desiredSize.width, height: resolvedHeight)
    }

    private func maxVisibleSurfaceContentHeight(anchorWindow: NSWindow?, desiredSize: NSSize) -> CGFloat? {
        let bottomPadding: CGFloat = 6

        if let anchorWindow,
           let screenFrame = anchorWindow.screen?.visibleFrame {
            let maxFrameHeight = max(
                0,
                anchorWindow.frame.maxY - screenFrame.minY - bottomPadding
            )
            let frameRect = NSRect(
                x: 0,
                y: 0,
                width: desiredSize.width,
                height: maxFrameHeight
            )
            return max(0, anchorWindow.contentRect(forFrameRect: frameRect).height)
        }

        guard model.surfaceMode == .popover,
              let button = statusItem?.button,
              let buttonWindow = button.window,
              let screenFrame = buttonWindow.screen?.visibleFrame else {
            return nil
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
        return max(0, buttonRectOnScreen.minY - screenFrame.minY - bottomPadding)
    }

    private var modeMorphInFlight: Bool {
        morphDriver.isRunning || CFAbsoluteTimeGetCurrent() < model.modeMorphDeadline
    }

    /// Target frame for the popover's backing window: sized to the current mode, top
    /// edge held where it is, centred on the status item. Returns nil when the window is
    /// already there. Shared by the morph and the ordinary layout pass so both agree.
    /// Rounds a target frame size up to whole points.
    ///
    /// `currentSurfaceContentSize` reports SwiftUI's ideal size, which is fractional — 274.3pt
    /// where the window is 275pt. A window never adopts the fraction, so comparing the two
    /// raw values finds a 0.7pt "difference" that no resize can ever close: the early-out
    /// below never fires, every content change schedules a resize, and each one folds the
    /// leftover fraction into the origin via `round(maxY - height)`. Measured, that walked the
    /// detached window upward exactly 1pt per track change, indefinitely.
    ///
    /// Rounding up — rather than to nearest — because this size has to *contain* the content;
    /// half a point short is a clipped descender.
    private func snappedFrameSize(_ size: NSSize) -> NSSize {
        NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func popoverTargetFrame(for window: NSWindow) -> NSRect? {
        let targetSize = currentSurfaceContentSize(
            anchorWindow: window,
            updatesHeightCap: model.surfaceMode == .popover
        )
        let targetFrameSize = snappedFrameSize(window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetSize)
        ).size)
        let current = window.frame
        if abs(current.width - targetFrameSize.width) < 0.5
            && abs(current.height - targetFrameSize.height) < 0.5 {
            return nil
        }

        var targetX = current.midX - (targetFrameSize.width / 2)
        if let button = statusItem?.button, let buttonWindow = button.window {
            let buttonRectInWindow = button.convert(button.bounds, to: nil)
            let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
            targetX = buttonRectOnScreen.midX - (targetFrameSize.width / 2)
        }

        var targetFrame = NSRect(
            x: round(targetX),
            y: round(current.maxY - targetFrameSize.height),
            width: targetFrameSize.width,
            height: targetFrameSize.height
        )
        if let screenFrame = window.screen?.visibleFrame {
            targetFrame.origin.x = min(
                max(targetFrame.origin.x, screenFrame.minX + 6),
                max(screenFrame.minX + 6, screenFrame.maxX - targetFrame.width - 6)
            )
        }
        return targetFrame
    }

    private func detachedTargetFrame(for window: NSWindow) -> NSRect? {
        let targetContentSize = currentSurfaceContentSize(
            anchorWindow: window,
            updatesHeightCap: model.surfaceMode == .detached
        )
        let targetFrameSize = snappedFrameSize(window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        ).size)
        let current = window.frame
        if abs(current.width - targetFrameSize.width) < 0.5
            && abs(current.height - targetFrameSize.height) < 0.5 {
            return nil
        }

        let targetFrame = NSRect(
            x: round(current.midX - (targetFrameSize.width / 2)),
            y: round(current.maxY - targetFrameSize.height),
            width: targetFrameSize.width,
            height: targetFrameSize.height
        )
        #if DEBUG
        NSLog(
            "PlayStatus detached: resize from (%.1f,%.1f %.1fx%.1f) to (%.1f,%.1f %.1fx%.1f)",
            current.origin.x, current.origin.y, current.width, current.height,
            targetFrame.origin.x, targetFrame.origin.y, targetFrame.width, targetFrame.height
        )
        #endif
        return clampedDetachedFrame(targetFrame, preferredScreen: window.screen)
    }

    /// Steps whichever surface is on screen to its new mode size. This is the only thing
    /// that moves during a morph; the SwiftUI content has no animation of its own and
    /// simply lays out into the host as it resizes.
    private func beginModeMorphResize() {
        let isDetached = model.surfaceMode == .detached

        let window: NSWindow?
        let targetFrame: NSRect?
        if isDetached {
            let detached = detachedWindow.flatMap { $0.isVisible ? $0 : nil }
            window = detached
            targetFrame = detached.flatMap { detachedTargetFrame(for: $0) }
        } else {
            let popoverWindow = popover.isShown ? popover.contentViewController?.view.window : nil
            window = popoverWindow
            targetFrame = popoverWindow.flatMap { popoverTargetFrame(for: $0) }
        }

        guard let window, let targetFrame else { return }

        // The hosting view does not track the window on its own — sizingOptions is
        // empty, and popover.contentSize is deliberately never touched while shown. On
        // shrink that lag is visible: the SwiftUI content derives its morph progress
        // from the host's width, so the artwork trailed the window and snapped into
        // place at the end. Stepping the host alongside the window keeps the two equal
        // on every tick. Shrink only: the grow direction reads as a reveal with the lag
        // in place, and that behaviour is approved as-is.
        let hostView = isDetached ? detachedHost.view : popoverHost.view
        let stepsHostView = targetFrame.width < window.frame.width

        // Both endpoints are captured up front and every frame is interpolated between
        // them. Nothing reads the live frame back, so per-frame rounding cannot
        // accumulate — that feedback loop used to walk the popover up the screen a
        // little further on every toggle.
        let startFrame = window.frame
        morphDriver.start(
            onFrame: { progress in
                let stepped = NSRect(
                    x: round(startFrame.minX + ((targetFrame.minX - startFrame.minX) * progress)),
                    y: round(startFrame.minY + ((targetFrame.minY - startFrame.minY) * progress)),
                    width: round(startFrame.width + ((targetFrame.width - startFrame.width) * progress)),
                    height: round(startFrame.height + ((targetFrame.height - startFrame.height) * progress))
                )
                window.setFrame(stepped, display: true)
                if stepsHostView {
                    hostView.setFrameSize(window.contentRect(forFrameRect: stepped).size)
                }
            },
            onFinish: { [weak self] in
                window.setFrame(targetFrame, display: true)
                if stepsHostView {
                    hostView.setFrameSize(window.contentRect(forFrameRect: targetFrame).size)
                }
                guard let self else { return }
                let settled = self.currentSurfaceContentSize(
                    anchorWindow: window,
                    updatesHeightCap: true
                )
                if isDetached {
                    self.persistDetachedWindowOrigin(from: targetFrame)
                } else {
                    self.lastAppliedPopoverSize = settled
                }
            }
        )
    }

    private func updatePopoverLayout() {
        let popoverOwnsHeightCap = model.surfaceMode == .popover
        var targetSize = currentSurfaceContentSize(updatesHeightCap: popoverOwnsHeightCap)
        let width = targetSize.width
        let hostView = popoverHost.view
        if !popover.isShown && abs(hostView.frame.width - width) > 0.5 {
            hostView.setFrameSize(NSSize(width: width, height: hostView.frame.height))
        }

        // Use pre-calculated heights for BOTH modes — never call layoutSubtreeIfNeeded().
        //
        // On macOS 26, calling layoutSubtreeIfNeeded() on an NSHostingController view
        // invokes DesignLibrary.AppKitPlatformGlassDefinition (the Liquid Glass compositor).
        // When SwiftUI's own layout is concurrently in-flight (e.g. during the 0.5-second
        // PlaybackClock tick that updates lyrics scroll position), this creates a recursive
        // compositor call chain that exhausts the stack → EXC_BAD_ACCESS on the guard page.
        //
        // Both modes have statically-known heights:
        //   • Regular: artworkDisplaySize + fixed padding + optional lyrics pane height
        //   • Mini:    miniBaseHeight + optional preset-driven miniLyricsPaneHeight
        // Mini mode still resolves to fixed target heights; SwiftUI uses live host height
        // while shown so pane reveal tracks the window animation without a second timeline.
        if !popover.isShown && !sizeApproximatelyEqual(hostView.frame.size, targetSize) {
            hostView.setFrameSize(targetSize)
        }

        // Only rebuild the root view when the popover is not yet shown (initial setup).
        // While shown, keep the existing SwiftUI tree and only adjust the outer window
        // frame to avoid transient intermediate layout states.
        if !popover.isShown, surfaceContentLoaded {
            popoverHost.rootView = AnyView(NowPlayingPopover(model: model))
            applyAppearanceOverride()
        }

        guard popover.isShown else {
            if !sizeApproximatelyEqual(popover.contentSize, targetSize) {
                popover.contentSize = targetSize
            }
            lastAppliedPopoverSize = targetSize
            return
        }

        // A morph owns the window frame for its duration.
        guard !modeMorphInFlight else { return }

        // While shown, always resize via the backing window frame (instead of
        // popover.contentSize) to avoid NSPopover's internal intermediate size
        // transitions that can flash during rapid SwiftUI tree updates.
        if let window = popover.contentViewController?.view.window {
            targetSize = currentSurfaceContentSize(anchorWindow: window, updatesHeightCap: popoverOwnsHeightCap)
            guard let targetFrame = popoverTargetFrame(for: window) else { return }

            let remainingLyricsResizeAnimation = max(0, lyricsResizeAnimationEndTime - CFAbsoluteTimeGetCurrent())
            if pendingLyricsResizeAnimation || remainingLyricsResizeAnimation > 0.001 {
                pendingLyricsResizeAnimation = false
                if remainingLyricsResizeAnimation <= 0.001 {
                    lyricsResizeAnimationEndTime = 0
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = min(
                        miniLyricsTransitionDuration,
                        max(0.08, remainingLyricsResizeAnimation)
                    )
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    context.allowsImplicitAnimation = true
                    window.animator().setFrame(targetFrame, display: true)
                }
            } else {
                window.setFrame(targetFrame, display: true)
            }
            lastAppliedPopoverSize = targetSize
        } else {
            // Fallback path if window is temporarily unavailable.
            if !sizeApproximatelyEqual(popover.contentSize, targetSize) ||
               !sizeApproximatelyEqual(lastAppliedPopoverSize, targetSize) {
                popover.contentSize = targetSize
                lastAppliedPopoverSize = targetSize
            }
        }
    }

    private func updateDetachedWindowLayout() {
        guard let window = detachedWindow else { return }
        let detachedOwnsHeightCap = model.surfaceMode == .detached
        let targetContentSize = currentSurfaceContentSize(anchorWindow: window, updatesHeightCap: detachedOwnsHeightCap)
        let targetFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        ).size

        if !window.isVisible {
            let current = window.frame
            if abs(current.width - targetFrameSize.width) < 0.5 &&
                abs(current.height - targetFrameSize.height) < 0.5 {
                return
            }

            var targetFrame = NSRect(
                x: round(current.midX - (targetFrameSize.width / 2)),
                y: round(current.maxY - targetFrameSize.height),
                width: targetFrameSize.width,
                height: targetFrameSize.height
            )
            targetFrame = clampedDetachedFrame(targetFrame, preferredScreen: window.screen)
            window.setFrame(targetFrame, display: false)
            persistDetachedWindowOrigin(from: targetFrame)
            return
        }

        // A morph owns the window frame for its duration.
        guard !modeMorphInFlight else { return }
        guard let targetFrame = detachedTargetFrame(for: window) else { return }

        let remainingLyricsResizeAnimation = max(0, lyricsResizeAnimationEndTime - CFAbsoluteTimeGetCurrent())
        if pendingLyricsResizeAnimation || remainingLyricsResizeAnimation > 0.001 {
            pendingLyricsResizeAnimation = false
            if remainingLyricsResizeAnimation <= 0.001 {
                lyricsResizeAnimationEndTime = 0
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = min(
                    miniLyricsTransitionDuration,
                    max(0.08, remainingLyricsResizeAnimation)
                )
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
        persistDetachedWindowOrigin(from: targetFrame)
    }

    private func ensureDetachedWindow() -> DetachedNowPlayingWindow {
        if let detachedWindow {
            return detachedWindow
        }

        let targetContentSize = currentSurfaceContentSize()
        let initialFrame = defaultDetachedWindowFrame(for: targetContentSize)
        let window = DetachedNowPlayingWindow(
            contentRect: initialFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.managed]
        window.level = detachedWindowLevel()
        window.isReleasedWhenClosed = false
        window.delegate = self

        detachedHost.rootView = AnyView(NowPlayingPopover(model: model))
        window.contentViewController = detachedContainerController
        detachedWindow = window
        applyAppearanceOverride()
        return window
    }

    private func showDetachedWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }
        ensureSurfaceContentLoaded()
        let window = ensureDetachedWindow()
        updateDetachedWindowLevel()
        applyAppearanceOverride()
        updateDetachedWindowLayout()
        NSApp.activate(ignoringOtherApps: false)
        window.makeKeyAndOrderFront(nil)
        model.isPopoverVisible = true
        syncKeyboardCommands()
    }

    private func hideDetachedWindow() {
        defer { syncKeyboardCommands() }
        guard let window = detachedWindow else {
            model.isPopoverVisible = popover.isShown
            return
        }
        if window.isVisible {
            persistDetachedWindowOrigin(from: window.frame)
            window.orderOut(nil)
        }
        model.isPopoverVisible = popover.isShown
    }

    private func detachedWindowLevel() -> NSWindow.Level {
        model.detachedWindowAlwaysOnTop ? .floating : .normal
    }

    private func updateDetachedWindowLevel() {
        detachedWindow?.level = detachedWindowLevel()
    }

    private func applyAppearanceOverride() {
        let appearance = model.appAppearanceMode.nsAppearance
        popoverHost.view.appearance = appearance
        detachedHost.view.appearance = appearance
        popover.contentViewController?.view.appearance = appearance
        popover.contentViewController?.view.window?.appearance = appearance
        detachedWindow?.appearance = appearance
        detachedWindow?.contentView?.appearance = appearance
        if detachedWindow != nil {
            detachedContainerController.applyAppearance(appearance)
        }
    }

    private func defaultDetachedWindowFrame(for contentSize: NSSize) -> NSRect {
        let frameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .fullSizeContentView]
        ).size

        let origin: CGPoint
        if let stored = savedDetachedWindowOrigin() {
            origin = stored
        } else if let statusOrigin = detachedOriginNearStatusItem(frameSize: frameSize) {
            origin = statusOrigin
        } else if let visible = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame {
            origin = CGPoint(
                x: round(visible.midX - (frameSize.width / 2)),
                y: round(visible.midY - (frameSize.height / 2))
            )
        } else {
            origin = .zero
        }

        let unclamped = NSRect(origin: origin, size: frameSize)
        return clampedDetachedFrame(unclamped, preferredScreen: screenContaining(point: CGPoint(x: unclamped.midX, y: unclamped.midY)))
    }

    private func detachedOriginNearStatusItem(frameSize: NSSize) -> CGPoint? {
        guard let button = statusItem?.button,
              let buttonWindow = button.window else { return nil }
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
        return CGPoint(
            x: round(buttonRectOnScreen.midX - (frameSize.width / 2)),
            y: round(buttonRectOnScreen.minY - frameSize.height - 8)
        )
    }

    private func clampedDetachedFrame(_ frame: NSRect, preferredScreen: NSScreen?) -> NSRect {
        let visibleFrame: NSRect
        if let preferredScreen {
            visibleFrame = preferredScreen.visibleFrame
        } else if let containing = screenContaining(point: CGPoint(x: frame.midX, y: frame.midY)) {
            visibleFrame = containing.visibleFrame
        } else if let main = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame {
            visibleFrame = main
        } else {
            return frame
        }

        var result = frame
        result.origin.x = min(
            max(result.origin.x, visibleFrame.minX + 6),
            max(visibleFrame.minX + 6, visibleFrame.maxX - result.width - 6)
        )
        result.origin.y = min(
            max(result.origin.y, visibleFrame.minY + 6),
            max(visibleFrame.minY + 6, visibleFrame.maxY - result.height - 6)
        )
        result.origin.x = round(result.origin.x)
        result.origin.y = round(result.origin.y)
        return result
    }

    private func screenContaining(point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) })
    }

    private func persistDetachedWindowOrigin() {
        guard let detachedWindow else { return }
        persistDetachedWindowOrigin(from: detachedWindow.frame)
    }

    private func persistDetachedWindowOrigin(from frame: NSRect) {
        UserDefaults.standard.set(frame.origin.x, forKey: detachedWindowOriginXKey)
        UserDefaults.standard.set(frame.origin.y, forKey: detachedWindowOriginYKey)
    }

    private func savedDetachedWindowOrigin() -> CGPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: detachedWindowOriginXKey) != nil,
              defaults.object(forKey: detachedWindowOriginYKey) != nil else {
            return nil
        }
        return CGPoint(
            x: defaults.double(forKey: detachedWindowOriginXKey),
            y: defaults.double(forKey: detachedWindowOriginYKey)
        )
    }

    private func schedulePopoverLayoutUpdate() {
        guard !popoverLayoutUpdateScheduled else { return }
        popoverLayoutUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.popoverLayoutUpdateScheduled = false
            self.updatePopoverLayout()
            self.updateDetachedWindowLayout()
        }
    }

    private func sizeApproximatelyEqual(_ lhs: NSSize, _ rhs: NSSize, tolerance: CGFloat = 0.5) -> Bool {
        abs(lhs.width - rhs.width) < tolerance && abs(lhs.height - rhs.height) < tolerance
    }

    private func currentLyricsPaneExpandedState() -> Bool {
        if model.miniMode {
            return model.miniLyricsEnabled
        }
        return model.showLyricsPanel && model.lyricsPanelExpanded
    }

    private func handleSurfaceVisibilityStateChanged(_ isVisible: Bool) {
        if isVisible {
            ensureSurfaceContentLoaded()
        } else {
            unloadSurfaceContentIfPossible()
        }
    }

    private func ensureSurfaceContentLoaded() {
        guard !surfaceContentLoaded else { return }
        popoverHost.rootView = AnyView(NowPlayingPopover(model: model))
        detachedHost.rootView = AnyView(NowPlayingPopover(model: model))
        applyAppearanceOverride()
        surfaceContentLoaded = true
    }

    private func unloadSurfaceContentIfPossible() {
        guard model.reduceHiddenMemoryUsage else { return }
        guard !popover.isShown, detachedWindow?.isVisible != true else { return }
        guard surfaceContentLoaded else { return }

        popoverHost.rootView = AnyView(EmptyView())
        detachedHost.rootView = AnyView(EmptyView())
        surfaceContentLoaded = false
    }

}

/// Slides the popover's backing window to follow its anchor, one display frame at a time.
///
/// Same constraint as `ModeMorphDriver`: `NSAnimationContext` + `window.animator()` does not
/// animate a popover's window — it snaps in a single frame — so the frame is stepped here.
/// Re-targeting mid-flight is expected (the menu bar can re-flow twice in quick succession),
/// and restarts from wherever the window currently sits rather than queueing a second slide.
@MainActor
final class PopoverAnchorFollowDriver: NSObject {
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var from: CGPoint = .zero
    private var target: CGPoint = .zero
    private weak var window: NSWindow?
    /// Short enough to stay tied to the menu bar re-flow that caused it, long enough to read
    /// as a slide rather than a jump.
    private let duration: CFTimeInterval = 0.22

    var isRunning: Bool { displayLink != nil }

    func animate(_ window: NSWindow, to target: CGPoint) {
        self.window = window
        self.from = window.frame.origin
        self.target = target
        startTime = CACurrentMediaTime()
        guard displayLink == nil else { return }
        guard let link = NSScreen.main?.displayLink(target: self, selector: #selector(tick)) else {
            window.setFrameOrigin(target)
            return
        }
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        window = nil
    }

    @objc private func tick() {
        guard let window else {
            cancel()
            return
        }
        let elapsed = (CACurrentMediaTime() - startTime) / duration
        guard elapsed < 1 else {
            window.setFrameOrigin(target)
            cancel()
            return
        }
        let progress = ModeMorphDriver.ease(elapsed)
        window.setFrameOrigin(
            CGPoint(
                x: from.x + (target.x - from.x) * progress,
                y: from.y + (target.y - from.y) * progress
            )
        )
    }
}
