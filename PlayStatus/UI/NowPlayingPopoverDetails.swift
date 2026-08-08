import SwiftUI
import AppKit

enum ArtworkPlayerControlPalette {
    static let activeAccent = Color(red: 0.68, green: 0.88, blue: 1.0)

    static func icon(isActive: Bool = false) -> Color {
        isActive ? activeAccent : .white.opacity(0.94)
    }

    static func fill(isActive: Bool = false, contrastBoost: Double = 0) -> Color {
        let clampedContrast = min(max(contrastBoost, 0), 1)
        let opacity = min(0.36, (isActive ? 0.18 : 0.24) + (0.10 * clampedContrast))
        return (isActive ? activeAccent : .black).opacity(opacity)
    }

    static func stroke(isActive: Bool = false, isHovering: Bool = false, contrastBoost: Double = 0) -> Color {
        let clampedContrast = min(max(contrastBoost, 0), 1)
        let opacity = min(0.42, (isHovering ? 0.34 : 0.20) + (0.08 * clampedContrast))
        return (isActive ? activeAccent : .white).opacity(opacity)
    }

    static func clusterItemFill(isActive: Bool, isHovering: Bool, contrastBoost: Double = 0) -> Color {
        let clampedContrast = min(max(contrastBoost, 0), 1)
        if isActive {
            return activeAccent.opacity(isHovering ? 0.32 : 0.22)
        }
        guard isHovering else { return .clear }
        return .white.opacity(min(0.26, 0.16 + (0.08 * clampedContrast)))
    }

    static func clusterItemStroke(isActive: Bool) -> Color {
        isActive ? activeAccent.opacity(0.44) : .clear
    }
}

/// Chrome for a control that lives inside the shared top-row capsule. The capsule
/// carries the glass, so each glyph stays bare until it is hovered or switched on.
private struct PlayerClusterGlyphChrome: ViewModifier {
    let diameter: CGFloat
    let isActive: Bool
    let isHovering: Bool
    let contrastBoost: Double

    func body(content: Content) -> some View {
        content
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(
                    ArtworkPlayerControlPalette.clusterItemFill(
                        isActive: isActive,
                        isHovering: isHovering,
                        contrastBoost: contrastBoost
                    )
                )
            )
            .overlay(
                Circle().stroke(ArtworkPlayerControlPalette.clusterItemStroke(isActive: isActive), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}

extension View {
    func playerClusterGlyphChrome(
        diameter: CGFloat,
        isActive: Bool = false,
        isHovering: Bool,
        contrastBoost: Double = 0
    ) -> some View {
        modifier(
            PlayerClusterGlyphChrome(
                diameter: diameter,
                isActive: isActive,
                isHovering: isHovering,
                contrastBoost: contrastBoost
            )
        )
    }
}

private struct DetailPaneSurfaceAppearance {
    let colorScheme: ColorScheme
    let glassTint: Color
    let bleed: (top: Double, mid: Double)

    var baseGradientColors: [Color] {
        if colorScheme == .dark {
            // Deeper than the player above it. At the old values the pane came out *lighter*
            // than the surface it hangs from, which inverts the hierarchy — a secondary
            // surface should read as a well, not as a highlight.
            return [
                Color.black.opacity(0.74),
                Color.black.opacity(0.80),
                Color.black.opacity(0.88)
            ]
        }

        return [
            Color.white.opacity(0.86),
            Color(red: 0.95, green: 0.96, blue: 0.98).opacity(0.82),
            Color(red: 0.89, green: 0.92, blue: 0.96).opacity(0.84)
        ]
    }

    var tintGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                glassTint.opacity(bleed.top),
                glassTint.opacity(bleed.mid),
                .clear
            ]
        }

