import SwiftUI
import AppKit

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
    /// Whether the four secondary controls are at full strength.
    ///
    /// Play/pause is never dimmed — the surface always has one legible control — so callers
    /// that have no hover signal can leave this alone and get the old, always-lit row.
    var secondariesRevealed: Bool = true

    private var clampedControlScale: CGFloat {
        min(max(controlScale, 0.80), 1.20)
    }

    private var secondaryOpacity: Double {
        secondariesRevealed ? 1 : playerTransportSecondaryRestingOpacity
    }

    var body: some View {
        HStack(spacing: 8 * clampedControlScale) {
            GlassButton(
                systemName: "shuffle",
                compact: true,
                isActive: isShuffleEnabled,
                isEnabled: controlsEnabled,
                helpText: isShuffleEnabled ? "Turn shuffle off" : "Turn shuffle on",
                accessibilityTitle: "Shuffle",
                accessibilityStateValue: isShuffleEnabled ? "On" : "Off",
                contrastBoost: contrastBoost,
                sizeScale: clampedControlScale,
                action: onShuffle
            )
            .opacity(secondaryOpacity)
            GlassButton(
                systemName: "backward.fill",
                isEnabled: controlsEnabled,
                helpText: "Previous track",
                contrastBoost: contrastBoost,
                sizeScale: clampedControlScale,
                action: onPrev
            )
            .opacity(secondaryOpacity)
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
            .opacity(secondaryOpacity)
            GlassButton(
                systemName: repeatMode.systemImageName,
                compact: true,
                isActive: repeatMode.isEnabled,
                isEnabled: controlsEnabled,
                helpText: repeatMode == .off ? "Turn repeat on" : repeatMode.displayName,
                accessibilityTitle: "Repeat",
                accessibilityStateValue: repeatMode == .off ? "Off" : repeatMode.displayName,
                contrastBoost: contrastBoost,
                sizeScale: clampedControlScale,
                action: onRepeat
            )
            .opacity(secondaryOpacity)
        }
        .animation(.easeInOut(duration: 0.18), value: secondariesRevealed)
    }
}

struct OutputControlsRow: View {
    @ObservedObject var model: NowPlayingModel
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

    /// The output menu and mute button are bare glyphs now, in the same register as the
    /// transport. They used to be a stroked capsule and a stroked circle, which made the
    /// quietest row on the surface look like the busiest.
    private var controlGlyphOpacity: Double {
        min(0.78, 0.58 + (0.14 * clampedContrastBoost))
    }

    private var clampedControlScale: CGFloat {
        min(max(controlScale, 0.80), 1.20)
    }

    private var selectedOutputDeviceName: String {
        model.availableOutputDevices
            .first { $0.id == model.selectedOutputDeviceID }?
            .name ?? "System default"
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
                // One legible glyph instead of a 11pt speaker plus a 7pt chevron, which at
                // that size read as an ambiguous little box. The chevron is gone — a menu
                // announces itself when you press it — and the device name is on hover.
                Image(systemName: "hifispeaker.fill")
                    .font(.system(size: 13 * clampedControlScale, weight: .semibold))
                    .foregroundStyle(controlForeground.opacity(controlGlyphOpacity))
                    .frame(width: 22 * clampedControlScale, height: 22 * clampedControlScale)
                    .contentShape(Rectangle())
            }
            .hoverHint(selectedOutputDeviceName)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(controlForeground.opacity(0.90))
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Output device"))
            .accessibilityValue(Text(selectedOutputDeviceName))
            // Menu derives a wide ideal width from its item content. Keep its
            // hit target aligned to the icon control so it cannot consume the
            // volume slider's lane in compact player surfaces.
            .fixedSize(horizontal: true, vertical: false)

