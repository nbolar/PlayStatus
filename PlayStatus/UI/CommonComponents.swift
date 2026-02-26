import SwiftUI
import AppKit
import AVFoundation

struct ProviderIconView: View {
    let icon: ProviderIconKind
    var size: CGFloat
    var weight: Font.Weight = .semibold

    var body: some View {
        Group {
            switch icon {
            case .sfSymbol(let systemName):
                Image(systemName: systemName)
                    .font(.system(size: size, weight: weight))
                    .symbolRenderingMode(.hierarchical)
            case .iconifyAsset(let assetName):
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size, alignment: .center)
    }
}

struct ProviderBadge: View {
    let provider: NowPlayingProvider
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 6) {
            ProviderIconView(icon: provider.iconKind, size: 11, weight: .semibold)

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
    var controlScale: CGFloat = 1

    private var clampedControlScale: CGFloat {
        min(max(controlScale, 0.80), 1.20)
    }

    var body: some View {
        HStack(spacing: 10 * clampedControlScale) {
            GlassButton(systemName: "backward.fill", contrastBoost: contrastBoost, sizeScale: clampedControlScale, action: onPrev)
            GlassButton(systemName: isPlaying ? "pause.fill" : "play.fill", isPrimary: true, contrastBoost: contrastBoost, sizeScale: clampedControlScale, action: onPlayPause)
            GlassButton(systemName: "forward.fill", contrastBoost: contrastBoost, sizeScale: clampedControlScale, action: onNext)
        }
    }
}

struct OutputControlsRow: View {
    @ObservedObject var model: NowPlayingModel
    let showDeviceName: Bool
    var contrastBoost: Double = 0
    var controlScale: CGFloat = 1
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

    private var clampedControlScale: CGFloat {
        min(max(controlScale, 0.80), 1.20)
    }

