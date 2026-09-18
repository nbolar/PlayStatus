import SwiftUI
import AppKit

let modePrimaryRevealAnimation = Animation.easeOut(duration: 0.20)
let modeSecondaryRevealAnimation = Animation.easeOut(duration: 0.24)
/// The curve the window resize runs on, and therefore the curve the whole morph runs on.
/// The content has no animation of its own: it lays out into whatever size the host
/// currently is and derives its morph progress from that width, so there is exactly one
/// timeline and nothing that can drift against it.
let modeMorphControlPoints: (Double, Double, Double, Double) = (0.30, 0.90, 0.35, 1.00)

/// Steps the window through a mode morph, one display frame at a time.
///
/// `NSAnimationContext` + `window.animator().setFrame` does not animate the popover's
/// backing window — measured frame by frame, it snapped to the new width in a single
/// frame every time. Since the content sizes itself from the host, the content snapped
/// with it. Stepping the frame ourselves is what actually produces motion here.
///
/// Ticks must not touch SwiftUI state: a display-link callback is outside the render
/// pass, which is what keeps this safe, whereas resizing from inside a SwiftUI animation
/// callback re-enters layout and trips an AttributeGraph precondition.
///
/// The clock starts on the first frame, not at `start()`. A transition usually begins by
/// mounting new content, and that first layout can hold the main thread for several
/// frames; a clock already running through it made the window open the transition by
/// jumping a third of the way along its curve. Progress is also sampled at the frame's
/// `targetTimestamp` — when it reaches the glass — rather than when the callback ran.
@MainActor
final class ModeMorphDriver: NSObject {
    private var displayLink: CADisplayLink?
    /// Zero until the first tick sets it.
    private var startTime: CFTimeInterval = 0
    private var onFrame: ((Double) -> Void)?
    private var onFinish: (() -> Void)?
    private var duration: Double = modeTransitionDuration
    private var curve = modeMorphControlPoints

    var isRunning: Bool { displayLink != nil }

    /// - Parameter screen: The screen the moving window is on, so the link runs at that
    ///   display's refresh rate. Falls back to the main screen.
    func start(
        on screen: NSScreen? = nil,
        duration: Double = modeTransitionDuration,
        curve: (Double, Double, Double, Double) = modeMorphControlPoints,
        onFrame: @escaping (Double) -> Void,
        onFinish: @escaping () -> Void
    ) {
        cancel()
        self.duration = duration
        self.curve = curve
        self.onFrame = onFrame
        self.onFinish = onFinish
        startTime = 0

        guard let link = (screen ?? NSScreen.main)?.displayLink(target: self, selector: #selector(tick(_:))) else {
            finish()
            return
        }
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        onFrame = nil
        onFinish = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if startTime == 0 {
            startTime = link.timestamp
        }
        let elapsed = (link.targetTimestamp - startTime) / duration
        guard elapsed < 1 else {
            finish()
            return
        }
        onFrame?(Self.ease(elapsed, curve: curve))
    }

    private func finish() {
        let completion = onFinish
        cancel()
        completion?()
    }

