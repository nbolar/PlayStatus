import SwiftUI
import AppKit

struct ProviderBadge: View {
    let provider: NowPlayingProvider
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: provider.icon)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(provider.displayName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))

            Text("•").foregroundStyle(.secondary.opacity(0.6))

            Text(isPlaying ? "active" : "idle")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Controls

struct ControlsRow: View {
    let isPlaying: Bool
    let onPrev: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    var contrastBoost: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            GlassButton(systemName: "backward.fill", contrastBoost: contrastBoost, action: onPrev)
            GlassButton(systemName: isPlaying ? "pause.fill" : "play.fill", isPrimary: true, contrastBoost: contrastBoost, action: onPlayPause)
            GlassButton(systemName: "forward.fill", contrastBoost: contrastBoost, action: onNext)
        }
    }
}

struct OutputControlsRow: View {
    @ObservedObject var model: NowPlayingModel
    let showDeviceName: Bool
    var contrastBoost: Double = 0
    var showFavorite: Bool = false
    var favoriteIsActive: Bool = false
    var favoritePulseToken: Int = 0
    var onFavorite: (() -> Void)? = nil
    @State private var favoritePulseActive = false

    private var selectedDeviceName: String {
        model.availableOutputDevices.first(where: { $0.id == model.selectedOutputDeviceID })?.name ?? "Output"
    }

    private var clampedContrastBoost: Double {
        min(max(contrastBoost, 0), 1)
    }

    private var controlForeground: Color {
        Color.white
    }

    private var controlFillOpacity: Double {
        min(0.34, 0.08 + (0.18 * clampedContrastBoost))
    }

    private var controlStrokeOpacity: Double {
        min(0.26, 0.10 + (0.08 * clampedContrastBoost))
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                if model.availableOutputDevices.isEmpty {
                    Text("No output devices found")
                } else {
                    ForEach(model.availableOutputDevices) { device in
                        Button {
                            model.setOutputDevice(device.id)
                        } label: {
                            if device.id == model.selectedOutputDeviceID {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "hifispeaker.fill")
                        .font(.system(size: 10, weight: .semibold))
//                    if showDeviceName {
//                        Text(selectedDeviceName)
//                            .lineLimit(1)
//                            .truncationMode(.tail)
//                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(controlForeground.opacity(0.90))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: showDeviceName ? 168 : nil, alignment: .leading)
                .background(Capsule().fill(Color.primary.opacity(controlFillOpacity)))
                .overlay(Capsule().stroke(.white.opacity(controlStrokeOpacity), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)

            Button {
                model.toggleOutputMute()
            } label: {
                Image(systemName: model.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(controlFillOpacity)))
                    .overlay(Circle().stroke(.white.opacity(controlStrokeOpacity), lineWidth: 1))
                    .foregroundStyle(model.outputMuted ? controlForeground.opacity(0.65) : controlForeground.opacity(0.94))
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { model.outputVolume },
                    set: { model.setOutputVolume($0) }
                ),
                in: 0...1
            )
            .frame(minWidth: 84, maxWidth: .infinity)
            .tint(controlForeground.opacity(0.88))
            .opacity(model.outputMuted ? 0.55 : 1.0)

            if showFavorite, let onFavorite {
                GlassButton(systemName: favoriteIsActive ? "heart.fill" : "heart", compact: true, contrastBoost: contrastBoost, action: onFavorite)
                    .foregroundStyle(favoriteIsActive ? Color.red.opacity(0.9) : controlForeground.opacity(0.94))
                    .scaleEffect(favoritePulseActive ? 1.16 : 1.0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.70), value: favoritePulseActive)
                    .onChange(of: favoritePulseToken) { _ in
                        favoritePulseActive = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            favoritePulseActive = false
                        }
                    }
                    .help(favoriteIsActive ? "Remove from Favorites (Apple Music)" : "Add to Favorites (Apple Music)")
            }
        }
        .onAppear {
            model.refreshAudioState()
        }
    }
}

struct GlassButton: View {
    let systemName: String
    var isPrimary: Bool = false
    var compact: Bool = false
    var contrastBoost: Double = 0
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    private var clampedContrastBoost: Double {
        min(max(contrastBoost, 0), 1)
    }

    private var iconColor: Color {
        Color.white
    }

    private var fillOpacity: Double {
        let base = isPrimary ? 0.13 : 0.08
        return min(0.38, base + (0.20 * clampedContrastBoost))
    }

    private var strokeOpacity: Double {
        let base = isPrimary ? 0.18 : 0.12
        return min(0.30, base + (0.08 * clampedContrastBoost))
    }

