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
@MainActor
final class ModeMorphDriver: NSObject {
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var onFrame: ((Double) -> Void)?
    private var onFinish: (() -> Void)?

    var isRunning: Bool { displayLink != nil }

    func start(onFrame: @escaping (Double) -> Void, onFinish: @escaping () -> Void) {
        cancel()
        self.onFrame = onFrame
        self.onFinish = onFinish
        startTime = CACurrentMediaTime()

        guard let link = NSScreen.main?.displayLink(target: self, selector: #selector(tick)) else {
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

    @objc private func tick() {
        let elapsed = (CACurrentMediaTime() - startTime) / modeTransitionDuration
        guard elapsed < 1 else {
            finish()
            return
        }
        onFrame?(Self.ease(elapsed))
    }

    private func finish() {
        let completion = onFinish
        cancel()
        completion?()
    }

    /// y for a given x on cubic-bezier(modeMorphControlPoints), bisected. Cheap enough at
    /// one evaluation per display frame, and keeps the shape documented in one place.
    static func ease(_ x: Double) -> Double {
        let (x1, y1, x2, y2) = modeMorphControlPoints
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
/// its full width at rest so nothing shifts when the cluster comes up on hover.
let playerControlClusterRestingOpacity: Double = 0
let playerControlClusterActiveRestingOpacity: Double = 0.62
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

private struct MiniBottomPanelChrome: View {
    let sizeScale: CGFloat
    let emphasis: Double
    let neutralWashOpacity: Double
    let blueFogOpacity: Double

    private var clampedEmphasis: Double {
        min(max(emphasis, 0), 1)
    }

    private var panel: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18 * sizeScale, style: .continuous)
    }

    private var baseFill: some View {
        panel.fill(Color.black.opacity(0.22 + (0.18 * clampedEmphasis)))
    }

    private var neutralWash: some View {
        panel.fill(
            Color(red: 0.60, green: 0.66, blue: 0.74)
                .opacity(neutralWashOpacity * (0.42 - (0.10 * clampedEmphasis)))
        )
    }

    private var blueWash: some View {
        panel.fill(
            Color(red: 0.52, green: 0.61, blue: 0.76)
                .opacity(blueFogOpacity * (0.44 - (0.12 * clampedEmphasis)))
        )
    }

    private var topGloss: some View {
        panel.fill(
            LinearGradient(
                colors: [
                    .white.opacity(0.10),
                    .white.opacity(0.03),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var lowerShade: some View {
        panel.fill(
            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.18 + (0.10 * clampedEmphasis))
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    var body: some View {
        baseFill
            .overlay(neutralWash)
            .overlay(blueWash)
            .overlay(topGloss)
            .overlay(lowerShade)
            .overlay(panel.stroke(.white.opacity(0.14 + (0.06 * clampedEmphasis)), lineWidth: 1))
    }
}

extension View {
    @ViewBuilder
    func forceHideScrollIndicators() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollIndicators(.hidden)
        } else {
            self
        }
    }

    func hoverHint(_ text: String, enabled: Bool = true) -> some View {
        modifier(HoverHintModifier(text: text, enabled: enabled))
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

    func miniBottomPanelBackground(
        sizeScale: CGFloat,
        emphasis: Double,
        neutralWashOpacity: Double,
        blueFogOpacity: Double,
        contentHorizontalPadding: CGFloat,
        contentVerticalPadding: CGFloat
    ) -> some View {
        self
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.vertical, contentVerticalPadding)
            .background(
                MiniBottomPanelChrome(
                    sizeScale: sizeScale,
                    emphasis: emphasis,
                    neutralWashOpacity: neutralWashOpacity,
                    blueFogOpacity: blueFogOpacity
                )
            )
            .shadow(
                color: .black.opacity(0.18 + (0.16 * min(max(emphasis, 0), 1))),
                radius: 10 * sizeScale,
                x: 0,
                y: 4 * sizeScale
            )
    }

    func onAnimationCompleted<Value: VectorArithmetic>(
        for value: Value,
        perform action: @escaping () -> Void
    ) -> some View {
        modifier(AnimationCompletionObserverModifier(observedValue: value, completion: action))
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
/// Geometry of the regular tile, mirrored from ArtworkView: a glass shell at radius 22
/// with a 12pt allowance, so the image plate sits inset 6 at radius 16 (22 − 6). The
/// mini hero is the bare artwork at radius 13. The shared morph node interpolates plate
/// to plate and dissolves the shell along the way.
let regularArtworkShellInset: CGFloat = 6
let regularArtworkShellCornerRadius: CGFloat = 22
let regularArtworkCornerRadius: CGFloat = 16
let miniArtworkCornerRadius: CGFloat = 13

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

private struct AnimationCompletionObserverModifier<Value>: AnimatableModifier where Value: VectorArithmetic {
    var targetValue: Value
    var completion: () -> Void

    var animatableData: Value {
        didSet {
            notifyCompletionIfFinished()
        }
    }

    init(observedValue: Value, completion: @escaping () -> Void) {
        targetValue = observedValue
        animatableData = observedValue
        self.completion = completion
    }

    func body(content: Content) -> some View {
        content
    }

    private func notifyCompletionIfFinished() {
        guard animatableData == targetValue else { return }
        DispatchQueue.main.async {
            completion()
        }
    }
}

private struct HoverHintModifier: ViewModifier {
    let text: String
    let enabled: Bool
    private let delay: Double = 0.32

    @State private var hovering = false
    @State private var showHint = false
    @State private var workItem: DispatchWorkItem?

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
            .overlay(alignment: .bottom) {
                if showHint {
                    Text(text)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.72))
                                .overlay(
                                    Capsule()
                                        .stroke(.white.opacity(0.16), lineWidth: 1)
                                )
                        )
                        .fixedSize()
                        .offset(y: 28)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .zIndex(20)
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

struct PlaybackProgressBlock: View {
    @ObservedObject private var clock = PlaybackClock.shared
    var contrastBoost: Double = 0
    let onSeek: (Double) -> Void

    var body: some View {
        ProgressBlock(
            progress: clock.progress,
            elapsed: clock.liveElapsed,
            duration: clock.duration,
            canSeek: clock.canSeek,
            contrastBoost: contrastBoost,
            onSeek: onSeek
        )
    }
}