            Button {
                model.toggleOutputMute()
            } label: {
                Image(systemName: model.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11 * clampedControlScale, weight: .semibold))
                    .frame(width: 22 * clampedControlScale, height: 22 * clampedControlScale)
                    .contentShape(Circle())
                    .foregroundStyle(controlForeground.opacity(model.outputMuted ? 0.44 : controlGlyphOpacity))
            }
            .buttonStyle(.plain)
            .help(model.outputMuted ? "Unmute" : "Mute")
            .accessibilityLabel(Text("Mute"))
            .accessibilityValue(Text(model.outputMuted ? "On" : "Off"))

            // The same rail the progress bar uses, rather than a stock `Slider` with a
            // permanent knob — the two sit one row apart and were speaking different
            // languages. Volume follows the pointer, so it updates continuously.
            PlayerRail(
                value: model.outputVolume,
                contrastBoost: contrastBoost,
                updatesContinuously: true,
                onScrub: { model.setOutputVolume($0) }
            )
            .frame(minWidth: 84 * clampedControlScale, maxWidth: .infinity)
            .layoutPriority(1)
            .opacity(model.outputMuted ? 0.55 : 1.0)
            .accessibilityElement()
            .accessibilityLabel(Text("Output volume"))
            .accessibilityValue(Text("\(Int((model.outputVolume * 100).rounded())) percent"))
            .accessibilityAdjustableAction { direction in
                let step = 0.05
                switch direction {
                case .increment:
                    model.setOutputVolume(min(1, model.outputVolume + step))
                case .decrement:
                    model.setOutputVolume(max(0, model.outputVolume - step))
                @unknown default:
                    break
                }
            }

            if showFavorite, let onFavorite {
                GlassButton(
                    systemName: favoriteIsActive ? "heart.fill" : "heart",
                    compact: true,
                    isActive: favoriteIsActive,
                    activeColor: Color(red: 0.94, green: 0.36, blue: 0.38),
                    helpText: favoriteIsActive ? "Remove from Favorites" : "Add to Favorites",
                    accessibilityTitle: "Favorite",
                    accessibilityStateValue: favoriteIsActive ? "On" : "Off",
                    contrastBoost: contrastBoost,
                    sizeScale: clampedControlScale,
                    action: onFavorite
                )
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
    var activeColor: Color = Color(red: 0.68, green: 0.88, blue: 1.0)
    var isEnabled: Bool = true
    var helpText: String? = nil
    /// The control's stable name for VoiceOver. Without it an icon-only button falls back to
    /// its SF Symbol name — "backward fill", "forward fill" — which is what these announced
    /// before, since `helpText` only ever reached the tooltip.
    ///
    /// Kept separate from `helpText` because a tooltip describes the *action* and changes
    /// with state ("Turn shuffle on" / "Turn shuffle off"), whereas a name must not: the
    /// state belongs in `accessibilityStateValue`.
    var accessibilityTitle: String? = nil
    var accessibilityStateValue: String? = nil
    var contrastBoost: Double = 0
    var sizeScale: CGFloat = 1
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    /// Only the play button gets a shape.
    ///
    /// Every transport control used to be a filled, stroked rounded rect, so nine of them
    /// on one surface left the eye with no primary — the play button was 8pt wider than
    /// its neighbours and that was the whole hierarchy. Now the secondary controls are
    /// bare glyphs that pick up a faint fill on hover, and play is a solid white squircle
    /// with a dark glyph: the one filled control in the window.
    private var iconColor: Color {
        if isPrimary { return Color(red: 0.10, green: 0.09, blue: 0.09) }
        return isActive ? activeColor : Color.white
    }

    private var iconOpacity: Double {
        if isPrimary { return 1 }
        if isActive { return 0.96 }
        return isHovering ? 0.96 : 0.72
    }

    private var primaryFillOpacity: Double {
        isHovering ? 1.0 : 0.94
    }

    /// An "on" control used to wear a filled disc, which made shuffle-on the most saturated
    /// object on the surface — louder than the play button, which is the actual primary. On
    /// state is carried by the glyph's tint plus a dot beneath it instead; the disc is now
    /// only ever a hover affordance.
    private var hoverDiscOpacity: Double {
        guard !isPrimary else { return 0 }
        return isHovering ? 0.12 : 0
    }

    private var dotSize: CGFloat { 3 * clampedSizeScale }

    /// The transport is squircles, not circles.
    ///
    /// A filled disc is what every macOS media control looks like, so the play button read
    /// as generic chrome dropped onto the artwork. Continuous corners at roughly a third of
    /// the side put it in the same radius family as the app icon and the artwork tile it
    /// sits under, which is the only other geometry on this surface.
    ///
    /// Secondaries follow at a proportionally tighter radius so the hover disc does not
    /// disagree with the shape it appears next to.
    private var cornerRadius: CGFloat {
        buttonSide * (isPrimary ? 0.34 : 0.28)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var clampedSizeScale: CGFloat {
        min(max(sizeScale, 0.80), 1.20)
    }

    private var iconSize: CGFloat {
        (compact ? 12 : (isPrimary ? 15 : 14)) * clampedSizeScale
    }

    private var buttonSide: CGFloat {
        (compact ? 26 : (isPrimary ? 38 : 30)) * clampedSizeScale
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: isPrimary ? .bold : .semibold))
                .frame(width: buttonSide, height: buttonSide)
                // State in form as well as colour, so "on" survives a colourblind reading.
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(activeColor)
                        .frame(width: dotSize, height: dotSize)
                        .opacity(isActive && !isPrimary ? 1 : 0)
                        .offset(y: -1)
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(iconColor.opacity(iconOpacity))
        .background(
            ZStack {
                if isPrimary {
                    shape
                        .fill(.white.opacity(primaryFillOpacity))
                        .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 2)
                } else {
                    shape
                        .fill((isActive ? activeColor : .white).opacity(hoverDiscOpacity))
                }
            }
        )
        .opacity(isEnabled ? 1 : 0.40)
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
        .accessibilityLabel(Text(accessibilityTitle ?? helpText ?? systemName))
        .accessibilityValue(Text(accessibilityStateValue ?? ""))
    }
}

