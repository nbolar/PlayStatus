import AppKit
import Observation
import SwiftUI

struct FeaturePill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }
}

struct MenuBarChip: View {
    let text: String
    let provider: NowPlayingProvider

    var body: some View {
        HStack(spacing: 8) {
            ProviderIconView(icon: provider.iconKind, size: 12, weight: .semibold)
                .frame(width: 14, height: 14)

            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.76))
                .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
        )
    }
}

struct FeaturePreviewStage: View, Equatable {
    let feature: WalkthroughFeature
    let preview: WalkthroughPreviewState

    var body: some View {
        switch feature {
        case .modes:
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 16) {
                    MiniPreviewCard(
                        artworkKey: preview.artworkKey,
                        provider: preview.provider,
                        title: preview.title
                    )
                    .frame(width: 190, height: 228)

                    RegularPreviewCard(preview: preview)
                        .frame(minWidth: 360, maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 16) {
                    MiniPreviewCard(
                        artworkKey: preview.artworkKey,
                        provider: preview.provider,
                        title: preview.title
                    )
                    .frame(width: 190, height: 228)

                    RegularPreviewCard(preview: preview)
                }
            }
        case .search:
            SearchPreviewCard(preview: preview)
        case .lyrics:
            LyricsPreviewCard(preview: preview)
        case .detached:
            DetachedPreviewCard(preview: preview)
        }
    }
}

struct PersonalizationPreviewStage: View {
    @Bindable var draft: WalkthroughDraftState

    private var titleLine: String {
        switch draft.menuBarTextMode {
        case .artist:
            return "Glass Almanac"
        case .song:
            return "Paper Satellites"
        case .artistAndSong:
            return "Glass Almanac — Paper Satellites"
        case .iconOnly:
            return "PlayStatus"
        }
    }

    private var themeDescription: String {
        switch draft.themeStyle {
        case .artworkAdaptive:
            return "Artwork tinting will drive the palette."
        case .frosted:
            return "Frosted surfaces keep the player airy and bright."
        case .midnight:
            return "Midnight leans darker and more cinematic."
        case .warmStudio:
            return "Warm Studio adds a softer amber studio glow."
        case .highContrast:
            return "High Contrast sharpens edges and text clarity."
        case .graphite:
            return "Graphite keeps everything neutral and understated."
        }
    }

