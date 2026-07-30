import SwiftUI
import AppKit

func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
    ceil((text as NSString).size(withAttributes: [.font: font]).width) + 10.0
}

/// The track title. Standard SF rather than SF Rounded: rounded reads friendly at menu bar
/// scale but soft at player scale, and the title is the one thing in the window that has to
/// outrank everything else.
struct NowPlayingTitleMarquee: View {
    let text: String
    let enabled: Bool
    let isVisible: Bool
    var laneWidth: CGFloat = 272
    var fontSize: CGFloat = 17

    @State private var startDate = Date()
    @State private var cachedTextWidth: CGFloat = 0

    private let gap: CGFloat = 108
    private let speed: CGFloat = 26
    private let leadInDelay: Double = 0.65

    private var resolvedText: String { text.isEmpty ? "Nothing Playing" : text }
    private var shouldScroll: Bool { isVisible && enabled && cachedTextWidth > laneWidth + 2 }
    private var travel: CGFloat { cachedTextWidth + gap }
    private var cycleDuration: Double { max(8.0, Double(travel / speed)) }
    private var measurementSignature: String { "\(resolvedText)|\(Int(fontSize.rounded()))" }
    private var marqueeSignature: String {
        "\(resolvedText)|\(enabled)|\(isVisible)|\(Int(laneWidth.rounded()))|\(Int(fontSize.rounded()))|\(shouldScroll ? 1 : 0)"
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if shouldScroll {
                TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { timeline in
                    HStack(spacing: gap) {
                        scrollingLabel
                        scrollingLabel
                    }
                    .offset(x: -currentOffset(at: timeline.date))
                }
            } else {
                staticLabel
            }
        }
        .frame(width: laneWidth, height: fontSize + 7, alignment: .leading)
        .id(marqueeSignature)
        .clipped()
        .modifier(ScrollingEdgeFade(enabled: shouldScroll))
        .onAppear { refreshCachedMetrics(resetStartDate: true) }
        .onChange(of: measurementSignature) { _, _ in
            refreshCachedMetrics(resetStartDate: true)
        }
        .onChange(of: marqueeSignature) { _, _ in startDate = Date() }
        .onDisappear { startDate = Date() }
    }

    private var staticLabel: some View {
        Text(resolvedText)
            .font(.system(size: fontSize, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var scrollingLabel: some View {
        Text(resolvedText)
            .font(.system(size: fontSize, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func currentOffset(at date: Date) -> CGFloat {
        guard shouldScroll else { return 0 }
        let elapsed = date.timeIntervalSince(startDate)
        guard elapsed > leadInDelay else { return 0 }
        let active = elapsed - leadInDelay
        let cycle = max(0.001, cycleDuration)
        let progress = active.truncatingRemainder(dividingBy: cycle) / cycle
        return CGFloat(progress) * travel
    }

    private func refreshCachedMetrics(resetStartDate: Bool) {
        let measuredWidth = measuredTextWidth(
            resolvedText,
            font: .systemFont(ofSize: fontSize, weight: .semibold)
        )
        if abs(cachedTextWidth - measuredWidth) > 0.5 {
            cachedTextWidth = measuredWidth
        }
        if resetStartDate {
            startDate = Date()
        }
    }
}

/// A supporting metadata line — artist, or album.
///
/// Size and opacity are explicit rather than a style flag, because the hierarchy is now
/// carried by those two values: artist at 68%, album two steps quieter at 44%. Both sit a
/// full step below the title instead of matching it in everything but weight.
struct NowPlayingSecondaryMarquee: View {
    let text: String
    let enabled: Bool
    let isVisible: Bool
    var laneWidth: CGFloat = 272
    var fontSize: CGFloat = 12.5
    var fontWeight: Font.Weight = .medium
    var textOpacity: Double = 0.68

    @State private var startDate = Date()
    @State private var cachedTextWidth: CGFloat = 0

    private let gap: CGFloat = 88
    private let speed: CGFloat = 26
    private let leadInDelay: Double = 0.55

    private var nsFontWeight: NSFont.Weight {
        fontWeight == .regular ? .regular : .medium
    }

    private var resolvedText: String { text.isEmpty ? " " : text }
    private var shouldScroll: Bool { isVisible && enabled && cachedTextWidth > laneWidth + 2 }
    private var travel: CGFloat { cachedTextWidth + gap }
    private var cycleDuration: Double { max(8.0, Double(travel / speed)) }
    private var measurementSignature: String {
        "\(resolvedText)|\(fontSize)|\(fontWeight == .regular ? 0 : 1)"
    }
    private var marqueeSignature: String {
        "\(resolvedText)|\(enabled)|\(isVisible)|\(Int(laneWidth.rounded()))|\(fontSize)|\(shouldScroll ? 1 : 0)"
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if shouldScroll {
                TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { timeline in
                    HStack(spacing: gap) {
                        scrollingLabel
                        scrollingLabel
                    }
                    .offset(x: -currentOffset(at: timeline.date))
                }
            } else {
                staticLabel
            }
        }
        .frame(width: laneWidth, height: fontSize + 5, alignment: .leading)
        .id(marqueeSignature)
        .clipped()
        .modifier(ScrollingEdgeFade(enabled: shouldScroll))
        .onAppear { refreshCachedMetrics(resetStartDate: true) }
        .onChange(of: measurementSignature) { _, _ in
            refreshCachedMetrics(resetStartDate: true)
        }
        .onChange(of: marqueeSignature) { _, _ in startDate = Date() }
        .onDisappear { startDate = Date() }
    }

    private var staticLabel: some View {
        Text(resolvedText)
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundStyle(.white.opacity(textOpacity))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var scrollingLabel: some View {
        Text(resolvedText)
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundStyle(.white.opacity(textOpacity))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func currentOffset(at date: Date) -> CGFloat {
        guard shouldScroll else { return 0 }
        let elapsed = date.timeIntervalSince(startDate)
        guard elapsed > leadInDelay else { return 0 }
        let active = elapsed - leadInDelay
        let cycle = max(0.001, cycleDuration)
        let progress = active.truncatingRemainder(dividingBy: cycle) / cycle
        return CGFloat(progress) * travel
    }

    private func refreshCachedMetrics(resetStartDate: Bool) {
        let measuredWidth = measuredTextWidth(
            resolvedText,
            font: .systemFont(ofSize: fontSize, weight: nsFontWeight)
        )
        if abs(cachedTextWidth - measuredWidth) > 0.5 {
            cachedTextWidth = measuredWidth
        }
        if resetStartDate {
            startDate = Date()
        }
    }
}

private struct ScrollingEdgeFade: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.03),
                        .init(color: .black, location: 0.97),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        } else {
            content
        }
    }
}
