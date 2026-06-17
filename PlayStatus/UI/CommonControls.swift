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

struct EmptyArtworkPlaceholderView: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)

            ZStack {
                LinearGradient(
                    colors: [.white.opacity(0.08), .black.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ProviderIconView(
                    icon: .appleMusic,
                    size: max(36, side * 0.20),
                    weight: .semibold
                )
                .foregroundStyle(.secondary.opacity(0.95))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct ControlsRow: View {
    let isPlaying: Bool
    let isShuffleEnabled: Bool
    let repeatMode: PlaybackRepeatMode
    let controlsEnabled: Bool
    let onShuffle: () -> Void
    let onPrev: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onRepeat: () -> Void
    var contrastBoost: Double = 0
    var controlScale: CGFloat = 1

    private var clampedControlScale: CGFloat {
        min(max(controlScale, 0.80), 1.20)
    }

    var body: some View {
        HStack(spacing: 8 * clampedControlScale) {
            GlassButton(
                systemName: "shuffle",
                compact: true,
                isActive: isShuffleEnabled,
                isEnabled: controlsEnabled,
                helpText: isShuffleEnabled ? "Turn shuffle off" : "Turn shuffle on",
                contrastBoost: contrastBoost,
                sizeScale: clampedControlScale,
                action: onShuffle
            )
            GlassButton(
                systemName: "backward.fill",
                isEnabled: controlsEnabled,
                helpText: "Previous track",
                contrastBoost: contrastBoost,
                sizeScale: clampedControlScale,
                action: onPrev
            )
            GlassButton(
                systemName: isPlaying ? "pause.fill" : "play.fill",
                isPrimary: true,
                isEnabled: controlsEnabled,
                helpText: isPlaying ? "Pause" : "Play",
                contrastBoost: contrastBoost,
                sizeScale: clampedControlScale,
                action: onPlayPause
            )
            GlassButton(
                systemName: "forward.fill",
                isEnabled: controlsEnabled,
                helpText: "Next track",
                contrastBoost: contrastBoost,
                sizeScale: clampedControlScale,
                action: onNext
            )
            GlassButton(
                systemName: repeatMode.systemImageName,
                compact: true,
                isActive: repeatMode.isEnabled,
                isEnabled: controlsEnabled,
                helpText: repeatMode == .off ? "Turn repeat on" : repeatMode.displayName,
                contrastBoost: contrastBoost,
                sizeScale: clampedControlScale,
                action: onRepeat
            )
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

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8 * clampedControlScale, weight: .bold))
                        .opacity(0.78)
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
            .menuIndicator(.hidden)
            .tint(controlForeground.opacity(0.90))
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
                    .onChange(of: favoritePulseToken) { _, _ in
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
    var isActive: Bool = false
    var isEnabled: Bool = true
    var helpText: String? = nil
    var contrastBoost: Double = 0
    var sizeScale: CGFloat = 1
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    private var clampedContrastBoost: Double {
        min(max(contrastBoost, 0), 1)
    }

    private var iconColor: Color {
        isActive ? Color(red: 0.68, green: 0.88, blue: 1.0) : Color.white
    }

    private var fillOpacity: Double {
        let base = isPrimary ? 0.13 : 0.08
        let activeBoost = isActive ? 0.10 : 0
        return min(0.46, base + activeBoost + (0.20 * clampedContrastBoost))
    }

    private var strokeOpacity: Double {
        let base = isPrimary ? 0.18 : 0.12
        let activeBoost = isActive ? 0.12 : 0
        return min(0.38, base + activeBoost + (0.08 * clampedContrastBoost))
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
        .disabled(!isEnabled)
        .foregroundStyle(iconColor.opacity(isPrimary ? 0.98 : 0.92))
        .background(
            ZStack {
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
        .opacity(isEnabled ? 1 : 0.46)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isPressed)
        .animation(.easeInOut(duration: 0.16), value: isActive)
        .animation(.easeInOut(duration: 0.16), value: isEnabled)
        .onHover { hovering in
            guard isEnabled else {
                if isHovering {
                    withAnimation(.easeOut(duration: 0.15)) { isHovering = false }
                }
                return
            }
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled else { return }
                    isPressed = true
                }
                .onEnded { _ in isPressed = false }
        )
        .help(helpText ?? "")
    }
}

struct ProgressBlock: View {
    let progress: Double
    let elapsed: Double
    let duration: Double
    let canSeek: Bool
    var contrastBoost: Double = 0
    let onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var railHovering = false

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

    private var railInteractionActive: Bool {
        canSeek && (railHovering || isDragging)
    }

    private var railHeight: CGFloat {
        railInteractionActive ? 10 : 7
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let resolvedProgress = isDragging ? dragValue : progress

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(railBaseOpacity))
                    Capsule().fill(.white.opacity(railFillOpacity))
                        .frame(width: max(6, width * CGFloat(min(max(resolvedProgress, 0), 1))))
                        .blendMode(.screen)
                }
                .frame(height: railHeight)
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard canSeek else {
                        railHovering = false
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.14)) {
                        railHovering = hovering
                    }
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard canSeek else { return }
                            isDragging = true
                            let x = min(max(0, value.location.x), width)
                            dragValue = Double(x / width)
                        }
                        .onEnded { _ in
                            guard canSeek else { return }
                            isDragging = false
                            onSeek(dragValue)
                        }
                )
            }
            .frame(height: railHeight)
            .opacity(canSeek ? 1.0 : 0.55)
            .animation(.easeInOut(duration: 0.14), value: railInteractionActive)
            .background(
                DetachedWindowDragLockBridge(locked: railInteractionActive)
                    .frame(width: 0, height: 0)
            )

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
        let roundedSeconds = Int(seconds.rounded())
        return String(format: "%d:%02d", roundedSeconds / 60, roundedSeconds % 60)
    }
}
