import SwiftUI
import AppKit

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
    private let speed: CGFloat = 24

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
        nil
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
        let height = bounds.height
        let y = floor((height - 16) / 2)
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
        let height = bounds.height
        let y = floor((height - 16) / 2)
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
        let delta = min(0.05, now - lastTickTime)
        lastTickTime = now

        xOffset += CGFloat(delta) * speed
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

final class DetachedNowPlayingContainerController: NSViewController {
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
        nil
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