/// The one rail in the app.
///
/// Playback position and output volume sat side by side as two different objects — a custom
/// hairline capsule above a stock `Slider` — which made the volume row the least considered
/// thing in a window where everything else had been stripped back. One view now draws both, so
/// they cannot drift apart again.
///
/// Thin at rest, thicker with a knob under the pointer: a readout most of the time, a control
/// only while you are aiming at it.
struct PlayerRail: View {
    let value: Double
    var isEnabled: Bool = true
    var contrastBoost: Double = 0
    /// Volume follows the pointer; seeking commits on release so the track does not scrub
    /// through every intermediate position.
    var updatesContinuously: Bool = false
    /// Applied to `value` changes so a rail whose value advances on its own can glide rather
    /// than step. Left nil by rails that only move when the user moves them, like volume.
    var advanceAnimation: Animation? = nil
    /// Changes exactly when `value` is refreshed, giving `.animation(_:value:)` something
    /// stable to trigger on.
    var advanceEpoch: Int = 0
    let onScrub: (Double) -> Void
    var onInteractionChanged: ((Bool) -> Void)? = nil

    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var hovering = false

    private var clampedContrastBoost: Double {
        min(max(contrastBoost, 0), 1)
    }

    private var baseOpacity: Double {
        min(0.30, 0.14 + (0.12 * clampedContrastBoost))
    }

    private var fillOpacity: Double {
        min(0.95, 0.86 + (0.09 * clampedContrastBoost))
    }

    private var interactionActive: Bool {
        isEnabled && (hovering || isDragging)
    }

    private var railHeight: CGFloat {
        interactionActive ? 8 : 4
    }

    /// The drawn capsule is centred in this lane and the whole lane is the hit target, so
    /// thinning the rail did not shrink the thing you have to hit.
    private let laneHeight: CGFloat = 14

    private var knobDiameter: CGFloat { 12 }

    private var resolvedValue: Double {
        min(max(isDragging ? dragValue : value, 0), 1)
    }

