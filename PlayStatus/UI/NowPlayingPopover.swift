import SwiftUI
import AppKit

private let modeMorphAnimation = Animation.interactiveSpring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.10)
private let modePrimaryRevealAnimation = Animation.easeOut(duration: 0.20)
private let modeSecondaryRevealAnimation = Animation.easeOut(duration: 0.24)
private let miniSeamBlendHeight: CGFloat = 1
private let miniSeamBlurRadius: CGFloat = 10

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
        .onPreferenceChange(SearchSectionFramePreferenceKey.self) { frame in
            updateSearchSectionFrame(frame)
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
        let showModeCoachmark = onboarding.isCoachmarkActive(.modeToggle)
        let showDetailsCoachmark = onboarding.isCoachmarkActive(.detailsToggle)
        let showDetachedCoachmark = onboarding.isCoachmarkActive(.detachedControls)
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
                    showModeCoachmark: showModeCoachmark,
                    showDetailsCoachmark: showDetailsCoachmark,
                    showDetachedCoachmark: showDetachedCoachmark
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
            seed: "regular|\(model.provider.rawValue)|\(model.artist)|\(model.title)",
            style: model.artworkMotionStyle,
            animatedArtworkURL: model.effectiveAnimatedArtworkURL,
            animatedArtworkIsVisible: model.isPopoverVisible,
            animateOnFirstAppear: !modeTransitionActive
        )
        .frame(width: regularArtworkSize, height: regularArtworkSize)
        .animatedArtworkMotion(
            isEnabled: model.animatedArtworkEnabled,
            seed: "regular|\(model.provider.rawValue)|\(model.artist)|\(model.title)",
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
        showModeCoachmark: Bool,
        showDetailsCoachmark: Bool,
        showDetachedCoachmark: Bool
    ) -> some View {
        HStack(spacing: 6 * controlScale) {
            regularModeToggle(
                contrastBoost: contrastBoost,
                controlScale: controlScale,
                restingRegularControlOpacity: restingRegularControlOpacity,
                showModeCoachmark: showModeCoachmark
            )

            regularDetachedControls(
                contrastBoost: contrastBoost,
                controlScale: controlScale,
                showDetachedCoachmark: showDetachedCoachmark
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
        restingRegularControlOpacity: Double,
        showModeCoachmark: Bool
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
        .overlay(alignment: .bottomTrailing) {
            if showModeCoachmark {
                CoachmarkBubble(
                    coachmark: .modeToggle,
                    accent: Color(red: 0.44, green: 0.71, blue: 0.97)
                ) {
                    onboarding.dismissCoachmark(.modeToggle)
                }
                .offset(x: 16, y: 42)
            }
        }
        .opacity(restingRegularControlOpacity)
    }

    @ViewBuilder
    private func regularDetachedControls(
        contrastBoost: Double,
        controlScale: CGFloat,
        showDetachedCoachmark: Bool
    ) -> some View {
        if regularPointerHovering || showDetachedCoachmark {
            DetachedSurfaceToggleControl(
                isDetachedMode: model.surfaceMode == .detached,
                transitionActive: modeTransitionActive,
                contrastBoost: contrastBoost,
                sizeScale: controlScale
            ) {
                model.requestToggleDetachedMode()
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }

        if model.surfaceMode == .detached && (regularPointerHovering || showDetachedCoachmark) {
            DetachedWindowPinControl(
                isPinned: model.detachedWindowAlwaysOnTop,
                transitionActive: modeTransitionActive,
                contrastBoost: contrastBoost,
                sizeScale: controlScale
            ) {
                model.detachedWindowAlwaysOnTop.toggle()
            }
            .overlay(alignment: .bottomTrailing) {
                if showDetachedCoachmark {
                    CoachmarkBubble(
                        coachmark: .detachedControls,
                        accent: Color(red: 0.53, green: 0.83, blue: 0.63)
                    ) {
                        onboarding.dismissCoachmark(.detachedControls)
                    }
                    .offset(x: 18, y: 42)
                }
            }
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
            .overlay(alignment: .bottomTrailing) {
                if showDetailsCoachmark {
                    CoachmarkBubble(
                        coachmark: .detailsToggle,
                        accent: Color(red: 0.87, green: 0.54, blue: 0.77)
                    ) {
                        onboarding.dismissCoachmark(.detailsToggle)
                    }
                    .offset(x: 18, y: 42)
                }
            }
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
        .overlay(alignment: .bottomTrailing) {
            if onboarding.isCoachmarkActive(.search) {
                CoachmarkBubble(
                    coachmark: .search,
                    accent: Color(red: 0.98, green: 0.72, blue: 0.35)
                ) {
                    onboarding.dismissCoachmark(.search)
                }
                .offset(x: 10, y: 42)
            }
        }
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
        onboarding.registerCoachmark(.detachedControls, available: regularSurface && model.surfaceMode == .detached)
    }

    private func clearCoachmarkAvailability() {
        onboarding.registerCoachmark(.modeToggle, available: false)
        onboarding.registerCoachmark(.search, available: false)
        onboarding.registerCoachmark(.detailsToggle, available: false)
        onboarding.registerCoachmark(.detachedControls, available: false)
    }

}

private struct SearchSectionFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct TopRoundedBandShape: Shape {
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

private extension View {
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
        return self
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
        return self
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

/// Thin wrapper around ProgressBlock that observes PlaybackClock instead of
/// NowPlayingModel. This prevents NowPlayingPopover (which observes NowPlayingModel)
/// from receiving objectWillChange notifications on every 0.5-second elapsed tick.
private struct PlaybackProgressBlock: View {
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

private struct MiniNowPlayingCard: View {
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
        let miniDetachedControlScale = model.detachedMiniControlScaleFactor
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
        let miniMetadataSpacing = (pointerHovering ? 8.0 : 5.0) * miniDetachedControlScale
        let miniLowerPanelContentHorizontalPadding = (pointerHovering ? 12.0 : 10.0) * miniDetachedControlScale
        let miniLowerPanelContentVerticalPadding = (pointerHovering ? 10.0 : 5.5) * miniDetachedControlScale
        let infoBandHeight: CGFloat = (infoExpanded ? 196.0 : 94.0) * miniDetachedControlScale
        let resolvedCardHeight = resolvedHeight
        let liveCardHeight = min(resolvedCardHeight, max(model.miniBaseHeight, availableHeight))
        let visibleLyricsHeight = min(
            model.miniLyricsPaneHeight,
            max(0, liveCardHeight - model.miniBaseHeight)
        )
        let shouldRenderMiniLyricsPane = showMiniLyricsPane || visibleLyricsHeight > 0.5
        let seamOpacity = min(1, max(0, visibleLyricsHeight / max(1, model.miniLyricsPaneHeight)))
        let miniMarqueeLaneWidth = max(120, model.miniPopoverWidth - 64)
        let miniTrackKey = "\(model.provider.rawValue)|\(model.artist)|\(model.album)|\(model.title)"
        let miniLowerPanelHorizontalInset = (pointerHovering ? 6.0 : 14.0) * miniDetachedControlScale
        let miniLowerPanelBottomInset = (pointerHovering ? 15.0 : 8.0) * miniDetachedControlScale
        let miniLowerPanelHoverLift = (pointerHovering ? 8.0 : 0) * miniDetachedControlScale
        let miniInfoBandTopCornerRadius = 24 * miniDetachedControlScale
        let showMiniControlRow = pointerHovering && primaryContentVisible
        let showMiniSecondaryControls = showMiniControlRow && secondaryContentVisible
        let cardShell = miniCardShell(
            bottomShade: bottomShade,
            topShade: topShade,
            neutralWashOpacity: neutralWashOpacity,
            blueFogOpacity: blueFogOpacity,
            miniDetachedControlScale: miniDetachedControlScale,
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
        miniDetachedControlScale: CGFloat,
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
            miniDetachedControlScale: miniDetachedControlScale,
            showMiniControlRow: showMiniControlRow,
            showMiniSecondaryControls: showMiniSecondaryControls,
            neutralWashOpacity: neutralWashOpacity,
            blueFogOpacity: blueFogOpacity
        )
        let bottomPanel = miniCardBottomPanel(
            miniDetachedControlScale: miniDetachedControlScale,
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
        // Re-clip after all overlays so bottom-band content cannot spill into the lyrics pane.
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
            seed: "mini|\(model.provider.rawValue)|\(model.artist)|\(model.title)",
            style: model.artworkMotionStyle,
            isPlaying: model.isPlaying,
            hasAnimatedStream: model.effectiveAnimatedArtworkURL != nil,
            tint: model.glassTint,
            artworkImage: model.artwork
        )
        .padding(8)
    }

    private func miniCardTopControls(
        miniDetachedControlScale: CGFloat,
        showMiniControlRow: Bool,
        showMiniSecondaryControls: Bool,
        neutralWashOpacity: Double,
        blueFogOpacity: Double
    ) -> some View {
        HStack(spacing: 6 * miniDetachedControlScale) {
            ModeToggleControl(
                isMiniMode: true,
                transitionActive: transitionActive,
                sizeScale: miniDetachedControlScale,
                action: onToggleMode
            )

            if showMiniSecondaryControls {
                DetachedSurfaceToggleControl(
                    isDetachedMode: model.surfaceMode == .detached,
                    transitionActive: transitionActive,
                    sizeScale: miniDetachedControlScale
                ) {
                    model.requestToggleDetachedMode()
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                if model.surfaceMode == .detached {
                    DetachedWindowPinControl(
                        isPinned: model.detachedWindowAlwaysOnTop,
                        transitionActive: transitionActive,
                        sizeScale: miniDetachedControlScale
                    ) {
                        model.detachedWindowAlwaysOnTop.toggle()
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))

                    DetachedWindowCloseControl(
                        transitionActive: transitionActive,
                        sizeScale: miniDetachedControlScale
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
                    sizeScale: miniDetachedControlScale
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
                    sizeScale: miniDetachedControlScale
                ) {
                    toggleMiniDetails(tab: .credits)
                }
            }

            if showMiniSecondaryControls {
                SettingsOpenControl {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16 * miniDetachedControlScale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .frame(
                            width: 26 * miniDetachedControlScale,
                            height: 26 * miniDetachedControlScale
                        )
                        .background(Circle().fill(Color.white.opacity(0.14)))
                        .overlay(
                            Circle().stroke(.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .hoverHint("Settings", enabled: !transitionActive)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .miniControlClusterBackground(
            sizeScale: miniDetachedControlScale,
            neutralWashOpacity: neutralWashOpacity * 0.65,
            blueFogOpacity: blueFogOpacity * 0.65
        )
        .fixedSize(horizontal: true, vertical: false)
        .padding(.top, 10 * miniDetachedControlScale)
        .padding(.trailing, 10 * miniDetachedControlScale)
        .opacity(showMiniControlRow ? 1 : 0)
        .offset(y: showMiniControlRow ? 0 : -6)
        .allowsHitTesting(showMiniControlRow)
        .animation(.easeInOut(duration: 0.16), value: pointerHovering)
        .animation(modePrimaryRevealAnimation, value: primaryContentVisible)
        .animation(modeSecondaryRevealAnimation, value: secondaryContentVisible)
    }

    private func miniCardBottomPanel(
        miniDetachedControlScale: CGFloat,
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
                                onPrev: { model.previousTrack() },
                                onPlayPause: { model.playPause() },
                                onNext: { model.nextTrack() },
                                contrastBoost: miniInfoBandContrastBoost,
                                controlScale: miniDetachedControlScale
                            )
                            Spacer(minLength: 0)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                        OutputControlsRow(
                            model: model,
                            showDeviceName: false,
                            contrastBoost: miniInfoBandContrastBoost,
                            controlScale: miniDetachedControlScale,
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
                sizeScale: miniDetachedControlScale,
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
            // Closing the pane shrinks the card immediately; keep controls visible
            // until we receive a definitive pointer-exit event.
            pointerHovering = true
            forceExpandedUntilPointerExit = true
        }

        model.toggleMiniDetailsTab(tab)
    }

    private var artworkLuminance: CGFloat {
        guard let average = model.artwork?.averageColor()?.usingColorSpace(.deviceRGB) else {
            return 0.45
        }
        let r = average.redComponent
        let g = average.greenComponent
        let b = average.blueComponent
        return (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
    }
}

private struct MiniArtworkTransitionSurface: View {
    let artwork: NSImage?
    let tint: Color
    let trackKey: String
    let animationsEnabled: Bool
    let transitionActive: Bool
    let animatedArtworkURL: URL?
    let isPopoverVisible: Bool

    var body: some View {
        ArtworkStreamTransitionSurface(
            image: artwork,
            animatedArtworkURL: animatedArtworkURL,
            isActive: isPopoverVisible,
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

private struct MiniCardPointerTrackingOverlay: NSViewRepresentable {
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

private final class TrackingNSView: NSView {
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
        // Run once more after attachment so first-entry hover is correct when
        // the popover/window appears under a stationary cursor.
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

private func lyricsBleedOpacities(for artworkColorIntensity: Double) -> (top: Double, mid: Double) {
    let intensity = min(max(artworkColorIntensity, 0.5), 1.8)
    // Directly scale bleed with the Settings "Artwork Color Intensity" slider.
    return (
        top: min(0.38, 0.20 * intensity),
        mid: min(0.20, 0.10 * intensity)
    )
}

private struct MiniExpandedDetailsPane: View {
    @ObservedObject var model: NowPlayingModel
    let selectedTab: DetailsPaneTab
    let visibleHeight: CGFloat
    @State private var activeLineID: UUID?
    @State private var coordinator = LyricsScrollCoordinator()
    @State private var enableLyricLineAnimations = false
    @State private var settleWorkItem: DispatchWorkItem?

    var body: some View {
        let bleed = lyricsBleedOpacities(for: model.artworkColorIntensity)

        ZStack(alignment: .top) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.56),
                        Color.black.opacity(0.62),
                        Color.black.opacity(0.70)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Subtle tint bleed so the details pane inherits current artwork mood.
                LinearGradient(
                    colors: [
                        model.glassTint.opacity(bleed.top),
                        model.glassTint.opacity(bleed.mid),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.screen)
            }
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.04), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: [
                            model.glassTint.opacity(0.18),
                            model.glassTint.opacity(0.08),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.screen)

                    LinearGradient(
                        colors: [
                            .white.opacity(0.07),
                            .white.opacity(0.025),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    LinearGradient(
                        colors: [
                            .black.opacity(0.14),
                            .black.opacity(0.05),
                            .clear
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                }
                .frame(height: miniSeamBlendHeight)
                .blur(radius: miniSeamBlurRadius * 0.35)
                .allowsHitTesting(false)
            }
            .overlay(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.16), .black.opacity(0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    DetailPaneTabChip(tab: .lyrics, isSelected: selectedTab == .lyrics) {
                        model.selectMiniDetailsTab(.lyrics)
                    }
                    DetailPaneTabChip(tab: .credits, isSelected: selectedTab == .credits) {
                        model.selectMiniDetailsTab(.credits)
                    }

                    Spacer(minLength: 0)
                    miniDetailSourceBadge
                }

                switch selectedTab {
                case .lyrics:
                    lyricsPaneContent
                case .credits:
                    creditsPaneContent
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .frame(height: max(0, visibleHeight), alignment: .top)
        .onAppear {
            updateLyricAnimationState(for: selectedTab)
        }
        .onDisappear {
            cancelLyricAnimationState()
        }
        .onChange(of: selectedTab) { _, tab in
            updateLyricAnimationState(for: tab)
        }
        .onChange(of: model.lyricsPayload?.lines.first?.id) { _, _ in
            guard selectedTab == .lyrics else { return }
            // Track changed — restart the coordinator with fresh lines.
            let lines = model.lyricsPayload?.lines ?? []
            let isTimed = model.lyricsPayload?.isTimed ?? false
            coordinator.lines = lines
            coordinator.isTimed = isTimed
            coordinator.onActiveLineChanged = { id in
                activeLineID = id
            }
            if coordinator.scrollProxy != nil {
                coordinator.start()
            }
        }
    }

    @ViewBuilder
    private var lyricsPaneContent: some View {
        switch model.lyricsState {
        case .idle:
            DetailPaneStateMessage(
                message: "Start playback to load lyrics.",
                icon: .sfSymbol("play.square"),
                style: .mini
            )
        case .loading:
            let progress = model.lyricsLoadingProgress
            LyricsLoadingPulseBlock(
                primaryFontSize: 12,
                secondaryText: miniLoadingMessage(progress: progress),
                secondaryFontSize: 11
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        case .unavailable:
            DetailPaneStateMessage(
                message: "Lyrics unavailable for this track.",
                icon: .sfSymbol("text.bubble"),
                style: .mini
            )
        case .failed:
            DetailPaneStateMessage(
                message: "Couldn't fetch lyrics right now.",
                icon: .sfSymbol("exclamationmark.octagon"),
                style: .mini
            )
        case .available:
            lyricsScroll
        }
    }

    @ViewBuilder
    private var creditsPaneContent: some View {
        if model.provider == .none || model.title.isEmpty {
            DetailPaneStateMessage(
                message: "Start playback to view credits.",
                icon: .sfSymbol("info.circle"),
                style: .mini
            )
        } else if let creditsPayload = model.creditsPayload, creditsPayload.hasContent {
            CreditsPaneContent(payload: creditsPayload, style: .compact(maxVisibleRows: 5))
        } else {
            DetailPaneStateMessage(
                message: "Credits unavailable for this track.",
                icon: .sfSymbol("info.circle"),
                style: .mini
            )
        }
    }

    private func miniLoadingMessage(progress: LyricsLoadingProgress?) -> String {
        guard let progress else { return "Preparing lyric request" }
        return "\(progress.stage.displayTitle) · Attempt \(progress.attempt) of \(progress.maxAttempts)"
    }

    @ViewBuilder
    private var miniDetailSourceBadge: some View {
        switch selectedTab {
        case .lyrics:
            if let source = model.lyricsPayload?.source, source != .none {
                if source == .lrclib {
                    Button(action: openLRCLibWebsite) {
                        DetailPaneSourceBadge(text: "LRCLib", emphasized: true, style: .mini)
                    }
                    .buttonStyle(.plain)
                    .help("Open LRCLIB website")
                } else {
                    DetailPaneSourceBadge(text: "Apple Music", style: .mini)
                }
            }
        case .credits:
            if let sourceName = model.creditsPayload?.sourceName, !sourceName.isEmpty {
                DetailPaneSourceBadge(text: sourceName, style: .mini)
            }
        }
    }

    private func updateLyricAnimationState(for tab: DetailsPaneTab) {
        cancelLyricAnimationState()
        guard tab == .lyrics else { return }

        // Immediate active-line scroll + per-line animations can fight the pane
        // expand transition and look jittery, so we stage them in after the reveal.
        let work = DispatchWorkItem {
            enableLyricLineAnimations = true
            coordinator.allowsAnimatedScroll = true
            settleWorkItem = nil
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + miniLyricsTransitionDuration, execute: work)
    }

    private func cancelLyricAnimationState() {
        settleWorkItem?.cancel()
        settleWorkItem = nil
        enableLyricLineAnimations = false
        coordinator.allowsAnimatedScroll = false
    }

    private func miniLyricsScrollEdgeInset(for viewportHeight: CGFloat) -> CGFloat {
        min(140, max(28, (viewportHeight * 0.5) - 30))
    }

    private var lyricsScroll: some View {
        let lines = model.lyricsPayload?.lines ?? []

        return GeometryReader { geometry in
            let edgeInset = miniLyricsScrollEdgeInset(for: geometry.size.height)
            let contentWidth = max(0, geometry.size.width)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        // Add runway so the first/last lyric can still center
                        // when the timed-scroll coordinator targets `.center`.
                        Color.clear
                            .frame(height: edgeInset)
                            .allowsHitTesting(false)

                        ForEach(lines) { line in
                            let isActive = line.id == activeLineID
                            Text(line.text)
                                .font(.system(size: isActive ? 17 : 12, weight: isActive ? .semibold : .medium, design: .rounded))
                                .foregroundStyle(isActive ? .white.opacity(0.98) : .white.opacity(0.72))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, isActive ? 5 : 1)
                                .animation(enableLyricLineAnimations ? .easeInOut(duration: 0.24) : nil, value: isActive)
                                .id(line.id)
                        }

                        Color.clear
                            .frame(height: edgeInset)
                            .allowsHitTesting(false)
                    }
                    .frame(width: contentWidth, alignment: .leading)
                }
                .forceHideScrollIndicators()
                .onAppear {
                    coordinator.lines = lines
                    coordinator.isTimed = model.lyricsPayload?.isTimed ?? false
                    coordinator.scrollProxy = proxy
                    coordinator.onActiveLineChanged = { id in
                        activeLineID = id
                    }
                    coordinator.start()
                }
                .onDisappear {
                    coordinator.stop()
                    coordinator.scrollProxy = nil
                }
            }
        }
    }
}

private struct ModeToggleControl: View {
    let isMiniMode: Bool
    let transitionActive: Bool
    var contrastBoost: Double = 0
    var sizeScale: CGFloat = 1
    let action: () -> Void
    @State private var hovering = false

    private var clampedSizeScale: CGFloat {
        min(max(sizeScale, 0.80), 1.20)
    }

    var body: some View {
        let clampedContrast = min(max(contrastBoost, 0), 1)
        Button(action: action) {
            Image(systemName: isMiniMode ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                .font(.system(size: 16 * clampedSizeScale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: 24 * clampedSizeScale, height: 24 * clampedSizeScale)
                .background(Circle().fill(Color.primary.opacity(min(0.34, 0.08 + (0.18 * clampedContrast)))))
                .overlay(
                    Circle()
                        .stroke(.white.opacity(min(0.32, (hovering ? 0.24 : 0.16) + (0.08 * clampedContrast))), lineWidth: 1)
                )
                .scaleEffect(hovering ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(transitionActive)
        .onHover { hovering in
            guard !transitionActive else {
                if self.hovering {
                    self.hovering = false
                }
                return
            }
            withAnimation(.easeOut(duration: 0.16)) {
                self.hovering = hovering
            }
        }
        .hoverHint(isMiniMode ? "Switch to regular mode" : "Switch to mini mode", enabled: !transitionActive)
    }
}

private struct DetachedSurfaceToggleControl: View {
    let isDetachedMode: Bool
    let transitionActive: Bool
    var contrastBoost: Double = 0
    var sizeScale: CGFloat = 1
    let action: () -> Void
    @State private var hovering = false

    private var clampedSizeScale: CGFloat {
        min(max(sizeScale, 0.80), 1.20)
    }

    var body: some View {
        let clampedContrast = min(max(contrastBoost, 0), 1)
        Button(action: action) {
            Image(systemName: isDetachedMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 15 * clampedSizeScale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: 24 * clampedSizeScale, height: 24 * clampedSizeScale)
                .background(Circle().fill(Color.primary.opacity(min(0.34, 0.08 + (0.18 * clampedContrast)))))
                .overlay(
                    Circle()
                        .stroke(.white.opacity(min(0.32, (hovering ? 0.24 : 0.16) + (0.08 * clampedContrast))), lineWidth: 1)
                )
                .scaleEffect(hovering ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(transitionActive)
        .onHover { hovering in
            guard !transitionActive else {
                if self.hovering { self.hovering = false }
                return
            }
            withAnimation(.easeOut(duration: 0.16)) {
                self.hovering = hovering
            }
        }
        .hoverHint(isDetachedMode ? "Attach to popover" : "Detach to window", enabled: !transitionActive)
    }
}

private struct DetachedWindowPinControl: View {
    let isPinned: Bool
    let transitionActive: Bool
    var contrastBoost: Double = 0
    var sizeScale: CGFloat = 1
    let action: () -> Void
    @State private var hovering = false

    private var clampedSizeScale: CGFloat {
        min(max(sizeScale, 0.80), 1.20)
    }

    var body: some View {
        let clampedContrast = min(max(contrastBoost, 0), 1)
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 14 * clampedSizeScale, weight: .semibold))
                .foregroundStyle(.white.opacity(isPinned ? 0.98 : 0.90))
                .frame(width: 24 * clampedSizeScale, height: 24 * clampedSizeScale)
                .background(Circle().fill(Color.primary.opacity(min(0.34, 0.08 + (0.18 * clampedContrast)))))
                .overlay(
                    Circle()
                        .stroke(.white.opacity(min(0.32, (hovering ? 0.24 : 0.16) + (0.08 * clampedContrast))), lineWidth: 1)
                )
                .scaleEffect(hovering ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(transitionActive)
        .onHover { hovering in
            guard !transitionActive else {
                if self.hovering { self.hovering = false }
                return
            }
            withAnimation(.easeOut(duration: 0.16)) {
                self.hovering = hovering
            }
        }
        .hoverHint(isPinned ? "Disable always-on-top" : "Enable always-on-top", enabled: !transitionActive)
    }
}

private struct DetachedWindowCloseControl: View {
    let transitionActive: Bool
    var contrastBoost: Double = 0
    var sizeScale: CGFloat = 1
    let action: () -> Void
    @State private var hovering = false

    private var clampedSizeScale: CGFloat {
        min(max(sizeScale, 0.80), 1.20)
    }

    var body: some View {
        let clampedContrast = min(max(contrastBoost, 0), 1)
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14 * clampedSizeScale, weight: .bold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: 24 * clampedSizeScale, height: 24 * clampedSizeScale)
                .background(Circle().fill(Color.primary.opacity(min(0.34, 0.08 + (0.18 * clampedContrast)))))
                .overlay(
                    Circle()
                        .stroke(.white.opacity(min(0.32, (hovering ? 0.24 : 0.16) + (0.08 * clampedContrast))), lineWidth: 1)
                )
                .scaleEffect(hovering ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(transitionActive)
        .onHover { hovering in
            guard !transitionActive else {
                if self.hovering { self.hovering = false }
                return
            }
            withAnimation(.easeOut(duration: 0.16)) {
                self.hovering = hovering
            }
        }
        .hoverHint("Close detached window", enabled: !transitionActive)
    }
}

private struct MiniDetailToggleControl: View {
    let isOn: Bool
    let systemName: String
    let helpText: String
    let transitionActive: Bool
    var sizeScale: CGFloat = 1
    let action: () -> Void
    @State private var hovering = false

    private var clampedSizeScale: CGFloat {
        min(max(sizeScale, 0.80), 1.20)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16 * clampedSizeScale, weight: .semibold))
                .foregroundStyle(.primary.opacity(isOn ? 0.98 : 0.90))
                .frame(width: 24 * clampedSizeScale, height: 24 * clampedSizeScale)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .overlay(
                    Circle()
                        .stroke(.white.opacity(hovering ? 0.24 : 0.16), lineWidth: 1)
                )
                .scaleEffect(hovering ? 1.06 : 1.0)
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(transitionActive)
        .onHover { hovering in
            guard !transitionActive else {
                if self.hovering { self.hovering = false }
                return
            }
            withAnimation(.easeOut(duration: 0.16)) {
                self.hovering = hovering
            }
        }
        .hoverHint(helpText, enabled: !transitionActive)
        .animation(.easeInOut(duration: 0.18), value: isOn)
    }
}

// MARK: - Lyrics scroll coordinator

/// Drives lyric line highlight and scroll position from a plain NSTimer without
/// going through SwiftUI's reactive system (no @Published / @ObservedObject).
///
/// Every timer tick reads PlaybackClock.shared.liveElapsed directly and computes the
/// active line. Sampling happens more frequently than provider polling, but the view
/// only re-renders when the resolved active line changes. If the active line changed it:
///   1. Calls the onActiveLineChanged closure (which updates a @State var in the view)
///   2. Calls the scrollProxy to scroll to the new line
///
/// Because the @State update only fires when the active LINE changes, the SwiftUI
/// re-render rate is bounded by song structure rather than the timer cadence. This
/// avoids triggering DesignLibrary's glass compositor on every sample on macOS 26.
private final class LyricsScrollCoordinator {
    var lines: [LyricsLine] = []
    var isTimed: Bool = false
    var allowsAnimatedScroll: Bool = true
    var onActiveLineChanged: ((UUID?) -> Void)?
    var scrollProxy: ScrollViewProxy?

    private var timer: Timer?
    private var lastActiveLineID: UUID?
    private let sampleInterval: TimeInterval = 1.0 / 15.0

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
        tick() // immediate initial pass
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let elapsed = PlaybackClock.shared.liveElapsed
        let duration = PlaybackClock.shared.duration
        let newID = computeActiveLineID(elapsed: elapsed, duration: duration)
        guard newID != lastActiveLineID else { return }
        lastActiveLineID = newID
        // Update SwiftUI state (causes a re-render only when the line changes)
        onActiveLineChanged?(newID)
        // Scroll the proxy without triggering a new render pass
        if let proxy = scrollProxy, let id = newID {
            if allowsAnimatedScroll {
                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            } else {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func computeActiveLineID(elapsed: Double, duration: Double) -> UUID? {
        guard !lines.isEmpty else { return nil }
        if isTimed {
            var selected: LyricsLine?
            for line in lines {
                guard let start = line.startTime else { continue }
                if start <= elapsed { selected = line } else { break }
            }
            return (selected ?? lines.first)?.id
        }
        if lines.count == 1 { return lines[0].id }
        let ratio = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
        let index = min(lines.count - 1, max(0, Int((ratio * Double(lines.count - 1)).rounded())))
        return lines[index].id
    }
}

// MARK: - Regular view details

private struct RegularDetailToggleControl: View {
    let isOn: Bool
    let systemName: String
    let helpText: String
    let transitionActive: Bool
    var contrastBoost: Double = 0
    var sizeScale: CGFloat = 1
    let action: () -> Void
    @State private var hovering = false

    private var clampedSizeScale: CGFloat {
        min(max(sizeScale, 0.80), 1.20)
    }

    var body: some View {
        let clampedContrast = min(max(contrastBoost, 0), 1)
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16 * clampedSizeScale, weight: .semibold))
                .foregroundStyle(.white.opacity(isOn ? 0.98 : 0.90))
                .frame(width: 24 * clampedSizeScale, height: 24 * clampedSizeScale)
                .background(Circle().fill(Color.primary.opacity(min(0.34, 0.08 + (0.18 * clampedContrast)))))
                .overlay(
                    Circle()
                        .stroke(.white.opacity(min(0.32, (hovering ? 0.24 : 0.16) + (0.08 * clampedContrast))), lineWidth: 1)
                )
                .scaleEffect(hovering ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(transitionActive)
        .onHover { h in
            guard !transitionActive else {
                if hovering {
                    hovering = false
                }
                return
            }
            withAnimation(.easeOut(duration: 0.16)) {
                hovering = h
            }
        }
        .hoverHint(helpText, enabled: !transitionActive)
        .animation(.easeInOut(duration: 0.18), value: isOn)
    }
}

/// Value-type wrapper so SwiftUI only re-renders RegularDetailsPane when its
/// displayed properties actually change — not on every model.elapsed tick.
private struct RegularDetailsPane: View {
    // model is passed through only for child use (retryLyricsFetch, scroll content).
    // The pane itself reads only value-type arguments so @ObservedObject churn is avoided.
    let model: NowPlayingModel
    let selectedTab: DetailsPaneTab
    let lyricsState: LyricsState
    let lyricsPayload: LyricsPayload?
    let lyricsLoadingProgress: LyricsLoadingProgress?
    let creditsPayload: CreditsPayload?
    let glassTint: Color
    let visibleHeight: CGFloat

    private var paneContentHeight: CGFloat {
        // visibleHeight includes the 1pt divider at the top of this pane.
        max(0, visibleHeight - 1)
    }

    var body: some View {
        let bleed = lyricsBleedOpacities(for: model.artworkColorIntensity)

        VStack(spacing: 0) {
            Divider()
                .overlay(glassTint.opacity(0.18))

            ZStack(alignment: .top) {
                // Background: artwork tint bleed — pure gradients only, no system materials.
                // System materials (.regularMaterial, .ultraThinMaterial) trigger
                // AppKitPlatformGlassDefinition (DesignLibrary) on every layout pass on macOS 26,
                // causing runaway GPU/memory allocation when the view re-renders.
                ZStack {
                    // Pure gradient background — no blurred Image, no system materials.
                    // On macOS 26, scaledToFill+blur Image triggers DesignLibrary
                    // glass compositor paths. Use gradients only, as MiniExpandedDetailsPane does.
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.56),
                            Color.black.opacity(0.62),
                            Color.black.opacity(0.70)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    LinearGradient(
                        colors: [
                            glassTint.opacity(bleed.top),
                            glassTint.opacity(bleed.mid),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.screen)
                }
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0.04), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.16), .black.opacity(0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Header controls — plain color fill, no system material
                HStack {
                    DetailPaneTabChip(tab: .lyrics, isSelected: selectedTab == .lyrics) {
                        model.selectRegularDetailsTab(.lyrics)
                    }
                    DetailPaneTabChip(tab: .credits, isSelected: selectedTab == .credits) {
                        model.selectRegularDetailsTab(.credits)
                    }

                    Spacer(minLength: 0)

                    detailSourceBadge
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                // Content — switch on coarse state only; elapsed-driven scroll lives in child.
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case .lyrics:
                        lyricsTabContent
                    case .credits:
                        creditsTabContent
                    }
                }
                .padding(.top, 36)
                .padding(.bottom, 12)
                .padding(.horizontal, 14)
            }
            .frame(height: paneContentHeight)
        }
        .frame(height: max(0, visibleHeight), alignment: .top)
        .clipped()
    }

    @ViewBuilder
    private var detailSourceBadge: some View {
        switch selectedTab {
        case .lyrics:
            if let source = lyricsPayload?.source, source != .none {
                if source == .lrclib {
                    Button(action: openLRCLibWebsite) {
                        DetailPaneSourceBadge(text: "LRCLib", emphasized: true)
                    }
                    .buttonStyle(.plain)
                    .help("Open LRCLIB website")
                } else {
                    DetailPaneSourceBadge(text: "Apple Music")
                }
            }
        case .credits:
            if let sourceName = creditsPayload?.sourceName, !sourceName.isEmpty {
                DetailPaneSourceBadge(text: sourceName)
            }
        }
    }

    @ViewBuilder
    private var lyricsTabContent: some View {
        switch lyricsState {
        case .idle:
            DetailPaneStateMessage(
                message: "Start playback to load lyrics.",
                icon: .provider(.appleMusic)
            )
        case .loading:
            loadingProgressView(progress: lyricsLoadingProgress)
        case .unavailable:
            DetailPaneStateMessage(
                message: "Lyrics unavailable for this track.",
                icon: .sfSymbol("text.bubble")
            )
        case .failed:
            VStack(spacing: 10) {
                DetailPaneStateMessage(
                    message: "Couldn't fetch lyrics right now.",
                    icon: .sfSymbol("exclamationmark.bubble")
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .available:
            // Delegate elapsed-sensitive rendering to a dedicated child so that
            // the expensive background ZStack above is NOT re-evaluated every 0.5 s.
            RegularLyricsScrollContent(
                lines: lyricsPayload?.lines ?? [],
                isTimed: lyricsPayload?.isTimed ?? false
            )
        }
    }

    @ViewBuilder
    private var creditsTabContent: some View {
        if model.provider == .none || model.title.isEmpty {
            DetailPaneStateMessage(
                message: "Start playback to view credits.",
                icon: .sfSymbol("info.circle")
            )
        } else if let creditsPayload, creditsPayload.hasContent {
            CreditsPaneContent(payload: creditsPayload, style: .regular)
        } else {
            DetailPaneStateMessage(
                message: "Credits unavailable for this track.",
                icon: .sfSymbol("info.circle")
            )
        }
    }

    @ViewBuilder
    private func loadingProgressView(progress: LyricsLoadingProgress?) -> some View {
        let attempt = progress?.attempt ?? 1
        let maxAttempts = progress?.maxAttempts ?? 1

        LyricsLoadingPulseBlock(
            primaryFontSize: 13,
            secondaryText: progress.map { "\($0.stage.displayTitle) · Attempt \(attempt) of \(maxAttempts)" },
            secondaryFontSize: 12
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }
}

private struct LyricsLoadingPulseBlock: View {
    let primaryFontSize: CGFloat
    let secondaryText: String?
    let secondaryFontSize: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let wave = (sin((2.0 * .pi / 1.7) * t) + 1.0) * 0.5 // 0...1
            let primaryOpacity = 0.62 + (0.32 * wave)
            let secondaryOpacity = 0.56 + (0.22 * wave)

            VStack(alignment: .leading, spacing: 3) {
                Text("Loading lyrics…")
                    .font(.system(size: primaryFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(primaryOpacity))

                if let secondaryText, !secondaryText.isEmpty {
                    Text(secondaryText)
                        .font(.system(size: secondaryFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(secondaryOpacity))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}

// Isolated child that drives lyric scrolling via LyricsScrollCoordinator — an
// NSTimer-based coordinator that reads PlaybackClock directly WITHOUT going through
// SwiftUI's reactive system. This means the view body is only re-evaluated when the
// active lyric LINE changes, not every 0.5 s. On macOS 26, ANY SwiftUI re-render
// inside the NSPopover triggers DesignLibrary's glass compositor; minimising re-renders
// to actual line-boundary crossings prevents the recursive stack overflow crash.
private struct RegularLyricsScrollContent: View {
    let lines: [LyricsLine]
    let isTimed: Bool
    @State private var activeLineID: UUID?
    @State private var coordinator = LyricsScrollCoordinator()
    private let maxRenderableLines: Int = 500

    private var renderLines: [LyricsLine] {
        if lines.count > maxRenderableLines {
            return Array(lines.prefix(maxRenderableLines))
        }
        return lines
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(renderLines) { line in
                        let isActive = line.id == activeLineID
                        lyricLineView(line: line, isActive: isActive)
                            .id(line.id)
                    }
                    if lines.count > maxRenderableLines {
                        Text("Showing first \(maxRenderableLines) lines.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 6)
            }
            .forceHideScrollIndicators()
            .onAppear {
                coordinator.lines = renderLines
                coordinator.isTimed = isTimed
                coordinator.scrollProxy = proxy
                coordinator.onActiveLineChanged = { id in
                    activeLineID = id
                }
                coordinator.start()
            }
            .onDisappear {
                coordinator.stop()
                coordinator.scrollProxy = nil
            }
            .onChange(of: renderLines.first?.id) { _, _ in
                coordinator.lines = renderLines
                coordinator.isTimed = isTimed
            }
            .onChange(of: isTimed) { _, timed in
                coordinator.isTimed = timed
            }
        }
    }

    private func lyricLineView(line: LyricsLine, isActive: Bool) -> some View {
        Text(line.text)
            .font(.system(size: isActive ? 17 : 13, weight: isActive ? .semibold : .regular, design: .rounded))
            .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary.opacity(0.72)))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
            .animation(.easeInOut(duration: 0.34), value: isActive)
    }
}
