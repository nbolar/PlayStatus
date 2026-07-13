import SwiftUI
import AppKit

struct TopRoundedBandShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width * 0.5, rect.height))
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

struct MiniNowPlayingCard: View {
    @ObservedObject var model: NowPlayingModel
    let artworkMorphNamespace: Namespace.ID
    let transitionActive: Bool
    let availableHeight: CGFloat
    let resolvedHeight: CGFloat
    let primaryContentVisible: Bool
    let secondaryContentVisible: Bool
    let startExpandedOnAppear: Bool
    let onInitialExpandConsumed: () -> Void
    let onToggleMode: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var pointerHovering = false
    @State private var forceExpandedUntilPointerExit = false
    @State private var showMiniLyricsPane = false
    @State private var miniLyricsHideWorkItem: DispatchWorkItem?

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
        let primaryShadowOpacity = min(0.94, 0.56 + (lightArtworkBoost * 0.22) + (darkArtworkBoost * 0.12))
        let secondaryShadowOpacity = min(0.84, 0.46 + (lightArtworkBoost * 0.18) + (darkArtworkBoost * 0.10))
        let miniInfoBandBaseOpacity = min(0.48, 0.29 + (lightArtworkBoost * 0.07) + (veryLightBoost * 0.07) + (pointerHovering ? 0.14 : 0))
        let miniInfoBandReadabilityDarken = min(0.96, readabilityDarken + (pointerHovering ? 0.15 : 0))
        let miniInfoBandNeutralWashOpacity = neutralWashOpacity * (pointerHovering ? 0.68 : 1.0)
        let miniInfoBandBlueFogOpacity = blueFogOpacity * (pointerHovering ? 0.72 : 1.0)
        let miniInfoBandMistOpacity = mistOpacity * (pointerHovering ? 0.60 : 1.0)
        let miniInfoBandPrimaryShadowOpacity = min(0.98, primaryShadowOpacity + (pointerHovering ? 0.10 : 0))
        let miniInfoBandSecondaryShadowOpacity = min(0.92, secondaryShadowOpacity + (pointerHovering ? 0.08 : 0))
        let miniInfoBandContrastBoost = min(1, 0.14 + (lightArtworkBoost * 0.56) + (veryLightBoost * 0.20) + (pointerHovering ? 0.30 : 0.02))
        let miniLowerPanelEmphasis = min(1, 0.50 + (lightArtworkBoost * 0.24) + (veryLightBoost * 0.12) + (pointerHovering ? 0.24 : 0.08))
        let miniMetadataSpacing = (pointerHovering ? 8.0 : 5.0) * miniControlScale
        let miniLowerPanelContentHorizontalPadding = (pointerHovering ? 12.0 : 10.0) * miniControlScale
        let miniLowerPanelContentVerticalPadding = (pointerHovering ? 10.0 : 5.5) * miniControlScale
        let infoBandHeight: CGFloat = (infoExpanded ? 196.0 : 94.0) * miniControlScale
        let resolvedCardHeight = resolvedHeight
        let liveCardHeight = min(resolvedCardHeight, max(model.miniBaseHeight, availableHeight))
        let visibleLyricsHeight = min(
            model.miniLyricsPaneHeight,
            max(0, liveCardHeight - model.miniBaseHeight)
        )
        let shouldRenderMiniLyricsPane = showMiniLyricsPane || visibleLyricsHeight > 0.5
        let seamOpacity = min(1, max(0, visibleLyricsHeight / max(1, model.miniLyricsPaneHeight)))
        let miniMarqueeLaneWidth = max(120, model.miniPopoverWidth - 64)
        let miniTrackKey = "\(model.provider.rawValue)|\(model.artist)|\(model.albumArtist)|\(model.album)|\(model.title)"
        let miniLowerPanelHorizontalInset = (pointerHovering ? 6.0 : 14.0) * miniControlScale
        let miniLowerPanelBottomInset = (pointerHovering ? 15.0 : 8.0) * miniControlScale
        let miniLowerPanelHoverLift = (pointerHovering ? 8.0 : 0) * miniControlScale
        let miniInfoBandTopCornerRadius = 24 * miniControlScale
        let showMiniControlRow = pointerHovering && primaryContentVisible
        let showMiniSecondaryControls = showMiniControlRow && secondaryContentVisible
        let cardShell = miniCardShell(
            bottomShade: bottomShade,
            topShade: topShade,
            neutralWashOpacity: neutralWashOpacity,
            blueFogOpacity: blueFogOpacity,
            miniControlScale: miniControlScale,
            miniTrackKey: miniTrackKey,
            showMiniControlRow: showMiniControlRow,
            showMiniSecondaryControls: showMiniSecondaryControls,
            miniInfoBandBaseOpacity: miniInfoBandBaseOpacity,
            miniInfoBandReadabilityDarken: miniInfoBandReadabilityDarken,
            miniInfoBandNeutralWashOpacity: miniInfoBandNeutralWashOpacity,
            miniInfoBandBlueFogOpacity: miniInfoBandBlueFogOpacity,
            miniInfoBandMistOpacity: miniInfoBandMistOpacity,
            miniInfoBandPrimaryShadowOpacity: miniInfoBandPrimaryShadowOpacity,
            miniInfoBandSecondaryShadowOpacity: miniInfoBandSecondaryShadowOpacity,
            miniInfoBandContrastBoost: miniInfoBandContrastBoost,
            miniLowerPanelEmphasis: miniLowerPanelEmphasis,
            miniMetadataSpacing: miniMetadataSpacing,
            infoBandHeight: infoBandHeight,
            miniMarqueeLaneWidth: miniMarqueeLaneWidth,
            infoExpanded: infoExpanded,
            miniLowerPanelContentHorizontalPadding: miniLowerPanelContentHorizontalPadding,
            miniLowerPanelContentVerticalPadding: miniLowerPanelContentVerticalPadding,
            miniLowerPanelHorizontalInset: miniLowerPanelHorizontalInset,
            miniLowerPanelBottomInset: miniLowerPanelBottomInset,
            miniLowerPanelHoverLift: miniLowerPanelHoverLift,
            miniInfoBandTopCornerRadius: miniInfoBandTopCornerRadius,
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func miniCardShell(
        bottomShade: Double,
        topShade: Double,
        neutralWashOpacity: Double,
        blueFogOpacity: Double,
        miniControlScale: CGFloat,
        miniTrackKey: String,
        showMiniControlRow: Bool,
        showMiniSecondaryControls: Bool,
        miniInfoBandBaseOpacity: Double,
        miniInfoBandReadabilityDarken: Double,
        miniInfoBandNeutralWashOpacity: Double,
        miniInfoBandBlueFogOpacity: Double,
        miniInfoBandMistOpacity: Double,
        miniInfoBandPrimaryShadowOpacity: Double,
        miniInfoBandSecondaryShadowOpacity: Double,
        miniInfoBandContrastBoost: Double,
        miniLowerPanelEmphasis: Double,
        miniMetadataSpacing: CGFloat,
        infoBandHeight: CGFloat,
        miniMarqueeLaneWidth: CGFloat,
        infoExpanded: Bool,
        miniLowerPanelContentHorizontalPadding: CGFloat,
        miniLowerPanelContentVerticalPadding: CGFloat,
        miniLowerPanelHorizontalInset: CGFloat,
        miniLowerPanelBottomInset: CGFloat,
        miniLowerPanelHoverLift: CGFloat,
        miniInfoBandTopCornerRadius: CGFloat,
        seamOpacity: Double
    ) -> some View {
        let artworkBackdrop = miniCardArtworkBackdrop(bottomShade: bottomShade, topShade: topShade)
        let heroSurface = miniCardHeroSurface(miniTrackKey: miniTrackKey)
        let topControls = miniCardTopControls(
            miniControlScale: miniControlScale,
            showMiniControlRow: showMiniControlRow,
            showMiniSecondaryControls: showMiniSecondaryControls,
            neutralWashOpacity: neutralWashOpacity,
            blueFogOpacity: blueFogOpacity
        )
        let bottomPanel = miniCardBottomPanel(
            miniControlScale: miniControlScale,
            miniInfoBandBaseOpacity: miniInfoBandBaseOpacity,
            miniInfoBandReadabilityDarken: miniInfoBandReadabilityDarken,
            miniInfoBandNeutralWashOpacity: miniInfoBandNeutralWashOpacity,
            miniInfoBandBlueFogOpacity: miniInfoBandBlueFogOpacity,
            miniInfoBandMistOpacity: miniInfoBandMistOpacity,
            miniInfoBandPrimaryShadowOpacity: miniInfoBandPrimaryShadowOpacity,
            miniInfoBandSecondaryShadowOpacity: miniInfoBandSecondaryShadowOpacity,
            miniInfoBandContrastBoost: miniInfoBandContrastBoost,
            miniLowerPanelEmphasis: miniLowerPanelEmphasis,
            miniMetadataSpacing: miniMetadataSpacing,
            infoBandHeight: infoBandHeight,
            miniMarqueeLaneWidth: miniMarqueeLaneWidth,
            infoExpanded: infoExpanded,
            miniLowerPanelContentHorizontalPadding: miniLowerPanelContentHorizontalPadding,
            miniLowerPanelContentVerticalPadding: miniLowerPanelContentVerticalPadding,
            miniLowerPanelHorizontalInset: miniLowerPanelHorizontalInset,
            miniLowerPanelBottomInset: miniLowerPanelBottomInset,
            miniLowerPanelHoverLift: miniLowerPanelHoverLift,
            miniInfoBandTopCornerRadius: miniInfoBandTopCornerRadius
        )
        let seamOverlay = miniCardSeamOverlay(seamOpacity: seamOpacity)

        return ZStack {
            artworkBackdrop
            heroSurface
        }
        .frame(height: model.miniBaseHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            topControls
        }
        .overlay(alignment: .bottom) {
            bottomPanel
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            if startExpandedOnAppear {
                forceExpandedUntilPointerExit = true
                onInitialExpandConsumed()
            }
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

            ArtworkBackdropCrossfadeView(
                image: model.artwork,
                animationKey: model.artwork?.artworkTransitionIdentity ?? "art:none",
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

    private func miniCardHeroSurface(miniTrackKey: String) -> some View {
        MiniArtworkTransitionSurface(
            artwork: model.artwork,
            tint: model.glassTint,
            trackKey: miniTrackKey,
            animationsEnabled: model.animatedArtworkEnabled,
            transitionActive: transitionActive,
            animatedArtworkURL: model.effectiveAnimatedArtworkURL,
            cropAnimatedArtworkToSquare: model.cropAnimatedArtworkToSquare,
            isPopoverVisible: model.isPopoverVisible
        )
        .matchedGeometryEffect(id: "heroArtwork", in: artworkMorphNamespace)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .animatedArtworkMotion(
            isEnabled: model.animatedArtworkEnabled,
            seed: "mini|\(model.provider.rawValue)|\(model.artist)|\(model.albumArtist)|\(model.album)|\(model.title)",
            style: model.artworkMotionStyle,
            isPlaying: model.isPlaying,
            hasAnimatedStream: model.effectiveAnimatedArtworkURL != nil,
            tint: model.glassTint,
            artworkImage: model.artwork
        )
        .padding(8)
    }

    private func miniCardTopControls(
        miniControlScale: CGFloat,
        showMiniControlRow: Bool,
        showMiniSecondaryControls: Bool,
        neutralWashOpacity: Double,
        blueFogOpacity: Double
    ) -> some View {
        HStack(spacing: 6 * miniControlScale) {
            ModeToggleControl(
                isMiniMode: true,
                transitionActive: transitionActive,
                sizeScale: miniControlScale,
                action: onToggleMode
            )

            if showMiniSecondaryControls {
                DetachedSurfaceToggleControl(
                    isDetachedMode: model.surfaceMode == .detached,
                    transitionActive: transitionActive,
                    sizeScale: miniControlScale
                ) {
                    model.requestToggleDetachedMode()
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                if model.surfaceMode == .detached {
                    DetachedWindowPinControl(
                        isPinned: model.detachedWindowAlwaysOnTop,
                        transitionActive: transitionActive,
                        sizeScale: miniControlScale
                    ) {
                        model.detachedWindowAlwaysOnTop.toggle()
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))

                    DetachedWindowCloseControl(
                        transitionActive: transitionActive,
                        sizeScale: miniControlScale
                    ) {
                        model.requestCloseDetachedWindow()
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }

            if showMiniControlRow {
                MiniDetailToggleControl(
                    isOn: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .lyrics,
                    systemName: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .lyrics ? "quote.bubble.fill" : "quote.bubble",
                    helpText: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .lyrics ? "Hide lyrics" : "Show lyrics",
                    transitionActive: transitionActive,
                    sizeScale: miniControlScale
                ) {
                    toggleMiniDetails(tab: .lyrics)
                }
            }

            if showMiniControlRow {
                MiniDetailToggleControl(
                    isOn: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .credits,
                    systemName: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .credits ? "info.circle.fill" : "info.circle",
                    helpText: model.miniLyricsEnabled && model.selectedMiniDetailsTab == .credits ? "Hide credits" : "Show credits",
                    transitionActive: transitionActive,
                    sizeScale: miniControlScale
                ) {
                    toggleMiniDetails(tab: .credits)
                }
            }

            if showMiniSecondaryControls {
                SettingsOpenControl {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16 * miniControlScale, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.94) : .primary.opacity(0.80))
                        .frame(
                            width: 26 * miniControlScale,
                            height: 26 * miniControlScale
                        )
                        .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.055)))
                        .overlay(
                            Circle().stroke(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.09), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .hoverHint("Settings", enabled: !transitionActive)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .miniControlClusterBackground(
            sizeScale: miniControlScale,
            neutralWashOpacity: neutralWashOpacity * 0.65,
            blueFogOpacity: blueFogOpacity * 0.65
        )
        .fixedSize(horizontal: true, vertical: false)
        .padding(.top, 10 * miniControlScale)
        .padding(.trailing, 10 * miniControlScale)
        .opacity(showMiniControlRow ? 1 : 0)
        .offset(y: showMiniControlRow ? 0 : -6)
        .allowsHitTesting(showMiniControlRow)
        .animation(.easeInOut(duration: 0.16), value: pointerHovering)
        .animation(modePrimaryRevealAnimation, value: primaryContentVisible)
        .animation(modeSecondaryRevealAnimation, value: secondaryContentVisible)
    }

    private func miniCardBottomPanel(
        miniControlScale: CGFloat,
        miniInfoBandBaseOpacity: Double,
        miniInfoBandReadabilityDarken: Double,
        miniInfoBandNeutralWashOpacity: Double,
        miniInfoBandBlueFogOpacity: Double,
        miniInfoBandMistOpacity: Double,
        miniInfoBandPrimaryShadowOpacity: Double,
        miniInfoBandSecondaryShadowOpacity: Double,
        miniInfoBandContrastBoost: Double,
        miniLowerPanelEmphasis: Double,
        miniMetadataSpacing: CGFloat,
        infoBandHeight: CGFloat,
        miniMarqueeLaneWidth: CGFloat,
        infoExpanded: Bool,
        miniLowerPanelContentHorizontalPadding: CGFloat,
        miniLowerPanelContentVerticalPadding: CGFloat,
        miniLowerPanelHorizontalInset: CGFloat,
        miniLowerPanelBottomInset: CGFloat,
        miniLowerPanelHoverLift: CGFloat,
        miniInfoBandTopCornerRadius: CGFloat
    ) -> some View {
        let restingPanelOpacity: Double = infoExpanded ? 1 : 0.72
        let restingPanelSaturation: Double = infoExpanded ? 1 : 0.90

        return ZStack(alignment: .bottom) {
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
                .mask(TopRoundedBandShape(cornerRadius: miniInfoBandTopCornerRadius))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: miniMetadataSpacing) {
                    Button(action: { model.openProviderApp() }) {
                        NowPlayingTitleMarquee(
                            text: model.displayTitle,
                            enabled: true,
                            isVisible: model.isPopoverVisible,
                            laneWidth: miniMarqueeLaneWidth
                        )
                        .foregroundStyle(.white.opacity(0.98))
                        .shadow(color: .black.opacity(miniInfoBandPrimaryShadowOpacity), radius: 2.5, x: 0, y: 1.2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    NowPlayingSecondaryMarquee(
                        text: model.artistAlbumLine,
                        enabled: true,
                        isVisible: model.isPopoverVisible,
                        laneWidth: miniMarqueeLaneWidth,
                        usesSecondaryStyle: false
                    )
                    .foregroundStyle(.white.opacity(0.90))
                    .shadow(color: .black.opacity(miniInfoBandSecondaryShadowOpacity), radius: 1.8, x: 0, y: 1)
                }
                .opacity(primaryContentVisible ? 1 : 0)
                .offset(y: primaryContentVisible ? 0 : 8)
                .animation(modePrimaryRevealAnimation, value: primaryContentVisible)

                if infoExpanded {
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
                            showDeviceName: false,
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
            .miniBottomPanelBackground(
                sizeScale: miniControlScale,
                emphasis: miniLowerPanelEmphasis,
                neutralWashOpacity: miniInfoBandNeutralWashOpacity,
                blueFogOpacity: miniInfoBandBlueFogOpacity,
                contentHorizontalPadding: miniLowerPanelContentHorizontalPadding,
                contentVerticalPadding: miniLowerPanelContentVerticalPadding
            )
            .padding(.horizontal, miniLowerPanelHorizontalInset)
            .padding(.bottom, miniLowerPanelBottomInset)
            .offset(y: -miniLowerPanelHoverLift)
            .opacity(restingPanelOpacity)
            .saturation(restingPanelSaturation)
            .animation(.interactiveSpring(response: 0.30, dampingFraction: 0.86, blendDuration: 0.10), value: pointerHovering)
        }
    }

    private func miniCardSeamOverlay(seamOpacity: Double) -> some View {
        ZStack(alignment: .bottom) {
            ArtworkBackdropCrossfadeView(
                image: model.artwork,
                animationKey: model.artwork?.artworkTransitionIdentity ?? "art:none",
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
            animateOnFirstAppear: !transitionActive
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
