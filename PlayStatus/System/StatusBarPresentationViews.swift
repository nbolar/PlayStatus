import SwiftUI
import AppKit

final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class StatusBarMarqueeView: NSView {
    private let contentLayer = CALayer()
    private let primaryTextLayer = CATextLayer()
    private let secondaryTextLayer = CATextLayer()

    private let font = NSFont.systemFont(ofSize: 13, weight: .regular)
    private let gap: CGFloat = 36
    private let speed: CGFloat = 26
    private let textHeight: CGFloat = 16
    private let leadInDelay: CFTimeInterval = 0.65
    private let scrollAnimationKey = "playstatus.statusbar.scroll"
    private let titleChangeAnimationKey = "playstatus.statusbar.title-change"

    private var currentSignature: String = ""
    private var resolvedText: String = "Not Playing"
    private var laneWidth: CGFloat = 120
    private var textWidth: CGFloat = 0
    private var shouldScroll = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = true

        contentLayer.masksToBounds = false
        layer?.addSublayer(contentLayer)

        configureTextLayer(primaryTextLayer)
        configureTextLayer(secondaryTextLayer)
        contentLayer.addSublayer(primaryTextLayer)
        contentLayer.addSublayer(secondaryTextLayer)
        secondaryTextLayer.isHidden = true
        updateContentsScale()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
        refreshTextAppearance()
        if window == nil {
            suspendScrolling()
        } else {
            restartScrollingIfNeeded(resetPhase: false)
        }
    }

    override func layout() {
        super.layout()
        updateLayerFrames()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshTextAppearance()
    }

    func update(text: String, enabled: Bool, laneWidth: CGFloat, slideOnChange: Bool) {
        let text = text.isEmpty ? "Not Playing" : text
        let width = floor(max(80, laneWidth))
        let signature = "\(text)|\(enabled)|\(Int(width.rounded()))|\(slideOnChange ? 1 : 0)"
        if signature == currentSignature { return }
        currentSignature = signature

        let previousText = resolvedText
        resolvedText = text
        self.laneWidth = width
        textWidth = measuredTextWidth(text, font: font)
        shouldScroll = enabled && textWidth > width + 1

        applyText(animateTransition: slideOnChange && previousText != text && window != nil)
        updateLayerFrames()
        restartScrollingIfNeeded(resetPhase: true)
    }

    func suspendScrolling() {
        stopScrolling(resetTransform: true)
        currentSignature = ""
        shouldScroll = false
        contentLayer.frame = CGRect(x: 0, y: floor((bounds.height - textHeight) / 2), width: laneWidth, height: textHeight)
        secondaryTextLayer.isHidden = true
        updateLayerFrames()
    }

    private func configureTextLayer(_ textLayer: CATextLayer) {
        textLayer.alignmentMode = .left
        textLayer.isWrapped = false
        textLayer.truncationMode = .end
        textLayer.foregroundColor = resolvedTextColor().cgColor
    }

    private func applyText(animateTransition: Bool) {
        let textColor = resolvedTextColor()
        let primaryAttributes = textAttributes(truncates: !shouldScroll, textColor: textColor)
        let scrollingAttributes = textAttributes(truncates: false, textColor: textColor)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryTextLayer.foregroundColor = textColor.cgColor
        secondaryTextLayer.foregroundColor = textColor.cgColor
        primaryTextLayer.string = NSAttributedString(
            string: resolvedText,
            attributes: shouldScroll ? scrollingAttributes : primaryAttributes
        )
        secondaryTextLayer.string = NSAttributedString(
            string: resolvedText,
            attributes: scrollingAttributes
        )
        CATransaction.commit()

        if animateTransition {
            let transition = CATransition()
            transition.duration = 0.20
            transition.type = .fade
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            contentLayer.add(transition, forKey: titleChangeAnimationKey)
        }
    }

    private func refreshTextAppearance() {
        guard !resolvedText.isEmpty else { return }
        applyText(animateTransition: false)
    }

    private func updateLayerFrames() {
        let y = floor((bounds.height - textHeight) / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if shouldScroll {
            let cycle = max(1, textWidth + gap)
            contentLayer.frame = CGRect(x: 0, y: y, width: cycle * 2, height: textHeight)
            primaryTextLayer.frame = CGRect(x: 0, y: 0, width: textWidth + 2, height: textHeight)
            secondaryTextLayer.frame = CGRect(x: cycle, y: 0, width: textWidth + 2, height: textHeight)
            secondaryTextLayer.isHidden = false
        } else {
            contentLayer.frame = CGRect(x: 0, y: y, width: laneWidth, height: textHeight)
            primaryTextLayer.frame = CGRect(x: 0, y: 0, width: laneWidth, height: textHeight)
            secondaryTextLayer.frame = .zero
            secondaryTextLayer.isHidden = true
        }
        CATransaction.commit()
    }

    private func restartScrollingIfNeeded(resetPhase: Bool) {
        guard shouldScroll, window != nil else {
            stopScrolling(resetTransform: true)
            return
        }

        if !resetPhase, contentLayer.animation(forKey: scrollAnimationKey) != nil {
            return
        }

        stopScrolling(resetTransform: true)

        let cycle = max(1, textWidth + gap)
        let duration = max(8.0, CFTimeInterval(cycle / speed))
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -cycle
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        animation.beginTime = CACurrentMediaTime() + (resetPhase ? leadInDelay : 0.05)
        contentLayer.add(animation, forKey: scrollAnimationKey)
    }

    private func stopScrolling(resetTransform: Bool) {
        contentLayer.removeAnimation(forKey: scrollAnimationKey)
        if resetTransform {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            contentLayer.transform = CATransform3DIdentity
            CATransaction.commit()
        }
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        contentLayer.contentsScale = scale
        primaryTextLayer.contentsScale = scale
        secondaryTextLayer.contentsScale = scale
    }

    private func textAttributes(truncates: Bool, textColor: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = truncates ? .byTruncatingTail : .byClipping
        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
    }

    private func resolvedTextColor() -> NSColor {
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        if #available(macOS 11.0, *) {
            var resolvedColor: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                resolvedColor = NSColor(cgColor: NSColor.labelColor.cgColor)
            }
            if let resolvedColor {
                return resolvedColor
            }
        }
        return fallbackTextColor(for: appearance)
    }

    private func fallbackTextColor(for appearance: NSAppearance) -> NSColor {
        switch appearance.bestMatch(from: [.vibrantDark, .darkAqua, .vibrantLight, .aqua]) {
        case .some(.vibrantDark), .some(.darkAqua):
            return NSColor(calibratedWhite: 1.0, alpha: 0.94)
        default:
            return NSColor(calibratedWhite: 0.08, alpha: 0.92)
        }
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
