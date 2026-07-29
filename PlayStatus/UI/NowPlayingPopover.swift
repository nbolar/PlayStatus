import SwiftUI
import AppKit

struct NowPlayingPopover: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject private var onboarding = OnboardingCoordinator.shared
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var searchSectionFrame: CGRect = .zero
    @State private var modeTransitionActive = false
    @State private var displayedMiniMode = false
    @State private var regularBranchVisible = true
    @State private var miniBranchVisible = false
    @State private var modeTransitionEndWorkItem: DispatchWorkItem?
    @State private var modeArtworkFrames: [ModeArtworkSlot: CGRect] = [:]
    /// Mounts both branches for one layout pass when the surface opens, so the artwork
    /// anchors for the mode you are *not* in are already known. Preferences only
    /// propagate after layout, so without this the shared artwork has no target on the
    /// first frames of a morph and blinks out just as it should be taking over.
    @State private var primingModeAnchors = false
    /// True for the single render pass in which the branches take their artwork back
    /// from the shared morph node. The remounting artwork views read it to skip their
    /// first-appear fade — without this the artwork blinked out at the exact frame the
    /// morph settled and faded back in from nothing.
    @State private var modeHandoffSettling = false
    @State private var modePrimaryContentVisible = true
    @State private var modeSecondaryContentVisible = true
    @State private var showRegularDetailsPane = false
    @State private var regularDetailsHideWorkItem: DispatchWorkItem?
    @State private var regularPointerHovering = false
    @State private var regularSettingsHovering = false
    @State private var coachmarkTargetFrames: [CoachmarkID: CGRect] = [:]

    private func surfaceSize(for miniMode: Bool) -> CGSize {
        CGSize(
            width: popoverWidth(for: miniMode),
            height: cappedPopoverHeight(popoverHeight(for: miniMode), miniMode: miniMode)
        )
    }

    /// Where the surface currently sits between the two modes, read back from the width
    /// the host actually is. Derived rather than animated, so it is by definition
    /// consistent with what is on screen at that instant — there is no second timeline
    /// that can drift away from the window.
    private func morphProgress(forSurfaceWidth width: CGFloat) -> Double {
        let regularWidth = popoverWidth(for: false)
        let span = popoverWidth(for: true) - regularWidth
        guard abs(span) > 0.5 else { return model.miniMode ? 1 : 0 }
        return min(max(Double((width - regularWidth) / span), 0), 1)
    }

    private var renderedPopoverWidth: CGFloat {
        surfaceSize(for: model.miniMode).width
    }

    private var renderedPopoverHeight: CGFloat {
        surfaceSize(for: model.miniMode).height
    }

    /// True whenever the shared morph node owns the artwork, or while anchors are being
    /// primed — in both cases the branches' own artwork subtrees are pure cost.
    private var artworkHandedOff: Bool {
        modeTransitionActive || primingModeAnchors
    }

    private var renderRegularBranch: Bool {
        !model.miniMode || modeTransitionActive || primingModeAnchors
    }

    private var renderMiniBranch: Bool {
        model.miniMode || modeTransitionActive || primingModeAnchors
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

    private func minimumPopoverHeight(for miniMode: Bool) -> CGFloat {
        miniMode ? model.miniBaseHeight : model.estimatedRegularPopoverHeight
    }

    private func cappedPopoverHeight(_ desiredHeight: CGFloat, miniMode: Bool) -> CGFloat {
        guard let cap = model.surfaceContentHeightCap else {
            return desiredHeight
        }

        return max(
            minimumPopoverHeight(for: miniMode),
            min(desiredHeight, cap)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            // The content fills whatever the host currently is rather than animating a
            // size of its own. Core Animation moves the window, AppKit resizes the host
            // under it, and the layout simply follows — so the content cannot slide
            // against its own window the way it does when both sides animate separately.
            // This is the same model the lyrics pane has always used.
            modeContent(surfaceSize: geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                // The travelling artwork lives on this overlay, not inside the branch
                // ZStack. The ZStack is as wide as its widest branch — wider than the
                // host mid-morph — so `.position()` coordinates inside it are shifted
                // left of host coordinates by half the overhang: zero at the wide end
                // of a morph, 75pt by the narrow end. The artwork drifted left along
                // exactly that curve and then snapped right at handoff. This overlay is
                // clamped to the host frame, so positions here mean host coordinates.
                .overlay(alignment: .topLeading) {
                    if modeTransitionActive {
                        sharedMorphingArtwork(
                            progress: morphProgress(forSurfaceWidth: geometry.size.width),
                            surface: geometry.size,
                            regularSize: surfaceSize(for: false),
                            miniSize: surfaceSize(for: true)
                        )
                    }
                }
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .coordinateSpace(name: "popoverRoot")
        .onPreferenceChange(ModeArtworkFramePreferenceKey.self) { frames in
            // Merge rather than replace: an unmounted branch contributes nothing, and
            // dropping its last known anchor would leave the next morph with no target.
            guard !frames.isEmpty else { return }
            modeArtworkFrames.merge(frames) { _, latest in latest }
        }
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
            runModeMorph(toMini: miniMode)

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
            settleModeMorphImmediately()
            modePrimaryContentVisible = true
            modeSecondaryContentVisible = true
            syncRenderedRegularDetailsPaneImmediately()
            updateCoachmarkAvailability()
            primingModeAnchors = true
            DispatchQueue.main.async {
                primingModeAnchors = false
            }
        }
        .onDisappear {
            regularDetailsHideWorkItem?.cancel()
            regularDetailsHideWorkItem = nil
            modeTransitionEndWorkItem?.cancel()
            modeTransitionEndWorkItem = nil
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
    }

    /// Both layouts live in one ZStack rather than an if/else. A branch swap gave the
    /// two modes separate view identities, which is why nothing could morph across them
    /// and both layouts ended up cross-dissolving at full strength. Here each branch
    /// renders at its own natural size, clipped by the morphing container, and the
    /// inactive one is retired only once the transition has settled.
    private func modeContent(surfaceSize surface: CGSize) -> some View {
        let regularSize = surfaceSize(for: false)
        let miniSize = surfaceSize(for: true)
        let progress = morphProgress(forSurfaceWidth: surface.width)
        let availableHeight = max(0, surface.height)

        return ZStack(alignment: .top) {
            modeMorphBackdrop(progress: progress, surface: surface)

            if renderRegularBranch {
                regularContent(availableHeight: model.miniMode ? regularSize.height : availableHeight)
                    .frame(width: regularSize.width, height: regularSize.height, alignment: .top)
                    .coordinateSpace(name: modeRegularBranchSpace)
                    .opacity(regularBranchVisible ? 1 : 0)
                    .allowsHitTesting(!model.miniMode && !modeTransitionActive)
            }

            if renderMiniBranch {
                MiniNowPlayingCard(
                    model: model,
                    transitionActive: artworkHandedOff,
                    handoffSettling: modeHandoffSettling,
                    availableHeight: model.miniMode ? availableHeight : miniSize.height,
                    resolvedHeight: miniSize.height,
                    primaryContentVisible: modePrimaryContentVisible,
                    secondaryContentVisible: modeSecondaryContentVisible,
                    onToggleMode: {
                        requestModeChange(toMini: false)
                    }
                )
                .frame(width: miniSize.width, height: miniSize.height, alignment: .top)
                .coordinateSpace(name: modeMiniBranchSpace)
                .opacity(miniBranchVisible ? 1 : 0)
                .allowsHitTesting(model.miniMode && !modeTransitionActive)
            }

        }
    }

    /// Fills the surface while a morph is in flight. Both branches sit at their own
    /// natural size inside a host that is between sizes, so without this the gap would
    /// show bare window backing.
    private func modeMorphBackdrop(progress: Double, surface: CGSize) -> some View {
        // Deliberately a flat gradient rather than LiquidGlassBackground. This only
        // exists for the ~300ms of a morph, which is precisely when the frame budget is
        // tightest — a third full-size glass layer on top of two live branches was
        // enough to stall the main thread outright.
        LinearGradient(
            colors: model.cardBackgroundPalette,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: surface.width, height: surface.height)
        // Solid almost immediately and held there for the body of the morph, so the
        // panel never looks hollow while the layouts trade places. Still exactly zero at
        // both rest states, so neither settled mode picks up a fill it did not have.
        .opacity(min(1, min(progress, 1 - progress) * 10))
        .allowsHitTesting(false)
    }

    /// One artwork node that travels between the two layouts' artwork slots. Each branch
    /// hides its own artwork for the duration, so the image the eye tracks is continuous
    /// instead of two copies fading past each other.
    @ViewBuilder
    private func sharedMorphingArtwork(
        progress: Double,
        surface: CGSize,
        regularSize: CGSize,
        miniSize: CGSize
    ) -> some View {
        if let regularAnchor = modeArtworkFrames[.regular],
           let miniAnchor = modeArtworkFrames[.mini] {
            // Each branch is centred in the host, so its anchor has to be shifted by the
            // same amount the host centres it before the two are interpolated.
            let regularShellRect = regularAnchor
                .offsetBy(dx: (surface.width - regularSize.width) / 2, dy: 0)
            let regularPlateRect = regularShellRect
                .insetBy(dx: regularArtworkShellInset, dy: regularArtworkShellInset)
            let miniRect = miniAnchor
                .offsetBy(dx: (surface.width - miniSize.width) / 2, dy: 0)
            let plateRect = CGRect(
                x: lerp(regularPlateRect.minX, miniRect.minX, progress),
                y: lerp(regularPlateRect.minY, miniRect.minY, progress),
                width: lerp(regularPlateRect.width, miniRect.width, progress),
                height: lerp(regularPlateRect.height, miniRect.height, progress)
            )
            // The shell travels with the plate, converging onto it as it dissolves.
            let shellRect = CGRect(
                x: lerp(regularShellRect.minX, miniRect.minX, progress),
                y: lerp(regularShellRect.minY, miniRect.minY, progress),
                width: lerp(regularShellRect.width, miniRect.width, progress),
                height: lerp(regularShellRect.height, miniRect.height, progress)
            )
            let plateRadius = lerp(regularArtworkCornerRadius, miniArtworkCornerRadius, progress)
            let shellRadius = lerp(regularArtworkShellCornerRadius, miniArtworkCornerRadius, progress)
            let plateShape = RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
            let shellShape = RoundedRectangle(cornerRadius: shellRadius, style: .continuous)
            let shellOpacity = 1 - progress
            let tint = model.glassTint

            ZStack {
                // The regular tile's glass shell, mirrored from ArtworkView and dissolved
                // over the morph. Without it the ring, gloss, and drop shadow vanished in
                // a single frame the instant the branch handed its artwork off.
                shellShape
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
                    .overlay(shellShape.stroke(.white.opacity(0.22), lineWidth: 1.2))
                    .overlay(shellShape.stroke(tint.opacity(0.2), lineWidth: 1))
                    .frame(width: max(0, shellRect.width), height: max(0, shellRect.height))
                    .position(x: shellRect.midX, y: shellRect.midY)
                    .opacity(shellOpacity)
                    .shadow(
                        color: .black.opacity(0.28 * shellOpacity),
                        radius: 16,
                        x: 0,
                        y: 10
                    )

                MorphingArtworkImage(image: model.artwork, tint: tint)
                    .frame(width: max(0, plateRect.width), height: max(0, plateRect.height))
                    .clipShape(plateShape)
                    .overlay(plateShape.stroke(.white.opacity(0.12), lineWidth: 1))
                    .position(x: plateRect.midX, y: plateRect.midY)
            }
            .allowsHitTesting(false)
        }
    }

    private func lerp(_ from: CGFloat, _ to: CGFloat, _ progress: Double) -> CGFloat {
        from + ((to - from) * progress)
    }

    private func regularContent(availableHeight: CGFloat) -> some View {
        // The branch always lays out at its own settled size; the morphing container
        // clips it. Reflowing this layout mid-transition would be both expensive and
        // visibly unstable.
        let regularSurfaceSize = surfaceSize(for: false)
        let baseRegularHeight = model.estimatedRegularPopoverHeight
        let resolvedRegularHeight = regularSurfaceSize.height
        let liveRegularHeight = min(resolvedRegularHeight, max(baseRegularHeight, availableHeight))
        let regularMarqueeLaneWidth = min(272, max(130, regularSurfaceSize.width - regularArtworkSize - 78))
        let visibleRegularDetailsHeight = min(
            model.regularLyricsPaneHeight,
            max(0, liveRegularHeight - baseRegularHeight)
        )
        let shouldRenderRegularDetailsPane = showRegularDetailsPane || visibleRegularDetailsHeight > 0.5
        let regularControlContrastBoost = model.regularControlsContrastBoost
        let searchTrailingAlignmentNudge: CGFloat = 4
        let regularDetachedTransparencyMultiplier: Double = model.surfaceMode == .detached ? 0.80 : 1.0
        let regularControlScale = model.regularControlScaleFactor
        let restingRegularControlOpacity: Double = playerControlClusterRestingOpacity
        let showDetailsCoachmark = onboarding.isCoachmarkActive(.detailsToggle)
        let showDetachedModeCoachmark = onboarding.isCoachmarkActive(.detachedMode)
        let showDetachedControlsCoachmark = onboarding.isCoachmarkActive(.detachedControls)
        let forceCoachmarkControlsVisible = onboarding.shouldForceModeCoachmarkControls()
        let interactiveRegularControlsVisible = regularPointerHovering || forceCoachmarkControlsVisible

        return VStack(spacing: 0) {
            regularPrimaryCard(
                regularMarqueeLaneWidth: regularMarqueeLaneWidth,
                regularControlContrastBoost: regularControlContrastBoost,
                regularControlScale: regularControlScale,
                searchTrailingAlignmentNudge: searchTrailingAlignmentNudge
            )
            .frame(height: baseRegularHeight, alignment: .top)
            .overlay(alignment: .topTrailing) {
                regularTrailingControls(
                    contrastBoost: regularControlContrastBoost,
                    controlScale: regularControlScale,
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
                    inactiveFontSize: model.regularLyricsInactiveFontSize,
                    activeFontSize: model.regularLyricsActiveFontSize,
                    glassTint: model.glassTint,
                    visibleHeight: visibleRegularDetailsHeight
                )
                .allowsHitTesting(regularDetailsRequested && visibleRegularDetailsHeight > 0.5)
            }
        }
        .frame(width: regularSurfaceSize.width, height: resolvedRegularHeight, alignment: .topLeading)
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
        regularControlScale: CGFloat,
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
                    regularControlScale: regularControlScale
                )

                regularSearchLane(
                    contrastBoost: regularControlContrastBoost,
                    controlScale: regularControlScale,
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
        regularControlScale: CGFloat
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
                    regularControlScale: regularControlScale
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var regularArtworkTile: some View {
        if artworkHandedOff {
            // Handed off to the shared morph node. Left out of the tree entirely rather
            // than hidden: `.opacity(0)` still rasterises, and this subtree carries two
            // blurs that the morph cannot afford to keep paying for. The placeholder
            // holds the same frame, so the anchor stays measurable and the surrounding
            // layout does not reflow.
            Color.clear
                .frame(width: regularArtworkSize, height: regularArtworkSize)
                .modeArtworkAnchor(.regular, in: modeRegularBranchSpace)
        } else {
            AnimatedArtworkView(
                image: model.artwork,
                tint: model.glassTint,
                isEnabled: false,
                seed: "regular|\(model.provider.rawValue)|\(model.artist)|\(model.albumArtist)|\(model.album)|\(model.title)",
                style: model.artworkMotionStyle,
                animatedArtworkURL: model.effectiveAnimatedArtworkURL,
                animatedArtworkIsVisible: model.isPopoverVisible,
                cropAnimatedArtworkToSquare: model.cropAnimatedArtworkToSquare,
                animateOnFirstAppear: !modeTransitionActive && !modeHandoffSettling
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
            .modeArtworkAnchor(.regular, in: modeRegularBranchSpace)
        }
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
                .foregroundStyle(.white.opacity(0.98))
                .shadow(color: .black.opacity(0.26), radius: 2.2, x: 0, y: 1)
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
            .foregroundStyle(.white.opacity(0.90))
            .shadow(color: .black.opacity(0.20), radius: 1.8, x: 0, y: 1)

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
        regularControlScale: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
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
                    contrastBoost: regularControlContrastBoost,
                    controlScale: regularControlScale
                )
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            OutputControlsRow(
                model: model,
                contrastBoost: regularControlContrastBoost,
                controlScale: regularControlScale,
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
        restingRegularControlOpacity: Double,
        interactiveRegularControlsVisible: Bool,
        showDetailsCoachmark: Bool,
        showDetachedModeCoachmark: Bool,
        showDetachedControlsCoachmark: Bool
    ) -> some View {
        let coachmarkForcesReveal = showDetailsCoachmark || showDetachedModeCoachmark || showDetachedControlsCoachmark
        let clusterRevealed = interactiveRegularControlsVisible || coachmarkForcesReveal

        return HStack(spacing: 2 * controlScale) {
            regularModeToggle(contrastBoost: contrastBoost, controlScale: controlScale)

            regularDetachedControls(contrastBoost: contrastBoost, controlScale: controlScale)

            regularDetailControls(contrastBoost: contrastBoost, controlScale: controlScale)

            regularSettingsControl(contrastBoost: contrastBoost, controlScale: controlScale)
        }
        .playerControlClusterBackground(
            sizeScale: controlScale,
            neutralWashOpacity: 0,
            blueFogOpacity: 0,
            contrastBoost: contrastBoost,
            artworkBacking: 0
        )
        .fixedSize(horizontal: true, vertical: false)
        .padding(.top, 6 * controlScale)
        .padding(.trailing, 14 * controlScale)
        .opacity(modeSecondaryContentVisible ? (clusterRevealed ? 1 : restingRegularControlOpacity) : 0)
        .offset(y: modeSecondaryContentVisible ? 0 : -8)
        .allowsHitTesting(modeSecondaryContentVisible)
        .animation(.easeInOut(duration: 0.16), value: clusterRevealed)
        .animation(modeSecondaryRevealAnimation, value: modeSecondaryContentVisible)
    }

    private func regularModeToggle(contrastBoost: Double, controlScale: CGFloat) -> some View {
        ModeToggleControl(
            isMiniMode: false,
            transitionActive: modeTransitionActive,
            contrastBoost: contrastBoost,
            sizeScale: controlScale
        ) {
            requestModeChange(toMini: true)
        }
        .playerCoachmarkTarget(.modeToggle)
    }

    @ViewBuilder
    private func regularDetachedControls(contrastBoost: Double, controlScale: CGFloat) -> some View {
        DetachedSurfaceToggleControl(
            isDetachedMode: model.surfaceMode == .detached,
            transitionActive: modeTransitionActive,
            contrastBoost: contrastBoost,
            sizeScale: controlScale
        ) {
            model.requestToggleDetachedMode()
        }
        .playerCoachmarkTarget(.detachedMode)

        if model.surfaceMode == .detached {
            DetachedWindowPinControl(
                isPinned: model.detachedWindowAlwaysOnTop,
                transitionActive: modeTransitionActive,
                contrastBoost: contrastBoost,
                sizeScale: controlScale
            ) {
                model.detachedWindowAlwaysOnTop.toggle()
            }
            .playerCoachmarkTarget(.detachedControls)

            DetachedWindowCloseControl(
                transitionActive: modeTransitionActive,
                contrastBoost: contrastBoost,
                sizeScale: controlScale
            ) {
                model.requestCloseDetachedWindow()
            }
        }
    }

    @ViewBuilder
    private func regularDetailControls(contrastBoost: Double, controlScale: CGFloat) -> some View {
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
    }

    private func regularSettingsControl(contrastBoost: Double, controlScale: CGFloat) -> some View {
        SettingsOpenControl {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16 * controlScale, weight: .semibold))
                .foregroundStyle(ArtworkPlayerControlPalette.icon())
                .playerClusterGlyphChrome(
                    diameter: 24 * controlScale,
                    isHovering: regularSettingsHovering,
                    contrastBoost: contrastBoost
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard !modeTransitionActive else {
                if regularSettingsHovering { regularSettingsHovering = false }
                return
            }
            regularSettingsHovering = hovering
        }
        .hoverHint("Settings", enabled: !modeTransitionActive)
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

    /// Entry point for a mode change originating inside the popover. Marks the transition
    /// active before flipping the model so both branches are mounted for the first frame.
    private func requestModeChange(toMini targetMiniMode: Bool) {
        guard targetMiniMode != model.miniMode else { return }
        modeTransitionActive = true
        if !targetMiniMode, model.miniLyricsEnabled {
            model.miniLyricsEnabled = false
        }
        model.miniMode = targetMiniMode
    }

    /// Geometry is not animated here at all. The window resize is the only timeline; the
    /// content follows the host it is given and derives its morph progress from it. All
    /// this schedules is the cross-fade between the two layouts.
    private func runModeMorph(toMini miniMode: Bool) {
        modeTransitionEndWorkItem?.cancel()
        modeTransitionActive = true
        displayedMiniMode = miniMode

        // The layout that is leaving fades out fast and does not move.
        withAnimation(modeOutgoingFadeAnimation) {
            if miniMode {
                regularBranchVisible = false
            } else {
                miniBranchVisible = false
            }
        }

        withAnimation(modeIncomingFadeAnimation.delay(modeIncomingFadeDelay)) {
            if miniMode {
                miniBranchVisible = true
            } else {
                regularBranchVisible = true
            }
        }

        let finish = DispatchWorkItem {
            guard displayedMiniMode == model.miniMode else { return }
            // Both flips land in one render pass: the shared morph node unmounts and the
            // branch artwork remounts — with its appear fade suppressed — on the same
            // frame, so the image never has a frame where nobody is drawing it.
            modeHandoffSettling = true
            modeTransitionActive = false
            modeTransitionEndWorkItem = nil
            DispatchQueue.main.async {
                modeHandoffSettling = false
            }
        }
        modeTransitionEndWorkItem = finish
        DispatchQueue.main.asyncAfter(deadline: .now() + modeTransitionDuration, execute: finish)
    }

    private func settleModeMorphImmediately() {
        modeTransitionEndWorkItem?.cancel()
        modeTransitionEndWorkItem = nil
        modeTransitionActive = false
        displayedMiniMode = model.miniMode
        regularBranchVisible = !model.miniMode
        miniBranchVisible = model.miniMode
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