    /// y for a given x on cubic-bezier(modeMorphControlPoints), bisected. Cheap enough at
    /// one evaluation per display frame, and keeps the shape documented in one place.
    static func ease(_ x: Double, curve: (Double, Double, Double, Double) = modeMorphControlPoints) -> Double {
        let (x1, y1, x2, y2) = curve
        var low = 0.0
        var high = 1.0
        var t = x
        for _ in 0..<24 {
            t = (low + high) / 2
            let inv = 1 - t
            let sampled = (3 * t * inv * inv * x1) + (3 * t * t * inv * x2) + (t * t * t)
            if sampled < x {
                low = t
            } else {
                high = t
            }
        }
        let inv = 1 - t
        return (3 * t * inv * inv * y1) + (3 * t * t * inv * y2) + (t * t * t)
    }
}
/// The layouts cross-fade with a deliberate overlap. Retiring the outgoing one before
/// the incoming one arrives leaves a window where neither is on screen — roughly 250ms
/// of bare artwork on an empty panel, which reads as a glitch rather than as a
/// transition. Fading out still leads, it just no longer finishes first.
let modeOutgoingFadeAnimation = Animation.easeOut(duration: 0.14)
let modeIncomingFadeAnimation = Animation.easeOut(duration: 0.16)
let modeIncomingFadeDelay: Double = 0.06
/// Opacity of the top-row control capsule when the pointer is elsewhere. The row keeps
/// its full width at rest so nothing shifts when the cluster comes up on hover. The
/// capsule hides whether or not the lyrics/credits pane is open — an open pane used to
/// keep it at a partial opacity, which just left chrome sitting over the artwork.
///
/// Both modes hide it outright. Search lives in this row too, so it is invisible at rest
/// as well: it comes back on the same hover that brings up everything else, and a player
/// at rest is a piece of artwork with a title under it.
let playerControlClusterRestingOpacity: Double = 0

/// Opacity of shuffle, repeat and the skip buttons when the pointer is elsewhere.
///
/// Unlike the top-row cluster this does not go to zero: play/pause stays at full strength
/// and the transport keeps its shape, so a player at rest reads as one bright control with
/// four ghosted ones beside it rather than a row that vanishes and reappears. Low enough to
/// stay out of the artwork, high enough that the controls are still discoverable without
/// moving the pointer.
let playerTransportSecondaryRestingOpacity: Double = 0.30

// MARK: - Surface tokens

/// One radius for every player surface — popover, mini card, detached window. Shapes
/// nested inside a surface derive their radius from this minus their inset, so corners
/// stay concentric instead of repeating the parent's curve at a smaller size.
let playerSurfaceCornerRadius: CGFloat = 18
/// Retina hairline. Interior 1pt borders are what made the player read as busy; a single
/// half-point line on the outermost shape does the whole separation job.
let playerHairlineWidth: CGFloat = 0.5
let playerHairlineOpacity: Double = 0.12
/// Padding between the surface edge and its content.
let playerSurfaceContentPadding: CGFloat = 20
/// Vertical lane the top-right control cluster occupies, reserved by the text column so the
/// track title never sits under it.
///
/// The cluster is an overlay, so it takes no space in the layout — and once the metadata was
/// aligned to the top of the artwork, the title ran straight into it. Reserved unconditionally
/// rather than only while the cluster is visible: the title must not shift when you hover.
let playerClusterReservedHeight: CGFloat = 22
/// The warm charcoal every player surface is built on.
///
/// The popover gets an opaque backing for free from `NSPopover`'s own chrome. The detached
/// window does not — it is a transparent window hosting deliberately translucent glass — so
/// it paints this as its window background. Shared from one place so the window's base and
/// the surface drawn on top of it cannot drift apart.
let playerSurfaceGroundNSColor = NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.08, alpha: 1)
let playerSurfaceGroundColor = Color(nsColor: playerSurfaceGroundNSColor)
let miniSeamBlendHeight: CGFloat = 1
let miniSeamBlurRadius: CGFloat = 10

struct SearchSectionFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Backing for the top-row control cluster.
///
/// The capsule has two jobs depending on what it sits on, so `artworkBacking` blends
/// between them. At 0 it rests on the player's own tinted glass and uses the same
/// recipe as `GlassButton` — a light `primary` wash, no material, no shadow — so it
/// reads as one of the player's controls. At 1 it floats over album artwork and has to
/// supply its own scrim instead, because white glyphs need to darken against a bright
/// photo, not lighten. `contrastBoost` strengthens whichever job is in play.
private struct PlayerControlClusterChrome: View {
    let sizeScale: CGFloat
    let neutralWashOpacity: Double
    let blueFogOpacity: Double
    let contrastBoost: Double
    let artworkBacking: Double

