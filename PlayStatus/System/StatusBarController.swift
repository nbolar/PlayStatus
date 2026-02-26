import SwiftUI
import AppKit
import Combine

final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class StatusBarMarqueeView: NSView {
    private let primaryLabel = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let transitionLabel = NSTextField(labelWithString: "")

    private let font = NSFont.systemFont(ofSize: 13, weight: .regular)
    private let gap: CGFloat = 18
    private let speed: CGFloat = 24 // px/s

    private var currentSignature: String = ""
    private var resolvedText: String = "Not Playing"
    private var laneWidth: CGFloat = 120
    private var textWidth: CGFloat = 0
    private var shouldScroll = false
    private var isTransitioning = false
    private var xOffset: CGFloat = 0
    private var tickTimer: Timer?
    private var lastTickTime: CFTimeInterval = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = true

        configureLabel(primaryLabel)
        configureLabel(secondaryLabel)
        configureLabel(transitionLabel)
        addSubview(primaryLabel)
        addSubview(secondaryLabel)
        addSubview(transitionLabel)
        secondaryLabel.isHidden = true
        transitionLabel.isHidden = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            suspendScrolling()
        } else if shouldScroll && !isTransitioning {
            startTickerIfNeeded()
        }
    }

    override func layout() {
        super.layout()
        applyLayout()
    }

    func update(text: String, enabled: Bool, laneWidth: CGFloat, slideOnChange: Bool) {
        let text = text.isEmpty ? "Not Playing" : text
        let width = floor(max(80, laneWidth))
        let signature = "\(text)|\(enabled)|\(Int(width.rounded()))|\(slideOnChange ? 1 : 0)"
        if signature == currentSignature { return }
        currentSignature = signature

        let previousText = resolvedText
        let previousShouldScroll = shouldScroll
        resolvedText = text
        self.laneWidth = width
        textWidth = measuredTextWidth(text, font: font)
        shouldScroll = enabled && textWidth > width + 1

        primaryLabel.stringValue = text
        secondaryLabel.stringValue = text
        xOffset = 0
        lastTickTime = 0

        primaryLabel.lineBreakMode = shouldScroll ? .byClipping : .byTruncatingTail
        secondaryLabel.lineBreakMode = .byClipping

        let shouldAnimateTitleSwap =
            slideOnChange &&
            previousText != text &&
            window != nil

        if shouldAnimateTitleSwap {
            let useSlideMotion = !(previousShouldScroll || shouldScroll)
            animateTitleSwap(
                from: previousText,
                to: text,
                newShouldScroll: shouldScroll,
                useSlideMotion: useSlideMotion
            )
            return
        }

        if shouldScroll {
            secondaryLabel.isHidden = false
            transitionLabel.isHidden = true
            transitionLabel.alphaValue = 1
            startTickerIfNeeded()
        } else {
            secondaryLabel.isHidden = true
            stopTicker()
        }

        isTransitioning = false
        transitionLabel.isHidden = true
        transitionLabel.alphaValue = 1
        applyLayout()
    }

    private func configureLabel(_ label: NSTextField) {
        label.font = font
        label.textColor = .labelColor
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.usesSingleLineMode = true
        label.maximumNumberOfLines = 1
        label.alignment = .left
        label.cell?.lineBreakMode = .byClipping
        label.cell?.truncatesLastVisibleLine = true
    }

    private func applyLayout() {
        guard !isTransitioning else { return }
        let h = bounds.height
        let y = floor((h - 16) / 2)
        if shouldScroll {
            let cycle = max(1, textWidth + gap)
            let firstX = -xOffset
            primaryLabel.frame = CGRect(x: firstX, y: y, width: textWidth + 2, height: 16)
            secondaryLabel.frame = CGRect(x: firstX + cycle, y: y, width: textWidth + 2, height: 16)
            secondaryLabel.isHidden = false
        } else {
            primaryLabel.frame = CGRect(x: 0, y: y, width: laneWidth, height: 16)
            secondaryLabel.frame = .zero
            secondaryLabel.isHidden = true
            if transitionLabel.isHidden {
                transitionLabel.frame = CGRect(x: 0, y: y, width: laneWidth, height: 16)
            }
        }
    }

    private func animateTitleSwap(from oldTitle: String, to newTitle: String, newShouldScroll: Bool, useSlideMotion: Bool) {
        let h = bounds.height
        let y = floor((h - 16) / 2)
        let animationOffset: CGFloat = useSlideMotion ? 12 : 0
        let cycle = max(1, textWidth + gap)

        stopTicker()

        transitionLabel.stringValue = oldTitle
        transitionLabel.frame = CGRect(x: 0, y: y, width: laneWidth, height: 16)
        transitionLabel.alphaValue = 1
        transitionLabel.isHidden = false
        isTransitioning = true

        primaryLabel.stringValue = newTitle
        secondaryLabel.stringValue = newTitle
        secondaryLabel.isHidden = true
        secondaryLabel.alphaValue = 1

        if !useSlideMotion {
            let targetPrimaryWidth = newShouldScroll ? (textWidth + 2) : laneWidth
            primaryLabel.frame = CGRect(x: 0, y: y, width: targetPrimaryWidth, height: 16)
            primaryLabel.alphaValue = 0
            if newShouldScroll {
                secondaryLabel.frame = CGRect(x: cycle, y: y, width: textWidth + 2, height: 16)
            } else {
                secondaryLabel.frame = .zero
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                transitionLabel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard let self else { return }
                self.transitionLabel.isHidden = true
                self.transitionLabel.alphaValue = 1

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.26
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    context.allowsImplicitAnimation = true
                    self.primaryLabel.animator().alphaValue = 1
                } completionHandler: { [weak self] in
                    guard let self else { return }
                    self.finishTitleSwap(newShouldScroll: newShouldScroll)
                }
            }
            return
        }

        if newShouldScroll {
            primaryLabel.frame = CGRect(x: animationOffset, y: y, width: textWidth + 2, height: 16)
            secondaryLabel.frame = CGRect(x: cycle, y: y, width: textWidth + 2, height: 16)
        } else {
            primaryLabel.frame = CGRect(x: animationOffset, y: y, width: laneWidth, height: 16)
            secondaryLabel.frame = .zero
        }
        primaryLabel.alphaValue = 0

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            transitionLabel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.transitionLabel.isHidden = true
            self.transitionLabel.alphaValue = 1

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.40
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                let targetPrimaryWidth = newShouldScroll ? (self.textWidth + 2) : self.laneWidth
                self.primaryLabel.animator().frame = CGRect(x: 0, y: y, width: targetPrimaryWidth, height: 16)
                self.primaryLabel.animator().alphaValue = 1
            } completionHandler: { [weak self] in
                guard let self else { return }
                self.finishTitleSwap(newShouldScroll: newShouldScroll)
            }
        }
    }

    private func finishTitleSwap(newShouldScroll: Bool) {
        isTransitioning = false
        transitionLabel.isHidden = true
        transitionLabel.alphaValue = 1
        primaryLabel.alphaValue = 1
        if newShouldScroll {
            secondaryLabel.isHidden = false
            secondaryLabel.alphaValue = 1
            startTickerIfNeeded()
        } else {
            secondaryLabel.isHidden = true
            secondaryLabel.alphaValue = 1
            stopTicker()
        }
        applyLayout()
    }

    func suspendScrolling() {
        stopTicker()
        isTransitioning = false
        shouldScroll = false
        currentSignature = ""
        xOffset = 0
        transitionLabel.isHidden = true
        transitionLabel.alphaValue = 1
        secondaryLabel.isHidden = true
        secondaryLabel.alphaValue = 1
        primaryLabel.alphaValue = 1
        applyLayout()
        #if DEBUG
        NSLog("PlayStatus marquee ticker: suspended")
        #endif
    }

    private func startTickerIfNeeded() {
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 240.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let tickTimer {
            RunLoop.main.add(tickTimer, forMode: .common)
        }
        #if DEBUG
        NSLog("PlayStatus marquee ticker: started")
        #endif
    }

    private func stopTicker() {
        let hadTimer = tickTimer != nil
        tickTimer?.invalidate()
        tickTimer = nil
        lastTickTime = 0
        #if DEBUG
        if hadTimer {
            NSLog("PlayStatus marquee ticker: stopped")
        }
        #endif
    }

    private func tick() {
        guard shouldScroll else { return }
        let now = CACurrentMediaTime()
        if lastTickTime == 0 {
            lastTickTime = now
            return
        }
        let dt = min(0.05, now - lastTickTime)
        lastTickTime = now

        xOffset += CGFloat(dt) * speed
        let cycle = max(1, textWidth + gap)
        while xOffset >= cycle {
            xOffset -= cycle
        }
        applyLayout()
    }
}

