import SwiftUI

/// What the pane shows while lyrics are being fetched.
///
/// Replaces five views — a regular route card, a mini route card, their two segment types and a
/// pulsing text block that no longer had any callers. One view now serves both surfaces, so the
/// copy and the timing cannot drift apart the way two parallel implementations had started to.
///
/// Three things changed in the design:
///
/// **It waits.** Most fetches resolve in a couple of hundred milliseconds, and an elaborate
/// status card that flashes for 200ms is noise. Nothing appears at all until `skeletonDelay`,
/// and the status strip only joins it if the fetch is still running at `statusDelay` — by which
/// point the user genuinely wants to know it has not stalled.
///
/// **It fills the pane.** Skeleton lines in the shape of lyrics mean the pane is never an empty
/// void with a card floating in it, and the real lyrics arriving is a swap rather than a sudden
/// appearance.
///
/// **It speaks plainly.** The old copy named the API, the matching strategy and the retry count
/// — "Checking LRCLIB exact match · Attempt 1 of 2". Which service answered is shown by the
/// source badge once lyrics arrive; while waiting, the useful signal is only that the search has
/// widened, which the two segments carry on their own.
struct LyricsFetchProgressView: View {
    let progress: LyricsLoadingProgress?
    let tint: Color
    /// Mini has roughly half the height to work with, so it gets fewer, tighter lines.
    var isCompact: Bool = false
    /// Matches the pane's real lyric type so the skeleton does not jump when it is replaced.
    var lineFontSize: CGFloat = 14
    /// A retry the user asked for shows itself at once. The waiting behaviour below is there to
    /// keep automatic fetches quiet, but applied to a tap it swallows the only feedback the
    /// button has.
    var startsImmediately: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSkeleton = false
    @State private var showStatus = false
    /// Latched, because the stage is not monotonic: a second attempt re-emits `.starting`, and
    /// without this the route would visibly walk backwards mid-fetch.
    @State private var hasWidened = false
    /// Bumped when a new fetch begins. See `resetForNewFetch`.
    @State private var fetchGeneration = 0

    private var skeletonDelay: TimeInterval { startsImmediately ? 0 : 0.5 }
    private var statusDelay: TimeInterval { startsImmediately ? 0.45 : 1.6 }

    /// Deterministic so the skeleton does not reshuffle on every re-render.
    private var lineWidths: [Double] {
        isCompact ? [0.74, 0.52, 0.86, 0.44] : [0.78, 0.56, 0.88, 0.62, 0.72, 0.46]
    }

    private var isWiderSearch: Bool {
        switch progress?.stage ?? .starting {
        case .lrclibSearch, .musicFallback: return true
        case .starting, .lrclibExact: return false
        }
    }

    private var accent: Color {
        DetailPaneAccent.legible(tint, in: colorScheme)
    }

    private var barHeight: CGFloat { max(8, lineFontSize * 0.72) }
    private var barSpacing: CGFloat { isCompact ? 7 : 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 10 : 14) {
            if showStatus {
                statusStrip
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if showSkeleton {
                skeleton
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: showStatus)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: showSkeleton)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: hasWidened)
        .onChange(of: isWiderSearch, initial: true) { _, isWider in
            if isWider { hasWidened = true }
        }
        // Skipping tracks mid-fetch keeps `lyricsState` on `.loading` throughout, so SwiftUI
        // reuses this view rather than rebuilding it — without an explicit reset the next track
        // inherits the previous one's shown strip and widened route, and never gets its grace
        // period. The model nils `progress` at the start of each fetch, which is the signal.
        .onChange(of: progress == nil) { _, isStartingOver in
            guard isStartingOver else { return }
            resetForNewFetch()
        }
        .task(id: fetchGeneration) {
            // Cancelled automatically when the state leaves `.loading`, so a fast fetch shows
            // nothing at all.
            try? await Task.sleep(nanoseconds: UInt64(skeletonDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            showSkeleton = true

            try? await Task.sleep(nanoseconds: UInt64((statusDelay - skeletonDelay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            showStatus = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(hasWidened ? "Searching more widely for lyrics" : "Finding lyrics"))
    }

    /// Returns the pane to its opening state so the next track earns the strip on its own timing
    /// instead of inheriting it. Bumping the generation restarts the delay task.
    private func resetForNewFetch() {
        showSkeleton = false
        showStatus = false
        hasWidened = false
        fetchGeneration &+= 1
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(colorScheme == .dark ? .black.opacity(0.80) : .white)
                .frame(width: 19, height: 19)
                .background(accent, in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))

            Text("Finding lyrics…")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.86) : .primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                routeSegment(isActive: !hasWidened, isComplete: hasWidened)
                routeSegment(isActive: hasWidened, isComplete: false)
            }
            .frame(width: isCompact ? 84 : 104)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(statusBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? .white.opacity(0.09) : accent.opacity(0.18),
                    lineWidth: playerHairlineWidth
                )
        )
    }