    private var clampedContrastBoost: Double {
        min(max(contrastBoost, 0), 1)
    }

    private var clampedArtworkBacking: Double {
        min(max(artworkBacking, 0), 1)
    }

    private var capsule: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12 * sizeScale, style: .continuous)
    }

    private var glassWash: some View {
        let strength = min(0.34, 0.09 + (0.20 * clampedContrastBoost))
        return capsule.fill(Color.primary.opacity(strength * (1 - clampedArtworkBacking)))
    }

    private var artworkScrim: some View {
        let strength = 0.28 + (0.16 * clampedContrastBoost)
        return capsule.fill(Color.black.opacity(strength * clampedArtworkBacking))
    }

    private var neutralWash: some View {
        capsule.fill(
            Color(red: 0.60, green: 0.66, blue: 0.74)
                .opacity(neutralWashOpacity * 0.42)
        )
    }

    private var blueWash: some View {
        capsule.fill(
            Color(red: 0.52, green: 0.61, blue: 0.76)
                .opacity(blueFogOpacity * 0.38)
        )
    }

    private var diagonalHighlight: some View {
        capsule
            .fill(
                LinearGradient(
                    colors: [.white.opacity(max(0.03, 0.10 - (0.06 * clampedContrastBoost))), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.plusLighter)
    }

    private var hairline: some View {
        capsule.stroke(
            .white.opacity(min(0.30, 0.13 + (0.05 * clampedArtworkBacking) + (0.08 * clampedContrastBoost))),
            lineWidth: 1
        )
    }

    var body: some View {
        capsule
            .fill(.ultraThinMaterial)
            .opacity(clampedArtworkBacking)
            .overlay(artworkScrim)
            .overlay(glassWash)
            .overlay(neutralWash)
            .overlay(blueWash)
            .overlay(diagonalHighlight)
            .overlay(hairline)
    }
}

extension View {
    /// Crosses a track's metadata when the song changes: the outgoing lines rise and fade as
    /// the incoming ones arrive from below.
    ///
    /// Shared by both modes. It started life inside the regular player only, which left mini
    /// swapping its text in place while the artwork beside it crossfaded — the two surfaces
    /// disagreeing about whether a track change is a moment.
    func trackChangeTransition(identity: String, isEnabled: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            self
                .id(identity)
                .transition(
                    .asymmetric(
                        insertion: .offset(y: 10).combined(with: .opacity),
                        removal: .offset(y: -10).combined(with: .opacity)
                    )
                )
        }
        .animation(isEnabled ? .easeOut(duration: 0.22) : nil, value: identity)
    }

    @ViewBuilder
    func forceHideScrollIndicators() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollIndicators(.hidden)
        } else {
            self
        }
    }

    /// Shows `text` on hover.
    ///
    /// `edge` is which side of the control the bubble sits on. It defaults to `.bottom`,
    /// but controls sitting on the surface's bottom edge — the volume row — need `.top`:
    /// the bubble is a plain overlay, so anything hanging past the surface is clipped in
    /// half rather than floating free the way an AppKit tooltip would.
    func hoverHint(_ text: String, enabled: Bool = true, edge: VerticalEdge = .bottom) -> some View {
        modifier(HoverHintModifier(text: text, enabled: enabled, edge: edge))
    }

    func playerControlClusterBackground(
        sizeScale: CGFloat,
        neutralWashOpacity: Double,
        blueFogOpacity: Double,
        contrastBoost: Double,
        artworkBacking: Double
    ) -> some View {
        let clampedArtworkBacking = min(max(artworkBacking, 0), 1)
        return self
            .padding(.horizontal, 6 * sizeScale)
            .padding(.vertical, 4 * sizeScale)
            .background(
                PlayerControlClusterChrome(
                    sizeScale: sizeScale,
                    neutralWashOpacity: neutralWashOpacity,
                    blueFogOpacity: blueFogOpacity,
                    contrastBoost: contrastBoost,
                    artworkBacking: clampedArtworkBacking
                )
            )
            .shadow(
                color: .black.opacity(0.26 * clampedArtworkBacking),
                radius: 7 * sizeScale,
                x: 0,
                y: 2 * sizeScale
            )
    }

    /// Publishes where a mode's artwork sits inside its own branch. Measured in the
    /// branch's local space, not the popover root, so the value stays constant while the
    /// container morphs and does not churn state on every animation frame.
    func modeArtworkAnchor(_ slot: ModeArtworkSlot, in space: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ModeArtworkFramePreferenceKey.self,
                    value: [slot: proxy.frame(in: .named(space))]
                )
            }
        }
    }
}