final class DetachedNowPlayingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class DetachedNowPlayingContainerController: NSViewController {
    private let hostController: NSHostingController<AnyView>
    private let materialView = NSVisualEffectView()
    private let neutralWashView = NSView()
    private let cornerRadius: CGFloat

    init(hostController: NSHostingController<AnyView>, cornerRadius: CGFloat = 18) {
        self.hostController = hostController
        self.cornerRadius = cornerRadius
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = cornerRadius
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        view = root

        materialView.translatesAutoresizingMaskIntoConstraints = false
        materialView.material = .popover
        materialView.blendingMode = .withinWindow
        materialView.state = .active

        neutralWashView.translatesAutoresizingMaskIntoConstraints = false
        neutralWashView.wantsLayer = true
        neutralWashView.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.28).cgColor

        root.addSubview(materialView)
        materialView.addSubview(neutralWashView)

        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            materialView.topAnchor.constraint(equalTo: root.topAnchor),
            materialView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            neutralWashView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            neutralWashView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            neutralWashView.topAnchor.constraint(equalTo: materialView.topAnchor),
            neutralWashView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor)
        ])

        addChild(hostController)
        let hostView = hostController.view
        hostView.translatesAutoresizingMaskIntoConstraints = false
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = NSColor.clear.cgColor
        materialView.addSubview(hostView)

        NSLayoutConstraint.activate([
            hostView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            hostView.topAnchor.constraint(equalTo: materialView.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor)
        ])
    }
}

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
    private var lastStatusLength: CGFloat = -1
    private var lastStatusIcon: ProviderIconKind?
    private var lastAppliedPopoverSize: NSSize = .zero
    private var pendingModeResizeAnimation = false
    private var pendingLyricsResizeAnimation = false
    private var lastMiniModeValue: Bool = false
    private var lastLyricsPaneExpandedValue: Bool = false
    private var lyricsResizeAnimationEndTime: CFAbsoluteTime = 0
    private var lastAppliedDetachedSize: NSSize = .zero
    private var popoverLayoutUpdateScheduled = false
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
                    self.pendingModeResizeAnimation = true
                    self.pendingLyricsResizeAnimation = false
                    self.lyricsResizeAnimationEndTime = 0
                    self.lastMiniModeValue = currentMiniMode
                    self.lastLyricsPaneExpandedValue = self.currentLyricsPaneExpandedState()
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
        hideDetachedWindow()
        updatePopoverLayout()
        model.isPopoverVisible = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: false)
            popover.contentViewController?.view.window?.makeKey()
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
        lastAppliedDetachedSize = .zero
        detachedWindow = nil
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
            return
        }

        let configuredLaneWidth = model.statusTextWidth
        let actualTextWidth = measuredTextWidth(
            model.menuBarTitle,
            font: .systemFont(ofSize: 13, weight: .regular)
        )
        let effectiveLaneWidth = floor(min(configuredLaneWidth, max(24, actualTextWidth + 2)))

        let desiredLength = effectiveLaneWidth + 8
        if abs(lastStatusLength - desiredLength) > 0.1 {
            statusItem.length = desiredLength
            lastStatusLength = desiredLength
        }
        let iconY = floor((button.bounds.height - iconSize) / 2)
        iconView.frame = CGRect(x: 4, y: iconY, width: iconSize, height: iconSize)
        marqueeView.isHidden = false

        let laneWidth = effectiveLaneWidth
        let laneHeight: CGFloat = 16
        let x = floor(iconView.frame.maxX + 5)
        let y = floor((button.bounds.height - laneHeight) / 2)
        let targetFrame = CGRect(x: x, y: y, width: laneWidth, height: laneHeight)
        if !marqueeView.frame.equalTo(targetFrame) {
            marqueeView.frame = targetFrame
        }
        marqueeView.update(
            text: model.menuBarTitle,
            enabled: model.scrollableTitle,
            laneWidth: laneWidth,
            slideOnChange: model.slideTitleOnChange
        )
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

    private func currentSurfaceContentSize() -> NSSize {
        let resolvedContentHeight: CGFloat = model.miniMode
            ? model.miniPopoverHeight
            : model.regularPopoverHeight
        return NSSize(width: model.popoverWidth, height: resolvedContentHeight)
    }

    private func updatePopoverLayout() {
        let targetSize = currentSurfaceContentSize()
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
        //   • Mini:    miniBaseHeight (380 pt) + optional miniLyricsPaneHeight (180 pt)
        // Mini mode still resolves to fixed target heights; SwiftUI uses live host height
        // while shown so pane reveal tracks the window animation without a second timeline.
        if !popover.isShown && !sizeApproximatelyEqual(hostView.frame.size, targetSize) {
            hostView.setFrameSize(targetSize)
        }

        // Only rebuild the root view when the popover is not yet shown (initial setup).
        // While shown, keep the existing SwiftUI tree and only adjust the outer window
        // frame to avoid transient intermediate layout states.
        if !popover.isShown {
            popoverHost.rootView = AnyView(NowPlayingPopover(model: model))
        }

        guard popover.isShown else {
            if !sizeApproximatelyEqual(popover.contentSize, targetSize) {
                popover.contentSize = targetSize
            }
            lastAppliedPopoverSize = targetSize
            return
        }

        // While shown, always resize via the backing window frame (instead of
        // popover.contentSize) to avoid NSPopover's internal intermediate size
        // transitions that can flash during rapid SwiftUI tree updates.
        if let window = popover.contentViewController?.view.window {
            let targetFrameSize = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: targetSize)
            ).size
            let current = window.frame
            if abs(current.width - targetFrameSize.width) < 0.5
                && abs(current.height - targetFrameSize.height) < 0.5 {
                return
            }

            let currentTop = current.maxY
            var targetX = current.midX - (targetFrameSize.width / 2)
            if let button = statusItem?.button, let buttonWindow = button.window {
                let buttonRectInWindow = button.convert(button.bounds, to: nil)
                let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
                targetX = buttonRectOnScreen.midX - (targetFrameSize.width / 2)
            }

            var targetFrame = NSRect(
                x: round(targetX),
                y: round(currentTop - targetFrameSize.height),
                width: targetFrameSize.width,
                height: targetFrameSize.height
            )
            if let screenFrame = window.screen?.visibleFrame {
                targetFrame.origin.x = min(
                    max(targetFrame.origin.x, screenFrame.minX + 6),
                    max(screenFrame.minX + 6, screenFrame.maxX - targetFrame.width - 6)
                )
            }

            let remainingLyricsResizeAnimation = max(0, lyricsResizeAnimationEndTime - CFAbsoluteTimeGetCurrent())
            if pendingModeResizeAnimation {
                pendingModeResizeAnimation = false
                pendingLyricsResizeAnimation = false
                lyricsResizeAnimationEndTime = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = modeTransitionDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    context.allowsImplicitAnimation = true
                    window.animator().setFrame(targetFrame, display: true)
                }
            } else if pendingLyricsResizeAnimation || remainingLyricsResizeAnimation > 0.001 {
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
        let targetContentSize = currentSurfaceContentSize()
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
            lastAppliedDetachedSize = targetContentSize
            return
        }

        let current = window.frame
        if abs(current.width - targetFrameSize.width) < 0.5
            && abs(current.height - targetFrameSize.height) < 0.5 {
            return
        }

        var targetFrame = NSRect(
            x: round(current.midX - (targetFrameSize.width / 2)),
            y: round(current.maxY - targetFrameSize.height),
            width: targetFrameSize.width,
            height: targetFrameSize.height
        )
        targetFrame = clampedDetachedFrame(targetFrame, preferredScreen: window.screen)

        let remainingLyricsResizeAnimation = max(0, lyricsResizeAnimationEndTime - CFAbsoluteTimeGetCurrent())
        if pendingModeResizeAnimation {
            pendingModeResizeAnimation = false
            pendingLyricsResizeAnimation = false
            lyricsResizeAnimationEndTime = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = modeTransitionDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(targetFrame, display: true)
            }
        } else if pendingLyricsResizeAnimation || remainingLyricsResizeAnimation > 0.001 {
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
        lastAppliedDetachedSize = targetContentSize
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
        lastAppliedDetachedSize = targetContentSize
        return window
    }

    private func showDetachedWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }
        let window = ensureDetachedWindow()
        updateDetachedWindowLevel()
        updateDetachedWindowLayout()
        NSApp.activate(ignoringOtherApps: false)
        window.makeKeyAndOrderFront(nil)
        model.isPopoverVisible = true
    }

    private func hideDetachedWindow() {
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

}
