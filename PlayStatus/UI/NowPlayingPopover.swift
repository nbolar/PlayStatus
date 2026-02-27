import SwiftUI
import AppKit

private let modeMorphAnimation = Animation.linear(duration: modeTransitionDuration / 3.0)
private let modeCrossfadeOutDuration: Double = modeTransitionDuration * 0.25
private let modeCrossfadeInDuration: Double = modeTransitionDuration * 0.65
private let miniSeamBlendHeight: CGFloat = 1
private let miniSeamBlurRadius: CGFloat = 10

struct NowPlayingPopover: View {
    @ObservedObject var model: NowPlayingModel
    @Namespace private var artworkMorphNamespace
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var searchSectionFrame: CGRect = .zero
    @State private var modeTransitionActive = false
    @State private var modeTransitionResetWorkItem: DispatchWorkItem?
    @State private var modeCrossfadeSwapWorkItem: DispatchWorkItem?
    @State private var artworkMorphEnabled = false
    @State private var regularArtworkOpacity: Double = 1
    @State private var pendingMiniInitialExpand = false
    @State private var displayedMiniMode = false
    @State private var modeCrossfadeOpacity: Double = 1
    @State private var modeCrossfadeSequence: Int = 0
    @State private var showRegularLyricsPane = false
    @State private var regularLyricsHideWorkItem: DispatchWorkItem?
    @State private var regularPointerHovering = false
    private var resolvedPopoverHeight: CGFloat {
        model.miniMode ? model.miniPopoverHeight : model.regularPopoverHeight
    }