    private var themeAccent: LinearGradient {
        switch draft.themeStyle {
        case .artworkAdaptive:
            return LinearGradient(colors: [Color(red: 0.33, green: 0.59, blue: 0.96), Color(red: 0.66, green: 0.44, blue: 0.91)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .frosted:
            return LinearGradient(colors: [Color(red: 0.76, green: 0.88, blue: 0.98), Color(red: 0.63, green: 0.79, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .midnight:
            return LinearGradient(colors: [Color(red: 0.12, green: 0.14, blue: 0.24), Color(red: 0.24, green: 0.31, blue: 0.47)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .warmStudio:
            return LinearGradient(colors: [Color(red: 0.72, green: 0.43, blue: 0.28), Color(red: 0.94, green: 0.72, blue: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .highContrast:
            return LinearGradient(colors: [Color.black, Color(red: 0.24, green: 0.24, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .graphite:
            return LinearGradient(colors: [Color(red: 0.38, green: 0.41, blue: 0.45), Color(red: 0.57, green: 0.60, blue: 0.66)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 10) {
                MenuBarChip(text: titleLine, provider: draft.previewProvider)
                Spacer()
                FeaturePill(label: draft.menuBarTextMode.displayName, color: summaryAccent)
            }

            PersonalizationThemeHero(
                artworkKey: WalkthroughPreviewArtworkKey(provider: draft.previewProvider, variant: 2),
                provider: draft.previewProvider,
                themeStyle: draft.themeStyle,
                themeDescription: themeDescription,
                accent: themeAccent
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    PersonalizationSummaryTile(
                        title: "Display Mode",
                        value: draft.menuBarTextMode.displayName,
                        message: "Shapes the menu bar label you see most often.",
                        accent: summaryAccent
                    )
                    PersonalizationSummaryTile(
                        title: "Artwork Motion",
                        value: draft.animatedArtworkEnabled ? "On" : "Off",
                        message: draft.animatedArtworkEnabled ? "Animated artwork stays expressive." : "Motion stays calmer by default.",
                        accent: Color(red: 0.87, green: 0.55, blue: 0.77)
                    )
                    PersonalizationSummaryTile(
                        title: "Launch Behavior",
                        value: draft.launchAtLoginEnabled ? "Start at login" : "Manual launch",
                        message: draft.launchAtLoginEnabled ? "PlayStatus is ready when you sign in." : "Startup stays lighter until you open it.",
                        accent: Color(red: 0.53, green: 0.83, blue: 0.63)
                    )
                }

                VStack(spacing: 12) {
                    PersonalizationSummaryTile(
                        title: "Display Mode",
                        value: draft.menuBarTextMode.displayName,
                        message: "Shapes the menu bar label you see most often.",
                        accent: summaryAccent
                    )
                    PersonalizationSummaryTile(
                        title: "Artwork Motion",
                        value: draft.animatedArtworkEnabled ? "On" : "Off",
                        message: draft.animatedArtworkEnabled ? "Animated artwork stays expressive." : "Motion stays calmer by default.",
                        accent: Color(red: 0.87, green: 0.55, blue: 0.77)
                    )
                    PersonalizationSummaryTile(
                        title: "Launch Behavior",
                        value: draft.launchAtLoginEnabled ? "Start at login" : "Manual launch",
                        message: draft.launchAtLoginEnabled ? "PlayStatus is ready when you sign in." : "Startup stays lighter until you open it.",
                        accent: Color(red: 0.53, green: 0.83, blue: 0.63)
                    )
                }
            }
        }
    }

    private var summaryAccent: Color {
        switch draft.themeStyle {
        case .artworkAdaptive:
            return Color(red: 0.33, green: 0.59, blue: 0.96)
        case .frosted:
            return Color(red: 0.63, green: 0.79, blue: 0.93)
        case .midnight:
            return Color(red: 0.24, green: 0.31, blue: 0.47)
        case .warmStudio:
            return Color(red: 0.94, green: 0.72, blue: 0.42)
        case .highContrast:
            return Color.black.opacity(0.88)
        case .graphite:
            return Color(red: 0.57, green: 0.60, blue: 0.66)
        }
    }
}

private struct PersonalizationThemeHero: View {
    let artworkKey: WalkthroughPreviewArtworkKey
    let provider: NowPlayingProvider
    let themeStyle: ThemeStyle
    let themeDescription: String
    let accent: LinearGradient

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(accent)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
            .frame(height: 176)
            .overlay(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 16) {
                    artworkCard
                    themeSummary
                    Spacer(minLength: 0)
                }
                .padding(18)
            }
            .overlay(alignment: .bottomTrailing) {
                trailingThemeCard
                    .padding(16)
            }
    }

    private var artworkCard: some View {
        WalkthroughArtworkSnapshot(artworkKey: artworkKey, cornerRadius: 20)
            .frame(width: 108, height: 108)
            .shadow(color: .black.opacity(0.20), radius: 10, x: 0, y: 6)
    }

    private var themeSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProviderIconView(icon: provider.iconKind, size: 13, weight: .bold)
                    .frame(width: 16, height: 16)
                Text("Theme Preview")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .textCase(.uppercase)
            }

            Text(themeStyle.displayName)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.98))

            Text(themeDescription)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                PreviewSmallControl(systemImage: "music.note")
                PreviewSmallControl(systemImage: "waveform")
                PreviewSmallControl(systemImage: "sparkles")
            }
        }
    }

    private var trailingThemeCard: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.18))
            .frame(width: 148, height: 64)
            .overlay(
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.82))
                        .frame(width: 88, height: 8)
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.46))
                        .frame(width: 120, height: 6)
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 72, height: 6)
                }
                .padding(14)
            )
    }
}