enum ModeArtworkSlot: Hashable {
    case regular
    case mini
}

let modeRegularBranchSpace = "modeRegularBranch"
let modeMiniBranchSpace = "modeMiniBranch"
/// Both modes now draw the artwork as a bare plate with a drop shadow — the glass shell
/// that used to ring the regular tile was the same "frame around a frame" as the old
/// inner card, one level down. With no shell there is nothing to dissolve, so the shared
/// morph node simply interpolates one plate into the other.
///
/// Mini's radius is concentric: the hero is inset 8 from an 18-radius card, so 18 − 8.
let regularArtworkCornerRadius: CGFloat = 14
let miniArtworkPadding: CGFloat = 8
let miniArtworkCornerRadius: CGFloat = playerSurfaceCornerRadius - miniArtworkPadding

/// The bare album art, with no per-mode chrome. Used only by the shared morph node —
/// each mode still draws its own full treatment when settled.
struct MorphingArtworkImage: View {
    let image: NSImage?
    let tint: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(0.34), .black.opacity(0.26)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
    }
}

struct ModeArtworkFramePreferenceKey: PreferenceKey {
    static var defaultValue: [ModeArtworkSlot: CGRect] = [:]

    static func reduce(value: inout [ModeArtworkSlot: CGRect], nextValue: () -> [ModeArtworkSlot: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

/// Coordinate space the hover hints measure themselves in, and the surface rect they are
/// clamped to. Both are published by `hoverHintSurface()` on the player's root view.
let hoverHintCoordinateSpace = "playerSurface"

private struct HoverHintSurfaceKey: EnvironmentKey {
    static let defaultValue: CGRect? = nil
}

extension EnvironmentValues {
    var hoverHintSurface: CGRect? {
        get { self[HoverHintSurfaceKey.self] }
        set { self[HoverHintSurfaceKey.self] = newValue }
    }
}

/// The hint that is showing, published up to the surface that draws it.
private struct ActiveHoverHint: Equatable {
    let text: String
    let edge: VerticalEdge
    /// The hinted control, in `hoverHintCoordinateSpace`.
    let controlFrame: CGRect
}

private struct ActiveHoverHintPreferenceKey: PreferenceKey {
    static var defaultValue: ActiveHoverHint?

    static func reduce(value: inout ActiveHoverHint?, nextValue: () -> ActiveHoverHint?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// Marks the player surface the hint bubbles are drawn on.
    ///
    /// Hinted controls do not draw their own bubble on this surface; they publish it, and
    /// the surface draws it in one overlay above everything. A bubble drawn as an overlay
    /// on its own control was clipped by every ancestor (the surface edge, the History
    /// scroll view) and painted over by later siblings — the next History row covered it,
    /// and a `zIndex` did not survive the lazy stack reordering rows on a track change.
    func hoverHintSurface(_ size: CGSize) -> some View {
        environment(\.hoverHintSurface, CGRect(origin: .zero, size: size))
            .coordinateSpace(name: hoverHintCoordinateSpace)
            .overlayPreferenceValue(ActiveHoverHintPreferenceKey.self, alignment: .topLeading) { hint in
                ZStack(alignment: .topLeading) {
                    Color.clear
                    if let hint {
                        // The padding is the surface inset: it narrows the width offered
                        // to the bubble, and the clamp below keeps it on the surface.
                        HoverHintBubble(text: hint.text)
                            .padding(.horizontal, HoverHintBubble.surfaceInset)
                            .alignmentGuide(.leading) { d in
                                // Centred on the control, slid back inside the surface
                                // when it would hang past a side.
                                let half = d.width / 2
                                let center = min(max(hint.controlFrame.midX, half), size.width - half)
                                return d[HorizontalAlignment.center] - center
                            }
                            .alignmentGuide(.top) { d in
                                let drop = HoverHintBubble.drop
                                let inset = HoverHintBubble.surfaceInset
                                let fitsBelow = hint.controlFrame.maxY + drop <= size.height - inset
                                let fitsAbove = hint.controlFrame.minY - drop >= inset
                                // The requested edge wins whenever it fits; the flip keeps
                                // the last visible History row's bubble on the surface.
                                let below = hint.edge == .bottom ? (fitsBelow || !fitsAbove) : (!fitsAbove && fitsBelow)
                                return below
                                    ? d[.bottom] - (hint.controlFrame.maxY + drop)
                                    : d[.top] - (hint.controlFrame.minY - drop)
                            }
                            .transition(.opacity)
                    }
                }
                .frame(width: size.width, height: size.height)
                .animation(.easeOut(duration: 0.14), value: hint)
                .allowsHitTesting(false)
            }
    }
}

private struct HoverHintBubble: View {
    let text: String

    /// How close to the surface edge a bubble may sit before it is pushed back in.
    static let surfaceInset: CGFloat = 6
    /// How far the bubble's outer edge sits past the control's edge.
    static let drop: CGFloat = 28

    var body: some View {
        // A bubble wider than the width on offer — a History row's "Play <long title>
        // again" — falls back to one line truncated in the middle, so "again" survives.
        // No `frame(maxWidth:)` here: a flexible frame grows to the offered width, which
        // pinned every bubble's centre to the middle of the surface.
        ViewThatFits(in: .horizontal) {
            bubble(Text(text))
                .fixedSize()
            bubble(Text(text).lineLimit(1).truncationMode(.middle))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bubble(_ label: some View) -> some View {
        label
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.94))
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.88))
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    )
            )
    }
}