        return [
            glassTint.opacity(min(0.48, 0.14 + (bleed.top * 1.10))),
            glassTint.opacity(min(0.36, 0.09 + (bleed.mid * 1.02))),
            glassTint.opacity(0.10)
        ]
    }

    var tintBlendMode: BlendMode {
        colorScheme == .dark ? .screen : .multiply
    }

    var topSheenColors: [Color] {
        colorScheme == .dark
            ? [.white.opacity(0.04), .clear]
            : [.white.opacity(0.38), .clear]
    }

    var bottomShadeColors: [Color] {
        colorScheme == .dark
            ? [.clear, .black.opacity(0.16), .black.opacity(0.28)]
            : [.clear, .black.opacity(0.035), .black.opacity(0.075)]
    }

    var seamTintColors: [Color] {
        if colorScheme == .dark {
            return [
                glassTint.opacity(0.18),
                glassTint.opacity(0.08),
                .clear
            ]
        }

        return [
            glassTint.opacity(0.26),
            glassTint.opacity(0.14),
            glassTint.opacity(0.04)
        ]
    }

    var seamSheenColors: [Color] {
        colorScheme == .dark
            ? [.white.opacity(0.07), .white.opacity(0.025), .clear]
            : [.white.opacity(0.44), .white.opacity(0.16), .clear]
    }

    var seamShadeColors: [Color] {
        colorScheme == .dark
            ? [.black.opacity(0.14), .black.opacity(0.05), .clear]
            : [.black.opacity(0.055), .black.opacity(0.018), .clear]
    }

    var separatorFill: Color {
        colorScheme == .dark ? Color.black.opacity(0.48) : Color.black.opacity(0.12)
    }

    var separatorTint: Color {
        colorScheme == .dark ? glassTint.opacity(0.08) : glassTint.opacity(0.20)
    }

    /// The active line is the only thing in the app that moves with the music, so it is the
    /// one place a saturated album colour earns its keep. Routed through
    /// `DetailPaneAccent.legible` so a dark or washed-out tint still reads as type.
    var activeLyricStyle: Color {
        DetailPaneAccent.legible(glassTint, in: colorScheme)
    }

    var miniActiveLyricStyle: Color { activeLyricStyle }

    var miniInactiveLyricStyle: Color {
        colorScheme == .dark ? .white.opacity(0.60) : .secondary.opacity(0.86)
    }
}

struct MiniExpandedDetailsPane: View {
    @ObservedObject var model: NowPlayingModel
    let selectedTab: DetailsPaneTab
    let visibleHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @State private var activeLineID: UUID?
    @State private var coordinator = LyricsScrollCoordinator()
    @State private var enableLyricLineAnimations = false
    @State private var settleWorkItem: DispatchWorkItem?