private struct PersonalizationSummaryTile: View {
    let title: String
    let value: String
    let message: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent.opacity(0.88))
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))

            Text(message)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.74))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accent.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct WalkthroughArtworkSnapshot: View, Equatable {
    let artworkKey: WalkthroughPreviewArtworkKey
    var cornerRadius: CGFloat = 22

    var body: some View {
        Image(nsImage: WalkthroughPreviewAssets.shared.image(for: artworkKey))
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

private struct MiniPreviewCard: View, Equatable {
    let artworkKey: WalkthroughPreviewArtworkKey
    let provider: NowPlayingProvider
    let title: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WalkthroughArtworkSnapshot(artworkKey: artworkKey, cornerRadius: 24)

            LinearGradient(
                colors: [.clear, .black.opacity(0.70)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(.rect(cornerRadius: 24))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProviderIconView(icon: provider.iconKind, size: 14, weight: .semibold)
                        .frame(width: 15, height: 15)
                    Text("Mini Mode")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.95))

                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.98))

                Text("Hover to expand controls")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(16)
        }
        .clipShape(.rect(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
    }
}

private struct RegularPreviewCard: View, Equatable {
    let preview: WalkthroughPreviewState

    var body: some View {
        VStack(spacing: 0) {
            WalkthroughArtworkMetadataLayout(
                artworkKey: preview.artworkKey,
                artworkSize: 142,
                cornerRadius: 20,
                horizontalSpacing: 18
            ) {
                previewMetadata
            }
            .padding(20)

            Divider()

            previewToolbar
        }
        .background(RegularPreviewCardChrome())
        .clipShape(.rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 6)
    }

    private var previewToolbar: some View {
        HStack {
            SearchCapsulePreview(text: preview.provider == .spotify ? "Search Spotify" : "Search Music")
            Spacer()
            PreviewSmallControl(systemImage: "quote.bubble")
            PreviewSmallControl(systemImage: "info.circle")
            PreviewSmallControl(systemImage: "gearshape.fill")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var previewMetadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProviderIconView(icon: preview.provider.iconKind, size: 14, weight: .semibold)
                    .frame(width: 16, height: 16)
                Text(preview.provider.displayName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text(preview.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text(preview.artist + " • " + preview.album)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.accentColor.opacity(0.82))
                        .frame(width: 120, height: 6)
                }

            HStack(spacing: 16) {
                PreviewTransportButton(systemImage: "backward.fill")
                PreviewTransportButton(systemImage: preview.isPlaying ? "pause.fill" : "play.fill", prominence: .prominent)
                PreviewTransportButton(systemImage: "forward.fill")
            }
        }
    }
}

private struct RegularPreviewCardChrome: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct SearchPreviewCard: View, Equatable {
    let preview: WalkthroughPreviewState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                SearchCapsulePreview(text: preview.provider == .spotify ? "Search Spotify" : "Search Music")
                Button("Open") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            }

            HStack(alignment: .top, spacing: 16) {
                WalkthroughArtworkSnapshot(artworkKey: preview.artworkKey, cornerRadius: 20)
                    .frame(width: 136, height: 136)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProviderIconView(icon: preview.provider.iconKind, size: 14, weight: .semibold)
                            .frame(width: 16, height: 16)
                        Text(preview.provider.displayName + " search handoff")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Text(preview.searchText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text(preview.provider == .spotify ? "Spotify opens the matching search immediately." : "Music can play from your local library when the query matches.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.80))
            )
        }
    }
}

