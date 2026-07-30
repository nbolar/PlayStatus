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
    private let iconSize: CGFloat = 13
    private let statusIconLeadingInset: CGFloat = 4
    private let statusIconTextSpacing: CGFloat = 5
    private let statusTextTrailingInset: CGFloat = 4
    private var lastStatusLength: CGFloat = -1
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
                .sink { [weak self] _ in self?.updateStatusButton() }
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

    func applicationWillTerminate(_ notification: Notification) {
        persistDetachedWindowOrigin()
        HotkeyManager.shared.unregisterAll()
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

        if !showMenuBarText {
            if abs(lastStatusLength - 22) > 0.1 {
                statusItem.length = 22
                lastStatusLength = 22
            }
            let iconY = floor((button.bounds.height - iconSize) / 2)
            let iconX = floor((button.bounds.width - iconSize) / 2)
            iconView.frame = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
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

        // The icon and marquee are custom button subviews, so their complete
        // horizontal layout must fit inside the status item. Reserving only the
        // text lane clips long titles as soon as they reach the configured width.
        let desiredLength = statusIconLeadingInset
            + iconSize
            + statusIconTextSpacing
            + effectiveLaneWidth
            + statusTextTrailingInset
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
    private func popoverTargetFrame(for window: NSWindow) -> NSRect? {
        let targetSize = currentSurfaceContentSize(
            anchorWindow: window,
            updatesHeightCap: model.surfaceMode == .popover
        )
        let targetFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetSize)
        ).size
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
        let targetFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        ).size
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
