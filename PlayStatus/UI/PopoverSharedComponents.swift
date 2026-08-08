import SwiftUI
import AppKit

enum DetailPaneVisualStyle {
    case mini
    case regular

    func foregroundStyle(for colorScheme: ColorScheme) -> AnyShapeStyle {
        if colorScheme == .dark {
            switch self {
            case .mini:
                return AnyShapeStyle(.white.opacity(0.86))
            case .regular:
                return AnyShapeStyle(.white.opacity(0.76))
            }
        }

        return AnyShapeStyle(Color.secondary.opacity(self == .mini ? 0.84 : 0.92))
    }
}

enum DetailPaneStateIcon {
    case sfSymbol(String)
    case provider(ProviderIconKind)
}

enum CreditsPanePresentationStyle {
    case compact(maxVisibleRows: Int)
    case regular
}

/// Lyrics / Credits, as a tab rather than a chip.
///
/// This used to be a filled *and* stroked capsule around an 11pt rounded label, which left
/// the pane speaking a different dialect from the player above it — bare glyphs up there,
/// bordered pills down here. Selection is now carried the same way it is everywhere else in
/// the player: opacity, plus a rule in the album's own colour on the selected tab only.
struct DetailPaneTabChip: View {
    let tab: DetailsPaneTab
    let isSelected: Bool
    var tint: Color = .accentColor
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    private var foregroundStyle: Color {
        if colorScheme == .dark {
            return .white.opacity(isSelected ? 1.0 : (hovering ? 0.72 : 0.44))
        }
        return isSelected ? .primary.opacity(0.92) : .secondary.opacity(hovering ? 0.86 : 0.62)
    }