    /// Never animate under the pointer: a drag must track the cursor exactly, and a glide
    /// toward a projected position would fight it.
    private var resolvedAdvanceAnimation: Animation? {
        isDragging ? nil : advanceAnimation
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let filled = width * CGFloat(resolvedValue)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(baseOpacity))
                Capsule()
                    .fill(.white.opacity(fillOpacity))
                    .frame(width: max(railHeight, filled))
                    .animation(resolvedAdvanceAnimation, value: advanceEpoch)
            }
            .frame(height: railHeight)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.32), radius: 3, x: 0, y: 1)
                    .frame(width: knobDiameter, height: knobDiameter)
                    .offset(x: min(max(filled - (knobDiameter / 2), 0), max(0, width - knobDiameter)))
                    // Same animation as the fill, or the knob would lag behind its own rail.
                    .animation(resolvedAdvanceAnimation, value: advanceEpoch)
                    .opacity(interactionActive ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .frame(height: laneHeight)
            .contentShape(Rectangle())
            .onHover { isInside in
                guard isEnabled else {
                    hovering = false
                    return
                }
                withAnimation(.easeInOut(duration: 0.14)) {
                    hovering = isInside
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled, width > 0 else { return }
                        isDragging = true
                        let x = min(max(0, gesture.location.x), width)
                        dragValue = Double(x / width)
                        if updatesContinuously {
                            onScrub(dragValue)
                        }
                    }
                    .onEnded { _ in
                        guard isEnabled else { return }
                        isDragging = false
                        onScrub(dragValue)
                    }
            )
        }
        .frame(height: laneHeight)
        .opacity(isEnabled ? 1.0 : 0.55)
        .animation(.easeInOut(duration: 0.14), value: interactionActive)
        .onChange(of: interactionActive) { _, active in
            onInteractionChanged?(active)
        }
    }
}

struct ProgressBlock: View {
    let progress: Double
    let elapsed: Double
    let duration: Double
    let canSeek: Bool
    var contrastBoost: Double = 0
    /// Passed through to the rail so the scrubber glides between position samples.
    var advanceAnimation: Animation? = nil
    var advanceEpoch: Int = 0
    let onSeek: (Double) -> Void

    @State private var scrubPreview: Double?
    @State private var railInteractionActive = false

    private var timeColor: Color {
        Color.white
    }

    /// Time remaining rather than track length: the number you actually want mid-track.
    private var trailingTimeText: String {
        let remaining = duration - displayedElapsed
        guard duration > 0, remaining.isFinite, remaining >= 0.5 else { return formatTime(duration) }
        return "−\(formatTime(remaining))"
    }

    private var displayedElapsed: Double {
        guard let scrubPreview else { return elapsed }
        return duration * scrubPreview
    }

    var body: some View {
        VStack(spacing: 5) {
            PlayerRail(
                value: progress,
                isEnabled: canSeek,
                contrastBoost: contrastBoost,
                advanceAnimation: advanceAnimation,
                advanceEpoch: advanceEpoch,
                onScrub: { target in
                    scrubPreview = nil
                    onSeek(target)
                },
                onInteractionChanged: { active in
                    railInteractionActive = active
                }
            )
            .background(
                DetachedWindowDragLockBridge(locked: railInteractionActive)
                    .frame(width: 0, height: 0)
            )
            // Seekable without a mouse. The rail was previously invisible to VoiceOver
            // entirely — a drag gesture on an unlabelled rectangle.
            .accessibilityElement()
            .accessibilityLabel(Text("Playback position"))
            .accessibilityValue(Text("\(formatTime(elapsed)) of \(formatTime(duration))"))
            .accessibilityAdjustableAction { direction in
                guard canSeek, duration > 0 else { return }
                let step = 5.0 / duration
                switch direction {
                case .increment:
                    onSeek(min(1, progress + step))
                case .decrement:
                    onSeek(max(0, progress - step))
                @unknown default:
                    break
                }
            }

            HStack {
                Text(formatTime(displayedElapsed))
                    .frame(width: 42, alignment: .leading)
                Spacer()
                Text(trailingTimeText)
                    .frame(width: 42, alignment: .trailing)
            }
            .monospacedDigit()
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(timeColor.opacity(0.50))
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let roundedSeconds = Int(seconds.rounded())
        return String(format: "%d:%02d", roundedSeconds / 60, roundedSeconds % 60)
    }
}
