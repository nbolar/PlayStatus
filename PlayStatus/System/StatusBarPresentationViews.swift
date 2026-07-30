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
    private let staticTextLabel = NSTextField(labelWithString: "")

    private let font = NSFont.systemFont(ofSize: 13, weight: .regular)
    private let gap: CGFloat = 36
    private let speed: CGFloat = 26
    private let textHeight: CGFloat = 16
    private let leadInDelay: CFTimeInterval = 0.65
    private let scrollAnimationKey = "playstatus.statusbar.scroll"
    private let titleChangeAnimationKey = "playstatus.statusbar.title-change"

    private var currentSignature: String = ""
    private var resolvedText: String = "Not Playing"
    /// Character range of the qualifying half of the title (the artist, plus its
    /// separator), drawn at reduced alpha. Empty when the title is a single part.
    private var secondaryRange: NSRange?
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

        configureStaticTextLabel()
        addSubview(staticTextLabel)
        staticTextLabel.isHidden = true
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

    func update(
        text: String,
        secondarySuffix: String? = nil,
        enabled: Bool,
        laneWidth: CGFloat,
        slideOnChange: Bool
    ) {
        let text = text.isEmpty ? "Not Playing" : text
        let width = floor(max(80, laneWidth))
        let signature = "\(text)|\(secondarySuffix ?? "")|\(enabled)|\(Int(width.rounded()))|\(slideOnChange ? 1 : 0)"
        if signature == currentSignature { return }
        currentSignature = signature

        let previousText = resolvedText
        resolvedText = text
        if let secondarySuffix, !secondarySuffix.isEmpty, text.hasSuffix(secondarySuffix) {
            secondaryRange = NSRange(
                location: (text as NSString).length - (secondarySuffix as NSString).length,
                length: (secondarySuffix as NSString).length
            )
        } else {
            secondaryRange = nil
        }
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
        primaryTextLayer.isHidden = true
        secondaryTextLayer.isHidden = true
        staticTextLabel.isHidden = true
        updateLayerFrames()
    }

    private func configureTextLayer(_ textLayer: CATextLayer) {
        textLayer.alignmentMode = .left
        textLayer.isWrapped = false
        textLayer.truncationMode = .end
        textLayer.foregroundColor = resolvedTextColor().cgColor
    }

    private func configureStaticTextLabel() {
        staticTextLabel.font = font
        staticTextLabel.isBezeled = false
        staticTextLabel.isEditable = false
        staticTextLabel.isSelectable = false
        staticTextLabel.drawsBackground = false
        staticTextLabel.usesSingleLineMode = true
        staticTextLabel.maximumNumberOfLines = 1
        staticTextLabel.alignment = .left
        staticTextLabel.lineBreakMode = .byTruncatingTail
        staticTextLabel.cell?.truncatesLastVisibleLine = true
        staticTextLabel.wantsLayer = true
    }

    private func applyText(animateTransition: Bool) {
        let textColor = resolvedTextColor()
        let attributed = attributedTitle(textColor: textColor)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryTextLayer.foregroundColor = textColor.cgColor
        secondaryTextLayer.foregroundColor = textColor.cgColor
        primaryTextLayer.isHidden = !shouldScroll
        primaryTextLayer.string = attributed
        secondaryTextLayer.string = attributed
        CATransaction.commit()

        staticTextLabel.attributedStringValue = attributed
        staticTextLabel.textColor = textColor
        staticTextLabel.isHidden = shouldScroll

        if animateTransition {
            let transition = CATransition()
            transition.duration = 0.20
            transition.type = .fade
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            let animatedLayer = shouldScroll ? contentLayer : staticTextLabel.layer
            animatedLayer?.add(transition, forKey: titleChangeAnimationKey)
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
            staticTextLabel.frame = .zero
        } else {
            contentLayer.frame = CGRect(x: 0, y: y, width: laneWidth, height: textHeight)
            primaryTextLayer.frame = .zero
            secondaryTextLayer.frame = .zero
            secondaryTextLayer.isHidden = true
            staticTextLabel.frame = CGRect(x: 0, y: y, width: laneWidth, height: textHeight)
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

    private func textAttributes(textColor: NSColor) -> [NSAttributedString.Key: Any] {
        return [
            .font: font,
            .foregroundColor: textColor
        ]
    }

    /// The title, with its qualifying half dimmed. Attributed rather than two labels so the
    /// marquee still measures, scrolls, and truncates one string.
    private func attributedTitle(textColor: NSColor) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: resolvedText,
            attributes: textAttributes(textColor: textColor)
        )

        if let secondaryRange,
           secondaryRange.location >= 0,
           NSMaxRange(secondaryRange) <= attributed.length {
            attributed.addAttribute(
                .foregroundColor,
                value: textColor.withAlphaComponent(textColor.alphaComponent),
                range: secondaryRange
            )
        }

        return attributed
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

/// Hosts the player in the detached window, and nothing else.
///
/// This used to stack three grounds inside one window: an `NSVisualEffectView(.popover)`,
/// then a hardcoded `white 0.08 / alpha 0.28` wash over it, and then the player's own full
/// surface on top of both — with the player dimmed to 80% to compensate for what was
/// underneath it. That is the same "two cards in nearly the same colour" problem the popover
/// had, one level up. The player surface is the window's background now; the window supplies
/// the shadow and the corner mask.
final class DetachedNowPlayingContainerController: NSViewController {
    private let hostController: NSHostingController<AnyView>
    private let cornerRadius: CGFloat

    init(hostController: NSHostingController<AnyView>, cornerRadius: CGFloat = 18) {
        self.hostController = hostController
        self.cornerRadius = cornerRadius
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func applyAppearance(_ appearance: NSAppearance?) {
        guard isViewLoaded else { return }
        view.appearance = appearance
        hostController.view.appearance = appearance
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = cornerRadius
        root.layer?.masksToBounds = true
        // The window is transparent so its corners can be rounded, and the player surface
        // and lyrics pane are both translucent glass by design — so without an opaque base
        // here the desktop shows through the whole player. This is the window's background,
        // not a decorative layer: one flat colour, the same one the surface is built on.
        root.layer?.backgroundColor = playerSurfaceGroundNSColor.cgColor
        view = root

        addChild(hostController)
        let hostView = hostController.view
        hostView.translatesAutoresizingMaskIntoConstraints = false
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = NSColor.clear.cgColor
        root.addSubview(hostView)

        NSLayoutConstraint.activate([
            hostView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            hostView.topAnchor.constraint(equalTo: root.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        root.appearance = hostController.view.appearance
    }
}
