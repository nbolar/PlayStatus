import SwiftUI
import AppKit

private struct DetailPaneSurfaceAppearance {
    let colorScheme: ColorScheme
    let glassTint: Color
    let bleed: (top: Double, mid: Double)

    var baseGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color.black.opacity(0.58),
                Color.black.opacity(0.62),
                Color.black.opacity(0.70)
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

    var miniActiveLyricStyle: Color {
        colorScheme == .dark ? .white.opacity(0.98) : .primary.opacity(0.92)
    }

    var miniInactiveLyricStyle: Color {
        colorScheme == .dark ? .white.opacity(0.72) : .secondary.opacity(0.86)
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
                            Text(line.text)
                                .font(.system(
                                    size: isActive ? model.miniLyricsActiveFontSize : model.miniLyricsInactiveFontSize,
                                    weight: isActive ? .semibold : .medium,
                                    design: .rounded
                                ))
                                .foregroundStyle(isActive ? surface.miniActiveLyricStyle : surface.miniInactiveLyricStyle)
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

struct MiniDetailToggleControl: View {
    let isOn: Bool
    let systemName: String
    let helpText: String
    let transitionActive: Bool
    var sizeScale: CGFloat = 1
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    private var clampedSizeScale: CGFloat {
        min(max(sizeScale, 0.80), 1.20)
    }

    private var iconStyle: Color {
        colorScheme == .dark ? .white.opacity(isOn ? 0.98 : 0.90) : .primary.opacity(isOn ? 0.90 : 0.74)
    }

    private var fillStyle: Color {
        colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(isOn ? 0.075 : 0.045)
    }

    private var strokeStyle: Color {
        colorScheme == .dark ? .white.opacity(hovering ? 0.24 : 0.16) : .black.opacity(hovering ? 0.14 : 0.08)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16 * clampedSizeScale, weight: .semibold))
                .foregroundStyle(iconStyle)
                .frame(width: 24 * clampedSizeScale, height: 24 * clampedSizeScale)
                .background(Circle().fill(fillStyle))
                .overlay(
                    Circle()
                        .stroke(strokeStyle, lineWidth: 1)
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
            RegularLyricsScrollContent(
                lines: lyricsPayload?.lines ?? [],
                isTimed: lyricsPayload?.isTimed ?? false,
                inactiveFontSize: inactiveFontSize,
                activeFontSize: activeFontSize
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

struct LyricsLoadingPulseBlock: View {
    let primaryFontSize: CGFloat
    let secondaryText: String?
    let secondaryFontSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private func primaryStyle(opacity: Double) -> Color {
        colorScheme == .dark ? .white.opacity(opacity) : .primary.opacity(min(0.92, opacity + 0.05))
    }

    private func secondaryStyle(opacity: Double) -> Color {
        colorScheme == .dark ? .white.opacity(opacity) : .secondary.opacity(min(0.86, opacity + 0.08))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let wave = (sin((2.0 * .pi / 1.7) * t) + 1.0) * 0.5
            let primaryOpacity = 0.62 + (0.32 * wave)
            let secondaryOpacity = 0.56 + (0.22 * wave)

            VStack(alignment: .leading, spacing: 3) {
                Text("Loading lyrics…")
                    .font(.system(size: primaryFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryStyle(opacity: primaryOpacity))

                if let secondaryText, !secondaryText.isEmpty {
                    Text(secondaryText)
                        .font(.system(size: secondaryFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryStyle(opacity: secondaryOpacity))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}

struct RegularLyricsScrollContent: View {
    let lines: [LyricsLine]
    let isTimed: Bool
    let inactiveFontSize: CGFloat
    let activeFontSize: CGFloat
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
            .font(.system(
                size: isActive ? activeFontSize : inactiveFontSize,
                weight: isActive ? .semibold : .regular,
                design: .rounded
            ))
            .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary.opacity(0.72)))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
            .animation(.easeInOut(duration: 0.34), value: isActive)
    }
}
