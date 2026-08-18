import AppKit

/// The optional previous / play-pause / next buttons that sit next to the title in the
/// menu bar.
///
/// These live as subviews of the `NSStatusBarButton` rather than in their own status
/// items: one item keeps the group glued together (separate items can be reordered
/// apart by the user) and lets the whole strip share a single width calculation.
///
/// The glyphs are `PassthroughImageView`s and the clicks are tracked by hand instead of
/// by three `NSButton`s. An `NSButton` resolves `contentTintColor` against its own
/// appearance, which is Aqua even when the menu bar is drawn dark over a bright
/// wallpaper — the arrows came out black next to a white provider icon. A plain
/// template image view inherits the status bar's vibrancy the same way `iconView` does.
///
/// Everything visible here is the menu bar reading of `GlassButton`: same symbols, same
/// resting/hover glyph strengths, same squircle hover chip, same press shrink. The
/// chip is a template image rather than a colour or a material, so it picks up the
/// menu bar's vibrancy exactly like the glyphs do: light ink over a dark bar, dark ink
/// over a light one, without the view having to guess which it is sitting on.
final class StatusBarTransportControlsView: NSView {
    static let buttonWidth: CGFloat = 18
    static let leadingGap: CGFloat = 5

    /// Width the status item has to reserve for the strip, including the gap that
    /// separates it from whatever sits before it.
    static var totalWidth: CGFloat { leadingGap + buttonWidth * 3 }

    private enum Control: Int, CaseIterable {
        case previous, playPause, next
    }

    private let symbolPointSize: CGFloat = 10.5
    private let glyphSize: CGFloat = 13
    private let chipSide: CGFloat = 17
    private let chipCornerRadius: CGFloat = 17 * 0.28

    // Alphas on the menu bar's own ink, not greys. Heavier than GlassButton's 0.12
    // hover disc: that disc sits on artwork, this one has to register against a strip
    // of desktop a few points tall.
    private let chipHoverAlpha: CGFloat = 0.30
    private let chipPressedAlpha: CGFloat = 0.42

    // Mirrors GlassButton: secondaries rest at 0.72, lift to 0.96 under the pointer,
    // and the whole row drops to 0.40 when there is nothing to control.
    private let restingAlpha: CGFloat = 0.72
    private let hoverAlpha: CGFloat = 0.96
    private let disabledAlpha: CGFloat = 0.40

    private let stateFadeDuration: TimeInterval = 0.14
    private let chipSlideDuration: TimeInterval = 0.16
    private let crossfadeDuration: TimeInterval = 0.18

    private let chip = PassthroughImageView()
    private var chipImageSize: CGSize = .zero

    private let previousGlyph = PassthroughImageView()
    private let playGlyph = PassthroughImageView()
    private let pauseGlyph = PassthroughImageView()
    private let nextGlyph = PassthroughImageView()

    private var isPlaying = false
    private var isEnabled = false
    private var hoveredControl: Control?
    private var pressedControl: Control?

    var onPrevious: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        chip.imageScaling = .scaleAxesIndependently
        chip.contentTintColor = .labelColor
        chip.alphaValue = 0
        addSubview(chip)

        for glyph in [previousGlyph, playGlyph, pauseGlyph, nextGlyph] {
            glyph.imageScaling = .scaleProportionallyDown
            glyph.contentTintColor = .labelColor
            addSubview(glyph)
        }
        previousGlyph.image = symbolImage(named: "backward.fill")
        playGlyph.image = symbolImage(named: "play.fill")
        pauseGlyph.image = symbolImage(named: "pause.fill")
        nextGlyph.image = symbolImage(named: "forward.fill")
        pauseGlyph.alphaValue = 0

        setAccessibilityLabel("Playback Controls")
        applyState(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        refreshToolTips()
        for control in Control.allCases {
            for glyph in glyphs(for: control) {
                glyph.frame = glyphFrame(for: control, pressed: pressedControl == control)
            }
        }
        if let hoveredControl {
            chip.frame = chipFrame(for: hoveredControl)
        }
    }

    private func slotRect(for control: Control) -> CGRect {
        CGRect(
            x: Self.leadingGap + CGFloat(control.rawValue) * Self.buttonWidth,
            y: 0,
            width: Self.buttonWidth,
            height: bounds.height
        )
    }

    /// A pressed glyph loses a point on every side — the menu bar reading of
    /// `GlassButton`'s 0.96 press scale, done with the frame so it does not depend on
    /// where AppKit decided to put a layer's anchor point.
    private func glyphFrame(for control: Control, pressed: Bool) -> CGRect {
        let slot = slotRect(for: control)
        let side = pressed ? glyphSize - 1 : glyphSize
        return CGRect(
            x: floor(slot.midX - side / 2),
            y: floor(slot.midY - side / 2),
            width: side,
            height: side
        )
    }

    private func chipFrame(for control: Control) -> CGRect {
        let slot = slotRect(for: control)
        let height = min(chipSide, max(bounds.height - 4, 1))
        refreshChipImage(for: CGSize(width: chipSide, height: height))
        return CGRect(
            x: floor(slot.midX - chipSide / 2),
            y: floor(slot.midY - height / 2),
            width: chipSide,
            height: height
        )
    }

    // MARK: - State

