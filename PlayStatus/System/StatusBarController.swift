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

    private let font = NSFont.systemFont(ofSize: 13, weight: .regular)
    private let gap: CGFloat = 18
    private let speed: CGFloat = 24 // px/s

    private var currentSignature: String = ""
    private var resolvedText: String = "Not Playing"
    private var laneWidth: CGFloat = 120
    private var textWidth: CGFloat = 0
    private var shouldScroll = false
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
        addSubview(primaryLabel)
        addSubview(secondaryLabel)
        secondaryLabel.isHidden = true
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
        } else if shouldScroll {
            startTickerIfNeeded()
        }
    }

    override func layout() {
        super.layout()
        applyLayout()
    }

    func update(text: String, enabled: Bool, laneWidth: CGFloat) {
        let text = text.isEmpty ? "Not Playing" : text
        let width = floor(max(80, laneWidth))
        let signature = "\(text)|\(enabled)|\(Int(width.rounded()))"
        if signature == currentSignature { return }
        currentSignature = signature

        resolvedText = text
        self.laneWidth = width
        textWidth = measuredTextWidth(text, font: font)
        shouldScroll = enabled && textWidth > width + 1

        primaryLabel.stringValue = text
        secondaryLabel.stringValue = text
        xOffset = 0
        lastTickTime = 0

        if shouldScroll {
            primaryLabel.lineBreakMode = .byClipping
            secondaryLabel.lineBreakMode = .byClipping
            secondaryLabel.isHidden = false
            startTickerIfNeeded()
        } else {
            primaryLabel.lineBreakMode = .byTruncatingTail
            secondaryLabel.isHidden = true
            stopTicker()
        }

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
        }
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
                self?.updatePopoverLayout()
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
        marqueeView.update(text: model.menuBarTitle, enabled: model.scrollableTitle, laneWidth: laneWidth)
    }

    private func updatePopoverLayout() {
        let width = model.popoverWidth
        popoverHost.rootView = AnyView(NowPlayingPopover(model: model).frame(width: width))
        popoverHost.view.layoutSubtreeIfNeeded()
        let fittingHeight = ceil(popoverHost.view.fittingSize.height)
        let targetSize = NSSize(width: width, height: max(1, fittingHeight))

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

        NSAnimationContext.runAnimationGroup { context in
            if model.miniMode {
                // Collapsing → mini: easeOut starts fast to match the spring's
                // initial velocity, finishing just before SwiftUI settles (~0.55s).
                context.duration = 0.44
            } else {
                // Expanding → regular: same easeOut feel, slightly snappier.
                context.duration = 0.40
            }
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(targetFrame, display: true)
        }
    }
}
