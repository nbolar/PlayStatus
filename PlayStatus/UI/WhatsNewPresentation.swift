import SwiftUI
import AppKit

/// The pieces both What's New surfaces are built from.
///
/// The launch sheet and the release ledger show the same catalog rows at two densities, so
/// the row — and the colour vocabulary it draws from — lives here rather than in either one.
enum WhatsNewPalette {
    /// The accents a release contributes to its backdrop, in the order its highlights list
    /// them. Duplicates are dropped so a release of three blue highlights does not paint
    /// three identical blooms on top of each other.
    static func accents(for release: WhatsNewRelease) -> [Color] {
        var seen: [String] = []
        var colors: [Color] = []
        for highlight in release.highlights {
            let key = String(describing: highlight.accent)
            guard !seen.contains(key) else { continue }
            seen.append(key)
            colors.append(highlight.accent.color)
        }
        return colors.isEmpty ? [WhatsNewAccent.blue.color] : colors
    }
}

/// The soft wash behind a release headline, mixed from that release's own accent colours.
///
/// It is deliberately unanimated and hit-testing-free: it sits under a scroll view, and a
/// moving gradient there reads as a rendering bug rather than as life.
struct WhatsNewAuroraBackdrop: View {
    let accents: [Color]
    var height: CGFloat = 230

    private var blooms: [(color: Color, x: CGFloat)] {
        let colors = Array(accents.prefix(3))
        guard !colors.isEmpty else { return [] }
        // Spread the blooms across the width rather than stacking them in the middle.
        let stops: [CGFloat] = colors.count == 1 ? [0.5] : colors.count == 2 ? [0.28, 0.74] : [0.2, 0.52, 0.84]
        return zip(colors, stops).map { (color: $0, x: $1) }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ForEach(Array(blooms.enumerated()), id: \.offset) { _, bloom in
                    Ellipse()
                        .fill(bloom.color.opacity(0.55))
                        .frame(width: proxy.size.width * 0.78, height: height * 0.9)
                        .position(x: proxy.size.width * bloom.x, y: height * 0.16)
                }
            }
            .blur(radius: 52)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .top)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white.opacity(0.9), location: 0.45),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One catalog highlight, drawn as an Apple-style icon row.
///
/// `emphasis` is the only difference between the sheet and the ledger: the sheet gives each
/// row more air because it only ever shows one release.
struct WhatsNewHighlightRow: View {
    enum Emphasis {
        case sheet
        case ledger

        var iconSize: CGFloat { self == .sheet ? 17 : 15 }
        var titleSize: CGFloat { self == .sheet ? 13.5 : 12.5 }
        var messageSize: CGFloat { self == .sheet ? 12 : 11.5 }
        var spacing: CGFloat { self == .sheet ? 15 : 13 }
    }

    let highlight: WhatsNewHighlight
    var emphasis: Emphasis = .sheet

    @Environment(\.colorScheme) private var colorScheme

    /// The catalog's accents are picked to sit on a dark surface. On white they are a shade
    /// too pale to carry a glyph, so they are deepened rather than swapped for other hues.
    private var tint: Color {
        let accent = highlight.accent.color
        guard colorScheme == .light else { return accent }
        let blended = NSColor(accent).blended(withFraction: 0.26, of: .black)
        return blended.map(Color.init) ?? accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: emphasis.spacing) {
            Image(systemName: highlight.symbolName)
                .font(.system(size: emphasis.iconSize, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, alignment: .center)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(highlight.title)
                    .font(.system(size: emphasis.titleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(highlight.message)
                    .font(.system(size: emphasis.messageSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The app's own icon, which is a more honest "this is PlayStatus" mark than any symbol.
struct WhatsNewAppIcon: View {
    var size: CGFloat = 60

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 6)
            .accessibilityHidden(true)
    }
}

/// A small capsule for a version number or a count.
struct WhatsNewPill: View {
    let text: String
    var tint: Color?

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint ?? Color.primary.opacity(0.68))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule().fill((tint ?? Color.primary).opacity(tint == nil ? 0.09 : 0.16))
            )
    }
}

/// A vertical scroll view that says when there is more below.
///
/// A list that only fades its last row still reads as finished, so while content runs past
/// the bottom this fades the edge *and* shows a More pill that scrolls to the end. Both go
/// away once the end is reached. Shared by the launch sheet and the release ledger so the
/// two surfaces answer "is there more?" the same way.
struct WhatsNewScrollingList<Content: View>: View {
    /// How tall the bottom fade is. A fixed height rather than a fraction of the viewport,
    /// so a tall ledger pane does not fade a whole row's worth of text.
    var fadeHeight: CGFloat = 44
    @ViewBuilder let content: Content

    @State private var hasMoreBelow = false
    private let endID = "whats-new-scroll-end"

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 2) {
                ScrollView(.vertical) {
                    content

                    Color.clear
                        .frame(height: 1)
                        .id(endID)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    // A few points of slack so the last pixel of bounce does not flicker the
                    // hint back on at the very end of the list.
                    geometry.contentOffset.y + geometry.containerSize.height
                        < geometry.contentSize.height - 12
                } action: { _, hasMore in
                    withAnimation(.easeOut(duration: 0.2)) {
                        hasMoreBelow = hasMore
                    }
                }
                // Only while there is something below: a fade over the final row, once the
                // list is at its end, would just look like a rendering fault.
                .mask {
                    VStack(spacing: 0) {
                        Color.white
                        LinearGradient(
                            colors: [.white, hasMoreBelow ? .clear : .white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: fadeHeight)
                    }
                }

                // Its own slot under the list, so the pill never sits on top of the text it is
                // pointing at. The slot keeps its height when the pill hides, so the list does
                // not jump as you reach the end.
                WhatsNewMoreBelowHint {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(endID, anchor: .bottom)
                    }
                }
                .opacity(hasMoreBelow ? 1 : 0)
                .allowsHitTesting(hasMoreBelow)
                .accessibilityHidden(!hasMoreBelow)
                .padding(.bottom, 8)
            }
        }
    }
}

/// The "there is more below" affordance under a `WhatsNewScrollingList`.
///
/// A pill rather than a bare chevron: a button is honest about the fact that clicking it
/// does something.
private struct WhatsNewMoreBelowHint: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text("More")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.primary.opacity(isHovering ? 0.95 : 0.78))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Show more changes")
    }
}
