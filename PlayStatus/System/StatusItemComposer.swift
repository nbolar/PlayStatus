import AppKit

/// The status item's contents — provider glyph, title lane and transport strip — and the
/// one place that decides how they are laid out from the model.
///
/// The menu bar and the settings preview both install one of these into a host view. The
/// preview used to be a SwiftUI approximation, and it drifted: it dimmed the artist whether
/// or not that was switched on, showed a title while nothing was playing, and never scrolled.
/// Driving the same views through the same layout is what keeps "live preview" honest.
final class StatusItemComposer {
    let iconView = PassthroughImageView()
    let marqueeView = StatusBarMarqueeView()
    let transportControlsView = StatusBarTransportControlsView()

    static let iconSize: CGFloat = 13
    static let iconOnlyLength: CGFloat = 22
    private let statusIconLeadingInset: CGFloat = 4
    private let statusIconTextSpacing: CGFloat = 5
    private let statusTextTrailingInset: CGFloat = 4

    private var lastStatusIcon: ProviderIconKind?

    init() {
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .labelColor
        marqueeView.isHidden = true
        transportControlsView.isHidden = true
    }

    func install(in host: NSView) {
        host.addSubview(iconView)
        host.addSubview(marqueeView)
        host.addSubview(transportControlsView)
    }

    /// Lays the contents out inside `host` for the model's current state and returns the
    /// width the item needs. Whether that width comes from `host` or is imposed on it is the
    /// caller's business: the status item sets its length, the preview sizes its frame.
    @discardableResult
    func apply(_ model: NowPlayingModel, in host: NSView) -> (length: CGFloat, showsTitle: Bool) {
        let icon = model.statusIcon
        if icon != lastStatusIcon {
            iconView.image = Self.statusImage(for: icon)
            lastStatusIcon = icon
        }

        let hostHeight = host.bounds.height

        // A paused title is still a title, so it goes through the same lane — but it is
        // drawn as a standing label rather than a moving one. See `pausedTitle` below.
        let pausedTitle = model.menuBarShowsPausedTitle
        let showMenuBarText = (model.isPlaying || pausedTitle) && model.menuBarTextMode != .iconOnly
        let transport = model.menuBarTransportAvailability
        let showControls = model.menuBarControlsEnabled && transport.isVisible
        let controlsWidth = showControls ? StatusBarTransportControlsView.totalWidth : 0
        transportControlsView.isHidden = !showControls
        if showControls {
            transportControlsView.apply(
                isPlaying: model.isPlaying,
                playEnabled: transport.playEnabled,
                skipEnabled: transport.skipEnabled
            )
        }

        if !showMenuBarText {
            let iconLength = Self.iconOnlyLength
            let iconY = floor((hostHeight - Self.iconSize) / 2)
            let iconX = floor((iconLength - Self.iconSize) / 2)
            iconView.frame = CGRect(x: iconX, y: iconY, width: Self.iconSize, height: Self.iconSize)
            layoutTransportControls(leadingEdge: iconLength, width: controlsWidth, height: hostHeight)
            marqueeView.suspendScrolling()
            marqueeView.isHidden = true
            return (iconLength + controlsWidth, false)
        }

        let configuredLaneWidth = model.statusTextWidth
        let actualTextWidth = measuredTextWidth(model.menuBarTitle, font: model.statusBarTitleFont)
        let effectiveLaneWidth = floor(min(configuredLaneWidth, max(24, actualTextWidth + 2)))
        let laneChrome = statusIconLeadingInset
            + Self.iconSize
            + statusIconTextSpacing
            + statusTextTrailingInset
            + controlsWidth

        let iconY = floor((hostHeight - Self.iconSize) / 2)
        iconView.frame = CGRect(x: statusIconLeadingInset, y: iconY, width: Self.iconSize, height: Self.iconSize)
        marqueeView.isHidden = false

        let laneHeight: CGFloat = 16
        let x = floor(iconView.frame.maxX + statusIconTextSpacing)
        let y = floor((hostHeight - laneHeight) / 2)
        let targetFrame = CGRect(x: x, y: y, width: effectiveLaneWidth, height: laneHeight)
        if !marqueeView.frame.equalTo(targetFrame) {
            marqueeView.frame = targetFrame
        }
        layoutTransportControls(
            leadingEdge: targetFrame.maxX + statusTextTrailingInset,
            width: controlsWidth,
            height: hostHeight
        )
        let titleParts = model.menuBarTitleParts
        // Scrolling reads as motion, and motion reads as playback. A paused title that
        // marquees back and forth says the opposite of what it is, so it stands still and
        // truncates instead, dimmed so the two states stay apart at a glance.
        marqueeView.update(
            text: model.menuBarTitle,
            secondarySuffix: titleParts.secondary.map { model.menuBarTitleSeparator + $0 },
            enabled: model.scrollableTitle && !pausedTitle,
            laneWidth: effectiveLaneWidth,
            slideOnChange: model.slideTitleOnChange,
            dimmed: pausedTitle,
            dimSecondary: model.dimSecondaryTitleText
        )
        // The icon and marquee are custom subviews, so their complete horizontal layout
        // must fit inside the item. Reserving only the text lane clips long titles as soon
        // as they reach the configured width.
        return (laneChrome + effectiveLaneWidth, true)
    }

    private func layoutTransportControls(leadingEdge: CGFloat, width: CGFloat, height: CGFloat) {
        guard width > 0 else { return }
        let targetFrame = CGRect(x: leadingEdge, y: 0, width: width, height: height)
        if !transportControlsView.frame.equalTo(targetFrame) {
            transportControlsView.frame = targetFrame
            transportControlsView.needsLayout = true
        }
    }

    private static func statusImage(for icon: ProviderIconKind) -> NSImage? {
        switch icon {
        case .sfSymbol(let symbolName):
            return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: iconSize, weight: .regular))
        case .iconifyAsset(let assetName):
            guard let base = NSImage(named: NSImage.Name(assetName)) else { return nil }
            let image = (base.copy() as? NSImage) ?? base
            image.isTemplate = true
            image.size = NSSize(width: iconSize, height: iconSize)
            return image
        }
    }
}
