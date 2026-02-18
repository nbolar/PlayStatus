import SwiftUI
import AppKit

struct NowPlayingPopover: View {
    @ObservedObject var model: NowPlayingModel
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var searchSectionFrame: CGRect = .zero

    private var regularProgress: CGFloat {
        min(max(model.modeMorphProgress, 0), 1)
    }

    private var sourceMiniMode: Bool {
        model.modeMorphSourceMini
    }

    private var targetMiniMode: Bool {
        model.miniMode
    }

    private var isMorphing: Bool {
        model.modeMorphIsActive
    }

    private var morphProgress: CGFloat {
        if sourceMiniMode == targetMiniMode {
            return 1
        }
        return sourceMiniMode ? regularProgress : (1 - regularProgress)
    }

    private var crossfadeProgress: CGFloat {
        let start: CGFloat = 0.52
        let p = min(max(morphProgress, 0), 1)
        return min(max((p - start) / (1 - start), 0), 1)
    }

    var body: some View {
        ZStack {
            if isMorphing, sourceMiniMode != targetMiniMode {
                modeContent(miniMode: sourceMiniMode)
                    .opacity(1 - crossfadeProgress)
                    .allowsHitTesting(false)

                if crossfadeProgress > 0.001 {
                    modeContent(miniMode: targetMiniMode)
                        .opacity(crossfadeProgress)
                        .allowsHitTesting(false)
                }
            } else {
                modeContent(miniMode: targetMiniMode)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            guard miniMode else { return }
            searchText = ""
            isSearchFocused = false
            withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)) {
                isSearchExpanded = false
            }
        }
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                guard isSearchExpanded else { return }
                guard model.provider == .music else { return }
                guard !searchSectionFrame.contains(value.location) else { return }
                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)) {
                    isSearchExpanded = false
                }
                isSearchFocused = false
            }
        )
    }

    @ViewBuilder
    private func modeContent(miniMode: Bool) -> some View {
        if miniMode {
            MiniNowPlayingCard(model: model, transitionActive: isMorphing)
        } else {
            regularContent
        }
    }

    private var regularContent: some View {
        VStack(spacing: 12) {
            LiquidGlassCard(tint: model.glassTint, palette: model.cardBackgroundPalette) {
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 16) {
                    ArtworkView(image: model.artwork, tint: model.glassTint)
                        .frame(width: model.artworkDisplaySize, height: model.artworkDisplaySize)

                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: { model.openProviderApp() }) {
                            NowPlayingTitleMarquee(
                                text: model.displayTitle,
                                enabled: model.scrollableTitle,
                                isVisible: model.isPopoverVisible
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        NowPlayingSecondaryMarquee(
                            text: model.artistAlbumLine,
                            enabled: model.scrollableTitle,
                            isVisible: model.isPopoverVisible,
                            laneWidth: min(320, max(130, model.regularPopoverWidth - model.artworkDisplaySize - 78)),
                            usesSecondaryStyle: false
                        )

                        ProgressBlock(
                            progress: model.progress,
                            elapsed: model.elapsed,
                            duration: model.duration,
                            canSeek: model.canSeek,
                            onSeek: { model.seek(to: $0) }
                        )

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
                        searchSection(maxWidth: min(280, max(170, model.regularPopoverWidth * 0.50)))
                    }
                    .padding(.top, -28)
                    .padding(.bottom, -12)
                }
            }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    ModeToggleControl(isMiniMode: false) {
                        model.miniMode = true
                    }

                    SettingsOpenControl {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.9))
                            .frame(width: 24, height: 24)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.16), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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

}

private struct SearchSectionFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct MiniNowPlayingCard: View {
    @ObservedObject var model: NowPlayingModel
    let transitionActive: Bool
    @State private var isHovering = false