private struct HoverHintModifier: ViewModifier {
    let text: String
    let enabled: Bool
    var edge: VerticalEdge = .bottom
    private let delay: Double = 0.32

    @Environment(\.hoverHintSurface) private var surface

    @State private var hovering = false
    @State private var showHint = false
    @State private var workItem: DispatchWorkItem?
    @State private var controlFrame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard enabled else {
                    resetState()
                    return
                }
                self.hovering = hovering
                if hovering {
                    scheduleShowHint()
                } else {
                    hideHint()
                }
            }
            .onChange(of: enabled) { _, isEnabled in
                if !isEnabled {
                    resetState()
                }
            }
            .onDisappear {
                resetState()
            }
            // Measured only while the pointer is on the control: every hinted control
            // would otherwise carry a live geometry reader for the whole session.
            .background {
                if hovering, surface != nil {
                    GeometryReader { proxy in
                        // Read straight into state rather than through a preference: the
                        // content's own subtree publishes the default value after the
                        // background does, so a preference arrives back here as `.zero`.
                        let frame = proxy.frame(in: .named(hoverHintCoordinateSpace))
                        Color.clear
                            .onAppear { controlFrame = frame }
                            .onChange(of: frame) { _, latest in controlFrame = latest }
                    }
                }
            }
            // A hinted control inside another (a History row's play count) already
            // published its own, more specific hint; only fill the slot when it is empty.
            .transformPreference(ActiveHoverHintPreferenceKey.self) { active in
                guard active == nil, surface != nil, showHint, !controlFrame.isEmpty else { return }
                active = ActiveHoverHint(text: text, edge: edge, controlFrame: controlFrame)
            }
            // Hosts that publish no surface still get a bubble, drawn on the control.
            .overlay(alignment: edge == .bottom ? .bottom : .top) {
                if showHint, surface == nil {
                    HoverHintBubble(text: text)
                        .fixedSize()
                        .offset(y: edge == .bottom ? HoverHintBubble.drop : -HoverHintBubble.drop)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
    }

    private func scheduleShowHint() {
        workItem?.cancel()
        workItem = nil

        let item = DispatchWorkItem {
            guard hovering, enabled else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                showHint = true
            }
            workItem = nil
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func hideHint() {
        workItem?.cancel()
        workItem = nil
        withAnimation(.easeOut(duration: 0.12)) {
            showHint = false
        }
    }

    private func resetState() {
        workItem?.cancel()
        workItem = nil
        hovering = false
        showHint = false
    }
}

/// The mini card's resting progress line: what the card shows while the pointer is away
/// and the full scrubber is not on screen. Deliberately not a `PlayerRail` — there is no
/// pointer here to seek with, so it carries no knob, no hit target and no gesture, and it
/// shares only the rail's fill/track opacities so the hover hand-off reads as one element
/// thickening rather than two different controls swapping places.
struct MiniRestingProgressRail: View {
    @ObservedObject private var clock = PlaybackClock.shared
    var contrastBoost: Double = 0
    /// When set, the fill takes the artwork tint rather than white.
    var tint: Color? = nil

    private var clampedContrastBoost: Double {
        min(max(contrastBoost, 0), 1)
    }

    /// Lighter than `PlayerRail`'s equivalents on purpose. The scrubber is a control you
    /// are pointing at; this is a status line read in passing, at the edge of a card whose
    /// subject is the artwork, so it sits well below the metadata in the card's hierarchy
    /// and only climbs toward the rail's weights as bright artwork forces it to.
    private var trackOpacity: Double {
        min(0.20, 0.07 + (0.11 * clampedContrastBoost))
    }

    private var fillOpacity: Double {
        min(0.80, 0.56 + (0.20 * clampedContrastBoost))
    }

    /// A tinted fill is doing the same job with less contrast to spend, so it gets a
    /// little more opacity back than the white fill would take.
    private var resolvedFill: Color {
        guard let tint else { return .white.opacity(fillOpacity) }
        return tint.opacity(min(0.92, fillOpacity + 0.12))
    }

    var body: some View {
        // A live stream has no meaningful position, and an unstarted track would pin the
        // rail at zero — in both cases the line says nothing and is better absent.
        if clock.canSeek {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(trackOpacity))

                    // Driven to where the position will be at the next sync, over exactly that
                    // interval, so Core Animation carries the motion. Redrawing this per frame
                    // instead would re-render inside the popover on every tick — the cost the
                    // vinyl overlay was rewritten to avoid.
                    Capsule()
                        .fill(resolvedFill)
                        .frame(width: max(0, proxy.size.width * clock.projectedProgress))
                        .animation(clock.progressAnimation, value: clock.positionEpoch)
                }
            }
            .frame(height: 2.5)
            .allowsHitTesting(false)
            // The rail is already announced by the scrubber on hover; a second
            // unreachable copy of the same value is only noise in the rotor.
            .accessibilityHidden(true)
        }
    }
}

struct PlaybackProgressBlock: View {
    @ObservedObject private var clock = PlaybackClock.shared
    var contrastBoost: Double = 0
    let onSeek: (Double) -> Void

    var body: some View {
        ProgressBlock(
            // The rail is driven to the projected position and animated there; the time label
            // reads the true current value, so the two never disagree by more than the poll.
            progress: clock.projectedProgress,
            elapsed: clock.liveElapsed,
            duration: clock.duration,
            canSeek: clock.canSeek,
            contrastBoost: contrastBoost,
            advanceAnimation: clock.progressAnimation,
            advanceEpoch: clock.positionEpoch,
            onSeek: onSeek
        )
    }
}
