import SwiftUI
import AppKit

private let modeMorphDuration: Double = 0.64
private let modeMorphAnimation = Animation.timingCurve(0.20, 0.94, 0.28, 1.0, duration: modeMorphDuration)

struct NowPlayingPopover: View {
    @ObservedObject var model: NowPlayingModel
    @Namespace private var artworkMorphNamespace
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var searchSectionFrame: CGRect = .zero
    @State private var modeTransitionActive = false
    @State private var modeTransitionResetWorkItem: DispatchWorkItem?
    @State private var artworkMorphEnabled = false
    @State private var regularArtworkOpacity: Double = 1
    @State private var pendingMiniInitialExpand = false
    private var resolvedPopoverHeight: CGFloat {
        model.miniMode ? model.miniPopoverHeight : model.regularPopoverHeight
    }

    var body: some View {
        modeContent(miniMode: model.miniMode)
        .frame(
            width: model.popoverWidth,
            height: resolvedPopoverHeight,
            alignment: .topLeading
        )
        .clipped()
        .coordinateSpace(name: "popoverRoot")
        .onPreferenceChange(SearchSectionFramePreferenceKey.self) { frame in
            searchSectionFrame = frame
        }
        .onChange(of: model.provider) { provider in
            guard provider != .music else { return }
            searchText = ""
            isSearchFocused = false
            withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)) {
                isSearchExpanded = false
            }
        }
        .onChange(of: model.miniMode) { miniMode in
            beginModeTransition()
            if miniMode {
                artworkMorphEnabled = true
            } else {
                artworkMorphEnabled = false
                regularArtworkOpacity = 0
                withAnimation(.easeInOut(duration: 0.80)) {
                    regularArtworkOpacity = 1
                }
            }
            guard miniMode else { return }
            searchText = ""
            isSearchFocused = false
            withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.90, blendDuration: 0.10)) {
                isSearchExpanded = false
            }
        }
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                guard isSearchExpanded else { return }
                guard model.provider == .music else { return }
                guard !searchSectionFrame.contains(value.location) else { return }
                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.90, blendDuration: 0.10)) {
                    isSearchExpanded = false
                }
                isSearchFocused = false
            }
        )
    }

    @ViewBuilder
    private func modeContent(miniMode: Bool) -> some View {
        if miniMode {
            MiniNowPlayingCard(
                model: model,
                artworkMorphNamespace: artworkMorphNamespace,
                transitionActive: modeTransitionActive,
                startExpandedOnAppear: pendingMiniInitialExpand,
                onInitialExpandConsumed: {
                    pendingMiniInitialExpand = false
                },
                onToggleMode: {
                    withAnimation(modeMorphAnimation) {
                        artworkMorphEnabled = false
                        model.miniMode = false
                    }
                }
            )
        } else {
            regularContent
        }
    }

    private var regularContent: some View {
        VStack(spacing: 0) {
            LiquidGlassCard(tint: model.glassTint, palette: model.cardBackgroundPalette) {
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 16) {
                    Group {
                        if artworkMorphEnabled {
                            ArtworkView(image: model.artwork, tint: model.glassTint)
                                .frame(width: model.artworkDisplaySize, height: model.artworkDisplaySize)
                                .matchedGeometryEffect(id: "heroArtwork", in: artworkMorphNamespace)
                        } else {
                            ArtworkView(image: model.artwork, tint: model.glassTint)
                                .frame(width: model.artworkDisplaySize, height: model.artworkDisplaySize)
                                .opacity(regularArtworkOpacity)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: { model.openProviderApp() }) {
                            NowPlayingTitleMarquee(
                                text: model.displayTitle,
                                enabled: true,
                                isVisible: model.isPopoverVisible
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        NowPlayingSecondaryMarquee(
                            text: model.artistAlbumLine,
                            enabled: true,
                            isVisible: model.isPopoverVisible,
                            laneWidth: min(320, max(130, model.popoverWidth - model.artworkDisplaySize - 78)),
                            usesSecondaryStyle: false
                        )

                        PlaybackProgressBlock(onSeek: { model.seek(to: $0) })

                        HStack {
                            Spacer(minLength: 0)
                            ControlsRow(
                                isPlaying: model.isPlaying,
                                onPrev: { model.previousTrack() },
                                onPlayPause: { model.playPause() },
                                onNext: { model.nextTrack() }
                            )
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 2)

                        OutputControlsRow(model: model, showDeviceName: true)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if model.provider == .music {
                    HStack {
                        Spacer(minLength: 0)
                        searchSection(maxWidth: min(280, max(170, model.popoverWidth * 0.50)))
                    }
                    .padding(.top, -28)
                    .padding(.bottom, -12)
                }

            }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    ModeToggleControl(isMiniMode: false, transitionActive: modeTransitionActive) {
                        withAnimation(modeMorphAnimation) {
                            artworkMorphEnabled = true
                            pendingMiniInitialExpand = true
                            model.miniMode = true
                        }
                    }

                    if model.showLyricsPanel {
                        RegularLyricsToggleControl(
                            isOn: model.lyricsPanelExpanded,
                            lyricsState: model.lyricsState
                        ) {
                            model.setLyricsPanelExpanded(!model.lyricsPanelExpanded)
                        }
                    }

                    SettingsOpenControl {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.9))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.16), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
            }

            if model.showLyricsPanel && model.lyricsPanelExpanded {
                RegularLyricsPane(
                    model: model,
                    lyricsState: model.lyricsState,
                    lyricsPayload: model.lyricsPayload,
                    glassTint: model.glassTint,
                    artwork: model.artwork
                )
            }
        }
        .background(
            ZStack {
                LiquidGlassBackground(tint: model.glassTint)
            }
        )
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

    private func searchSection(maxWidth: CGFloat) -> some View {
        let spacing: CGFloat = 4
        let collapsedWidth: CGFloat = 30
        let playWidth: CGFloat = 64
        let rowWidth = max(180, maxWidth)
        let expandedSearchWidth = max(140, rowWidth - playWidth - spacing)
        let containerWidth = isSearchExpanded ? expandedSearchWidth : collapsedWidth
        let textFieldWidth = max(0, expandedSearchWidth - 40)
        let spring = Animation.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)

        return HStack(spacing: spacing) {
            HStack(spacing: isSearchExpanded ? 6 : 0) {
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
                        DispatchQueue.main.async {
                            isSearchFocused = true
                        }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .frame(maxWidth: isSearchExpanded ? nil : .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)

                TextField("Search Music library", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .focused($isSearchFocused)
                    .onSubmit { runSearchAndPlay() }
                    .frame(width: isSearchExpanded ? textFieldWidth : 0, alignment: .leading)
                    .opacity(isSearchExpanded ? 1 : 0)
                    .allowsHitTesting(isSearchExpanded)
            }
            .padding(.horizontal, isSearchExpanded ? 8 : 0)
            .frame(width: containerWidth, height: 34, alignment: isSearchExpanded ? .leading : .center)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .onTapGesture {
                guard !isSearchExpanded else { return }
                withAnimation(spring) {
                    isSearchExpanded = true
                }
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            }

            Button("Play") {
                runSearchAndPlay()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(width: isSearchExpanded ? playWidth : 0)
            .opacity(isSearchExpanded ? 1 : 0)
            .scaleEffect(isSearchExpanded ? 1 : 0.95)
            .allowsHitTesting(isSearchExpanded)
            .clipped()
            .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        }
        .frame(height: 34)
        .animation(spring, value: isSearchExpanded)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchSectionFramePreferenceKey.self,
                    value: proxy.frame(in: .named("popoverRoot"))
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

    private func runSearchAndPlay() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        model.searchAndPlayInMusicLibrary(query: query)
        searchText = ""
    }

    private func beginModeTransition() {
        modeTransitionResetWorkItem?.cancel()
        modeTransitionActive = true
        let reset = DispatchWorkItem {
            modeTransitionActive = false
        }
        modeTransitionResetWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + modeMorphDuration + 0.06, execute: reset)
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
}

/// Thin wrapper around ProgressBlock that observes PlaybackClock instead of
/// NowPlayingModel. This prevents NowPlayingPopover (which observes NowPlayingModel)
/// from receiving objectWillChange notifications on every 0.5-second elapsed tick.
private struct PlaybackProgressBlock: View {
    @ObservedObject private var clock = PlaybackClock.shared
    let onSeek: (Double) -> Void

    var body: some View {
        ProgressBlock(
            progress: clock.progress,
            elapsed: clock.elapsed,
            duration: clock.duration,
            canSeek: clock.canSeek,
            onSeek: onSeek
        )
    }
}

private struct MiniNowPlayingCard: View {
    @ObservedObject var model: NowPlayingModel
    let artworkMorphNamespace: Namespace.ID
    let transitionActive: Bool
    let startExpandedOnAppear: Bool
    let onInitialExpandConsumed: () -> Void
    let onToggleMode: () -> Void
    @State private var pointerHovering = false
    @State private var forceExpandedUntilPointerExit = false

    var body: some View {
        let luminance = artworkLuminance
        let lightArtworkBoost = max(0, (luminance - 0.54) / 0.46)
        let veryLightBoost = max(0, (luminance - 0.72) / 0.28)
        let darkArtworkBoost = max(0, (0.52 - luminance) / 0.52)
        let effectiveHover = (pointerHovering || forceExpandedUntilPointerExit) && !transitionActive
        let controlsVisible = effectiveHover || model.miniLyricsEnabled
        let infoExpanded = effectiveHover || model.miniLyricsEnabled
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

                Group {
                    if let artwork = model.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [model.glassTint.opacity(0.45), .black.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .matchedGeometryEffect(id: "heroArtwork", in: artworkMorphNamespace)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
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
                HStack(spacing: 6) {
                    ModeToggleControl(isMiniMode: true, transitionActive: transitionActive, action: onToggleMode)

                    MiniLyricsToggleControl(
                        isOn: model.miniLyricsEnabled,
                        transitionActive: transitionActive
                    ) {
                        if model.miniLyricsEnabled {
                            // Closing lyrics shrinks the card immediately; keep controls visible
                            // until we receive a definitive pointer-exit event.
                            pointerHovering = true
                            forceExpandedUntilPointerExit = true
                        }
                        // Avoid compounding internal SwiftUI animation with popover resize animation.
                        model.miniLyricsEnabled.toggle()
                    }

                    SettingsOpenControl {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.94))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.14)))
                            .overlay(
                                Circle().stroke(.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.26))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.10), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.30), radius: 6, x: 0, y: 2)
                .padding(.top, 10)
                .padding(.trailing, 10)
                .opacity(controlsVisible ? 1 : 0)
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
                                isVisible: model.isPopoverVisible
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
                            laneWidth: max(120, model.popoverWidth - 64),
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
                                    onNext: { model.nextTrack() }
                                )
                                Spacer(minLength: 0)
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))

                            OutputControlsRow(model: model, showDeviceName: false)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
            // Re-clip after all overlays so bottom-band content cannot spill into the lyrics pane.
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                if startExpandedOnAppear {
                    forceExpandedUntilPointerExit = true
                    onInitialExpandConsumed()
                }
            }
            .onChange(of: transitionActive) { active in
                if active {
                    withAnimation(.easeOut(duration: 0.08)) {
                        pointerHovering = false
                    }
                }
            }

            if model.miniLyricsEnabled {
                Divider()
                    .overlay(.white.opacity(0.12))

                MiniExpandedLyricsPane(model: model)
            }
        }
        .frame(height: model.miniPopoverHeight)
        .background(.clear)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
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
    }

    override func updateTrackingAreas() {
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
            self.trackingAreaRef = nil
        }
        guard enabled else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .assumeInside],
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

