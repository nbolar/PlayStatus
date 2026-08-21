import SwiftUI
import AppKit

struct MiniNowPlayingCard: View {
    @ObservedObject var model: NowPlayingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let transitionActive: Bool
    /// True on the render pass where this card takes its artwork back from the shared
    /// morph node; the hero skips its first-appear fade so the swap is invisible.
    let handoffSettling: Bool
    let availableHeight: CGFloat
    let resolvedHeight: CGFloat
    let primaryContentVisible: Bool
    let secondaryContentVisible: Bool
    let onToggleMode: () -> Void
    @State private var pointerHovering = false
    @State private var forceExpandedUntilPointerExit = false
    @State private var showMiniLyricsPane = false
    @State private var miniLyricsHideWorkItem: DispatchWorkItem?
    @State private var settingsHovering = false

    var body: some View {
        let luminance = artworkLuminance
        let lightArtworkBoost = max(0, (luminance - 0.54) / 0.46)
        let veryLightBoost = max(0, (luminance - 0.72) / 0.28)
        let darkArtworkBoost = max(0, (0.52 - luminance) / 0.52)
        let effectiveHover = pointerHovering || forceExpandedUntilPointerExit
        let infoExpanded = effectiveHover
        let miniControlScale = model.miniControlScaleFactor
        let bottomShade = min(0.82, 0.34 + (lightArtworkBoost * 0.24) + (veryLightBoost * 0.18) + (effectiveHover ? 0.10 : 0.04))
        let topShade = min(0.34, 0.10 + (darkArtworkBoost * 0.14))
        let readabilityDarken = min(0.84, 0.42 + (lightArtworkBoost * 0.24) + (veryLightBoost * 0.24) + (effectiveHover ? 0.08 : 0.02))
        let neutralWashOpacity = min(0.52, 0.16 + (lightArtworkBoost * 0.20) + (veryLightBoost * 0.18))
        let blueFogOpacity = min(0.34, 0.08 + (lightArtworkBoost * 0.10) + (veryLightBoost * 0.14))
        let mistOpacity = min(0.60, 0.20 + (lightArtworkBoost * 0.18) + (veryLightBoost * 0.16))
        let miniInfoBandBaseOpacity = min(0.48, 0.29 + (lightArtworkBoost * 0.07) + (veryLightBoost * 0.07) + (pointerHovering ? 0.14 : 0))
        // With the metadata panel gone, this gradient is the only thing standing between
        // white type and a bright album, so it carries what the panel's own fill used to.
        let miniInfoBandReadabilityDarken = min(0.98, readabilityDarken + 0.16 + (pointerHovering ? 0.12 : 0))
        let miniInfoBandNeutralWashOpacity = neutralWashOpacity * (pointerHovering ? 0.68 : 1.0)
        let miniInfoBandBlueFogOpacity = blueFogOpacity * (pointerHovering ? 0.72 : 1.0)
        let miniInfoBandMistOpacity = mistOpacity * (pointerHovering ? 0.60 : 1.0)
        let miniInfoBandContrastBoost = min(1, 0.14 + (lightArtworkBoost * 0.56) + (veryLightBoost * 0.20) + (pointerHovering ? 0.30 : 0.02))
        let miniMetadataSpacing = (pointerHovering ? 6.0 : 3.0) * miniControlScale
        let miniLowerPanelContentHorizontalPadding = 18.0 * miniControlScale
        let miniLowerPanelContentVerticalPadding = (pointerHovering ? 16.0 : 14.0) * miniControlScale
        let infoBandHeight: CGFloat = (infoExpanded ? 216.0 : 118.0) * miniControlScale
        let resolvedCardHeight = resolvedHeight
        let liveCardHeight = min(resolvedCardHeight, max(model.miniBaseHeight, availableHeight))
        let visibleLyricsHeight = min(
            model.miniLyricsPaneHeight,
            max(0, liveCardHeight - model.miniBaseHeight)
        )
        let shouldRenderMiniLyricsPane = showMiniLyricsPane || visibleLyricsHeight > 0.5
        let seamOpacity = min(1, max(0, visibleLyricsHeight / max(1, model.miniLyricsPaneHeight)))
        let miniMarqueeLaneWidth = max(120, model.miniPopoverWidth - (miniLowerPanelContentHorizontalPadding * 2))
        let miniTrackKey = "\(model.provider.rawValue)|\(model.artist)|\(model.albumArtist)|\(model.album)|\(model.title)"
        let showMiniControlRow = pointerHovering && primaryContentVisible
        let cardShell = miniCardShell(
            bottomShade: bottomShade,
            topShade: topShade,
            neutralWashOpacity: neutralWashOpacity,
            blueFogOpacity: blueFogOpacity,
            miniControlScale: miniControlScale,
            miniTrackKey: miniTrackKey,
            showMiniControlRow: showMiniControlRow,
            miniInfoBandBaseOpacity: miniInfoBandBaseOpacity,
            miniInfoBandReadabilityDarken: miniInfoBandReadabilityDarken,
            miniInfoBandNeutralWashOpacity: miniInfoBandNeutralWashOpacity,
            miniInfoBandBlueFogOpacity: miniInfoBandBlueFogOpacity,
            miniInfoBandMistOpacity: miniInfoBandMistOpacity,
            miniInfoBandContrastBoost: miniInfoBandContrastBoost,
            miniMetadataSpacing: miniMetadataSpacing,
            infoBandHeight: infoBandHeight,
            miniMarqueeLaneWidth: miniMarqueeLaneWidth,
            infoExpanded: infoExpanded,
            miniLowerPanelContentHorizontalPadding: miniLowerPanelContentHorizontalPadding,
            miniLowerPanelContentVerticalPadding: miniLowerPanelContentVerticalPadding,
            seamOpacity: seamOpacity
        )

        return VStack(spacing: 0) {
            cardShell

            if shouldRenderMiniLyricsPane {
                MiniExpandedDetailsPane(
                    model: model,
                    selectedTab: model.selectedMiniDetailsTab,
                    visibleHeight: visibleLyricsHeight
                )
                .allowsHitTesting(model.miniLyricsEnabled && visibleLyricsHeight > 0.5)
            }
        }
        .frame(width: model.miniPopoverWidth, height: resolvedCardHeight, alignment: .top)
        .background(.clear)
        .clipShape(RoundedRectangle(cornerRadius: playerSurfaceCornerRadius, style: .continuous))
        // One hairline on the outermost shape. The card used to carry three separate 1pt
        // strokes at 14% — here, on the shell inside it, and around the artwork — which is
        // what made the window look like a screenshot of itself.
        .overlay(
            RoundedRectangle(cornerRadius: playerSurfaceCornerRadius, style: .continuous)
                .stroke(.white.opacity(playerHairlineOpacity), lineWidth: playerHairlineWidth)
        )
        .shadow(color: .black.opacity(0.34), radius: 20, x: 0, y: 8)
    }