    /// A gradient rather than `.ultraThinMaterial`.
    ///
    /// This view re-renders on every progress update, and on macOS 26 a material re-invokes the
    /// Liquid Glass compositor each time — the same hazard `ArtworkView` documents and avoids.
    private var statusBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [.white.opacity(0.09), .white.opacity(0.05)]
                        : [.black.opacity(0.05), .black.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(colorScheme == .dark ? 0.07 : 0.05))
            )
    }

    private func routeSegment(isActive: Bool, isComplete: Bool) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.12))

            if isComplete {
                Capsule().fill(accent.opacity(0.70))
            } else if isActive {
                // A resting tint under the sweep, so the active leg still reads as active at
                // the moment the highlight is off the end of the track.
                Capsule().fill(accent.opacity(0.28))

                if reduceMotion {
                    // A static half-fill still says "this one is running" without motion.
                    GeometryReader { geo in
                        Capsule()
                            .fill(accent.opacity(0.70))
                            .frame(width: geo.size.width * 0.5)
                    }
                } else {
                    LyricsFetchRouteSweep(accent: accent)
                }
            }
        }
        .frame(height: 2)
        .clipShape(Capsule())
    }

    private var skeleton: some View {
        skeletonBars
            // Measured on screen: 0.07 was indistinguishable from the pane's own gradient — the
            // bars read as compression artefacts rather than as placeholders for text.
            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.10))
            .modifier(
                LyricsSkeletonShimmer(
                    shape: skeletonBars,
                    // The band has to move *away* from the page in each scheme. A light band on
                    // light-mode bars is the background colour and vanishes.
                    band: colorScheme == .dark ? .white.opacity(0.22) : .black.opacity(0.10),
                    isEnabled: !reduceMotion
                )
            )
            .accessibilityHidden(true)
    }

    /// Untinted, so the same geometry can serve twice: once tinted as the bars themselves, once
    /// at full alpha as the shimmer's mask. Masking with the *tinted* bars would square their
    /// opacity — 0.14 became 0.02, which is why the skeleton was all but invisible.
    private var skeletonBars: some View {
        VStack(alignment: .leading, spacing: barSpacing) {
            ForEach(Array(lineWidths.enumerated()), id: \.offset) { _, width in
                GeometryReader { geo in
                    Capsule().frame(width: geo.size.width * width)
                }
                .frame(height: barHeight)
            }
        }
    }
}

/// A highlight travelling along the active leg of the route.
private struct LyricsFetchRouteSweep: View {
    let accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            GeometryReader { geometry in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.45) / 1.45
                let highlightWidth = geometry.size.width * 0.45

                Capsule()
                    .fill(accent)
                    .frame(width: highlightWidth, height: 2)
                    .blur(radius: 1.2)
                    .offset(x: (geometry.size.width + highlightWidth) * phase - highlightWidth)
            }
        }
    }
}

/// A slow bright band drifting across the skeleton, so it reads as pending rather than as
/// content that failed to load.
private struct LyricsSkeletonShimmer<Shape: View>: ViewModifier {
    /// The bar geometry at full alpha, used only to clip the band to the bars.
    let shape: Shape
    let band: Color
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            // Only the band redraws each frame; the bars underneath are static, so the 24fps
            // timeline does not drag the whole skeleton through a re-render.
            content.overlay(
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 2.2) / 2.2
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, band, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.45)
                        .offset(x: (geo.size.width * 1.45 * phase) - (geo.size.width * 0.45))
                    }
                }
                .mask(shape.foregroundStyle(.white))
                .allowsHitTesting(false)
            )
        } else {
            content
        }
    }
}
