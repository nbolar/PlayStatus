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
            stopTicker()
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

    private func startTickerIfNeeded() {
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 240.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let tickTimer {
            RunLoop.main.add(tickTimer, forMode: .common)
        }
    }

    private func stopTicker() {
        tickTimer?.invalidate()
        tickTimer = nil
        lastTickTime = 0
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

final class StatusBarController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let popoverHost = NSHostingController(rootView: AnyView(EmptyView()))
    private var cancellables = Set<AnyCancellable>()
    private let model = NowPlayingModel.shared
    private let iconView = PassthroughImageView()
    private let marqueeView = StatusBarMarqueeView()
    private let iconSize: CGFloat = 13
    private var lastStatusLength: CGFloat = -1
    private var lastStatusIconName: String = ""
    private var modeMorphCompletionWorkItem: DispatchWorkItem?
    private let modeMorphDuration: TimeInterval = 0.44
    private var cachedMiniHeight: CGFloat = 380
    private var cachedRegularHeight: CGFloat = 260
    private var hasCachedMiniHeight = true
    private var hasCachedRegularHeight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        popover.delegate = self
        popover.contentViewController = popoverHost
        popoverHost.rootView = AnyView(NowPlayingPopover(model: model))
        model.modeMorphProgress = model.miniMode ? 0 : 1
        model.modeMorphIsActive = false
        model.modeMorphSourceMini = model.miniMode
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
                self?.updateStatusButton()
                // Delay by one runloop pass so SwiftUI commits its layout change
                // (e.g. mini mode toggle) before we measure fittingSize.
                DispatchQueue.main.async {
                    self?.updatePopoverLayout(animated: true)
                }
            }
            .store(in: &cancellables)

        model.$miniModeRevision
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.startModeMorphTransition(toMiniMode: self?.model.miniMode ?? false)
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
            .likeSong: { [weak self] in self?.model.likeCurrentSong() }
        ])
        HotkeyManager.shared.registerAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            model.isPopoverVisible = false
        } else {
            updatePopoverLayout()
            model.isPopoverVisible = true
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                NSApp.activate(ignoringOtherApps: false)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    private func togglePopoverFromHotkey() {
        togglePopover(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        model.isPopoverVisible = false
        modeMorphCompletionWorkItem?.cancel()
        modeMorphCompletionWorkItem = nil
        model.modeMorphIsActive = false
        model.modeMorphProgress = model.miniMode ? 0 : 1
        model.modeMorphSourceMini = model.miniMode
    }

    private func updateStatusButton() {
        guard let statusItem, let button = statusItem.button else { return }

        let iconName = model.statusIcon
        if iconName != lastStatusIconName {
            let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            iconView.image = icon
            lastStatusIconName = iconName
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

    private func updatePopoverLayout(animated: Bool = true, preferMeasuredHeight: Bool = true) {
        guard !model.modeMorphIsActive else { return }
        let targetProgress: CGFloat = model.miniMode ? 0 : 1
        let targetSize = contentSize(for: targetProgress, preferMeasuredHeight: preferMeasuredHeight)
        applyPopoverSize(targetSize, animated: animated)
    }

    private func startModeMorphTransition(toMiniMode miniMode: Bool) {
        let target: CGFloat = miniMode ? 0 : 1
        let current = min(max(model.modeMorphProgress, 0), 1)

        if !popover.isShown {
            modeMorphCompletionWorkItem?.cancel()
            modeMorphCompletionWorkItem = nil
            model.modeMorphIsActive = false
            model.modeMorphProgress = target
            model.modeMorphSourceMini = miniMode
            updatePopoverLayout(animated: false)
            return
        }

        guard abs(current - target) > 0.001 else {
            modeMorphCompletionWorkItem?.cancel()
            modeMorphCompletionWorkItem = nil
            model.modeMorphIsActive = false
            model.modeMorphProgress = target
            model.modeMorphSourceMini = miniMode
            updatePopoverLayout(animated: false)
            return
        }

        modeMorphCompletionWorkItem?.cancel()
        modeMorphCompletionWorkItem = nil

        if let window = popover.contentViewController?.view.window {
            let currentHeight = max(1, window.contentRect(forFrameRect: window.frame).height)
            if target > current {
                cachedMiniHeight = currentHeight
                hasCachedMiniHeight = true
            } else {
                cachedRegularHeight = currentHeight
                hasCachedRegularHeight = true
            }
        }

        model.modeMorphSourceMini = current < 0.5
        model.modeMorphIsActive = true
        withAnimation(.timingCurve(0.22, 0.90, 0.20, 1.0, duration: modeMorphDuration)) {
            model.modeMorphProgress = target
        }

        let targetSize = contentSize(for: target, preferMeasuredHeight: false)
        applyPopoverSize(targetSize, animated: true, duration: modeMorphDuration)

        let completion = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.modeMorphIsActive = false
            self.model.modeMorphProgress = target
            self.model.modeMorphSourceMini = miniMode
            self.updatePopoverLayout(animated: false, preferMeasuredHeight: false)
            DispatchQueue.main.async { [weak self] in
                self?.updatePopoverLayout(animated: false, preferMeasuredHeight: true)
            }
        }
        modeMorphCompletionWorkItem = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + modeMorphDuration + 0.03, execute: completion)
    }

    private func contentSize(for progress: CGFloat, preferMeasuredHeight: Bool) -> NSSize {
        let clampedProgress = min(max(progress, 0), 1)
        let width = model.miniPopoverWidth + ((model.regularPopoverWidth - model.miniPopoverWidth) * clampedProgress)
        let hostView = popoverHost.view
        if abs(hostView.frame.width - width) > 0.5 {
            hostView.setFrameSize(NSSize(width: width, height: hostView.frame.height))
        }

        var measuredHeight: CGFloat?
        if preferMeasuredHeight {
            hostView.layoutSubtreeIfNeeded()
            let fittingHeight = ceil(hostView.fittingSize.height)
            if fittingHeight > 1 {
                measuredHeight = fittingHeight
                if clampedProgress < 0.5 {
                    cachedMiniHeight = fittingHeight
                    hasCachedMiniHeight = true
                } else {
                    cachedRegularHeight = fittingHeight
                    hasCachedRegularHeight = true
                }
            }
        }

        let miniHeight = hasCachedMiniHeight ? cachedMiniHeight : model.miniPopoverHeight
        let regularHeight = hasCachedRegularHeight ? cachedRegularHeight : model.estimatedRegularPopoverHeight
        let fallbackHeight = miniHeight + ((regularHeight - miniHeight) * clampedProgress)
        let height = measuredHeight ?? fallbackHeight
        return NSSize(width: width, height: max(1, ceil(height)))
    }

    private func applyPopoverSize(_ targetSize: NSSize, animated: Bool, duration: TimeInterval = 0.32) {
        guard popover.isShown else {
            if popover.contentSize != targetSize {
                popover.contentSize = targetSize
            }
            return
        }

        guard let window = popover.contentViewController?.view.window else { return }
        let targetFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetSize)).size

        let current = window.frame
        if abs(current.width - targetFrameSize.width) < 0.5 && abs(current.height - targetFrameSize.height) < 0.5 {
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

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.90, 0.20, 1.0)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
    }

}