    var body: some View {
        GeometryReader { geometry in
            modeContent(
                miniMode: displayedMiniMode,
                availableHeight: max(0, geometry.size.height)
            )
            .opacity(modeCrossfadeOpacity)
            .frame(
                width: model.popoverWidth,
                height: resolvedPopoverHeight,
                alignment: .topLeading
            )
            .clipped()
        }
        .frame(
            width: model.popoverWidth,
            height: model.isPopoverVisible ? nil : resolvedPopoverHeight,
            alignment: .topLeading
        )
        .clipped()
        .coordinateSpace(name: "popoverRoot")
        .onPreferenceChange(SearchSectionFramePreferenceKey.self) { frame in
            updateSearchSectionFrame(frame)
        }
        .onChange(of: model.provider) { _ in
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isSearchFocused = false
                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)) {
                    isSearchExpanded = false
                }
            }
        }
        .onChange(of: model.miniMode) { miniMode in
            beginModeTransition()
            modeCrossfadeSwapWorkItem?.cancel()
            modeCrossfadeSequence += 1
            let sequence = modeCrossfadeSequence
            withAnimation(.easeOut(duration: modeCrossfadeOutDuration)) {
                modeCrossfadeOpacity = 0
            }

            let swap = DispatchWorkItem {
                guard sequence == modeCrossfadeSequence else { return }
                displayedMiniMode = miniMode

                if miniMode {
                    artworkMorphEnabled = true
                } else {
                    artworkMorphEnabled = false
                    regularArtworkOpacity = 0
                    withAnimation(.easeInOut(duration: modeTransitionDuration)) {
                        regularArtworkOpacity = 1
                    }
                }

                withAnimation(.easeInOut(duration: modeCrossfadeInDuration)) {
                    modeCrossfadeOpacity = 1
                }
                modeCrossfadeSwapWorkItem = nil
            }
            modeCrossfadeSwapWorkItem = swap
            DispatchQueue.main.asyncAfter(deadline: .now() + modeCrossfadeOutDuration, execute: swap)
            syncRenderedRegularLyricsPane(for: regularLyricsRequested)

            if miniMode {
                regularPointerHovering = false
            }
            guard miniMode else { return }
            searchText = ""
            isSearchFocused = false
            withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.90, blendDuration: 0.90)) {
                isSearchExpanded = false
            }
        }
        .onChange(of: model.lyricsPanelExpanded) { _ in
            syncRenderedRegularLyricsPane(for: regularLyricsRequested)
        }
        .onChange(of: model.showLyricsPanel) { _ in
            syncRenderedRegularLyricsPane(for: regularLyricsRequested)
        }
        .onAppear {
            displayedMiniMode = model.miniMode
            modeCrossfadeOpacity = 1
            syncRenderedRegularLyricsPaneImmediately()
        }
        .onDisappear {
            modeCrossfadeSwapWorkItem?.cancel()
            modeCrossfadeSwapWorkItem = nil
            regularLyricsHideWorkItem?.cancel()
            regularLyricsHideWorkItem = nil
            regularPointerHovering = false
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

    @ViewBuilder
    private func modeContent(miniMode: Bool, availableHeight: CGFloat) -> some View {
        if miniMode {
            MiniNowPlayingCard(
                model: model,
                artworkMorphNamespace: artworkMorphNamespace,
                transitionActive: modeTransitionActive,
                availableHeight: availableHeight,
                startExpandedOnAppear: pendingMiniInitialExpand,
                onInitialExpandConsumed: {
                    pendingMiniInitialExpand = false
                },
                onToggleMode: {
                    withAnimation(modeMorphAnimation) {
                        artworkMorphEnabled = false
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
        let resolvedRegularHeight = model.regularPopoverHeight
        let liveRegularHeight = min(resolvedRegularHeight, max(baseRegularHeight, availableHeight))
        let regularMarqueeLaneWidth = min(272, max(130, model.popoverWidth - model.artworkDisplaySize - 78))
        let visibleRegularLyricsHeight = min(
            model.regularLyricsPaneHeight,
            max(0, liveRegularHeight - baseRegularHeight)
        )
        let shouldRenderRegularLyricsPane = showRegularLyricsPane || visibleRegularLyricsHeight > 0.5
        let regularControlContrastBoost = model.regularControlsContrastBoost
        let searchTrailingAlignmentNudge: CGFloat = 4
        let regularDetachedTransparencyMultiplier: Double = model.surfaceMode == .detached ? 0.80 : 1.0
        let regularDetachedControlScale = model.detachedRegularControlScaleFactor
        let regularTopControlsVisible = regularPointerHovering

        return VStack(spacing: 0) {
            LiquidGlassCard(
                tint: model.glassTint,
                palette: model.cardBackgroundPalette,
                readabilityBoost: regularControlContrastBoost,
                transparencyMultiplier: regularDetachedTransparencyMultiplier
            ) {
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 16) {
                    Group {
                        if artworkMorphEnabled {
                            AnimatedArtworkView(
                                image: model.artwork,
                                tint: model.glassTint,
                                isEnabled: false,
                                seed: "regular|\(model.provider.rawValue)|\(model.artist)|\(model.title)",
                                style: model.artworkMotionStyle,
                                animatedArtworkURL: model.effectiveAnimatedArtworkURL,
                                animatedArtworkIsVisible: model.isPopoverVisible
                            )
                                .frame(width: model.artworkDisplaySize, height: model.artworkDisplaySize)
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
                        } else {
                            AnimatedArtworkView(
                                image: model.artwork,
                                tint: model.glassTint,
                                isEnabled: false,
                                seed: "regular|\(model.provider.rawValue)|\(model.artist)|\(model.title)",
                                style: model.artworkMotionStyle,
                                animatedArtworkURL: model.effectiveAnimatedArtworkURL,
                                animatedArtworkIsVisible: model.isPopoverVisible
                            )
                                .frame(width: model.artworkDisplaySize, height: model.artworkDisplaySize)
                                .animatedArtworkMotion(
                                    isEnabled: model.animatedArtworkEnabled,
                                    seed: "regular|\(model.provider.rawValue)|\(model.artist)|\(model.title)",
                                    style: model.artworkMotionStyle,
                                    isPlaying: model.isPlaying,
                                    hasAnimatedStream: model.effectiveAnimatedArtworkURL != nil,
                                    tint: model.glassTint,
                                    artworkImage: model.artwork
                                )
                                .opacity(regularArtworkOpacity)
                        }
                    }

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
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if model.resolvedSearchProvider != .none {
                    HStack {
                        Spacer(minLength: 0)
                        searchSection(
                            maxWidth: min(280, max(170, model.popoverWidth * 0.50)),
                            contrastBoost: regularControlContrastBoost,
                            controlScale: regularDetachedControlScale
                        )
                    }
                    .padding(.trailing, -searchTrailingAlignmentNudge)
                    .padding(.top, -24)
                    .padding(.bottom, -12)
                }

            }
            }
            .frame(height: baseRegularHeight, alignment: .top)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6 * regularDetachedControlScale) {
                    ModeToggleControl(
                        isMiniMode: false,
                        transitionActive: modeTransitionActive,
                        contrastBoost: regularControlContrastBoost,
                        sizeScale: regularDetachedControlScale
                    ) {
                        withAnimation(modeMorphAnimation) {
                            artworkMorphEnabled = true
                            pendingMiniInitialExpand = true
                            model.miniMode = true
                        }
                    }

                    DetachedSurfaceToggleControl(
                        isDetachedMode: model.surfaceMode == .detached,
                        transitionActive: modeTransitionActive,
                        contrastBoost: regularControlContrastBoost,
                        sizeScale: regularDetachedControlScale
                    ) {
                        model.requestToggleDetachedMode()
                    }

                    if model.surfaceMode == .detached {
                        DetachedWindowPinControl(
                            isPinned: model.detachedWindowAlwaysOnTop,
                            transitionActive: modeTransitionActive,
                            contrastBoost: regularControlContrastBoost,
                            sizeScale: regularDetachedControlScale
                        ) {
                            model.detachedWindowAlwaysOnTop.toggle()
                        }

                        DetachedWindowCloseControl(
                            transitionActive: modeTransitionActive,
                            contrastBoost: regularControlContrastBoost,
                            sizeScale: regularDetachedControlScale
                        ) {
                            model.requestCloseDetachedWindow()
                        }
                    }

                    if model.showLyricsPanel {
                        RegularLyricsToggleControl(
                            isOn: model.lyricsPanelExpanded,
                            lyricsState: model.lyricsState,
                            contrastBoost: regularControlContrastBoost,
                            sizeScale: regularDetachedControlScale
                        ) {
                            let targetExpanded = !model.lyricsPanelExpanded
                            syncRenderedRegularLyricsPane(
                                for: model.showLyricsPanel && targetExpanded && !model.miniMode
                            )
                            model.setLyricsPanelExpanded(targetExpanded)
                        }
                    }

                    SettingsOpenControl {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16 * regularDetachedControlScale, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.94))
                            .frame(
                                width: 24 * regularDetachedControlScale,
                                height: 24 * regularDetachedControlScale
                            )
                            .background(Circle().fill(Color.primary.opacity(min(0.34, 0.08 + (0.18 * regularControlContrastBoost)))))
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(min(0.28, 0.16 + (0.08 * regularControlContrastBoost))), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .hoverHint("Settings", enabled: !modeTransitionActive)
                }
                .padding(.top, 8 * regularDetachedControlScale)
                .padding(.trailing, 14 * regularDetachedControlScale)
                .opacity(regularTopControlsVisible ? 1 : 0)
                .allowsHitTesting(regularTopControlsVisible)
                .animation(.easeInOut(duration: 0.16), value: regularTopControlsVisible)
            }

            if shouldRenderRegularLyricsPane {
                RegularLyricsPane(
                    model: model,
                    lyricsState: model.lyricsState,
                    lyricsPayload: model.lyricsPayload,
                    lyricsLoadingProgress: model.lyricsLoadingProgress,
                    glassTint: model.glassTint,
                    artwork: model.artwork,
                    visibleHeight: visibleRegularLyricsHeight
                )
                .allowsHitTesting(regularLyricsRequested && visibleRegularLyricsHeight > 0.5)
            }
        }
        .frame(width: model.popoverWidth, height: resolvedRegularHeight, alignment: .topLeading)
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
            MiniCardPointerTrackingOverlay(enabled: true) { hovering in
                withAnimation(.easeInOut(duration: 0.16)) {
                    regularPointerHovering = hovering
                }
            }
            .allowsHitTesting(false)
        }
    }