    var body: some View {
        let bleed = lyricsBleedOpacities(for: model.artworkColorIntensity)
        let surface = DetailPaneSurfaceAppearance(
            colorScheme: colorScheme,
            glassTint: model.glassTint,
            bleed: bleed
        )

        ZStack(alignment: .top) {
            ZStack {
                LinearGradient(
                    colors: surface.baseGradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: surface.tintGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(surface.tintBlendMode)
            }
            .overlay(
                LinearGradient(
                    colors: surface.topSheenColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: surface.seamTintColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(surface.tintBlendMode)

                    LinearGradient(
                        colors: surface.seamSheenColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    LinearGradient(
                        colors: surface.seamShadeColors,
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
                    colors: surface.bottomShadeColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 18) {
                    DetailPaneTabChip(tab: .lyrics, isSelected: selectedTab == .lyrics, tint: model.glassTint) {
                        model.selectMiniDetailsTab(.lyrics)
                    }
                    DetailPaneTabChip(tab: .credits, isSelected: selectedTab == .credits, tint: model.glassTint) {
                        model.selectMiniDetailsTab(.credits)
                    }
                    DetailPaneTabChip(tab: .history, isSelected: selectedTab == .history, tint: model.glassTint) {
                        model.selectMiniDetailsTab(.history)
                    }

                    Spacer(minLength: 0)
                    miniDetailSourceBadge
                }

                switch selectedTab {
                case .lyrics:
                    lyricsPaneContent
                case .credits:
                    creditsPaneContent
                case .history:
                    historyPaneContent
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
            LyricsFetchProgressView(
                progress: model.lyricsLoadingProgress,
                tint: model.glassTint,
                isCompact: true,
                lineFontSize: model.miniLyricsInactiveFontSize,
                startsImmediately: model.lyricsFetchIsUserInitiated
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        case .instrumental:
            DetailPaneStateMessage(
                message: "Instrumental — no lyrics for this track.",
                icon: .sfSymbol("waveform"),
                style: .mini
            )
        case .unavailable:
            DetailPaneStateMessage(
                message: LyricsDeadEndCopy.unavailable(afterRetry: model.lyricsRetryFoundNothing),
                icon: .sfSymbol("text.bubble"),
                style: .mini,
                retryTitle: "Look again",
                onRetry: { model.retryLyricsFetch() }
            )
        case .failed:
            DetailPaneStateMessage(
                message: LyricsDeadEndCopy.failed(afterRetry: model.lyricsRetryFoundNothing),
                icon: .sfSymbol("exclamationmark.octagon"),
                style: .mini,
                retryTitle: "Try again",
                onRetry: { model.retryLyricsFetch() }
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

    @ViewBuilder
    private var historyPaneContent: some View {
        if model.playHistory.isEmpty {
            DetailPaneStateMessage(
                message: "Nothing played yet.",
                icon: .sfSymbol("clock.arrow.circlepath"),
                style: .mini
            )
        } else {
            HistoryPaneContent(
                entries: model.playHistory,
                style: .compact,
                tint: model.glassTint,
                playCounts: model.playHistoryPlayCounts,
                onReplay: { model.replayHistoryEntry($0) },
                onRemove: { model.removeHistoryEntry($0) }
            )
        }
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
        case .history:
            if !model.playHistory.isEmpty {
                DetailPaneSourceBadge(text: model.playHistoryBadgeText, style: .mini)
            }
        }
    }

    private func updateLyricAnimationState(for tab: DetailsPaneTab) {
        cancelLyricAnimationState()
        guard tab == .lyrics else { return }

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
        let bleed = lyricsBleedOpacities(for: model.artworkColorIntensity)
        let surface = DetailPaneSurfaceAppearance(
            colorScheme: colorScheme,
            glassTint: model.glassTint,
            bleed: bleed
        )

        return GeometryReader { geometry in
            let edgeInset = miniLyricsScrollEdgeInset(for: geometry.size.height)
            let contentWidth = max(0, geometry.size.width)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        Color.clear
                            .frame(height: edgeInset)
                            .allowsHitTesting(false)

                        ForEach(lines) { line in
                            let isActive = line.id == activeLineID
                            let isSeekable = (model.lyricsPayload?.isTimed ?? false) && line.startTime != nil
                            Text(line.text)
                                .font(.system(
                                    size: isActive ? model.miniLyricsActiveFontSize : model.miniLyricsInactiveFontSize,
                                    weight: isActive ? .semibold : .regular
                                ))
                                .foregroundStyle(isActive ? surface.miniActiveLyricStyle : surface.miniInactiveLyricStyle)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, isActive ? 5 : 1)
                                .animation(enableLyricLineAnimations ? .easeInOut(duration: 0.24) : nil, value: isActive)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard isSeekable, let start = line.startTime else { return }
                                    model.seek(toSeconds: start)
                                }
                                .accessibilityAddTraits(isSeekable ? .isButton : [])
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

struct ModeToggleControl: View {
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
                .font(.system(size: 14 * clampedSizeScale, weight: .semibold))
                .foregroundStyle(ArtworkPlayerControlPalette.icon())
                .playerClusterGlyphChrome(
                    diameter: 26 * clampedSizeScale,
                    isHovering: hovering,
                    contrastBoost: clampedContrast
                )
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
        .accessibilityLabel(Text(isMiniMode ? "Switch to regular mode" : "Switch to mini mode"))
    }
}

struct DetachedSurfaceToggleControl: View {
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
                .font(.system(size: 14 * clampedSizeScale, weight: .semibold))
                .foregroundStyle(ArtworkPlayerControlPalette.icon())
                .playerClusterGlyphChrome(
                    diameter: 26 * clampedSizeScale,
                    isHovering: hovering,
                    contrastBoost: clampedContrast
                )
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
        .accessibilityLabel(Text(isDetachedMode ? "Attach to popover" : "Detach to window"))
    }
}

struct DetachedWindowPinControl: View {
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
                .foregroundStyle(ArtworkPlayerControlPalette.icon(isActive: isPinned))
                .playerClusterGlyphChrome(
                    diameter: 26 * clampedSizeScale,
                    isActive: isPinned,
                    isHovering: hovering,
                    contrastBoost: clampedContrast
                )
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
        .accessibilityLabel(Text("Always on top"))
        .accessibilityValue(Text(isPinned ? "On" : "Off"))
    }
}

struct DetachedWindowCloseControl: View {
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
                .foregroundStyle(ArtworkPlayerControlPalette.icon())
                .playerClusterGlyphChrome(
                    diameter: 26 * clampedSizeScale,
                    isHovering: hovering,
                    contrastBoost: clampedContrast
                )
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
        .accessibilityLabel(Text("Close detached window"))
    }
}

struct MiniDetailToggleControl: View {
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
                .font(.system(size: 14 * clampedSizeScale, weight: .semibold))
                .foregroundStyle(ArtworkPlayerControlPalette.icon(isActive: isOn))
                .playerClusterGlyphChrome(
                    diameter: 26 * clampedSizeScale,
                    isActive: isOn,
                    isHovering: hovering
                )
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
        .accessibilityLabel(Text(helpText))
        .animation(.easeInOut(duration: 0.18), value: isOn)
    }
}

final class LyricsScrollCoordinator {
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
        tick()
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
        onActiveLineChanged?(newID)
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

struct RegularDetailToggleControl: View {
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
                .font(.system(size: 14 * clampedSizeScale, weight: .semibold))
                .foregroundStyle(ArtworkPlayerControlPalette.icon(isActive: isOn))
                .playerClusterGlyphChrome(
                    diameter: 26 * clampedSizeScale,
                    isActive: isOn,
                    isHovering: hovering,
                    contrastBoost: clampedContrast
                )
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
        .hoverHint(helpText, enabled: !transitionActive)
        .accessibilityLabel(Text(helpText))
        .animation(.easeInOut(duration: 0.18), value: isOn)
    }
}

struct RegularDetailsPane: View {
    let model: NowPlayingModel
    let selectedTab: DetailsPaneTab
    let lyricsState: LyricsState
    let lyricsPayload: LyricsPayload?
    let lyricsLoadingProgress: LyricsLoadingProgress?
    let creditsPayload: CreditsPayload?
    let inactiveFontSize: CGFloat
    let activeFontSize: CGFloat
    let glassTint: Color
    let visibleHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let bleed = lyricsBleedOpacities(for: model.artworkColorIntensity)
        let surface = DetailPaneSurfaceAppearance(
            colorScheme: colorScheme,
            glassTint: glassTint,
            bleed: bleed
        )

        ZStack(alignment: .top) {
            ZStack {
                LinearGradient(
                    colors: surface.baseGradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: surface.tintGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(surface.tintBlendMode)
            }
            .overlay(
                LinearGradient(
                    colors: surface.topSheenColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                LinearGradient(
                    colors: surface.bottomShadeColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Rectangle()
                .fill(surface.separatorFill)
                .overlay(surface.separatorTint)
                .frame(height: 1)

            HStack(spacing: 18) {
                DetailPaneTabChip(tab: .lyrics, isSelected: selectedTab == .lyrics, tint: glassTint) {
                    model.selectRegularDetailsTab(.lyrics)
                }
                DetailPaneTabChip(tab: .credits, isSelected: selectedTab == .credits, tint: glassTint) {
                    model.selectRegularDetailsTab(.credits)
                }
                DetailPaneTabChip(tab: .history, isSelected: selectedTab == .history, tint: glassTint) {
                    model.selectRegularDetailsTab(.history)
                }

                Spacer(minLength: 0)

                detailSourceBadge
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 0) {
                switch selectedTab {
                case .lyrics:
                    lyricsTabContent
                case .credits:
                    creditsTabContent
                case .history:
                    historyTabContent
                }
            }
            // Clears the tab row: 12pt top inset + a 12pt label + 6pt gap + the 1.5pt rule,
            // plus breathing room. The old 36 was measured against the shorter capsule
            // chips and left the first lyric line clipped underneath the tabs.
            .padding(.top, 46)
            .padding(.bottom, 12)
            .padding(.horizontal, 14)
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
        case .history:
            if !model.playHistory.isEmpty {
                DetailPaneSourceBadge(text: model.playHistoryBadgeText)
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
        case .instrumental:
            DetailPaneStateMessage(
                message: "Instrumental — no lyrics for this track.",
                icon: .sfSymbol("waveform")
            )
        case .unavailable:
            DetailPaneStateMessage(
                message: LyricsDeadEndCopy.unavailable(afterRetry: model.lyricsRetryFoundNothing),
                icon: .sfSymbol("text.bubble"),
                retryTitle: "Look again",
                onRetry: { model.retryLyricsFetch() }
            )
        case .failed:
            DetailPaneStateMessage(
                message: LyricsDeadEndCopy.failed(afterRetry: model.lyricsRetryFoundNothing),
                icon: .sfSymbol("exclamationmark.bubble"),
                retryTitle: "Try again",
                onRetry: { model.retryLyricsFetch() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .available:
            RegularLyricsScrollContent(
                lines: lyricsPayload?.lines ?? [],
                isTimed: lyricsPayload?.isTimed ?? false,
                inactiveFontSize: inactiveFontSize,
                activeFontSize: activeFontSize,
                activeStyle: DetailPaneAccent.legible(glassTint, in: colorScheme),
                inactiveStyle: colorScheme == .dark ? .white.opacity(0.42) : .secondary.opacity(0.72),
                onSeekToLine: { line in
                    guard let start = line.startTime else { return }
                    model.seek(toSeconds: start)
                }
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
    private var historyTabContent: some View {
        if model.playHistory.isEmpty {
            DetailPaneStateMessage(
                message: "Nothing played yet.\nTracks appear here once you've listened to them.",
                icon: .sfSymbol("clock.arrow.circlepath")
            )
        } else {
            HistoryPaneContent(
                entries: model.playHistory,
                style: .regular,
                tint: glassTint,
                playCounts: model.playHistoryPlayCounts,
                onReplay: { model.replayHistoryEntry($0) },
                onRemove: { model.removeHistoryEntry($0) }
            )
        }
    }

    @ViewBuilder
    private func loadingProgressView(progress: LyricsLoadingProgress?) -> some View {
        LyricsFetchProgressView(
            progress: progress,
            tint: glassTint,
            lineFontSize: inactiveFontSize,
            startsImmediately: model.lyricsFetchIsUserInitiated
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }
}

struct RegularLyricsScrollContent: View {
    let lines: [LyricsLine]
    let isTimed: Bool
    let inactiveFontSize: CGFloat
    let activeFontSize: CGFloat
    var activeStyle: Color = .primary
    var inactiveStyle: Color = .secondary.opacity(0.72)
    /// Absent for untimed lyrics, which have no position to seek to.
    var onSeekToLine: ((LyricsLine) -> Void)? = nil
    @State private var activeLineID: UUID?
    @State private var hoveredLineID: UUID?
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
            // The line above the active one was being sliced in half against the tab row.
            // Mini solves this with spacer insets; the regular pane had no edge treatment at
            // all, so a partially scrolled line just collided with the chrome.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.06),
                        .init(color: .black, location: 0.94),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
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
        let isSeekable = canSeek(to: line)
        let isHovered = isSeekable && hoveredLineID == line.id

        return Text(line.text)
            .font(.system(
                size: isActive ? activeFontSize : inactiveFontSize,
                weight: isActive ? .semibold : .regular
            ))
            .foregroundStyle(isActive ? activeStyle : (isHovered ? activeStyle.opacity(0.75) : inactiveStyle))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            // Inset by the same amount the padding adds, so turning lines into hit targets does
            // not shift the column of text away from where it has always sat.
            .padding(.horizontal, -6)
            .background(seekHighlight(isVisible: isHovered))
            .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
            .animation(.easeInOut(duration: 0.34), value: isActive)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .contentShape(Rectangle())
            .onHover { hovering in
                guard isSeekable else { return }
                hoveredLineID = hovering ? line.id : (hoveredLineID == line.id ? nil : hoveredLineID)
            }
            .onTapGesture {
                guard isSeekable else { return }
                onSeekToLine?(line)
            }
            .accessibilityAddTraits(isSeekable ? .isButton : [])
            .accessibilityHint(isSeekable ? Text("Play from this line") : Text(""))
    }

    private func canSeek(to line: LyricsLine) -> Bool {
        isTimed && line.startTime != nil && onSeekToLine != nil
    }

    @ViewBuilder
    private func seekHighlight(isVisible: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(activeStyle.opacity(isVisible ? 0.10 : 0))
    }
}
