import SwiftUI
import AppKit

private let modeMorphAnimation = Animation.interactiveSpring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.10)

struct NowPlayingPopover: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject private var onboarding = OnboardingCoordinator.shared
    @Namespace private var artworkMorphNamespace
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var searchSectionFrame: CGRect = .zero
    @State private var modeTransitionActive = false
    @State private var pendingMiniInitialExpand = false
    @State private var displayedMiniMode = false
    @State private var modePrimaryContentVisible = true
    @State private var modeSecondaryContentVisible = true
    @State private var showRegularDetailsPane = false
    @State private var regularDetailsHideWorkItem: DispatchWorkItem?
    @State private var regularPointerHovering = false
    @State private var coachmarkTargetFrames: [CoachmarkID: CGRect] = [:]

    private var renderedPopoverWidth: CGFloat {
        popoverWidth(for: displayedMiniMode)
    }

    private var renderedPopoverHeight: CGFloat {
        popoverHeight(for: displayedMiniMode)
    }

    private var regularArtworkSize: CGFloat {
        model.regularArtworkDisplaySize
    }

    private func popoverWidth(for miniMode: Bool) -> CGFloat {
        miniMode ? model.miniPopoverWidth : model.regularPopoverWidth
    }

    private func popoverHeight(for miniMode: Bool, miniLyricsEnabled: Bool? = nil) -> CGFloat {
        if miniMode {
            return (miniLyricsEnabled ?? model.miniLyricsEnabled) ? model.miniExpandedHeight : model.miniBaseHeight
        }

        let base = model.estimatedRegularPopoverHeight
        return model.lyricsPanelExpanded ? base + model.regularLyricsPaneHeight : base
    }

    var body: some View {
        GeometryReader { geometry in
            modeContent(
                miniMode: displayedMiniMode,
                availableHeight: max(0, geometry.size.height)
            )
            .frame(
                width: renderedPopoverWidth,
                height: renderedPopoverHeight,
                alignment: .topLeading
            )
            .clipped()
        }
        .frame(
            width: renderedPopoverWidth,
            height: model.isPopoverVisible ? nil : renderedPopoverHeight,
            alignment: .topLeading
        )
        .clipped()
        .coordinateSpace(name: "popoverRoot")
        .onPreferenceChange(PlayerCoachmarkFramePreferenceKey.self) { frames in
            coachmarkTargetFrames = frames
        }
        .onPreferenceChange(SearchSectionFramePreferenceKey.self) { frame in
            updateSearchSectionFrame(frame)
        }
        .overlay(alignment: .topLeading) {
            playerCoachmarkOverlay
        }
        .onChange(of: model.provider) { _, _ in
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isSearchFocused = false
                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)) {
                    isSearchExpanded = false
                }
            }
        }
        .onChange(of: model.miniMode) { _, miniMode in
            beginModeTransition()
            withAnimation(modeMorphAnimation) {
                displayedMiniMode = miniMode
            }

            var immediate = Transaction(animation: nil)
            immediate.disablesAnimations = true
            withTransaction(immediate) {
                modePrimaryContentVisible = true
                modeSecondaryContentVisible = true
            }
            syncRenderedRegularDetailsPane(for: regularDetailsRequested)

            if miniMode {
                regularPointerHovering = false
            }
            guard miniMode else { return }
            searchText = ""
            isSearchFocused = false
            withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.90, blendDuration: 0.12)) {
                isSearchExpanded = false
            }
            updateCoachmarkAvailability()
        }
        .onChange(of: model.lyricsPanelExpanded) { _, _ in
            syncRenderedRegularDetailsPane(for: regularDetailsRequested)
        }
        .onAppear {
            displayedMiniMode = model.miniMode
            modePrimaryContentVisible = true
            modeSecondaryContentVisible = true
            syncRenderedRegularDetailsPaneImmediately()
            updateCoachmarkAvailability()
        }
        .onDisappear {
            regularDetailsHideWorkItem?.cancel()
            regularDetailsHideWorkItem = nil
            regularPointerHovering = false
            clearCoachmarkAvailability()
        }
        .onChange(of: model.surfaceMode) { _, _ in
            updateCoachmarkAvailability()
        }
        .onChange(of: model.resolvedSearchProvider) { _, _ in
            updateCoachmarkAvailability()
        }
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                guard isSearchExpanded else { return }
                guard !searchSectionFrame.contains(value.location) else { return }
                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.90, blendDuration: 0.10)) {
                    isSearchExpanded = false
                }
                isSearchFocused = false
            }
        )
        .onAnimationCompleted(for: displayedMiniMode ? 1.0 : 0.0) {
            guard modeTransitionActive else { return }
            guard displayedMiniMode == model.miniMode else { return }
            modeTransitionActive = false
        }
    }

    @ViewBuilder
    private func modeContent(miniMode: Bool, availableHeight: CGFloat) -> some View {
        if miniMode {
            MiniNowPlayingCard(
                model: model,
                artworkMorphNamespace: artworkMorphNamespace,
                transitionActive: modeTransitionActive,
                availableHeight: availableHeight,
                resolvedHeight: renderedPopoverHeight,
                primaryContentVisible: modePrimaryContentVisible,
                secondaryContentVisible: modeSecondaryContentVisible,
                startExpandedOnAppear: pendingMiniInitialExpand,
                onInitialExpandConsumed: {
                    pendingMiniInitialExpand = false
                },
                onToggleMode: {
                    prepareModeTransition(to: false)
                    withAnimation(modeMorphAnimation) {
                        if model.miniLyricsEnabled {
                            model.miniLyricsEnabled = false
                        }
                        model.miniMode = false
                    }
                }
            )
        } else {
            regularContent(availableHeight: availableHeight)
        }
    }

    private func regularContent(availableHeight: CGFloat) -> some View {
        let baseRegularHeight = model.estimatedRegularPopoverHeight
        let resolvedRegularHeight = renderedPopoverHeight
        let liveRegularHeight = min(resolvedRegularHeight, max(baseRegularHeight, availableHeight))
        let regularMarqueeLaneWidth = min(272, max(130, renderedPopoverWidth - regularArtworkSize - 78))
        let visibleRegularDetailsHeight = min(
            model.regularLyricsPaneHeight,
            max(0, liveRegularHeight - baseRegularHeight)
        )
        let shouldRenderRegularDetailsPane = showRegularDetailsPane || visibleRegularDetailsHeight > 0.5
        let regularControlContrastBoost = model.regularControlsContrastBoost
        let searchTrailingAlignmentNudge: CGFloat = 4
        let regularDetachedTransparencyMultiplier: Double = model.surfaceMode == .detached ? 0.80 : 1.0
        let regularDetachedControlScale = model.detachedRegularControlScaleFactor
        let restingRegularDetailTab = model.selectedRegularDetailsTab
        let restingRegularControlOpacity: Double = regularPointerHovering ? 1 : 0.44
        let showDetailsCoachmark = onboarding.isCoachmarkActive(.detailsToggle)
        let showDetachedModeCoachmark = onboarding.isCoachmarkActive(.detachedMode)
        let showDetachedControlsCoachmark = onboarding.isCoachmarkActive(.detachedControls)
        let forceCoachmarkControlsVisible = onboarding.shouldForceModeCoachmarkControls()
        let interactiveRegularControlsVisible = regularPointerHovering || forceCoachmarkControlsVisible

        return VStack(spacing: 0) {
            regularPrimaryCard(
                regularMarqueeLaneWidth: regularMarqueeLaneWidth,
                regularControlContrastBoost: regularControlContrastBoost,
                regularDetachedControlScale: regularDetachedControlScale,
                searchTrailingAlignmentNudge: searchTrailingAlignmentNudge
            )
            .frame(height: baseRegularHeight, alignment: .top)
            .overlay(alignment: .topTrailing) {
                regularTrailingControls(
                    contrastBoost: regularControlContrastBoost,
                    controlScale: regularDetachedControlScale,
                    restingRegularDetailTab: restingRegularDetailTab,
                    restingRegularControlOpacity: restingRegularControlOpacity,
                    interactiveRegularControlsVisible: interactiveRegularControlsVisible,
                    showDetailsCoachmark: showDetailsCoachmark,
                    showDetachedModeCoachmark: showDetachedModeCoachmark,
                    showDetachedControlsCoachmark: showDetachedControlsCoachmark
                )
            }

            if shouldRenderRegularDetailsPane {
                RegularDetailsPane(
                    model: model,
                    selectedTab: model.selectedRegularDetailsTab,
                    lyricsState: model.lyricsState,
                    lyricsPayload: model.lyricsPayload,
                    lyricsLoadingProgress: model.lyricsLoadingProgress,
                    creditsPayload: model.creditsPayload,
                    glassTint: model.glassTint,
                    visibleHeight: visibleRegularDetailsHeight
                )
                .allowsHitTesting(regularDetailsRequested && visibleRegularDetailsHeight > 0.5)
            }
        }
        .frame(width: renderedPopoverWidth, height: resolvedRegularHeight, alignment: .topLeading)
        .background(
            ZStack {
                LiquidGlassBackground(
                    tint: model.glassTint,
                    readabilityBoost: regularControlContrastBoost,
                    transparencyMultiplier: regularDetachedTransparencyMultiplier
                )
            }
        )
        .overlay {
            regularPointerTrackingOverlay
        }
    }

    private func regularPrimaryCard(
        regularMarqueeLaneWidth: CGFloat,
        regularControlContrastBoost: Double,
        regularDetachedControlScale: CGFloat,
        searchTrailingAlignmentNudge: CGFloat
    ) -> some View {
        LiquidGlassCard(
            tint: model.glassTint,
            palette: model.cardBackgroundPalette,
            readabilityBoost: regularControlContrastBoost,
            transparencyMultiplier: model.surfaceMode == .detached ? 0.80 : 1.0
        ) {
            VStack(spacing: 8) {
                regularHeroRow(
                    regularMarqueeLaneWidth: regularMarqueeLaneWidth,
                    regularControlContrastBoost: regularControlContrastBoost,
                    regularDetachedControlScale: regularDetachedControlScale
                )

                regularSearchLane(
                    contrastBoost: regularControlContrastBoost,
                    controlScale: regularDetachedControlScale,
                    searchTrailingAlignmentNudge: searchTrailingAlignmentNudge
                )
            }
        }
    }

    private func coachmarkPopoverEdge(for coachmark: CoachmarkID) -> Edge {
        switch coachmark {
        case .search:
            return .bottom
        case .modeToggle, .detailsToggle, .detachedMode, .detachedControls, .settingsNavigation:
            return .top
        }
    }

    private func coachmarkAccent(for coachmark: CoachmarkID) -> Color {
        switch coachmark {
        case .modeToggle:
            return Color(red: 0.44, green: 0.71, blue: 0.97)
        case .search:
            return Color(red: 0.98, green: 0.72, blue: 0.35)
        case .detailsToggle:
            return Color(red: 0.87, green: 0.54, blue: 0.77)
        case .detachedMode:
            return Color(red: 0.53, green: 0.83, blue: 0.63)
        case .detachedControls:
            return Color(red: 0.53, green: 0.83, blue: 0.63)
        case .settingsNavigation:
            return Color.accentColor
        }
    }

    private var activePlayerCoachmark: CoachmarkID? {
        switch onboarding.activeCoachmark {
        case .modeToggle, .search, .detailsToggle, .detachedMode, .detachedControls:
            return onboarding.activeCoachmark
        case .settingsNavigation, .none:
            return nil
        }
    }

    @ViewBuilder
    private var playerCoachmarkOverlay: some View {
        if let coachmark = activePlayerCoachmark,
           let targetFrame = coachmarkTargetFrames[coachmark] {
            let layout = playerCoachmarkLayout(for: coachmark, targetFrame: targetFrame)
            PlayerCoachmarkCallout(
                coachmark: coachmark,
                accent: coachmarkAccent(for: coachmark),
                arrowEdge: layout.arrowEdge,
                arrowX: layout.arrowX
            ) {
                onboarding.dismissCoachmark(coachmark)
            }
            .offset(x: layout.origin.x, y: layout.origin.y)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topLeading)))
            .zIndex(40)
        }
    }

    private func playerCoachmarkLayout(for coachmark: CoachmarkID, targetFrame: CGRect) -> PlayerCoachmarkLayout {
        let bubbleWidth: CGFloat = 200
        let bubbleHeight = estimatedCoachmarkHeight(for: coachmark)
        let horizontalMargin: CGFloat = 14
        let verticalMargin: CGFloat = 14
        let targetSpacing: CGFloat = 12
        let arrowEdge = coachmarkPopoverEdge(for: coachmark)
        let clampedX = min(
            max(targetFrame.midX - (bubbleWidth / 2), horizontalMargin),
            max(horizontalMargin, renderedPopoverWidth - bubbleWidth - horizontalMargin)
        )
        let rawY: CGFloat

        switch arrowEdge {
        case .bottom:
            rawY = targetFrame.minY - bubbleHeight - targetSpacing
        case .top:
            rawY = targetFrame.maxY + targetSpacing
        default:
            rawY = targetFrame.maxY + targetSpacing
        }

        let clampedY = min(
            max(rawY, verticalMargin),
            max(verticalMargin, renderedPopoverHeight - bubbleHeight - verticalMargin)
        )
        let arrowX = min(max(targetFrame.midX - clampedX, 22), bubbleWidth - 22)

        return PlayerCoachmarkLayout(
            origin: CGPoint(x: clampedX, y: clampedY),
            arrowEdge: arrowEdge,
            arrowX: arrowX
        )
    }

    private func estimatedCoachmarkHeight(for coachmark: CoachmarkID) -> CGFloat {
        switch coachmark {
        case .modeToggle, .detailsToggle, .detachedControls:
            return 126
        case .search:
            return 136
        case .detachedMode:
            return 148
        case .settingsNavigation:
            return 128
        }
    }

    private func regularHeroRow(
        regularMarqueeLaneWidth: CGFloat,
        regularControlContrastBoost: Double,
        regularDetachedControlScale: CGFloat
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            regularArtworkTile

            VStack(alignment: .leading, spacing: 6) {
                regularMetadataColumn(
                    regularMarqueeLaneWidth: regularMarqueeLaneWidth,
                    regularControlContrastBoost: regularControlContrastBoost
                )

                regularControlsColumn(
                    regularControlContrastBoost: regularControlContrastBoost,
                    regularDetachedControlScale: regularDetachedControlScale
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var regularArtworkTile: some View {
        AnimatedArtworkView(
            image: model.artwork,
            tint: model.glassTint,
            isEnabled: false,
            seed: "regular|\(model.provider.rawValue)|\(model.artist)|\(model.albumArtist)|\(model.album)|\(model.title)",
            style: model.artworkMotionStyle,
            animatedArtworkURL: model.effectiveAnimatedArtworkURL,
            animatedArtworkIsVisible: model.isPopoverVisible,
            animateOnFirstAppear: !modeTransitionActive
        )
        .frame(width: regularArtworkSize, height: regularArtworkSize)
        .animatedArtworkMotion(
            isEnabled: model.animatedArtworkEnabled,
            seed: "regular|\(model.provider.rawValue)|\(model.artist)|\(model.albumArtist)|\(model.album)|\(model.title)",
            style: model.artworkMotionStyle,
            isPlaying: model.isPlaying,
            hasAnimatedStream: model.effectiveAnimatedArtworkURL != nil,
            tint: model.glassTint,
            artworkImage: model.artwork
        )
        .matchedGeometryEffect(id: "heroArtwork", in: artworkMorphNamespace)
    }

    private func regularMetadataColumn(
        regularMarqueeLaneWidth: CGFloat,
        regularControlContrastBoost: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { model.openProviderApp() }) {
                NowPlayingTitleMarquee(
                    text: model.displayTitle,
                    enabled: true,
                    isVisible: model.isPopoverVisible,
                    laneWidth: regularMarqueeLaneWidth
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NowPlayingSecondaryMarquee(
                text: model.artistAlbumLine,
                enabled: true,
                isVisible: model.isPopoverVisible,
                laneWidth: regularMarqueeLaneWidth,
                usesSecondaryStyle: false
            )

            PlaybackProgressBlock(
                contrastBoost: regularControlContrastBoost,
                onSeek: { model.seek(to: $0) }
            )
        }
        .opacity(modePrimaryContentVisible ? 1 : 0)
        .offset(y: modePrimaryContentVisible ? 0 : 8)
        .animation(modePrimaryRevealAnimation, value: modePrimaryContentVisible)
    }

    private func regularControlsColumn(
        regularControlContrastBoost: Double,
        regularDetachedControlScale: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                ControlsRow(
                    isPlaying: model.isPlaying,
                    onPrev: { model.previousTrack() },
                    onPlayPause: { model.playPause() },
                    onNext: { model.nextTrack() },
                    contrastBoost: regularControlContrastBoost,
                    controlScale: regularDetachedControlScale
                )
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            OutputControlsRow(
                model: model,
                showDeviceName: true,
                contrastBoost: regularControlContrastBoost,
                controlScale: regularDetachedControlScale,
                showFavorite: model.canFavoriteCurrentTrack,
                favoriteIsActive: model.isCurrentTrackFavorited,
                favoritePulseToken: model.favoriteActionPulseToken,
                onFavorite: { _ = model.toggleCurrentTrackFavorite() }
            )
            .padding(.top, 4)
        }
        .opacity(modeSecondaryContentVisible ? 1 : 0)
        .offset(y: modeSecondaryContentVisible ? 0 : 10)
        .animation(modeSecondaryRevealAnimation, value: modeSecondaryContentVisible)
    }

    @ViewBuilder
    private func regularSearchLane(
        contrastBoost: Double,
        controlScale: CGFloat,
        searchTrailingAlignmentNudge: CGFloat
    ) -> some View {
        if model.resolvedSearchProvider != .none {
            HStack {
                Spacer(minLength: 0)
                searchSection(
                    maxWidth: min(280, max(170, renderedPopoverWidth * 0.50)),
                    contrastBoost: contrastBoost,
                    controlScale: controlScale
                )
            }
            .padding(.trailing, -searchTrailingAlignmentNudge)
            .padding(.top, -24)
            .padding(.bottom, -12)
            .opacity(modeSecondaryContentVisible ? 1 : 0)
            .offset(y: modeSecondaryContentVisible ? 0 : 10)
            .animation(modeSecondaryRevealAnimation, value: modeSecondaryContentVisible)
        }
    }

    private func regularTrailingControls(
        contrastBoost: Double,
        controlScale: CGFloat,
        restingRegularDetailTab: DetailsPaneTab,
        restingRegularControlOpacity: Double,
        interactiveRegularControlsVisible: Bool,
        showDetailsCoachmark: Bool,
        showDetachedModeCoachmark: Bool,
        showDetachedControlsCoachmark: Bool
    ) -> some View {
        HStack(spacing: 6 * controlScale) {
            regularModeToggle(
                contrastBoost: contrastBoost,
                controlScale: controlScale,
                restingRegularControlOpacity: restingRegularControlOpacity
            )

            regularDetachedControls(
                contrastBoost: contrastBoost,
                controlScale: controlScale,
                showDetachedModeCoachmark: showDetachedModeCoachmark,
                showDetachedControlsCoachmark: showDetachedControlsCoachmark
            )

            regularDetailControls(
                contrastBoost: contrastBoost,
                controlScale: controlScale,
                restingRegularDetailTab: restingRegularDetailTab,
                restingRegularControlOpacity: restingRegularControlOpacity,
                interactiveRegularControlsVisible: interactiveRegularControlsVisible,
                showDetailsCoachmark: showDetailsCoachmark
            )

            if regularPointerHovering {
                regularSettingsControl(contrastBoost: contrastBoost, controlScale: controlScale)
            }
        }
        .padding(.top, 8 * controlScale)
        .padding(.trailing, 14 * controlScale)
        .opacity(modeSecondaryContentVisible ? 1 : 0)
        .offset(y: modeSecondaryContentVisible ? 0 : -8)
        .allowsHitTesting(modeSecondaryContentVisible)
        .animation(.easeInOut(duration: 0.16), value: interactiveRegularControlsVisible)
        .animation(modeSecondaryRevealAnimation, value: modeSecondaryContentVisible)
    }

    private func regularModeToggle(
        contrastBoost: Double,
        controlScale: CGFloat,
        restingRegularControlOpacity: Double
    ) -> some View {
        ModeToggleControl(
            isMiniMode: false,
            transitionActive: modeTransitionActive,
            contrastBoost: contrastBoost,
            sizeScale: controlScale
        ) {
            prepareModeTransition(to: true)
            withAnimation(modeMorphAnimation) {
                pendingMiniInitialExpand = true
                model.miniMode = true
            }
        }
        .playerCoachmarkTarget(.modeToggle)
        .opacity(restingRegularControlOpacity)
    }

    @ViewBuilder
    private func regularDetachedControls(
        contrastBoost: Double,
        controlScale: CGFloat,
        showDetachedModeCoachmark: Bool,
        showDetachedControlsCoachmark: Bool
    ) -> some View {
        if regularPointerHovering || showDetachedModeCoachmark || showDetachedControlsCoachmark {
            DetachedSurfaceToggleControl(
                isDetachedMode: model.surfaceMode == .detached,
                transitionActive: modeTransitionActive,
                contrastBoost: contrastBoost,
                sizeScale: controlScale
            ) {
                model.requestToggleDetachedMode()
            }
            .playerCoachmarkTarget(.detachedMode)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }

        if model.surfaceMode == .detached && (regularPointerHovering || showDetachedControlsCoachmark) {
            DetachedWindowPinControl(
                isPinned: model.detachedWindowAlwaysOnTop,
                transitionActive: modeTransitionActive,
                contrastBoost: contrastBoost,
                sizeScale: controlScale
            ) {
                model.detachedWindowAlwaysOnTop.toggle()
            }
            .playerCoachmarkTarget(.detachedControls)
            .transition(.opacity.combined(with: .move(edge: .trailing)))

            DetachedWindowCloseControl(
                transitionActive: modeTransitionActive,
                contrastBoost: contrastBoost,
                sizeScale: controlScale
            ) {
                model.requestCloseDetachedWindow()
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    @ViewBuilder
    private func regularDetailControls(
        contrastBoost: Double,
        controlScale: CGFloat,
        restingRegularDetailTab: DetailsPaneTab,
        restingRegularControlOpacity: Double,
        interactiveRegularControlsVisible: Bool,
        showDetailsCoachmark: Bool
    ) -> some View {
        if regularPointerHovering || restingRegularDetailTab == .lyrics || showDetailsCoachmark {
            RegularDetailToggleControl(
                isOn: model.lyricsPanelExpanded && model.selectedRegularDetailsTab == .lyrics,
                systemName: model.selectedRegularDetailsTab == .lyrics && model.lyricsPanelExpanded ? "quote.bubble.fill" : "quote.bubble",
                helpText: model.lyricsPanelExpanded && model.selectedRegularDetailsTab == .lyrics ? "Hide lyrics" : "Show lyrics",
                transitionActive: modeTransitionActive,
                contrastBoost: contrastBoost,
                sizeScale: controlScale
            ) {
                toggleRegularDetails(tab: .lyrics)
            }
            .playerCoachmarkTarget(.detailsToggle)
            .opacity(interactiveRegularControlsVisible ? 1 : restingRegularControlOpacity)
        }

        if regularPointerHovering || restingRegularDetailTab == .credits {
            RegularDetailToggleControl(
                isOn: model.lyricsPanelExpanded && model.selectedRegularDetailsTab == .credits,
                systemName: model.lyricsPanelExpanded && model.selectedRegularDetailsTab == .credits ? "info.circle.fill" : "info.circle",
                helpText: model.lyricsPanelExpanded && model.selectedRegularDetailsTab == .credits ? "Hide credits" : "Show credits",
                transitionActive: modeTransitionActive,
                contrastBoost: contrastBoost,
                sizeScale: controlScale
            ) {
                toggleRegularDetails(tab: .credits)
            }
            .opacity(regularPointerHovering ? 1 : restingRegularControlOpacity)
        }
    }

    private func regularSettingsControl(contrastBoost: Double, controlScale: CGFloat) -> some View {
        SettingsOpenControl {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16 * controlScale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: 24 * controlScale, height: 24 * controlScale)
                .background(Circle().fill(Color.primary.opacity(min(0.34, 0.08 + (0.18 * contrastBoost)))))
                .overlay(
                    Circle()
                        .stroke(.white.opacity(min(0.28, 0.16 + (0.08 * contrastBoost))), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .hoverHint("Settings", enabled: !modeTransitionActive)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var regularPointerTrackingOverlay: some View {
        MiniCardPointerTrackingOverlay(enabled: true) { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                regularPointerHovering = hovering
            }
        }
        .allowsHitTesting(false)
    }

    private func searchSection(maxWidth: CGFloat, contrastBoost: Double, controlScale: CGFloat = 1) -> some View {
        let searchProvider = model.resolvedSearchProvider
        let searchPlaceholder = searchProvider == .spotify ? "Search Spotify" : "Search Music library"
        let actionLabel = searchProvider == .spotify ? "Open" : "Play"
        let clampedContrast = min(max(contrastBoost, 0), 1)
        let clampedControlScale = min(max(controlScale, 0.80), 1.20)
        let searchForeground = Color.white
        let searchFillOpacity = min(0.34, 0.08 + (0.18 * clampedContrast))
        let searchStrokeOpacity = min(0.28, 0.12 + (0.08 * clampedContrast))
        let searchDarkenOpacity = 0.10 * clampedContrast
        let actionTint = Color.black.opacity(min(0.88, 0.44 + (0.34 * clampedContrast)))
        let spacing: CGFloat = 4 * clampedControlScale
        let collapsedWidth: CGFloat = 30 * clampedControlScale
        let playWidth: CGFloat = 64 * clampedControlScale
        let rowWidth = max(180, maxWidth)
        let expandedSearchWidth = max(140, rowWidth - playWidth - spacing)
        let containerWidth = isSearchExpanded ? expandedSearchWidth : collapsedWidth
        let textFieldWidth = max(0, expandedSearchWidth - (40 * clampedControlScale))
        let spring = Animation.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)

        return HStack(spacing: spacing) {
            HStack(spacing: isSearchExpanded ? (6 * clampedControlScale) : 0) {
                Button {
                    if isSearchExpanded && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        withAnimation(spring) {
                            isSearchExpanded = false
                        }
                        isSearchFocused = false
                    } else if !isSearchExpanded {
                        withAnimation(spring) {
                            isSearchExpanded = true
                        }
                        isSearchFocused = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .imageScale(.small)
                        .foregroundStyle(searchForeground.opacity(0.90))
                        .frame(width: 18 * clampedControlScale, height: 18 * clampedControlScale)
                }
                .buttonStyle(.plain)
                .playerCoachmarkTarget(.search)
                .frame(
                    width: isSearchExpanded ? (18 * clampedControlScale) : collapsedWidth,
                    height: 34 * clampedControlScale,
                    alignment: .center
                )
                .contentShape(Rectangle())

                TextField(searchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12 * clampedControlScale, weight: .medium, design: .rounded))
                    .foregroundStyle(searchForeground.opacity(0.94))
                    .focused($isSearchFocused)
                    .onSubmit { runSearchAction() }
                    .frame(width: isSearchExpanded ? textFieldWidth : 0, alignment: .leading)
                    .opacity(isSearchExpanded ? 1 : 0)
                    .allowsHitTesting(isSearchExpanded)
            }
            .padding(.horizontal, isSearchExpanded ? (8 * clampedControlScale) : 0)
            .frame(width: containerWidth, height: 34 * clampedControlScale, alignment: isSearchExpanded ? .leading : .center)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 11 * clampedControlScale, style: .continuous)
                        .fill(Color.primary.opacity(searchFillOpacity))
                    RoundedRectangle(cornerRadius: 11 * clampedControlScale, style: .continuous)
                        .fill(Color.black.opacity(searchDarkenOpacity))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11 * clampedControlScale, style: .continuous)
                    .stroke(.white.opacity(searchStrokeOpacity), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11 * clampedControlScale, style: .continuous))
            .onTapGesture {
                guard !isSearchExpanded else { return }
                withAnimation(spring) {
                    isSearchExpanded = true
                }
                isSearchFocused = true
            }

            Button(actionLabel) {
                runSearchAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(actionTint)
            .foregroundStyle(.white.opacity(0.95))
            .controlSize(.small)
            .frame(width: isSearchExpanded ? playWidth : 0)
            .opacity(isSearchExpanded ? 1 : 0)
            .scaleEffect(isSearchExpanded ? 1 : 0.95)
            .allowsHitTesting(isSearchExpanded)
            .clipped()
            .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        }
        .frame(height: 44 * clampedControlScale)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchSectionFramePreferenceKey.self,
                    value: isSearchExpanded ? proxy.frame(in: .named("popoverRoot")) : .zero
                )
            }
        )
        .onChange(of: isSearchFocused) { _, focused in
            if !focused && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                withAnimation(spring) {
                    isSearchExpanded = false
                }
            }
        }
    }

    private func updateSearchSectionFrame(_ frame: CGRect) {
        guard isSearchExpanded else {
            if searchSectionFrame != .zero {
                searchSectionFrame = .zero
            }
            return
        }

        let snappedFrame = CGRect(
            x: frame.origin.x.rounded(),
            y: frame.origin.y.rounded(),
            width: frame.size.width.rounded(),
            height: frame.size.height.rounded()
        )

        guard !rectApproximatelyEqual(searchSectionFrame, snappedFrame, tolerance: 0.5) else { return }
        searchSectionFrame = snappedFrame
    }

    private func rectApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
        abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
        abs(lhs.size.width - rhs.size.width) <= tolerance &&
        abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    private func runSearchAction() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        model.runSearchAction(query: query)
        searchText = ""
    }

    private func prepareModeTransition(to targetMiniMode: Bool) {
        guard targetMiniMode != model.miniMode else { return }
        modeTransitionActive = true
    }

    private func beginModeTransition() {
        modeTransitionActive = true
    }

    private var regularDetailsRequested: Bool {
        !model.miniMode && model.lyricsPanelExpanded
    }

    private func syncRenderedRegularDetailsPaneImmediately() {
        regularDetailsHideWorkItem?.cancel()
        regularDetailsHideWorkItem = nil
        showRegularDetailsPane = regularDetailsRequested
    }

    private func syncRenderedRegularDetailsPane(for enabled: Bool) {
        regularDetailsHideWorkItem?.cancel()
        regularDetailsHideWorkItem = nil

        if enabled {
            showRegularDetailsPane = true
            return
        }

        let work = DispatchWorkItem {
            guard !regularDetailsRequested else { return }
            showRegularDetailsPane = false
            regularDetailsHideWorkItem = nil
        }
        regularDetailsHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + miniLyricsTransitionDuration, execute: work)
    }

    private func toggleRegularDetails(tab: DetailsPaneTab) {
        let willExpand = !(model.lyricsPanelExpanded && model.selectedRegularDetailsTab == tab)
        model.toggleRegularDetailsTab(tab)
        syncRenderedRegularDetailsPane(for: willExpand && !model.miniMode)
    }

    private func updateCoachmarkAvailability() {
        let regularSurface = !displayedMiniMode
        onboarding.registerCoachmark(.modeToggle, available: regularSurface)
        onboarding.registerCoachmark(.search, available: regularSurface && model.resolvedSearchProvider != .none)
        onboarding.registerCoachmark(.detailsToggle, available: regularSurface)
        onboarding.registerCoachmark(.detachedMode, available: regularSurface && model.surfaceMode == .popover)
        onboarding.registerCoachmark(.detachedControls, available: regularSurface && model.surfaceMode == .detached)
    }

    private func clearCoachmarkAvailability() {
        onboarding.registerCoachmark(.modeToggle, available: false)
        onboarding.registerCoachmark(.search, available: false)
        onboarding.registerCoachmark(.detailsToggle, available: false)
        onboarding.registerCoachmark(.detachedMode, available: false)
        onboarding.registerCoachmark(.detachedControls, available: false)
    }
}