//    private var header: some View {
//        HStack(alignment: .center, spacing: 10) {
//            Text("Now Playing")
//                .font(.system(size: 13, weight: .semibold, design: .rounded))
//                .foregroundStyle(.primary.opacity(0.85))
//
//            Spacer()
//
//            HStack(spacing: 6) {
//                Circle()
//                    .frame(width: 6, height: 6)
//                    .foregroundStyle(model.isPlaying ? .green : .secondary)
//
//                Text(model.statusLine)
//                    .font(.system(size: 11, weight: .medium, design: .rounded))
//                    .foregroundStyle(.secondary)
//            }
//            .padding(.horizontal, 10)
//            .padding(.vertical, 6)
//            .background(.ultraThinMaterial, in: Capsule())
//            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
//        }
//    }

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
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchSectionFramePreferenceKey.self,
                    value: isSearchExpanded ? proxy.frame(in: .named("popoverRoot")) : .zero
                )
            }
        )
        .onChange(of: isSearchFocused) { focused in
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

    private func beginModeTransition() {
        modeTransitionResetWorkItem?.cancel()
        modeTransitionActive = true
        let reset = DispatchWorkItem {
            modeTransitionActive = false
        }
        modeTransitionResetWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + modeTransitionDuration + 0.06, execute: reset)
    }

    private var regularLyricsRequested: Bool {
        !model.miniMode && model.showLyricsPanel && model.lyricsPanelExpanded
    }

    private func syncRenderedRegularLyricsPaneImmediately() {
        regularLyricsHideWorkItem?.cancel()
        regularLyricsHideWorkItem = nil
        showRegularLyricsPane = regularLyricsRequested
    }

    private func syncRenderedRegularLyricsPane(for enabled: Bool) {
        regularLyricsHideWorkItem?.cancel()
        regularLyricsHideWorkItem = nil

        if enabled {
            showRegularLyricsPane = true
            return
        }

        let work = DispatchWorkItem {
            guard !regularLyricsRequested else { return }
            showRegularLyricsPane = false
            regularLyricsHideWorkItem = nil
        }
        regularLyricsHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + miniLyricsTransitionDuration, execute: work)
    }

}