    var body: some View {
        HStack(spacing: 8 * clampedControlScale) {
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
                HStack(spacing: 5 * clampedControlScale) {
                    Image(systemName: "hifispeaker.fill")
                        .font(.system(size: 10 * clampedControlScale, weight: .semibold))
//                    if showDeviceName {
//                        Text(selectedDeviceName)
//                            .lineLimit(1)
//                            .truncationMode(.tail)
//                    }
                }
                .font(.system(size: 10 * clampedControlScale, weight: .semibold, design: .rounded))
                .foregroundStyle(controlForeground.opacity(0.90))
                .padding(.horizontal, 8 * clampedControlScale)
                .padding(.vertical, 5 * clampedControlScale)
                .frame(maxWidth: showDeviceName ? (168 * clampedControlScale) : nil, alignment: .leading)
                .background(Capsule().fill(Color.primary.opacity(controlFillOpacity)))
                .overlay(Capsule().stroke(.white.opacity(controlStrokeOpacity), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)

            Button {
                model.toggleOutputMute()
            } label: {
                Image(systemName: model.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10 * clampedControlScale, weight: .semibold))
                    .frame(width: 22 * clampedControlScale, height: 22 * clampedControlScale)
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
            .frame(minWidth: 84 * clampedControlScale, maxWidth: .infinity)
            .tint(controlForeground.opacity(0.88))
            .opacity(model.outputMuted ? 0.55 : 1.0)

            if showFavorite, let onFavorite {
                GlassButton(
                    systemName: favoriteIsActive ? "heart.fill" : "heart",
                    compact: true,
                    contrastBoost: contrastBoost,
                    sizeScale: clampedControlScale,
                    action: onFavorite
                )
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
    var sizeScale: CGFloat = 1
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

    private var clampedSizeScale: CGFloat {
        min(max(sizeScale, 0.80), 1.20)
    }

    private var iconSize: CGFloat {
        (compact ? 12 : 13) * clampedSizeScale
    }

    private var buttonWidth: CGFloat {
        (compact ? 30 : (isPrimary ? 40 : 32)) * clampedSizeScale
    }

    private var buttonHeight: CGFloat {
        (compact ? 26 : (isPrimary ? 32 : 28)) * clampedSizeScale
    }

    private var cornerRadius: CGFloat {
        (compact ? 10 : 12) * clampedSizeScale
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: buttonWidth, height: buttonHeight)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(iconColor.opacity(isPrimary ? 0.98 : 0.92))
        .background(
            ZStack {
                // macOS 26: avoid system materials (.ultraThinMaterial/.thinMaterial) inside
                // NSHostingController — they trigger DesignLibrary glass compositor on every
                // SwiftUI re-render, causing recursive stack overflow. Use plain fills instead.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(fillOpacity))

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.18 * clampedContrastBoost))

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(highlightOpacity), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.plusLighter)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
    let isPlaying: Bool
    let hasAnimatedStream: Bool
    let tint: Color
    let artworkImage: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hovering = false
    @State private var pointerLocation: CGPoint = .zero
    @State private var viewSize: CGSize = .zero
    @State private var filmDriftPhase = false
    @State private var vinylBaseTurns: Double = 0
    @State private var vinylSpinStartDate: Date? = nil
    @State private var wasVinylSpinning = false

    private let vinylRotationDuration: Double = 12.0
    private let filmDriftDuration: Double = 7.6

    private var parallaxEnabled: Bool {
        isEnabled && style == .parallaxByPointer && !reduceMotion
    }

    private var shouldSpinVinyl: Bool {
        isEnabled &&
            style == .vinylSpin &&
            isPlaying &&
            !hasAnimatedStream &&
            !reduceMotion
    }

    private var shouldAnimateFilmDrift: Bool {
        isEnabled &&
            style == .filmGrainDrift &&
            isPlaying &&
            !reduceMotion
    }

    private var filmGrainOpacity: Double {
        let base: Double
        if reduceMotion {
            base = 0.08
        } else if isPlaying {
            base = 0.17
        } else {
            base = 0.11
        }
        return hasAnimatedStream ? (base * 0.58) : base
    }

    private var filmDriftOffsetPrimary: CGSize {
        guard shouldAnimateFilmDrift else { return .zero }
        let amplitude: CGFloat = hasAnimatedStream ? 6 : 12
        let x = filmDriftPhase ? amplitude : -amplitude
        let y = filmDriftPhase ? (-amplitude * 0.72) : (amplitude * 0.72)
        return CGSize(width: x, height: y)
    }

    private var filmDriftOffsetSecondary: CGSize {
        let primary = filmDriftOffsetPrimary
        return CGSize(width: -primary.width * 0.62, height: primary.height * 0.48)
    }

    private var centeredPointerX: CGFloat {
        guard viewSize.width > 0 else { return 0 }
        return (pointerLocation.x / viewSize.width) - 0.5
    }

    private var centeredPointerY: CGFloat {
        guard viewSize.height > 0 else { return 0 }
        return (pointerLocation.y / viewSize.height) - 0.5
    }

    private var parallaxScale: CGFloat {
        guard parallaxEnabled, hovering else { return 1.0 }
        return 1.018
    }

    private var parallaxOffset: CGSize {
        guard parallaxEnabled else { return .zero }
        let x = centeredPointerX * 14
        let y = centeredPointerY * 12
        return CGSize(width: x, height: y)
    }

    private var parallaxTiltX: Double {
        guard parallaxEnabled else { return 0 }
        return Double(-centeredPointerY * 9)
    }

    private var parallaxTiltY: Double {
        guard parallaxEnabled else { return 0 }
        return Double(centeredPointerX * 11)
    }

    private var filmDriftScale: CGFloat {
        guard shouldAnimateFilmDrift else { return 1.0 }
        return filmDriftPhase ? 1.06 : 1.0
    }

    private var artworkSide: CGFloat {
        max(0, min(viewSize.width, viewSize.height))
    }

    private var vinylDiscDiameter: CGFloat {
        artworkSide * 0.98
    }

    private var vinylCenterLabelDiameter: CGFloat {
        vinylDiscDiameter * 0.82
    }

    private var vinylLabelRingWidth: CGFloat {
        max(1.6, vinylCenterLabelDiameter * 0.055)
    }

    private var vinylHubHoleDiameter: CGFloat {
        vinylCenterLabelDiameter * 0.13
    }

    private var vinylGrooveWidth: CGFloat {
        max(1.4, vinylDiscDiameter * 0.034)
    }

    private var filmDriftAnimation: Animation {
        .linear(duration: filmDriftDuration).repeatForever(autoreverses: true)
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
            .scaleEffect(parallaxScale)
            .offset(
                x: parallaxOffset.width,
                y: parallaxOffset.height
            )
            .rotation3DEffect(.degrees(parallaxTiltX), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(parallaxTiltY), axis: (x: 0, y: 1, z: 0))
            .overlay {
                if style == .vinylSpin && isEnabled && !hasAnimatedStream && artworkSide > 1 {
                    ZStack {
                        // Translucent background (no artwork outside the disc)
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.black.opacity(0.95))

                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(0.16),
                                        .black.opacity(0.22),
                                        .white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.screen)
                            .opacity(0.62)

                        TimelineView(.periodic(from: Date(), by: 1.0 / 60.0)) { context in
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.black.opacity(0.94),
                                                Color.black.opacity(0.74),
                                                Color.black.opacity(0.92)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )

                                Circle()
                                    .stroke(.white.opacity(0.14), lineWidth: 1.1)

                                Circle()
                                    .stroke(tint.opacity(0.18), lineWidth: 1.2)

                                Circle()
                                    .trim(from: 0.03, to: 0.97)
                                    .stroke(
                                        Color.black.opacity(0.38),
                                        style: StrokeStyle(
                                            lineWidth: vinylGrooveWidth,
                                            lineCap: .round
                                        )
                                    )

                                Circle()
                                    .trim(from: 0.08, to: 0.92)
                                    .stroke(
                                        .white.opacity(0.08),
                                        style: StrokeStyle(
                                            lineWidth: vinylGrooveWidth * 0.42,
                                            lineCap: .round
                                        )
                                    )

                                Circle()
                                    .fill(.white.opacity(0.08))
                                    .blur(radius: vinylDiscDiameter * 0.10)
                                    .scaleEffect(0.72)
                                    .offset(x: -vinylDiscDiameter * 0.14, y: -vinylDiscDiameter * 0.14)
                                    .blendMode(.screen)

                                Group {
                                    if let artworkImage {
                                        Image(nsImage: artworkImage)
                                            .resizable()
                                            .interpolation(.high)
                                            .scaledToFill()
                                    } else {
                                        LinearGradient(
                                            colors: [tint.opacity(0.58), .black.opacity(0.50)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    }
                                }
                                .frame(width: vinylCenterLabelDiameter, height: vinylCenterLabelDiameter)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(.white.opacity(0.26), lineWidth: 1.0)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.34), lineWidth: vinylLabelRingWidth)
                                )

                                Circle()
                                    .fill(Color.black.opacity(0.92))
                                    .frame(width: vinylHubHoleDiameter, height: vinylHubHoleDiameter)

                                Circle()
                                    .fill(.white.opacity(0.26))
                                    .frame(width: vinylHubHoleDiameter * 0.42, height: vinylHubHoleDiameter * 0.42)
                            }
                            .frame(width: vinylDiscDiameter, height: vinylDiscDiameter)
                            .rotationEffect(.degrees(vinylRotationDegrees(at: context.date)))
                            .opacity(shouldSpinVinyl ? 0.99 : 0.94)
                        }
                        .frame(width: vinylDiscDiameter, height: vinylDiscDiameter)
                    }
                    .frame(width: artworkSide, height: artworkSide)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                if style == .filmGrainDrift && isEnabled {
                    ZStack {
                        Image(nsImage: FilmGrainTexture.image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                            .scaleEffect(filmDriftScale)
                            .offset(filmDriftOffsetPrimary)
                            .opacity(filmGrainOpacity)
                            .blendMode(.overlay)

                        Image(nsImage: FilmGrainTexture.image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                            .scaleEffect(filmDriftScale * 1.03)
                            .offset(filmDriftOffsetSecondary)
                            .opacity(filmGrainOpacity * 0.58)
                            .blendMode(.softLight)

                        LinearGradient(
                            colors: [
                                .white.opacity(filmDriftPhase ? 0.06 : 0.03),
                                .clear,
                                .black.opacity(filmDriftPhase ? 0.05 : 0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .blendMode(.overlay)
                        .opacity(reduceMotion ? 0.22 : 0.34)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
            .animation(filmDriftAnimation, value: filmDriftPhase)
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
                if pointerLocation == .zero {
                    pointerLocation = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                }
                synchronizeAnimationState(allowVinylSettle: false)
            }
            .onDisappear {
                stopVinylMotion(allowSettle: false)
            }
            .onChange(of: style) { _ in
                if style == .vinylSpin, vinylSpinStartDate == nil {
                    vinylSpinStartDate = Date()
                    wasVinylSpinning = true
                }
                synchronizeAnimationState(allowVinylSettle: false)
            }
            .onChange(of: isEnabled) { enabled in
                if !enabled {
                    hovering = false
                }
                synchronizeAnimationState(allowVinylSettle: false)
            }
            .onChange(of: isPlaying) { _ in
                synchronizeAnimationState(allowVinylSettle: true)
            }
            .onChange(of: hasAnimatedStream) { _ in
                synchronizeAnimationState(allowVinylSettle: true)
            }
            .onChange(of: reduceMotion) { _ in
                synchronizeAnimationState(allowVinylSettle: false)
            }
            .onChange(of: shouldSpinVinyl) { shouldSpin in
                if shouldSpin {
                    if vinylSpinStartDate == nil {
                        vinylSpinStartDate = Date()
                    }
                    wasVinylSpinning = true
                } else {
                    stopVinylMotion(allowSettle: true)
                }
            }
    }

    private func synchronizeAnimationState(allowVinylSettle: Bool) {
        if shouldSpinVinyl {
            if vinylSpinStartDate == nil {
                vinylSpinStartDate = Date()
            }
            wasVinylSpinning = true
        } else {
            stopVinylMotion(allowSettle: allowVinylSettle)
        }

        if shouldAnimateFilmDrift {
            filmDriftPhase = true
        } else {
            filmDriftPhase = false
        }
    }

    private func vinylRotationDegrees(at date: Date) -> Double {
        vinylTurns(at: date) * 360
    }

    private func vinylTurns(at date: Date) -> Double {
        guard shouldSpinVinyl, let startDate = vinylSpinStartDate else {
            return vinylBaseTurns
        }
        let elapsed = max(0, date.timeIntervalSince(startDate))
        return vinylBaseTurns + (elapsed / vinylRotationDuration)
    }

    private func stopVinylMotion(allowSettle: Bool) {
        if let startDate = vinylSpinStartDate {
            let elapsed = max(0, Date().timeIntervalSince(startDate))
            vinylBaseTurns += elapsed / vinylRotationDuration
            vinylSpinStartDate = nil
        }
        if wasVinylSpinning && allowSettle {
            withAnimation(.easeOut(duration: 0.85)) {
                vinylBaseTurns += 0.08
            }
        }
        wasVinylSpinning = false
    }
}

private enum FilmGrainTexture {
    static let image: NSImage = {
        let width = 192
        let height = 192
        let fallback = NSImage(size: NSSize(width: 1, height: 1))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ), let bytes = bitmap.bitmapData else {
            return fallback
        }

        var state: UInt64 = 0xA24BAED4963EE407
        func nextByte(state: inout UInt64) -> UInt8 {
            state = state &* 6364136223846793005 &+ 1
            return UInt8((state >> 33) & 0xFF)
        }

        for y in 0..<height {
            for x in 0..<width {
                let index = ((y * width) + x) * 4
                let value = Int(nextByte(state: &state))
                let grain = UInt8(min(255, max(0, value + (value > 127 ? 22 : -18))))
                bytes[index] = grain
                bytes[index + 1] = grain
                bytes[index + 2] = grain
                bytes[index + 3] = 180
            }
        }

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }()
}

extension View {
    func animatedArtworkMotion(
        isEnabled: Bool,
        seed: String,
        style: ArtworkMotionStyle,
        isPlaying: Bool,
        hasAnimatedStream: Bool,
        tint: Color = .white,
        artworkImage: NSImage? = nil
    ) -> some View {
        modifier(
            ArtworkMotionModifier(
                isEnabled: isEnabled,
                seed: seed,
                style: style,
                isPlaying: isPlaying,
                hasAnimatedStream: hasAnimatedStream,
                tint: tint,
                artworkImage: artworkImage
            )
        )
        .id("motion|\(seed)|\(style.rawValue)|\(isEnabled ? 1 : 0)|\(hasAnimatedStream ? 1 : 0)")
    }
}

struct AnimatedArtworkView: View {
    let image: NSImage?
    let tint: Color
    let isEnabled: Bool
    let seed: String
    let style: ArtworkMotionStyle
    let animatedArtworkURL: URL?
    let animatedArtworkIsVisible: Bool
    var body: some View {
        ArtworkView(
            image: image,
            tint: tint,
            animatedArtworkURL: animatedArtworkURL,
            animatedArtworkIsVisible: animatedArtworkIsVisible
        )
            .animatedArtworkMotion(
                isEnabled: isEnabled,
                seed: seed,
                style: style,
                isPlaying: true,
                hasAnimatedStream: animatedArtworkURL != nil,
                tint: tint,
                artworkImage: image
            )
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let tint: Color
    let animatedArtworkURL: URL?
    let animatedArtworkIsVisible: Bool
    @State private var streamReadyForDisplay = false
    private let streamCrossfadeDuration: Double = 2.8

    private var streamCrossfadeAnimation: Animation {
        .easeInOut(duration: streamCrossfadeDuration)
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let contentSide = side - 12
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
                    ZStack {
                        staticArtworkContent(side: contentSide)

                        if let animatedArtworkURL {
                            AnimatedArtworkPlayerView(
                                streamURL: animatedArtworkURL,
                                isActive: animatedArtworkIsVisible,
                                onRenderReadinessChanged: { isReady in
                                    guard isReady != streamReadyForDisplay else { return }
                                    withAnimation(streamCrossfadeAnimation) {
                                        streamReadyForDisplay = isReady
                                    }
                                }
                            )
                            .frame(width: contentSide, height: contentSide)
                            .opacity(streamReadyForDisplay ? 1 : 0)
                        }
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
            .onChange(of: animatedArtworkURL) { _ in
                withAnimation(streamCrossfadeAnimation) {
                    streamReadyForDisplay = false
                }
            }
        }
        .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 10)
    }

    @ViewBuilder
    private func staticArtworkContent(side: CGFloat) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: side, height: side)
                .background(tint.opacity(0.12))
        } else {
            ZStack {
                LinearGradient(
                    colors: [.white.opacity(0.08), .black.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                ProviderIconView(icon: .appleMusic, size: 36, weight: .semibold)
                    .foregroundStyle(.secondary.opacity(0.95))
            }
            .frame(width: side, height: side)
        }
    }
}

struct AnimatedArtworkPlayerView: View {
    let streamURL: URL
    let isActive: Bool
    var onRenderReadinessChanged: (Bool) -> Void = { _ in }

    var body: some View {
        AnimatedArtworkPlayerRepresentable(
            streamURL: streamURL,
            isActive: isActive,
            onRenderReadinessChanged: onRenderReadinessChanged
        )
            .background(Color.black.opacity(0.08))
    }
}

private struct AnimatedArtworkPlayerRepresentable: NSViewRepresentable {
    let streamURL: URL
    let isActive: Bool
    let onRenderReadinessChanged: (Bool) -> Void

    func makeNSView(context: Context) -> AnimatedArtworkPlayerContainerView {
        AnimatedArtworkPlayerContainerView()
    }

    func updateNSView(_ nsView: AnimatedArtworkPlayerContainerView, context: Context) {
        nsView.configure(
            streamURL: streamURL,
            isActive: isActive,
            onRenderReadinessChanged: onRenderReadinessChanged
        )
    }

    static func dismantleNSView(_ nsView: AnimatedArtworkPlayerContainerView, coordinator: ()) {
        nsView.reset()
    }
}

private final class AnimatedArtworkPlayerContainerView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var layerReadinessObservation: NSKeyValueObservation?
    private var onRenderReadinessChanged: ((Bool) -> Void)?
    private var hasReportedReadyForDisplay = false
    private var shouldBePlaying = false
    private var startedPlaybackForCurrentItem = false
    private var lastNotifiedReadiness: Bool?
    private var currentURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    deinit {
        teardownPlayer(shouldNotify: false)
    }

    func configure(
        streamURL: URL,
        isActive: Bool,
        onRenderReadinessChanged: @escaping (Bool) -> Void
    ) {
        self.onRenderReadinessChanged = onRenderReadinessChanged
        shouldBePlaying = isActive
        if currentURL != streamURL || player == nil {
            setupPlayer(streamURL: streamURL)
        } else {
            notifyRenderReadiness(hasReportedReadyForDisplay)
        }

        if isActive {
            startPlaybackIfPossible()
        } else {
            player?.pause()
        }
    }

    func reset() {
        // During NSViewRepresentable dismantle, avoid mutating SwiftUI state.
        onRenderReadinessChanged = nil
        teardownPlayer(shouldNotify: false)
    }

    private func setupPlayer(streamURL: URL) {
        teardownPlayer(shouldNotify: false)
        hasReportedReadyForDisplay = false
        startedPlaybackForCurrentItem = false
        notifyRenderReadiness(false)

        let item = AVPlayerItem(url: streamURL)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true
        playerLayer.player = player
        currentURL = streamURL
        self.player = player

        itemStatusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] observedItem, _ in
            guard let self else { return }
            if observedItem.status == .failed {
                self.hasReportedReadyForDisplay = false
                self.notifyRenderReadiness(false)
            }
        }

        layerReadinessObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new, .initial]) { [weak self] layer, _ in
            guard let self else { return }
            guard layer.isReadyForDisplay else { return }
            guard !self.hasReportedReadyForDisplay else { return }
            self.hasReportedReadyForDisplay = true
            self.notifyRenderReadiness(true)
            self.startPlaybackIfPossible()
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard self.shouldBePlaying else { return }
            self.player?.seek(to: .zero)
            self.player?.play()
        }
    }