private struct MiniExpandedLyricsPane: View {
    @ObservedObject var model: NowPlayingModel
    @State private var activeLineID: UUID?
    @State private var coordinator = LyricsScrollCoordinator()

    var body: some View {
        let clampedArtworkIntensity = min(max(model.artworkColorIntensity, 0.5), 1.8)
        let bleedScale = (clampedArtworkIntensity - 0.5) / 1.3
        let tintTopOpacity = 0.14 + (0.22 * bleedScale)
        let tintMidOpacity = 0.06 + (0.12 * bleedScale)

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
                        model.glassTint.opacity(tintTopOpacity),
                        model.glassTint.opacity(tintMidOpacity),
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

            VStack(alignment: .leading, spacing: 8) {
                switch model.lyricsState {
                case .idle:
                    stateRow("Start playback to load lyrics.")
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Fetching lyrics…")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .unavailable:
                    stateRow("Lyrics unavailable for this track.")
                case .failed:
                    stateRow("Couldn't fetch lyrics right now.")
                case .available:
                    lyricsScroll
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .frame(height: max(0, model.miniLyricsPaneHeight))
        .onChange(of: model.lyricsPayload?.lines.first?.id) { _ in
            // Track changed — restart the coordinator with fresh lines.
            let lines = model.lyricsPayload?.lines ?? []
            let isTimed = model.lyricsPayload?.isTimed ?? false
            coordinator.lines = lines
            coordinator.isTimed = isTimed
            coordinator.onActiveLineChanged = { id in
                activeLineID = id
            }
            coordinator.start()
        }
    }

    private func stateRow(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.86))
            .frame(maxWidth: .infinity, alignment: .leading)
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
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isMiniMode ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.92))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .overlay(
                    Circle()
                        .stroke(.white.opacity(hovering ? 0.24 : 0.16), lineWidth: 1)
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
        .help(isMiniMode ? "Switch to regular mode" : "Switch to mini mode")
    }
}