private struct SearchSectionFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
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
            .onChange(of: enabled) { isEnabled in
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
            elapsed: clock.elapsed,
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
        let effectiveHover = (pointerHovering || forceExpandedUntilPointerExit) && !transitionActive
        let controlsVisible = effectiveHover
        let infoExpanded = effectiveHover
        let bottomShade = min(0.82, 0.34 + (lightArtworkBoost * 0.24) + (veryLightBoost * 0.18) + (effectiveHover ? 0.10 : 0.04))
        let topShade = min(0.34, 0.10 + (darkArtworkBoost * 0.14))
        let readabilityDarken = min(0.84, 0.42 + (lightArtworkBoost * 0.24) + (veryLightBoost * 0.24) + (effectiveHover ? 0.08 : 0.02))
        let neutralWashOpacity = min(0.52, 0.16 + (lightArtworkBoost * 0.20) + (veryLightBoost * 0.18))
        let blueFogOpacity = min(0.34, 0.08 + (lightArtworkBoost * 0.10) + (veryLightBoost * 0.14))
        let mistOpacity = min(0.60, 0.20 + (lightArtworkBoost * 0.18) + (veryLightBoost * 0.16))
        let primaryShadowOpacity = min(0.94, 0.56 + (lightArtworkBoost * 0.22) + (darkArtworkBoost * 0.12))
        let secondaryShadowOpacity = min(0.84, 0.46 + (lightArtworkBoost * 0.18) + (darkArtworkBoost * 0.10))
        let infoBandHeight: CGFloat = infoExpanded ? 196 : 126
        let blurFadeHeight: CGFloat = min(44, infoBandHeight * 0.34)
        let resolvedCardHeight = model.miniPopoverHeight
        let liveCardHeight = min(resolvedCardHeight, max(model.miniBaseHeight, availableHeight))
        let visibleLyricsHeight = min(
            model.miniLyricsPaneHeight,
            max(0, liveCardHeight - model.miniBaseHeight)
        )
        let shouldRenderMiniLyricsPane = showMiniLyricsPane || visibleLyricsHeight > 0.5
        let seamOpacity = min(1, max(0, visibleLyricsHeight / max(1, model.miniLyricsPaneHeight)))
        let miniMarqueeLaneWidth = max(120, model.popoverWidth - 64)
        let miniTrackKey = "\(model.provider.rawValue)|\(model.artist)|\(model.album)|\(model.title)"
        let miniDetachedControlScale = model.detachedMiniControlScaleFactor

        return VStack(spacing: 0) {
            ZStack {
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

                    if let artwork = model.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .blur(radius: 32)
                            .scaleEffect(1.08)
                            .opacity(0.32)
                    }
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
            .frame(height: model.miniBaseHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6 * miniDetachedControlScale) {
                    ModeToggleControl(
                        isMiniMode: true,
                        transitionActive: transitionActive,
                        sizeScale: miniDetachedControlScale,
                        action: onToggleMode
                    )

                    DetachedSurfaceToggleControl(
                        isDetachedMode: model.surfaceMode == .detached,
                        transitionActive: transitionActive,
                        sizeScale: miniDetachedControlScale
                    ) {
                        model.requestToggleDetachedMode()
                    }

                    if model.surfaceMode == .detached {
                        DetachedWindowPinControl(
                            isPinned: model.detachedWindowAlwaysOnTop,
                            transitionActive: transitionActive,
                            sizeScale: miniDetachedControlScale
                        ) {
                            model.detachedWindowAlwaysOnTop.toggle()
                        }

                        DetachedWindowCloseControl(
                            transitionActive: transitionActive,
                            sizeScale: miniDetachedControlScale
                        ) {
                            model.requestCloseDetachedWindow()
                        }
                    }

                    MiniLyricsToggleControl(
                        isOn: model.miniLyricsEnabled,
                        transitionActive: transitionActive,
                        sizeScale: miniDetachedControlScale
                    ) {
                        let targetEnabled = !model.miniLyricsEnabled
                        syncRenderedMiniLyricsPane(for: targetEnabled)
                        if model.miniLyricsEnabled {
                            // Closing lyrics shrinks the card immediately; keep controls visible
                            // until we receive a definitive pointer-exit event.
                            pointerHovering = true
                            forceExpandedUntilPointerExit = true
                        }
                        model.miniLyricsEnabled = targetEnabled
                    }

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
                }
                .padding(.horizontal, 6 * miniDetachedControlScale)
                .padding(.vertical, 5 * miniDetachedControlScale)
                .background(
                    GeometryReader { geo in
                        ZStack {
                            // Faux backdrop blur constrained to the control capsule bounds.
                            if let artwork = model.artwork {
                                Image(nsImage: artwork)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFill()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .blur(radius: 14)
                                    .scaleEffect(1.01)
                                    .opacity(0.85)
                            }

                            RoundedRectangle(cornerRadius: 12 * miniDetachedControlScale, style: .continuous)
                                .fill(Color.black.opacity(0.30))
                                .overlay(
                                    Color(red: 0.60, green: 0.66, blue: 0.74)
                                        .opacity(neutralWashOpacity * 0.65)
                                )
                                .overlay(
                                    Color(red: 0.52, green: 0.61, blue: 0.76)
                                        .opacity(blueFogOpacity * 0.65)
                                )

                            RoundedRectangle(cornerRadius: 12 * miniDetachedControlScale, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.10), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                            RoundedRectangle(cornerRadius: 12 * miniDetachedControlScale, style: .continuous)
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12 * miniDetachedControlScale, style: .continuous))
                    }
                )
                .shadow(color: .black.opacity(0.30), radius: 6 * miniDetachedControlScale, x: 0, y: 2 * miniDetachedControlScale)
                .padding(.top, 10 * miniDetachedControlScale)
                .padding(.trailing, 10 * miniDetachedControlScale)
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
            }
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    if effectiveHover, let artwork = model.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .blur(radius: 14)
                            .scaleEffect(1.01)
                            .padding(8)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .mask(
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    VStack(spacing: 0) {
                                        LinearGradient(
                                            colors: [.clear, .white],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: blurFadeHeight)

                                        Rectangle()
                                            .frame(height: max(0, infoBandHeight - 20 - blurFadeHeight))
                                    }
                                }
                            )
                            .opacity(0.85)
                            .animation(.easeInOut(duration: 0.18), value: effectiveHover)
                            .allowsHitTesting(false)
                    }

                    Rectangle()
                        .fill(Color.black.opacity(0.30))
                        .overlay(
                            Color(red: 0.60, green: 0.66, blue: 0.74)
                                .opacity(neutralWashOpacity)
                        )
                        .overlay(
                            Color(red: 0.52, green: 0.61, blue: 0.76)
                                .opacity(blueFogOpacity)
                        )
                        .overlay(
                            LinearGradient(
                                colors: [
                                    .white.opacity(mistOpacity),
                                    .white.opacity(mistOpacity * 0.22),
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
                                    .black.opacity(readabilityDarken * 0.62),
                                    .black.opacity(readabilityDarken)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: infoBandHeight)
                        .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: { model.openProviderApp() }) {
                            NowPlayingTitleMarquee(
                                text: model.displayTitle,
                                enabled: true,
                                isVisible: model.isPopoverVisible,
                                laneWidth: miniMarqueeLaneWidth
                            )
                            .foregroundStyle(.white.opacity(0.98))
                            .shadow(color: .black.opacity(primaryShadowOpacity), radius: 2.5, x: 0, y: 1.2)
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
                        .shadow(color: .black.opacity(secondaryShadowOpacity), radius: 1.8, x: 0, y: 1)

                        if infoExpanded {
                            PlaybackProgressBlock(onSeek: { model.seek(to: $0) })
                            .transition(.opacity.combined(with: .move(edge: .bottom)))

                            HStack {
                                Spacer(minLength: 0)
                                ControlsRow(
                                    isPlaying: model.isPlaying,
                                    onPrev: { model.previousTrack() },
                                    onPlayPause: { model.playPause() },
                                    onNext: { model.nextTrack() },
                                    controlScale: miniDetachedControlScale
                                )
                                Spacer(minLength: 0)
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))

                            OutputControlsRow(
                                model: model,
                                showDeviceName: false,
                                controlScale: miniDetachedControlScale,
                                showFavorite: model.canFavoriteCurrentTrack,
                                favoriteIsActive: model.isCurrentTrackFavorited,
                                favoritePulseToken: model.favoriteActionPulseToken,
                                onFavorite: { _ = model.toggleCurrentTrackFavorite() }
                            )
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
            // Re-clip after all overlays so bottom-band content cannot spill into the lyrics pane.
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    if let artwork = model.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .blur(radius: miniSeamBlurRadius)
                            .opacity(0.28)
                            .frame(height: miniSeamBlendHeight * 2.2)
                            .offset(y: 2)
                            .clipped()
                    }

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
            .onChange(of: transitionActive) { active in
                if active {
                    withAnimation(.easeOut(duration: 0.08)) {
                        pointerHovering = false
                    }
                }
            }
            .onChange(of: model.miniLyricsEnabled) { enabled in
                syncRenderedMiniLyricsPane(for: enabled)
            }

            if shouldRenderMiniLyricsPane {
                MiniExpandedLyricsPane(
                    model: model,
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastTrackKey: String = ""
    @State private var incomingOpacity: Double = 1
    @State private var incomingScale: CGFloat = 1
    @State private var incomingBlur: CGFloat = 0
    @State private var streamReadyForDisplay: Bool = false
    private let streamCrossfadeDuration: Double = 2.8

    private var streamCrossfadeAnimation: Animation {
        .easeInOut(duration: streamCrossfadeDuration)
    }

    var body: some View {
        artworkLayer(for: artwork, animatedURL: animatedArtworkURL)
            .opacity(incomingOpacity)
            .scaleEffect(incomingScale)
            .blur(radius: incomingBlur)
        .clipped()
        .onAppear {
            seedPresentationState()
        }
        .onChange(of: animatedArtworkURL) { _ in
            withAnimation(streamCrossfadeAnimation) {
                streamReadyForDisplay = false
            }
        }
        .onChange(of: trackKey) { _ in
            handleArtworkStateChange()
        }
        .onChange(of: animationsEnabled) { enabled in
            guard !enabled else { return }
            seedPresentationState()
        }
        .onChange(of: transitionActive) { active in
            guard active else { return }
            seedPresentationState()
        }
    }

    @ViewBuilder
    private func artworkLayer(for image: NSImage?, animatedURL: URL?) -> some View {
        ZStack {
            staticArtworkLayer(for: image)

            if let animatedURL {
                AnimatedArtworkPlayerView(
                    streamURL: animatedURL,
                    isActive: isPopoverVisible,
                    onRenderReadinessChanged: { isReady in
                        guard isReady != streamReadyForDisplay else { return }
                        withAnimation(streamCrossfadeAnimation) {
                            streamReadyForDisplay = isReady
                        }
                    }
                )
                .opacity(streamReadyForDisplay ? 1 : 0)
            }
        }
    }

    @ViewBuilder
    private func staticArtworkLayer(for image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [tint.opacity(0.45), .black.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func seedPresentationState() {
        incomingOpacity = 1
        incomingScale = 1
        incomingBlur = 0
        lastTrackKey = trackKey
    }

    private func handleArtworkStateChange() {
        let trackChanged = trackKey != lastTrackKey
        guard trackChanged else { return }
        lastTrackKey = trackKey

        guard animationsEnabled, !transitionActive else {
            seedPresentationState()
            return
        }

        if reduceMotion {
            runFadeIn(duration: 0.18)
            return
        }

        runFadeIn(duration: 0.48, startScale: 1.02, startBlur: 6)
    }

    private func runFadeIn(duration: Double, startScale: CGFloat = 1, startBlur: CGFloat = 0) {
        var reset = Transaction(animation: nil)
        reset.disablesAnimations = true
        withTransaction(reset) {
            incomingOpacity = 0
            incomingScale = startScale
            incomingBlur = startBlur
        }
        withAnimation(.easeInOut(duration: duration)) {
            incomingOpacity = 1
            incomingScale = 1
            incomingBlur = 0
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

private struct MiniExpandedLyricsPane: View {
    @ObservedObject var model: NowPlayingModel
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

                // Subtle tint bleed so the lyrics pane inherits current artwork mood.
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
                switch model.lyricsState {
                case .idle:
                    stateRow("Start playback to load lyrics.", icon: "play.square")
                case .loading:
                    let progress = model.lyricsLoadingProgress
                    LyricsLoadingPulseBlock(
                        primaryFontSize: 12,
                        secondaryText: miniLoadingMessage(progress: progress),
                        secondaryFontSize: 11
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .unavailable:
                    stateRow("Lyrics unavailable for this track.", icon: "text.bubble")
                case .failed:
                    stateRow("Couldn't fetch lyrics right now.", icon: "exclamationmark.octagon")
                case .available:
                    lyricsScroll
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .overlay(alignment: .topTrailing) {
                miniLyricsSourceBadge
                    .padding(.top, 5)
                    .padding(.trailing, 10)
            }
        }
        .frame(height: max(0, visibleHeight), alignment: .top)
        .onAppear {
            // When lyrics are available, immediate active-line scroll + per-line animations
            // can fight the pane expand transition and look jittery.
            settleWorkItem?.cancel()
            enableLyricLineAnimations = false
            coordinator.allowsAnimatedScroll = false

            let work = DispatchWorkItem {
                enableLyricLineAnimations = true
                coordinator.allowsAnimatedScroll = true
                settleWorkItem = nil
            }
            settleWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + miniLyricsTransitionDuration, execute: work)
        }
        .onDisappear {
            settleWorkItem?.cancel()
            settleWorkItem = nil
            enableLyricLineAnimations = false
            coordinator.allowsAnimatedScroll = false
        }
        .onChange(of: model.lyricsPayload?.lines.first?.id) { _ in
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

    private func stateRow(_ message: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func miniLoadingMessage(progress: LyricsLoadingProgress?) -> String {
        guard let progress else { return "Preparing lyric request" }
        return "\(progress.stage.displayTitle) · Attempt \(progress.attempt) of \(progress.maxAttempts)"
    }

    @ViewBuilder
    private var miniLyricsSourceBadge: some View {
        if let source = model.lyricsPayload?.source, source != .none {
            if source == .lrclib {
                Button(action: openLRCLibWebsite) {
                    Text("LRCLib")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Open LRCLIB website")
            } else {
                Text("Apple Music")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
            }
        }
    }

    private func openLRCLibWebsite() {
        guard let url = URL(string: "https://lrclib.net") else { return }
        NSWorkspace.shared.open(url)
    }

    private var lyricsScroll: some View {
        let lines = model.lyricsPayload?.lines ?? []

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(lines) { line in
                        let isActive = line.id == activeLineID
                        Text(line.text)
                            .font(.system(size: isActive ? 17 : 12, weight: isActive ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(isActive ? .white.opacity(0.98) : .white.opacity(0.72))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, isActive ? 5 : 1)
                            .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
                            .animation(enableLyricLineAnimations ? .easeInOut(duration: 0.24) : nil, value: isActive)
                            .id(line.id)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 2)
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

private struct MiniLyricsToggleControl: View {
    let isOn: Bool
    let transitionActive: Bool
    var sizeScale: CGFloat = 1
    let action: () -> Void
    @State private var hovering = false

    private var clampedSizeScale: CGFloat {
        min(max(sizeScale, 0.80), 1.20)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "quote.bubble.fill" : "quote.bubble")
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
        .onHover { hovering in
            guard !transitionActive else {
                if self.hovering { self.hovering = false }
                return
            }
            withAnimation(.easeOut(duration: 0.16)) {
                self.hovering = hovering
            }
        }
        .hoverHint(isOn ? "Hide lyrics" : "Show lyrics", enabled: !transitionActive)
    }
}

// MARK: - Lyrics scroll coordinator

/// Drives lyric line highlight and scroll position from a plain NSTimer without
/// going through SwiftUI's reactive system (no @Published / @ObservedObject).
///
/// Every timer tick reads PlaybackClock.shared.elapsed directly and computes the
/// active line. If the active line changed it:
///   1. Calls the onActiveLineChanged closure (which updates a @State var in the view)
///   2. Calls the scrollProxy to scroll to the new line
///
/// Because the @State update only fires when the active LINE changes (not every 0.5 s),
/// the SwiftUI re-render rate is bounded by song structure — typically a few times per
/// minute, not 120 times per minute. This avoids triggering DesignLibrary's glass
/// compositor on every tick on macOS 26.
private final class LyricsScrollCoordinator {
    var lines: [LyricsLine] = []
    var isTimed: Bool = false
    var allowsAnimatedScroll: Bool = true
    var onActiveLineChanged: ((UUID?) -> Void)?
    var scrollProxy: ScrollViewProxy?

    private var timer: Timer?
    private var lastActiveLineID: UUID?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
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
        let elapsed = PlaybackClock.shared.elapsed
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

// MARK: - Regular view lyrics

private struct RegularLyricsToggleControl: View {
    let isOn: Bool
    let lyricsState: LyricsState
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
            ZStack {
                Image(systemName: isOn ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 16 * clampedSizeScale, weight: .semibold))
                    .foregroundStyle(.white.opacity(isOn ? 0.98 : 0.90))

                // Subtle loading indicator dot
//                if lyricsState == .loading && !isOn {
//                    Circle()
//                        .fill(Color.accentColor.opacity(0.72))
//                        .frame(width: 5, height: 5)
//                        .offset(x: 7, y: -7)
//                }
            }
            .frame(width: 24 * clampedSizeScale, height: 24 * clampedSizeScale)
            .background(Circle().fill(Color.primary.opacity(min(0.34, 0.08 + (0.18 * clampedContrast)))))
            .overlay(
                Circle()
                    .stroke(.white.opacity(min(0.32, (hovering ? 0.24 : 0.16) + (0.08 * clampedContrast))), lineWidth: 1)
            )
            .scaleEffect(hovering ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.16)) {
                hovering = h
            }
        }
        .hoverHint(isOn ? "Hide lyrics" : "Show lyrics")
        .animation(.easeInOut(duration: 0.18), value: isOn)
    }
}

/// Value-type wrapper so SwiftUI only re-renders RegularLyricsPane when its
/// displayed properties actually change — not on every model.elapsed tick.
private struct RegularLyricsPane: View {
    // model is passed through only for child use (retryLyricsFetch, scroll content).
    // The pane itself reads only value-type arguments so @ObservedObject churn is avoided.
    let model: NowPlayingModel
    let lyricsState: LyricsState
    let lyricsPayload: LyricsPayload?
    let lyricsLoadingProgress: LyricsLoadingProgress?
    let glassTint: Color
    let artwork: NSImage?
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
                    // glass compositor paths. Use gradients only, as MiniExpandedLyricsPane does.
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

                // Header label — plain color fill, no system material
                HStack {
                    Label("Lyrics", systemImage: "quote.bubble.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))

                    Spacer(minLength: 0)

                    // Source badge — plain color fill, no system material
                    if let source = lyricsPayload?.source, source != .none {
                        if source == .lrclib {
                            Button(action: openLRCLibWebsite) {
                                Text("LRCLib")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.58))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.white.opacity(0.10)))
                                    .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help("Open LRCLIB website")
                        } else {
                            Text("Apple Music")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.46))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                                .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                // Content — switch on coarse state only; elapsed-driven scroll lives in child
                VStack(alignment: .leading, spacing: 0) {
                    switch lyricsState {
                    case .idle:
                        stateView("Start playback to load lyrics.", icon: .provider(.appleMusic))
                    case .loading:
                        loadingProgressView(progress: lyricsLoadingProgress)
                    case .unavailable:
                        stateView("Lyrics unavailable for this track.", icon: .sfSymbol("text.bubble"))
                    case .failed:
                        VStack(spacing: 10) {
                            stateView("Couldn't fetch lyrics right now.", icon: .sfSymbol("exclamationmark.bubble"))
//                            Button("Retry") { model.retryLyricsFetch() }
//                                .buttonStyle(.bordered)
//                                .controlSize(.small)
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
                .padding(.top, 36)
                .padding(.bottom, 12)
                .padding(.horizontal, 14)
            }
            .frame(height: paneContentHeight)
        }
        .frame(height: max(0, visibleHeight), alignment: .top)
        .clipped()
    }

    private enum LyricsStateIcon {
        case sfSymbol(String)
        case provider(ProviderIconKind)
    }

    private func stateView(_ message: String, icon: LyricsStateIcon) -> some View {
        VStack(spacing: 8) {
            Group {
                switch icon {
                case .sfSymbol(let symbolName):
                    Image(systemName: symbolName)
                        .font(.system(size: 22, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                case .provider(let providerIcon):
                    ProviderIconView(icon: providerIcon, size: 22, weight: .regular)
                }
            }
            .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

    private func openLRCLibWebsite() {
        guard let url = URL(string: "https://lrclib.net") else { return }
        NSWorkspace.shared.open(url)
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
            .onChange(of: renderLines.first?.id) { _ in
                coordinator.lines = renderLines
                coordinator.isTimed = isTimed
            }
            .onChange(of: isTimed) { timed in
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
