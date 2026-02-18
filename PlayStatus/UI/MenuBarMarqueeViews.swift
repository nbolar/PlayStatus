import SwiftUI
import AppKit

struct MenuBarLabel: View {
    @ObservedObject var model: NowPlayingModel

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: model.statusIcon)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 13, alignment: .center)

            if model.menuBarTextMode != .iconOnly {
                Text(model.menuBarDisplayTitle)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .lineLimit(1)
                    .frame(width: model.statusTextWidth, alignment: .leading)
                    .clipped()
            }
        }
        .frame(width: model.menuBarLabelWidth, alignment: .leading)
        .accessibilityLabel("PlayStatus")
        .accessibilityValue(model.menuBarTitle)
    }
}

func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
    ceil((text as NSString).size(withAttributes: [.font: font]).width) + 10.0
}

struct NowPlayingTitleMarquee: View {
    let text: String
    let enabled: Bool
    let isVisible: Bool
    var laneWidth: CGFloat = 272

    @State private var startDate = Date()

    private let gap: CGFloat = 108
    private let speed: CGFloat = 26
    private let leadInDelay: Double = 0.65

    private var resolvedText: String { text.isEmpty ? "Nothing Playing" : text }
    private var textWidth: CGFloat {
        measuredTextWidth(resolvedText, font: .systemFont(ofSize: 15, weight: .semibold))
    }
    private var shouldScroll: Bool { isVisible && enabled && textWidth > laneWidth + 2 }
    private var travel: CGFloat { textWidth + gap }
    private var cycleDuration: Double { max(8.0, Double(travel / speed)) }
    private var marqueeSignature: String {
        "\(resolvedText)|\(enabled)|\(isVisible)|\(Int(laneWidth.rounded()))|\(shouldScroll ? 1 : 0)"
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
        .frame(width: laneWidth, height: 24, alignment: .leading)
        .id(marqueeSignature)
        .clipped()
        .modifier(ScrollingEdgeFade(enabled: shouldScroll))
        .onAppear { startDate = Date() }
        .onChange(of: marqueeSignature) { _ in startDate = Date() }
        .onDisappear { startDate = Date() }
    }

    private var staticLabel: some View {
        Text(resolvedText)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var scrollingLabel: some View {
        Text(resolvedText)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
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
}

struct NowPlayingSecondaryMarquee: View {
    let text: String
    let enabled: Bool
    let isVisible: Bool
    var laneWidth: CGFloat = 272
    var usesSecondaryStyle: Bool = true

    @State private var startDate = Date()

    private let gap: CGFloat = 88
    private let speed: CGFloat = 26
    private let leadInDelay: Double = 0.55

    private var resolvedText: String { text.isEmpty ? " " : text }
    private var textWidth: CGFloat {
        measuredTextWidth(resolvedText, font: .systemFont(ofSize: 12, weight: .medium))
    }
    private var shouldScroll: Bool { isVisible && enabled && textWidth > laneWidth + 2 }
    private var travel: CGFloat { textWidth + gap }
    private var cycleDuration: Double { max(8.0, Double(travel / speed)) }
    private var marqueeSignature: String {
        "\(resolvedText)|\(enabled)|\(isVisible)|\(Int(laneWidth.rounded()))|\(shouldScroll ? 1 : 0)"
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
        .frame(width: laneWidth, height: 20, alignment: .leading)
        .id(marqueeSignature)
        .clipped()
        .modifier(ScrollingEdgeFade(enabled: shouldScroll))
        .onAppear { startDate = Date() }
        .onChange(of: marqueeSignature) { _ in startDate = Date() }
        .onDisappear { startDate = Date() }
    }

    private var staticLabel: some View {
        Group {
            if usesSecondaryStyle {
                Text(resolvedText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(resolvedText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var scrollingLabel: some View {
        Group {
            if usesSecondaryStyle {
                Text(resolvedText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Text(resolvedText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
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