    func apply(isPlaying: Bool, enabled: Bool) {
        let playStateChanged = self.isPlaying != isPlaying
        let enabledChanged = isEnabled != enabled
        guard playStateChanged || enabledChanged else { return }
        self.isPlaying = isPlaying
        isEnabled = enabled
        if !enabled {
            hoveredControl = nil
            pressedControl = nil
        }
        if playStateChanged {
            refreshToolTips()
        }
        // Only animate a live change. The first pass, and any pass that arrives while the
        // strip is hidden, would otherwise fade in from nothing the moment it appears.
        applyState(
            animated: window != nil && !isHidden,
            duration: playStateChanged ? crossfadeDuration : stateFadeDuration
        )
    }

    private func applyState(animated: Bool, duration: TimeInterval? = nil) {
        let apply = { (proxy: Bool) -> Void in
            for control in Control.allCases {
                for glyph in self.glyphs(for: control) {
                    let target = proxy ? glyph.animator() : glyph
                    target.alphaValue = self.alpha(for: glyph, control: control)
                    target.frame = self.glyphFrame(for: control, pressed: self.pressedControl == control)
                }
            }
            let chipTarget = proxy ? self.chip.animator() : self.chip
            if let active = self.hoveredControl {
                // Sliding from a cold start would have the chip fly in from the origin.
                if self.chip.alphaValue == 0 && !proxy {
                    self.chip.frame = self.chipFrame(for: active)
                }
                chipTarget.frame = self.chipFrame(for: active)
                chipTarget.alphaValue = self.pressedControl == active
                    ? self.chipPressedAlpha
                    : self.chipHoverAlpha
            } else {
                chipTarget.alphaValue = 0
            }
        }

        guard animated else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                apply(false)
            }
            return
        }

        // A chip that is already on screen slides between slots; one that is fading in
        // has to be parked on its slot first, or it travels from wherever it died.
        if chip.alphaValue == 0, let hoveredControl {
            chip.frame = chipFrame(for: hoveredControl)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
                ?? (hoveredControl == nil ? stateFadeDuration : chipSlideDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            apply(true)
        }
    }

    private func glyphs(for control: Control) -> [PassthroughImageView] {
        switch control {
        case .previous: return [previousGlyph]
        case .playPause: return [playGlyph, pauseGlyph]
        case .next: return [nextGlyph]
        }
    }

    private func alpha(for glyph: PassthroughImageView, control: Control) -> CGFloat {
        // The idle half of the play/pause pair is always fully out; the visible half
        // takes the row's strength, so the swap reads as a crossfade in place.
        if control == .playPause {
            let isVisibleHalf = (glyph === pauseGlyph) == isPlaying
            guard isVisibleHalf else { return 0 }
        }
        guard isEnabled else { return disabledAlpha }
        if pressedControl == control { return hoverAlpha }
        return hoveredControl == control ? hoverAlpha : restingAlpha
    }

    // MARK: - Pointer

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressedControl = control(at: convert(event.locationInWindow, from: nil))
        hoveredControl = pressedControl ?? hoveredControl
        applyState(animated: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, pressedControl != nil else { return }
        let inside = control(at: convert(event.locationInWindow, from: nil)) == pressedControl
        let target = inside ? pressedControl : nil
        guard hoveredControl != target else { return }
        hoveredControl = target
        applyState(animated: true)
    }

    override func mouseUp(with event: NSEvent) {
        let landed = control(at: convert(event.locationInWindow, from: nil))
        let fired = isEnabled && landed != nil && landed == pressedControl ? landed : nil
        pressedControl = nil
        hoveredControl = isEnabled ? landed : nil
        applyState(animated: true)

        switch fired {
        case .previous: onPrevious?()
        case .playPause: onPlayPause?()
        case .next: onNext?()
        case nil: break
        }
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard pressedControl == nil, hoveredControl != nil else { return }
        hoveredControl = nil
        applyState(animated: true)
    }

    private func updateHover(at point: NSPoint) {
        guard isEnabled, pressedControl == nil else { return }
        let target = control(at: point)
        guard hoveredControl != target else { return }
        hoveredControl = target
        applyState(animated: true)
    }

    /// Without this the strip is transparent to clicks until the app is frontmost, which
    /// for a menu bar app is almost never.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        // `.mouseMoved` as well as enter/exit: the chip has to follow the pointer across
        // the three slots, not just light up when it arrives at the strip.
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    private func control(at point: NSPoint) -> Control? {
        guard bounds.contains(point) else { return nil }
        let offset = point.x - Self.leadingGap
        guard offset >= 0 else { return nil }
        return Control(rawValue: Int(offset / Self.buttonWidth))
    }

    // MARK: - Chrome

    /// The glyph views pass their hits through, so tooltips have to be registered as
    /// rects on the container instead of set on each image view.
    private func refreshToolTips() {
        removeAllToolTips()
        let titles = ["Previous Track", isPlaying ? "Pause" : "Play", "Next Track"]
        for (index, title) in titles.enumerated() {
            guard let control = Control(rawValue: index) else { continue }
            addToolTip(slotRect(for: control), owner: title as NSString, userData: nil)
        }
    }

    /// A filled squircle drawn once per size and flagged as a template, which is what
    /// lets the vibrancy tint it alongside the glyphs.
    private func refreshChipImage(for size: CGSize) {
        guard size.width > 0, size.height > 0, size != chipImageSize else { return }
        chipImageSize = size
        let image = NSImage(size: size, flipped: false) { [chipCornerRadius] rect in
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: rect,
                xRadius: chipCornerRadius,
                yRadius: chipCornerRadius
            ).fill()
            return true
        }
        image.isTemplate = true
        chip.image = image
    }

    private func symbolImage(named name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: symbolPointSize, weight: .semibold))
        image?.isTemplate = true
        return image
    }
}