    var body: some View {
        Button(action: action) {
            // The rule is an overlay on the label rather than a sibling in a VStack: a bare
            // `Capsule` has no intrinsic width, so as a sibling it stretched to fill the row
            // and dragged the tab's whole hit area with it.
            Text(tab.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foregroundStyle)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(isSelected ? DetailPaneAccent.legible(tint, in: colorScheme) : .clear)
                        .frame(height: 1.5)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { self.hovering = hovering }
        }
        .animation(.easeOut(duration: 0.16), value: isSelected)
        .accessibilityLabel(Text(tab.displayName))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Where the lyrics or credits came from. Provenance, not a control — so it reads as a
/// caption instead of wearing the same pill a tappable thing would.
struct DetailPaneSourceBadge: View {
    let text: String
    var emphasized: Bool = false
    var style: DetailPaneVisualStyle = .regular
    @Environment(\.colorScheme) private var colorScheme

    private var opacity: Double {
        emphasized ? 0.44 : 0.34
    }

    private var foregroundStyle: Color {
        if colorScheme == .dark {
            return .white.opacity(opacity)
        }
        return .secondary.opacity(opacity + 0.26)
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .kerning(0.7)
            .foregroundStyle(foregroundStyle)
    }
}

/// Keeps an album-derived colour readable as type.
///
/// The album tint is chosen to look right as a *surface*, which means it is regularly too
/// dark to set text in on a dark pane, or too pale on a light one. This lifts it to a
/// luminance that works on the ground it is actually being drawn on, keeping the hue.
enum DetailPaneAccent {
    static func legible(_ tint: Color, in colorScheme: ColorScheme) -> Color {
        let base = NSColor(tint).usingColorSpace(.deviceRGB) ?? NSColor.white
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // A near-grey tint has no hue worth preserving; fall back to plain label colour
        // rather than tinting the active line an indeterminate beige.
        guard saturation > 0.10 else {
            return colorScheme == .dark ? .white.opacity(0.98) : .primary.opacity(0.92)
        }

        if colorScheme == .dark {
            return Color(
                NSColor(
                    hue: hue,
                    saturation: min(saturation, 0.62),
                    brightness: max(brightness, 0.86),
                    alpha: 1
                )
            )
        }

        return Color(
            NSColor(
                hue: hue,
                saturation: max(saturation, 0.55),
                brightness: min(brightness, 0.46),
                alpha: 1
            )
        )
    }
}

/// The two lyric dead ends, in their first-time and post-retry wording.
///
/// A retry that lands on the same outcome used to redraw the identical sentence. The fetch really
/// had run — it just finished faster than the pane took to show anything — so the honest fix is
/// copy that reports the re-check, not more animation. Shared because the mini and regular panes
/// word these independently and had already started to drift.
enum LyricsDeadEndCopy {
    static func unavailable(afterRetry: Bool) -> String {
        afterRetry ? "Still no lyrics for this track." : "No lyrics found for this track."
    }

    static func failed(afterRetry: Bool) -> String {
        afterRetry ? "Still couldn't fetch lyrics." : "Couldn't fetch lyrics right now."
    }
}

struct DetailPaneStateMessage: View {
    let message: String
    let icon: DetailPaneStateIcon
    var style: DetailPaneVisualStyle = .regular
    /// Offered when the state is one the user can do something about — a miss is cached for a
    /// day, so without this a transient failure sticks around with nothing to act on.
    var retryTitle: String? = nil
    var onRetry: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var retryHovering = false

    var body: some View {
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
            .foregroundStyle(colorScheme == .dark ? AnyShapeStyle(.white.opacity(0.38)) : AnyShapeStyle(.tertiary))

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(style.foregroundStyle(for: colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            if let retryTitle, let onRetry {
                Button(action: onRetry) {
                    Text(retryTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(
                            colorScheme == .dark
                                ? .white.opacity(retryHovering ? 0.96 : 0.66)
                                : .primary.opacity(retryHovering ? 0.92 : 0.70)
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(retryHovering ? 0.14 : 0.08)
                                    : Color.black.opacity(retryHovering ? 0.09 : 0.05)
                            )
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.14)) { retryHovering = hovering }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct CreditsPaneContent: View {
    let payload: CreditsPayload
    let style: CreditsPanePresentationStyle
    @Environment(\.colorScheme) private var colorScheme

    private var compactLabelStyle: Color {
        colorScheme == .dark ? .white.opacity(0.60) : .secondary.opacity(0.88)
    }

    private var compactValueStyle: Color {
        colorScheme == .dark ? .white.opacity(0.90) : .primary.opacity(0.88)
    }

    private var regularSectionStyle: Color {
        colorScheme == .dark ? .white.opacity(0.56) : .secondary.opacity(0.78)
    }

    private var regularLabelStyle: Color {
        colorScheme == .dark ? .white.opacity(0.64) : .secondary.opacity(0.92)
    }

    private var regularValueStyle: Color {
        colorScheme == .dark ? .white.opacity(0.90) : .primary.opacity(0.90)
    }

    var body: some View {
        ScrollView(.vertical) {
            switch style {
            case .compact(let maxVisibleRows):
                compactContent(maxVisibleRows: maxVisibleRows)
            case .regular:
                regularContent
            }
        }
        .scrollIndicators(.hidden)
    }

    private var allRows: [CreditsRow] {
        payload.sections.flatMap(\.rows)
    }

    private func compactContent(maxVisibleRows: Int) -> some View {
        let visibleRows = Array(allRows.prefix(maxVisibleRows))

        return LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(visibleRows) { row in
                HStack(alignment: .top, spacing: 10) {
                    Text(row.label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(compactLabelStyle)
                        .frame(width: 76, alignment: .leading)

                    Text(row.value)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(compactValueStyle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            if allRows.count > maxVisibleRows {
                Text("More credits available in regular view.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.46) : .secondary.opacity(0.72))
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private var regularContent: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(payload.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(regularSectionStyle)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(section.rows) { row in
                            HStack(alignment: .top, spacing: 12) {
                                Text(row.label)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(regularLabelStyle)
                                    .frame(width: 92, alignment: .leading)

                                Text(row.value)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(regularValueStyle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

func openLRCLibWebsite() {
    guard let url = URL(string: "https://lrclib.net") else { return }
    NSWorkspace.shared.open(url)
}