    private var highlightOpacity: Double {
        let base = isHovering ? 0.16 : 0.06
        return max(0.03, base - (0.06 * clampedContrastBoost))
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .frame(width: compact ? 30 : (isPrimary ? 40 : 32), height: compact ? 26 : (isPrimary ? 32 : 28))
                .contentShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(iconColor.opacity(isPrimary ? 0.98 : 0.92))
        .background(
            ZStack {
                // macOS 26: avoid system materials (.ultraThinMaterial/.thinMaterial) inside
                // NSHostingController — they trigger DesignLibrary glass compositor on every
                // SwiftUI re-render, causing recursive stack overflow. Use plain fills instead.
                RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                    .fill(Color.primary.opacity(fillOpacity))

                RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                    .fill(Color.black.opacity(0.18 * clampedContrastBoost))

                RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(highlightOpacity), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.plusLighter)

                RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                    .stroke(.white.opacity(strokeOpacity), lineWidth: 1)
            }
        )
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isPressed)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Progress

struct ProgressBlock: View {
    let progress: Double
    let elapsed: Double
    let duration: Double
    let canSeek: Bool
    var contrastBoost: Double = 0
    let onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    private var clampedContrastBoost: Double {
        min(max(contrastBoost, 0), 1)
    }

    private var railBaseOpacity: Double {
        min(0.28, 0.10 + (0.12 * clampedContrastBoost))
    }

    private var railFillOpacity: Double {
        min(0.50, 0.35 + (0.10 * clampedContrastBoost))
    }

    private var timeColor: Color {
        Color.white
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let p = isDragging ? dragValue : progress

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(railBaseOpacity))
                    Capsule().fill(.white.opacity(railFillOpacity))
                        .frame(width: max(6, w * CGFloat(min(max(p, 0), 1))))
                        .blendMode(.screen)
                }
                .frame(height: 7)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard canSeek else { return }
                            isDragging = true
                            let x = min(max(0, value.location.x), w)
                            dragValue = Double(x / w)
                        }
                        .onEnded { _ in
                            guard canSeek else { return }
                            isDragging = false
                            onSeek(dragValue)
                        }
                )
            }
            .frame(height: 7)
            .opacity(canSeek ? 1.0 : 0.55)

            HStack {
                Text(formatTime(isDragging ? (duration * dragValue) : elapsed))
                    .monospacedDigit()
                    .frame(width: 42, alignment: .leading)
                Spacer()
                Text(formatTime(duration))
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(timeColor.opacity(0.86))
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Artwork

private struct ArtworkMotionModifier: ViewModifier {
    let isEnabled: Bool
    let seed: String
    let style: ArtworkMotionStyle
    @State private var pulsePhase = false
    @State private var hovering = false
    @State private var pointerLocation: CGPoint = .zero
    @State private var viewSize: CGSize = .zero

    private var centeredPointerX: CGFloat {
        guard viewSize.width > 0 else { return 0 }
        return (pointerLocation.x / viewSize.width) - 0.5
    }

    private var centeredPointerY: CGFloat {
        guard viewSize.height > 0 else { return 0 }
        return (pointerLocation.y / viewSize.height) - 0.5
    }

    private var parallaxScale: CGFloat {
        guard isEnabled, style == .parallaxByPointer, hovering else { return 1.0 }
        return 1.018
    }

    private var parallaxOffset: CGSize {
        guard isEnabled, style == .parallaxByPointer else { return .zero }
        let x = centeredPointerX * 14
        let y = centeredPointerY * 12
        return CGSize(width: x, height: y)
    }

    private var parallaxTiltX: Double {
        guard isEnabled, style == .parallaxByPointer else { return 0 }
        return Double(-centeredPointerY * 9)
    }

    private var parallaxTiltY: Double {
        guard isEnabled, style == .parallaxByPointer else { return 0 }
        return Double(centeredPointerX * 11)
    }

    private var pulseScale: CGFloat {
        guard isEnabled, style == .depthPulse else { return 1.0 }
        return pulsePhase ? 1.026 : 1.0
    }

    private var pulseOpacity: Double {
        guard isEnabled, style == .depthPulse else { return 0 }
        return pulsePhase ? 0.22 : 0.0
    }

    private var pulseAnimation: Animation {
        .easeInOut(duration: 1.8).repeatForever(autoreverses: true)
    }

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { viewSize = geo.size }
                        .onChange(of: geo.size) { newSize in
                            viewSize = newSize
                        }
                }
            )
            .scaleEffect(parallaxScale * pulseScale)
            .offset(
                x: parallaxOffset.width,
                y: parallaxOffset.height
            )
            .rotation3DEffect(.degrees(parallaxTiltX), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(parallaxTiltY), axis: (x: 0, y: 1, z: 0))
            .overlay {
                if style == .depthPulse && isEnabled {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(pulseOpacity), lineWidth: 1.2)
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                }
            }
            .animation(
                .interactiveSpring(response: 0.28, dampingFraction: 0.84, blendDuration: 0.1),
                value: pointerLocation
            )
            .animation(
                .spring(response: 0.26, dampingFraction: 0.80, blendDuration: 0.1),
                value: hovering
            )
            .animation(pulseAnimation, value: pulsePhase)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    pointerLocation = location
                    hovering = true
                case .ended:
                    hovering = false
                    pointerLocation = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                }
            }
            .onAppear {
                if isEnabled && style == .depthPulse {
                    pulsePhase = true
                }
                if pointerLocation == .zero {
                    pointerLocation = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                }
            }
            .onChange(of: style) { newStyle in
                pulsePhase = isEnabled && newStyle == .depthPulse
            }
            .onChange(of: isEnabled) { enabled in
                pulsePhase = enabled && style == .depthPulse
                if !enabled {
                    hovering = false
                }
            }
    }
}