    private func miniCardShell(
        bottomShade: Double,
        topShade: Double,
        neutralWashOpacity: Double,
        blueFogOpacity: Double,
        miniControlScale: CGFloat,
        miniTrackKey: String,
        showMiniControlRow: Bool,
        miniInfoBandBaseOpacity: Double,
        miniInfoBandReadabilityDarken: Double,
        miniInfoBandNeutralWashOpacity: Double,
        miniInfoBandBlueFogOpacity: Double,
        miniInfoBandMistOpacity: Double,
        miniInfoBandContrastBoost: Double,
        miniMetadataSpacing: CGFloat,
        infoBandHeight: CGFloat,
        miniMarqueeLaneWidth: CGFloat,
        infoExpanded: Bool,
        miniLowerPanelContentHorizontalPadding: CGFloat,
        miniLowerPanelContentVerticalPadding: CGFloat,
        seamOpacity: Double
    ) -> some View {
        let artworkBackdrop = miniCardArtworkBackdrop(bottomShade: bottomShade, topShade: topShade)
        let heroSurface = miniCardHeroSurface(miniTrackKey: miniTrackKey)
        let topControls = miniCardTopControls(
            miniControlScale: miniControlScale,
            showMiniControlRow: showMiniControlRow,
            neutralWashOpacity: neutralWashOpacity,
            blueFogOpacity: blueFogOpacity,
            clusterContrastBoost: miniInfoBandContrastBoost
        )
        let bottomPanel = miniCardBottomPanel(
            miniControlScale: miniControlScale,
            miniInfoBandBaseOpacity: miniInfoBandBaseOpacity,
            miniInfoBandReadabilityDarken: miniInfoBandReadabilityDarken,
            miniInfoBandNeutralWashOpacity: miniInfoBandNeutralWashOpacity,
            miniInfoBandBlueFogOpacity: miniInfoBandBlueFogOpacity,
            miniInfoBandMistOpacity: miniInfoBandMistOpacity,
            miniInfoBandContrastBoost: miniInfoBandContrastBoost,
            miniMetadataSpacing: miniMetadataSpacing,
            infoBandHeight: infoBandHeight,
            miniMarqueeLaneWidth: miniMarqueeLaneWidth,
            infoExpanded: infoExpanded,
            miniLowerPanelContentHorizontalPadding: miniLowerPanelContentHorizontalPadding,
            miniLowerPanelContentVerticalPadding: miniLowerPanelContentVerticalPadding
        )
        let seamOverlay = miniCardSeamOverlay(seamOpacity: seamOpacity)

        return ZStack {
            artworkBackdrop
            heroSurface
        }
        .frame(height: model.miniBaseHeight)
        .clipShape(RoundedRectangle(cornerRadius: playerSurfaceCornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            topControls
        }
        .overlay(alignment: .bottom) {
            bottomPanel
        }
        .clipShape(RoundedRectangle(cornerRadius: playerSurfaceCornerRadius, style: .continuous))
        .overlay(alignment: .bottom) {
            seamOverlay
        }
        .overlay {
            MiniCardPointerTrackingOverlay(enabled: !transitionActive) { hovering in
                withAnimation(.easeInOut(duration: 0.18)) {
                    pointerHovering = hovering
                    if !hovering {
                        forceExpandedUntilPointerExit = false
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            syncRenderedMiniLyricsPaneImmediately()
        }
        .onDisappear {
            miniLyricsHideWorkItem?.cancel()
            miniLyricsHideWorkItem = nil
        }
        .onChange(of: transitionActive) { _, active in
            if active {
                withAnimation(.easeOut(duration: 0.08)) {
                    pointerHovering = false
                }
            }
        }
        .onChange(of: model.miniLyricsEnabled) { _, enabled in
            syncRenderedMiniLyricsPane(for: enabled)
        }
    }

    private func miniCardArtworkBackdrop(bottomShade: Double, topShade: Double) -> some View {
        ZStack {
            LinearGradient(
                colors: model.cardBackgroundPalette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [model.glassTint.opacity(0.34), .clear, model.glassTint.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .opacity(0.82)

            // Mounted for the whole life of the branch, morph included. This was once
            // skipped mid-morph to save its 34pt blur, but remounting it at handoff
            // popped a full-card blurred-artwork layer into existence in a single frame
            // — visible in the margins and through every translucent layer above it.
            // It rides the branch's own cross-fade in, so nothing snaps.
            // Idle drops the artwork here as well as in the hero. Leaving the blurred
            // wash up under "Nothing playing" kept the last track on screen after it
            // stopped being true — and it is the loudest layer on an otherwise empty card.
            ArtworkBackdropCrossfadeView(
                image: idleArtworkCleared ? nil : model.artwork,
                animationKey: idleArtworkCleared ? "art:idle" : (model.artwork?.artworkTransitionIdentity ?? "art:none"),
                isEnabled: model.animatedArtworkEnabled,
                animateOnFirstAppear: !transitionActive,
                maxOpacity: 0.34,
                blurRadius: 34,
                scale: 1.10,
                tint: model.glassTint,
                tintOpacity: 0.05
            )
        }
        .overlay(
            LinearGradient(
                colors: [.clear, .black.opacity(bottomShade)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            LinearGradient(
                colors: [.black.opacity(topShade), .clear],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        )
    }

    /// Whether this card is standing in for a cover it no longer has a track for.
    ///
    /// Not `model.artwork == nil`: the image outlives the track it came from, so an idle
    /// card would keep showing the cover of whatever stopped playing.
    private var idleArtworkCleared: Bool {
        model.isIdle
    }

    /// Mini's copy of `PlayerIdleView`'s plate. The card *is* the artwork here, so this
    /// fills the hero frame rather than a fixed square.
    private var miniIdlePlate: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)

            RoundedRectangle(cornerRadius: miniArtworkCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.055), .white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: max(30, side * 0.19), weight: .light))
                        .foregroundStyle(.white.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: miniArtworkCornerRadius, style: .continuous)
                        .stroke(.white.opacity(playerHairlineOpacity * 0.7), lineWidth: playerHairlineWidth)
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func miniCardHeroSurface(miniTrackKey: String) -> some View {
        if transitionActive {
            // Handed off to the shared morph node. Dropped from the tree rather than
            // hidden — `.opacity(0)` still rasterises, and this is the single most
            // expensive subtree in the card.
            Color.clear
                .modeArtworkAnchor(.mini, in: modeMiniBranchSpace)
                .padding(miniArtworkPadding)
        } else if idleArtworkCleared {
            // The regular player's idle plate, sized to mini's hero. Same anchor and
            // padding as the cover it stands in for, so the mode morph still has
            // something in the right place to fly to.
            miniIdlePlate
                .clipShape(RoundedRectangle(cornerRadius: miniArtworkCornerRadius, style: .continuous))
                .modeArtworkAnchor(.mini, in: modeMiniBranchSpace)
                .padding(miniArtworkPadding)
        } else {
            MiniArtworkTransitionSurface(
                artwork: model.artwork,
                tint: model.glassTint,
                trackKey: miniTrackKey,
                animationsEnabled: model.animatedArtworkEnabled,
                transitionActive: transitionActive,
                suppressAppearAnimation: handoffSettling,
                animatedArtworkURL: model.effectiveAnimatedArtworkURL,
                cropAnimatedArtworkToSquare: model.cropAnimatedArtworkToSquare,
                isPopoverVisible: model.isPopoverVisible
            )
            .clipShape(RoundedRectangle(cornerRadius: miniArtworkCornerRadius, style: .continuous))
            .modeArtworkAnchor(.mini, in: modeMiniBranchSpace)
            .animatedArtworkMotion(
                isEnabled: model.animatedArtworkEnabled,
                seed: "mini|\(model.provider.rawValue)|\(model.artist)|\(model.albumArtist)|\(model.album)|\(model.title)",
                style: model.artworkMotionStyle,
                isPlaying: model.isPlaying,
                hasAnimatedStream: model.effectiveAnimatedArtworkURL != nil,
                tint: model.glassTint,
                artworkImage: model.artwork
            )
            .padding(miniArtworkPadding)
        }
    }

    private func miniCardTopControls(
        miniControlScale: CGFloat,
        showMiniControlRow: Bool,
        neutralWashOpacity: Double,
        blueFogOpacity: Double,
        clusterContrastBoost: Double
    ) -> some View {
        let restingOpacity = playerControlClusterRestingOpacity

        return HStack(spacing: 2 * miniControlScale) {
            ModeToggleControl(
                isMiniMode: true,
                transitionActive: transitionActive,
                sizeScale: miniControlScale,
                action: onToggleMode
            )

            DetachedSurfaceToggleControl(
                isDetachedMode: model.surfaceMode == .detached,
                transitionActive: transitionActive,
                sizeScale: miniControlScale
            ) {
                model.requestToggleDetachedMode()
            }

            if model.surfaceMode == .detached {
                DetachedWindowPinControl(
                    isPinned: model.detachedWindowAlwaysOnTop,
                    transitionActive: transitionActive,
                    sizeScale: miniControlScale
                ) {
                    model.detachedWindowAlwaysOnTop.toggle()
                }

                DetachedWindowCloseControl(
                    transitionActive: transitionActive,
                    sizeScale: miniControlScale
                ) {
                    model.requestCloseDetachedWindow()
                }
            }

            MiniDetailToggleControl(
                isOn: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .lyrics,
                systemName: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .lyrics ? "quote.bubble.fill" : "quote.bubble",
                helpText: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .lyrics ? "Hide lyrics" : "Show lyrics",
                transitionActive: transitionActive,
                sizeScale: miniControlScale
            ) {
                toggleMiniDetails(tab: .lyrics)
            }

            MiniDetailToggleControl(
                isOn: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .credits,
                systemName: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .credits ? "info.circle.fill" : "info.circle",
                helpText: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .credits ? "Hide credits" : "Show credits",
                transitionActive: transitionActive,
                sizeScale: miniControlScale
            ) {
                toggleMiniDetails(tab: .credits)
            }

            // See the regular cluster: no filled variant exists, so `isOn` carries the state.
            MiniDetailToggleControl(
                isOn: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .history,
                systemName: "clock.arrow.circlepath",
                helpText: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .history ? "Hide history" : "Show history",
                transitionActive: transitionActive,
                sizeScale: miniControlScale
            ) {
                toggleMiniDetails(tab: .history)
            }

            SettingsOpenControl {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16 * miniControlScale, weight: .semibold))
                    .foregroundStyle(ArtworkPlayerControlPalette.icon())
                    .playerClusterGlyphChrome(
                        diameter: 24 * miniControlScale,
                        isHovering: settingsHovering
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                guard !transitionActive else {
                    if settingsHovering { settingsHovering = false }
                    return
                }
                settingsHovering = hovering
            }
            .hoverHint("Settings", enabled: !transitionActive)
            .accessibilityLabel(Text("Settings"))
        }
        .playerControlClusterBackground(
            sizeScale: miniControlScale,
            neutralWashOpacity: neutralWashOpacity * 0.65,
            blueFogOpacity: blueFogOpacity * 0.65,
            contrastBoost: clusterContrastBoost,
            artworkBacking: 1
        )
        .fixedSize(horizontal: true, vertical: false)
        .padding(.top, 10 * miniControlScale)
        .padding(.trailing, 10 * miniControlScale)
        .opacity(primaryContentVisible ? (showMiniControlRow ? 1 : restingOpacity) : 0)
        .offset(y: primaryContentVisible ? 0 : -6)
        .allowsHitTesting(primaryContentVisible)
        .animation(.easeInOut(duration: 0.16), value: pointerHovering)
        .animation(modePrimaryRevealAnimation, value: primaryContentVisible)
        .animation(modeSecondaryRevealAnimation, value: secondaryContentVisible)
    }

    /// Mini's copy of the regular idle call to action, at this card's type sizes.
    /// Same two kinds `PlayerIdleView` handles: launch the provider, or start it playing.
    private func miniIdleActionButton(
        _ action: PlayerIdlePresentation.Action,
        scale: CGFloat
    ) -> some View {
        Button {
            switch action.kind {
            case .play:
                model.playPause()
            case .openApp:
                model.openProviderApp()
            }
        } label: {
            HStack(spacing: 5 * scale) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 10.5 * scale, weight: .bold))
                Text(action.title)
                    .font(.system(size: 11.5 * scale, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.09, green: 0.10, blue: 0.11))
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 6 * scale)
            .background(
                RoundedRectangle(cornerRadius: 7 * scale, style: .continuous)
                    .fill(.white.opacity(0.94))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7 * scale, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(action.title))
    }

    private var showRestingProgressRail: Bool {
        model.miniRestingProgressEnabled
    }

    private func miniCardBottomPanel(
        miniControlScale: CGFloat,
        miniInfoBandBaseOpacity: Double,
        miniInfoBandReadabilityDarken: Double,
        miniInfoBandNeutralWashOpacity: Double,
        miniInfoBandBlueFogOpacity: Double,
        miniInfoBandMistOpacity: Double,
        miniInfoBandContrastBoost: Double,
        miniMetadataSpacing: CGFloat,
        infoBandHeight: CGFloat,
        miniMarqueeLaneWidth: CGFloat,
        infoExpanded: Bool,
        miniLowerPanelContentHorizontalPadding: CGFloat,
        miniLowerPanelContentVerticalPadding: CGFloat
    ) -> some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(miniInfoBandBaseOpacity))
                .overlay(
                    Color(red: 0.60, green: 0.66, blue: 0.74)
                        .opacity(miniInfoBandNeutralWashOpacity)
                )
                .overlay(
                    Color(red: 0.52, green: 0.61, blue: 0.76)
                        .opacity(miniInfoBandBlueFogOpacity)
                )
                .overlay(
                    LinearGradient(
                        colors: [
                            .white.opacity(miniInfoBandMistOpacity),
                            .white.opacity(miniInfoBandMistOpacity * 0.22),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.45), .white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(miniInfoBandReadabilityDarken * 0.62),
                            .black.opacity(miniInfoBandReadabilityDarken)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: infoBandHeight)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: miniMetadataSpacing) {
                    if model.isIdle {
                        // The same copy the regular player shows, at mini's type sizes.
                        let idle = model.idlePresentation
                        Text(idle.headline)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.84))
                        Text(idle.detail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        // The one action worth taking, same as the regular player offers.
                        // Mini used to read `idle.action` and drop it on the floor, so the
                        // card said the player wasn't running and gave you no way to start it.
                        if let action = idle.action {
                            miniIdleActionButton(action, scale: miniControlScale)
                                .padding(.top, 9 * miniControlScale)
                        }
                    } else {
                        // The same crossing the regular player uses, so both surfaces treat a
                        // track change as the same moment.
                        VStack(alignment: .leading, spacing: miniMetadataSpacing) {
                            Button(action: { model.openProviderApp() }) {
                                NowPlayingTitleMarquee(
                                    text: model.displayTitle,
                                    enabled: true,
                                    isVisible: model.isPopoverVisible,
                                    laneWidth: miniMarqueeLaneWidth,
                                    fontSize: 16
                                )
                                .foregroundStyle(.white)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            NowPlayingSecondaryMarquee(
                                text: model.artistAlbumLine,
                                enabled: true,
                                isVisible: model.isPopoverVisible,
                                laneWidth: miniMarqueeLaneWidth,
                                fontSize: 12,
                                textOpacity: 0.66
                            )
                        }
                        .trackChangeTransition(
                            identity: model.trackIdentity,
                            isEnabled: model.slideTitleOnChange && !reduceMotion
                        )
                    }
                }
                .opacity(primaryContentVisible ? 1 : 0)
                .offset(y: primaryContentVisible ? 0 : 8)
                .animation(modePrimaryRevealAnimation, value: primaryContentVisible)

                // The resting line. It occupies the same margins the hover scrubber lands
                // on, so the two cross-fade in place: this fades out as the block below
                // fades in, rather than one element vanishing somewhere else on the card.
                // Suppressed on an idle card for the same reason the hover block is —
                // there is no position to report.
                if showRestingProgressRail && !infoExpanded && !model.isIdle {
                    MiniRestingProgressRail(
                        contrastBoost: miniInfoBandContrastBoost,
                        tint: model.miniRestingProgressUsesTint ? model.glassTint : nil
                    )
                        .opacity(primaryContentVisible ? 1 : 0)
                        .transition(.opacity)
                }

                // Hovering an idle card used to reveal a progress rail, five transport
                // controls and a volume slider, none of which had anything to act on.
                if infoExpanded && !model.isIdle {
                    VStack(spacing: 8) {
                        PlaybackProgressBlock(
                            contrastBoost: miniInfoBandContrastBoost,
                            onSeek: { model.seek(to: $0) }
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                        HStack {
                            Spacer(minLength: 0)
                            ControlsRow(
                                isPlaying: model.isPlaying,
                                isShuffleEnabled: model.isShuffleEnabled,
                                repeatMode: model.repeatMode,
                                controlsEnabled: model.canControlPlayback,
                                onShuffle: { model.toggleShuffle() },
                                onPrev: { model.previousTrack() },
                                onPlayPause: { model.playPause() },
                                onNext: { model.nextTrack() },
                                onRepeat: { model.cycleRepeatMode() },
                                contrastBoost: miniInfoBandContrastBoost,
                                controlScale: miniControlScale
                            )
                            Spacer(minLength: 0)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                        OutputControlsRow(
                            model: model,
                            contrastBoost: miniInfoBandContrastBoost,
                            controlScale: miniControlScale,
                            showFavorite: model.canFavoriteCurrentTrack,
                            favoriteIsActive: model.isCurrentTrackFavorited,
                            favoritePulseToken: model.favoriteActionPulseToken,
                            onFavorite: { _ = model.toggleCurrentTrackFavorite() }
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    .opacity(secondaryContentVisible ? 1 : 0)
                    .offset(y: secondaryContentVisible ? 0 : 10)
                    .animation(modeSecondaryRevealAnimation, value: secondaryContentVisible)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Scrim, not card. The metadata used to sit on its own rounded, stroked panel
            // floating over the artwork — a second corner radius to reconcile and a box
            // drawn around type that the band gradient behind it was already darkening.
            // The band does the whole job; the text just pads against the card edge.
            .padding(.horizontal, miniLowerPanelContentHorizontalPadding)
            .padding(.bottom, miniLowerPanelContentVerticalPadding)
            .animation(.interactiveSpring(response: 0.30, dampingFraction: 0.86, blendDuration: 0.10), value: pointerHovering)
        }
    }

    private func miniCardSeamOverlay(seamOpacity: Double) -> some View {
        ZStack(alignment: .bottom) {
            ArtworkBackdropCrossfadeView(
                image: idleArtworkCleared ? nil : model.artwork,
                animationKey: idleArtworkCleared ? "art:idle" : (model.artwork?.artworkTransitionIdentity ?? "art:none"),
                isEnabled: model.animatedArtworkEnabled,
                animateOnFirstAppear: !transitionActive,
                maxOpacity: 0.28,
                blurRadius: miniSeamBlurRadius,
                scale: 1.04,
                tint: model.glassTint,
                tintOpacity: 0.03
            )
            .frame(maxWidth: .infinity)
            .frame(height: miniSeamBlendHeight * 2.2)
            .offset(y: 2)
            .clipped()

            LinearGradient(
                colors: [
                    .black.opacity(0.20),
                    .black.opacity(0.08),
                    .clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )

            LinearGradient(
                colors: [
                    model.glassTint.opacity(0.14),
                    model.glassTint.opacity(0.07),
                    .clear
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .blendMode(.screen)
        }
        .frame(height: miniSeamBlendHeight)
        .opacity(seamOpacity)
        .allowsHitTesting(false)
    }

    private func syncRenderedMiniLyricsPaneImmediately() {
        miniLyricsHideWorkItem?.cancel()
        miniLyricsHideWorkItem = nil
        showMiniLyricsPane = model.miniLyricsEnabled
    }

    private func syncRenderedMiniLyricsPane(for enabled: Bool) {
        miniLyricsHideWorkItem?.cancel()
        miniLyricsHideWorkItem = nil

        if enabled {
            showMiniLyricsPane = true
            return
        }

        let work = DispatchWorkItem {
            guard !model.miniLyricsEnabled else { return }
            showMiniLyricsPane = false
            miniLyricsHideWorkItem = nil
        }
        miniLyricsHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + miniLyricsTransitionDuration, execute: work)
    }

    private func toggleMiniDetails(tab: DetailsPaneTab) {
        let willExpand = !(model.miniLyricsEnabled && model.selectedMiniDetailsTab == tab)
        syncRenderedMiniLyricsPane(for: willExpand)

        if !willExpand {
            pointerHovering = true
            forceExpandedUntilPointerExit = true
        }

        model.toggleMiniDetailsTab(tab)
    }

    private var artworkLuminance: CGFloat {
        guard let average = model.artwork?.averageColor()?.usingColorSpace(.deviceRGB) else {
            return 0.45
        }
        let red = average.redComponent
        let green = average.greenComponent
        let blue = average.blueComponent
        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }
}

struct MiniArtworkTransitionSurface: View {
    let artwork: NSImage?
    let tint: Color
    let trackKey: String
    let animationsEnabled: Bool
    let transitionActive: Bool
    let suppressAppearAnimation: Bool
    let animatedArtworkURL: URL?
    let cropAnimatedArtworkToSquare: Bool
    let isPopoverVisible: Bool

    var body: some View {
        ArtworkStreamTransitionSurface(
            image: artwork,
            animatedArtworkURL: animatedArtworkURL,
            isActive: isPopoverVisible,
            cropAnimatedArtworkToSquare: cropAnimatedArtworkToSquare,
            transitionKeyPrefix: trackKey,
            transitionAnimationsEnabled: animationsEnabled && !transitionActive,
            animateOnFirstAppear: !transitionActive && !suppressAppearAnimation
        ) {
            staticArtworkLayer(for: artwork)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func staticArtworkLayer(for image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            EmptyArtworkPlaceholderView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct MiniCardPointerTrackingOverlay: NSViewRepresentable {
    let enabled: Bool
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onHoverChanged = onHoverChanged
        view.enabled = enabled
        return view
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
        nsView.enabled = enabled
        nsView.syncHoverState()
    }
}

final class TrackingNSView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    var enabled: Bool = true {
        didSet {
            if oldValue != enabled {
                updateTrackingAreas()
                if !enabled {
                    lastKnownHover = false
                    onHoverChanged?(false)
                }
            }
        }
    }
    private var trackingAreaRef: NSTrackingArea?
    private var lastKnownHover = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncHoverState()
        DispatchQueue.main.async { [weak self] in
            self?.syncHoverState()
        }
    }

    override func updateTrackingAreas() {
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
            self.trackingAreaRef = nil
        }
        guard enabled else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
        super.updateTrackingAreas()
        syncHoverState()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncHoverState()
    }

    override func mouseEntered(with event: NSEvent) {
        guard enabled else { return }
        setHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHover(false)
    }

    func syncHoverState() {
        guard enabled else { return }
        guard let window else { return }
        let pointInWindow = window.mouseLocationOutsideOfEventStream
        let pointInView = convert(pointInWindow, from: nil)
        setHover(bounds.contains(pointInView))
    }

    private func setHover(_ hovering: Bool) {
        guard hovering != lastKnownHover else { return }
        lastKnownHover = hovering
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onHoverChanged?(hovering)
        }
    }
}

func lyricsBleedOpacities(for artworkColorIntensity: Double) -> (top: Double, mid: Double) {
    let intensity = min(max(artworkColorIntensity, 0.5), 1.8)
    return (
        top: min(0.38, 0.20 * intensity),
        mid: min(0.20, 0.10 * intensity)
    )
}