    private func teardownPlayer(shouldNotify: Bool) {
        itemStatusObservation = nil
        layerReadinessObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        hasReportedReadyForDisplay = false
        startedPlaybackForCurrentItem = false
        shouldBePlaying = false
        if shouldNotify {
            notifyRenderReadiness(false)
        } else {
            lastNotifiedReadiness = nil
        }
        player?.pause()
        playerLayer.player = nil
        player = nil
        currentURL = nil
    }

    private func notifyRenderReadiness(_ isReady: Bool) {
        guard lastNotifiedReadiness != isReady else { return }
        lastNotifiedReadiness = isReady
        let callback = onRenderReadinessChanged
        guard let callback else { return }
        DispatchQueue.main.async {
            callback(isReady)
        }
    }

    private func startPlaybackIfPossible() {
        guard shouldBePlaying else { return }
        guard hasReportedReadyForDisplay else { return }

        if startedPlaybackForCurrentItem {
            player?.play()
            return
        }

        startedPlaybackForCurrentItem = true
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            guard self.shouldBePlaying else { return }
            self.player?.play()
        }
    }
}

// MARK: - Liquid Glass background/card

struct LiquidGlassBackground: View {
    let tint: Color
    var readabilityBoost: Double = 0
    var transparencyMultiplier: Double = 1

    private var clampedTransparencyMultiplier: Double {
        min(max(transparencyMultiplier, 0.35), 2.0)
    }

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
                        colors: [
                            tint.opacity(0.10 * clampedTransparencyMultiplier),
                            tint.opacity(0.06 * clampedTransparencyMultiplier),
                            tint.opacity(0.09 * clampedTransparencyMultiplier)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(darkenOpacity * clampedTransparencyMultiplier))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.14 * clampedTransparencyMultiplier), .clear],
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
    var transparencyMultiplier: Double = 1
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
    private var clampedTransparencyMultiplier: Double {
        min(max(transparencyMultiplier, 0.35), 2.0)
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
                .opacity(0.90 * clampedTransparencyMultiplier)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(darkenOpacity * clampedTransparencyMultiplier))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.10), .white.opacity(0.03), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)
                .opacity(sheenOpacity * clampedTransparencyMultiplier)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(strokeOpacity * clampedTransparencyMultiplier), lineWidth: 1)

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