private struct MiniLyricsToggleControl: View {
    let isOn: Bool
    let transitionActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "quote.bubble.fill" : "quote.bubble")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.primary.opacity(isOn ? 0.98 : 0.90))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .overlay(
                    Circle()
                        .stroke(.white.opacity(hovering ? 0.24 : 0.16), lineWidth: 1)
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
        .help(isOn ? "Hide lyrics" : "Show lyrics")
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
            proxy.scrollTo(id, anchor: .center)
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
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: isOn ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(isOn ? 0.98 : 0.88))

                // Subtle loading indicator dot
                if lyricsState == .loading && !isOn {
                    Circle()
                        .fill(Color.accentColor.opacity(0.72))
                        .frame(width: 5, height: 5)
                        .offset(x: 7, y: -7)
                }
            }
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.primary.opacity(0.08)))
            .overlay(
                Circle()
                    .stroke(.white.opacity(hovering ? 0.24 : 0.16), lineWidth: 1)
            )
            .scaleEffect(hovering ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.16)) {
                hovering = h
            }
        }
        .help(isOn ? "Hide lyrics" : "Show lyrics")
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
    let glassTint: Color
    let artwork: NSImage?

    private let paneHeight: CGFloat = 240

    var body: some View {
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
                            glassTint.opacity(0.14),
                            glassTint.opacity(0.06),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.55)
                    )

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.06)],
                        startPoint: .init(x: 0.5, y: 0.60),
                        endPoint: .bottom
                    )
                }

                // Header label — plain color fill, no system material
                HStack {
                    Label("Lyrics", systemImage: "quote.bubble.fill")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))

                    Spacer(minLength: 0)

                    // Source badge — plain color fill, no system material
                    if let source = lyricsPayload?.source, source != .none {
                        Text(source == .musicApp ? "Apple Music" : "LRCLib")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.46))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                            .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                // Content — switch on coarse state only; elapsed-driven scroll lives in child
                VStack(alignment: .leading, spacing: 0) {
                    switch lyricsState {
                    case .idle:
                        stateView("Start playback to load lyrics.", icon: "music.note")
                    case .loading:
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.9)
                            Text("Fetching lyrics…")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    case .unavailable:
                        stateView("Lyrics unavailable for this track.", icon: "text.bubble")
                    case .failed:
                        VStack(spacing: 10) {
                            stateView("Couldn't fetch lyrics right now.", icon: "exclamationmark.bubble")
                            Button("Retry") { model.retryLyricsFetch() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
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
            .frame(height: paneHeight)
        }
    }

    private func stateView(_ message: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.black.opacity(0.45), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 16)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 20)
                .allowsHitTesting(false)
            }
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
            .font(.system(size: isActive ? 18 : 13, weight: isActive ? .bold : .regular, design: .rounded))
            .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary.opacity(0.72)))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, isActive ? 7 : 4)
    }
}