extension View {
    func animatedArtworkMotion(isEnabled: Bool, seed: String, style: ArtworkMotionStyle) -> some View {
        modifier(ArtworkMotionModifier(isEnabled: isEnabled, seed: seed, style: style))
    }
}

struct AnimatedArtworkView: View {
    let image: NSImage?
    let tint: Color
    let isEnabled: Bool
    let seed: String
    let style: ArtworkMotionStyle
    var body: some View {
        ArtworkView(image: image, tint: tint)
            .animatedArtworkMotion(isEnabled: isEnabled, seed: seed, style: style)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let outer = RoundedRectangle(cornerRadius: 22, style: .continuous)
            let inner = RoundedRectangle(cornerRadius: 18, style: .continuous)

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.34), .black.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 14)
                    .scaleEffect(0.92)
                    .opacity(0.9)

                // macOS 26: .ultraThinMaterial triggers DesignLibrary glass compositor
                // on every SwiftUI re-render, causing recursive stack overflow.
                // Use a gradient approximation instead.
                outer
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.10),
                                tint.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(outer.stroke(.white.opacity(0.22), lineWidth: 1.2))
                    .overlay(outer.stroke(tint.opacity(0.2), lineWidth: 1))

                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: side - 12, height: side - 12)
                            .background(tint.opacity(0.12))
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [.white.opacity(0.08), .black.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note")
                                .font(.system(size: 36, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary.opacity(0.95))
                        }
                        .frame(width: side - 12, height: side - 12)
                    }
                }
                .clipShape(inner, style: FillStyle(eoFill: false, antialiased: true))
                .overlay(inner.stroke(.white.opacity(0.1), lineWidth: 1))
                .overlay(
                    inner
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .clear, .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                )
            }
            .frame(width: side, height: side)
            .clipped()
            .compositingGroup()
        }
        .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 10)
    }
}

// MARK: - Liquid Glass background/card

struct LiquidGlassBackground: View {
    let tint: Color
    var readabilityBoost: Double = 0

    private var clampedReadabilityBoost: Double {
        min(max(readabilityBoost, 0), 1)
    }

    private var darkenOpacity: Double {
        min(0.22, 0.01 + (0.18 * clampedReadabilityBoost))
    }

    private var sheenOpacity: Double {
        max(0.14, 0.50 - (0.26 * clampedReadabilityBoost))
    }

    private var strokeOpacity: Double {
        min(0.24, 0.10 + (0.10 * clampedReadabilityBoost))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.10), tint.opacity(0.06), tint.opacity(0.09)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(darkenOpacity))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.14), .clear],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: 300
                    )
                )
                .blendMode(.screen)
                .opacity(sheenOpacity)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(strokeOpacity), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 8)
    }
}

struct LiquidGlassCard<Content: View>: View {
    let tint: Color
    let palette: [Color]
    var readabilityBoost: Double = 0
    @ViewBuilder var content: Content

    private var primary: Color { palette.first ?? tint }
    private var secondary: Color { palette.dropFirst().first ?? tint }
    private var tertiary: Color { palette.dropFirst(2).first ?? tint }
    private var clampedReadabilityBoost: Double {
        min(max(readabilityBoost, 0), 1)
    }
    private var darkenOpacity: Double {
        min(0.24, 0.02 + (0.20 * clampedReadabilityBoost))
    }
    private var sheenOpacity: Double {
        max(0.10, 0.26 - (0.12 * clampedReadabilityBoost))
    }
    private var strokeOpacity: Double {
        min(0.26, 0.12 + (0.10 * clampedReadabilityBoost))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            primary.opacity(0.90),
                            secondary.opacity(0.84),
                            tertiary.opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.90)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(darkenOpacity))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.10), .white.opacity(0.03), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)
                .opacity(sheenOpacity)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(strokeOpacity), lineWidth: 1)

            content.padding(14)
        }
    }
}

struct RegularPopoverBackdrop: View {
    let tint: Color
    let palette: [Color]
    let artwork: NSImage?

    var body: some View {
        ZStack {
            tint.opacity(0.10)

            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .saturation(1.04)
                    .blur(radius: 52)
                    .scaleEffect(1.10)
                    .opacity(0.14)
            }
        }
    }
}

struct OuterCardBleedMask: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black)
                .padding(7)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}