private struct PlayerCoachmarkLayout {
    let origin: CGPoint
    let arrowEdge: Edge
    let arrowX: CGFloat
}

private struct PlayerCoachmarkFramePreferenceKey: PreferenceKey {
    static var defaultValue: [CoachmarkID: CGRect] = [:]

    static func reduce(value: inout [CoachmarkID: CGRect], nextValue: () -> [CoachmarkID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct PlayerCoachmarkArrow: Shape {
    let edge: Edge

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch edge {
        case .top:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .bottom:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        default:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.closeSubpath()
        return path
    }
}

private struct PlayerCoachmarkCallout: View {
    let coachmark: CoachmarkID
    let accent: Color
    let arrowEdge: Edge
    let arrowX: CGFloat
    let onDismiss: () -> Void

    private let bubbleWidth: CGFloat = 200
    private let arrowWidth: CGFloat = 18
    private let arrowHeight: CGFloat = 10

    var body: some View {
        Group {
            if arrowEdge == .bottom {
                VStack(spacing: -1) {
                    bubble
                    arrow
                }
            } else {
                VStack(spacing: -1) {
                    arrow
                    bubble
                }
            }
        }
        .frame(width: bubbleWidth, alignment: .leading)
        .allowsHitTesting(true)
    }

    private var bubble: some View {
        CoachmarkBubble(
            coachmark: coachmark,
            accent: accent,
            onDismiss: onDismiss
        )
    }

    private var arrow: some View {
        Color.clear
            .frame(width: bubbleWidth, height: arrowHeight)
            .overlay(alignment: .leading) {
                PlayerCoachmarkArrow(edge: arrowEdge)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: arrowWidth, height: arrowHeight)
                    .overlay {
                        PlayerCoachmarkArrow(edge: arrowEdge)
                            .stroke(accent.opacity(0.28), lineWidth: 1)
                    }
                    .offset(x: min(max(arrowX - (arrowWidth / 2), 12), bubbleWidth - arrowWidth - 12))
            }
    }
}

private extension View {
    func playerCoachmarkTarget(_ coachmark: CoachmarkID) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PlayerCoachmarkFramePreferenceKey.self,
                    value: [coachmark: proxy.frame(in: .named("popoverRoot"))]
                )
            }
        }
    }
}