    var body: some View {
        let effectiveHover = isHovering && !transitionActive
        let luminance = artworkLuminance
        let lightArtworkBoost = max(0, (luminance - 0.54) / 0.46)
        let veryLightBoost = max(0, (luminance - 0.72) / 0.28)
        let darkArtworkBoost = max(0, (0.52 - luminance) / 0.52)
        let bottomShade = min(0.82, 0.34 + (lightArtworkBoost * 0.24) + (veryLightBoost * 0.18) + (effectiveHover ? 0.10 : 0.04))
        let topShade = min(0.34, 0.10 + (darkArtworkBoost * 0.14))
        let readabilityDarken = min(0.84, 0.42 + (lightArtworkBoost * 0.24) + (veryLightBoost * 0.24) + (effectiveHover ? 0.08 : 0.02))
        let neutralWashOpacity = min(0.52, 0.16 + (lightArtworkBoost * 0.20) + (veryLightBoost * 0.18))
        let blueFogOpacity = min(0.34, 0.08 + (lightArtworkBoost * 0.10) + (veryLightBoost * 0.14))
        let mistOpacity = min(0.60, 0.20 + (lightArtworkBoost * 0.18) + (veryLightBoost * 0.16))
        let primaryShadowOpacity = min(0.94, 0.56 + (lightArtworkBoost * 0.22) + (darkArtworkBoost * 0.12))
        let secondaryShadowOpacity = min(0.84, 0.46 + (lightArtworkBoost * 0.18) + (darkArtworkBoost * 0.10))
        let infoBandHeight: CGFloat = effectiveHover ? 196 : 126
        let blurFadeHeight: CGFloat = min(44, infoBandHeight * 0.34)

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
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .padding(8)
        }
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                ModeToggleControl(isMiniMode: true) {
                    model.miniMode = false
                }

                SettingsOpenControl {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .frame(width: 26, height: 26)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle().stroke(.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .opacity(effectiveHover ? 1 : 0)
            .padding(.top, 10)
            .padding(.trailing, 10)
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
                    .fill(.ultraThinMaterial)
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
                            enabled: model.scrollableTitle,
                            isVisible: model.isPopoverVisible
                        )
                        .foregroundStyle(.white.opacity(0.98))
                        .shadow(color: .black.opacity(primaryShadowOpacity), radius: 2.5, x: 0, y: 1.2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    NowPlayingSecondaryMarquee(
                        text: model.artistAlbumLine,
                        enabled: model.scrollableTitle,
                        isVisible: model.isPopoverVisible,
                        laneWidth: max(120, model.miniPopoverWidth - 64),
                        usesSecondaryStyle: false
                    )
                    .foregroundStyle(.white.opacity(0.90))
                    .shadow(color: .black.opacity(secondaryShadowOpacity), radius: 1.8, x: 0, y: 1)

                    if effectiveHover {
                        ProgressBlock(
                            progress: model.progress,
                            elapsed: model.elapsed,
                            duration: model.duration,
                            canSeek: model.canSeek,
                            onSeek: { model.seek(to: $0) }
                        )
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
        .onHover { hovering in
            guard !transitionActive else {
                if isHovering {
                    isHovering = false
                }
                return
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
        .onChange(of: transitionActive) { active in
            guard active else { return }
            if isHovering {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovering = false
                }
            }
        }
    }

    private var artworkLuminance: CGFloat {
        guard let average = model.artwork?.averageColor()?.usingColorSpace(.deviceRGB) else {
            return 0.45
        }
        let r = average.redComponent
        let g = average.greenComponent
        let b = average.blueComponent
        // Rec. 709 luma approximation.
        return (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
    }
}

private struct ModeToggleControl: View {
    let isMiniMode: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isMiniMode ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.92))
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(hovering ? 0.24 : 0.16), lineWidth: 1)
                )
                .scaleEffect(hovering ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                self.hovering = hovering
            }
        }
        .help(isMiniMode ? "Switch to regular mode" : "Switch to mini mode")
    }
}
