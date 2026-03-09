import SwiftUI
import AppKit

let modePrimaryRevealAnimation = Animation.easeOut(duration: 0.20)
let modeSecondaryRevealAnimation = Animation.easeOut(duration: 0.24)
let miniSeamBlendHeight: CGFloat = 1
let miniSeamBlurRadius: CGFloat = 10

struct SearchSectionFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct MiniControlClusterChrome: View {
    let sizeScale: CGFloat
    let neutralWashOpacity: Double
    let blueFogOpacity: Double

    private var capsule: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12 * sizeScale, style: .continuous)
    }

    private var shadowWash: some View {
        capsule.fill(Color.black.opacity(0.30))
    }

    private var neutralWash: some View {
        capsule.fill(
            Color(red: 0.60, green: 0.66, blue: 0.74)
                .opacity(neutralWashOpacity * 0.62)
        )
    }

    private var blueWash: some View {
        capsule.fill(
            Color(red: 0.52, green: 0.61, blue: 0.76)
                .opacity(blueFogOpacity * 0.58)
        )
    }

    private var lowerShade: some View {
        capsule.fill(
            LinearGradient(
                colors: [
                    .black.opacity(0.12),
                    .black.opacity(0.03),
                    .clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }

    private var upperGloss: some View {
        capsule.fill(
            LinearGradient(
                colors: [.white.opacity(0.16), .white.opacity(0.03), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    var body: some View {
        capsule
            .fill(.ultraThinMaterial)
            .overlay(shadowWash)
            .overlay(neutralWash)
            .overlay(blueWash)
            .overlay(lowerShade)
            .overlay(upperGloss)
            .overlay(capsule.stroke(.white.opacity(0.18), lineWidth: 1))
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

    func miniControlClusterBackground(
        sizeScale: CGFloat,
        neutralWashOpacity: Double,
        blueFogOpacity: Double
    ) -> some View {
        self
            .padding(.horizontal, 6 * sizeScale)
            .padding(.vertical, 5 * sizeScale)
            .background(
                MiniControlClusterChrome(
                    sizeScale: sizeScale,
                    neutralWashOpacity: neutralWashOpacity,
                    blueFogOpacity: blueFogOpacity
                )
            )
            .shadow(color: .black.opacity(0.26), radius: 7 * sizeScale, x: 0, y: 2 * sizeScale)
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