private struct LyricsPreviewCard: View, Equatable {
    let preview: WalkthroughPreviewState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                WalkthroughArtworkSnapshot(artworkKey: preview.artworkKey, cornerRadius: 20)
                    .frame(width: 126, height: 126)

                VStack(alignment: .leading, spacing: 8) {
                    Text(preview.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(preview.artist + " • " + preview.album)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        FeaturePill(label: "Lyrics", color: WalkthroughFeature.lyrics.accentColor)
                        FeaturePill(label: "Credits", color: WalkthroughFeature.search.accentColor)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(preview.lyricsLines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: index == 1 ? 14 : 12, weight: index == 1 ? .bold : .medium, design: .rounded))
                        .foregroundStyle(index == 1 ? Color.primary : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(index == 1 ? WalkthroughFeature.lyrics.accentColor.opacity(0.16) : Color.white.opacity(0.70))
                        )
                }
            }
        }
    }
}

private struct DetachedPreviewCard: View, Equatable {
    let preview: WalkthroughPreviewState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.06))

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    WalkthroughTrafficLights()
                    Spacer()
                    Text("Detached Player")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    PreviewSmallControl(systemImage: "pin.fill")
                    PreviewSmallControl(systemImage: "xmark")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.74))

                WalkthroughArtworkMetadataLayout(
                    artworkKey: preview.artworkKey,
                    artworkSize: 140,
                    cornerRadius: 20,
                    horizontalSpacing: 16
                ) {
                    detachedMetadata
                }
                .padding(22)
                .background(Color.white.opacity(0.80))
            }
            .clipShape(.rect(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .frame(minWidth: 320, idealWidth: 420, maxWidth: 420)
            .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 6)
        }
    }

    private var detachedMetadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(preview.artist + " • " + preview.album)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.black.opacity(0.10))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(WalkthroughFeature.detached.accentColor.opacity(0.86))
                        .frame(width: 150, height: 6)
                }
            HStack(spacing: 16) {
                PreviewTransportButton(systemImage: "backward.fill")
                PreviewTransportButton(systemImage: preview.isPlaying ? "pause.fill" : "play.fill", prominence: .prominent)
                PreviewTransportButton(systemImage: "forward.fill")
            }
        }
    }
}

private struct WalkthroughArtworkMetadataLayout<Metadata: View>: View {
    let artworkKey: WalkthroughPreviewArtworkKey
    let artworkSize: CGFloat
    let cornerRadius: CGFloat
    let horizontalSpacing: CGFloat
    @ViewBuilder let metadata: () -> Metadata

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: horizontalSpacing) {
                artwork
                metadata()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 16) {
                artwork
                metadata()
            }
        }
    }

    private var artwork: some View {
        WalkthroughArtworkSnapshot(artworkKey: artworkKey, cornerRadius: cornerRadius)
            .frame(width: artworkSize, height: artworkSize)
    }
}

private struct WalkthroughTrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red.opacity(0.82)).frame(width: 10, height: 10)
            Circle().fill(Color.orange.opacity(0.86)).frame(width: 10, height: 10)
            Circle().fill(Color.green.opacity(0.82)).frame(width: 10, height: 10)
        }
    }
}

private enum PreviewTransportProminence {
    case normal
    case prominent
}

private struct PreviewTransportButton: View {
    let systemImage: String
    var prominence: PreviewTransportProminence = .normal

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: prominence == .prominent ? 16 : 13, weight: .bold))
            .foregroundStyle(prominence == .prominent ? Color.white.opacity(0.96) : Color.primary.opacity(0.86))
            .frame(width: prominence == .prominent ? 42 : 34, height: prominence == .prominent ? 42 : 34)
            .background(
                Circle()
                    .fill(prominence == .prominent ? Color.accentColor.opacity(0.92) : Color.black.opacity(0.08))
            )
    }
}

private struct PreviewSmallControl: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.06))
            )
    }
}

private struct SearchCapsulePreview: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.07))
        )
    }
}
