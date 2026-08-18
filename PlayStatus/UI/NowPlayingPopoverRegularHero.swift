import SwiftUI
import Combine

// The regular player's hero row, as four `View` structs rather than four methods on
// `NowPlayingPopover`.
//
// This is a stack-depth fix, not a style preference. A method returning `some View` is called
// from inside its parent's body, so the whole subtree — every nested `VStack<TupleView<…>>` —
// is constructed inline in one enormous body evaluation. A `View` struct instead has its body
// called by the view graph at its own, shallower depth.
//
// PlayStatus crashed on 2026-08-10 with `KERN_PROTECTION_FAILURE` on the main thread's stack
// guard page: 115 frames, no recursion, dying in the Swift runtime's demangler while resolving
// the opaque return type of `trackTextLines`. Roughly 27 of those frames were this one chain,
// built inline. At `-Onone` each of those unoptimized generic frames is large enough that the
// chain plus a demangler recursion overran an 8 MB stack. Splitting it here means those frames
// no longer coexist.

/// Artwork, then the text-and-controls column, both the artwork's height.
///
/// Both columns share the artwork's top and bottom edges: the title starts level with the top
/// of the cover and the volume row sits on its baseline. They used to be two separately centred
/// blocks, so the title floated 14pt below the artwork's top and the artwork overhung the last
/// control row by 23pt — nothing in the window lined up with anything else.
struct RegularHeroRow: View {
    @ObservedObject var model: NowPlayingModel
    let marqueeLaneWidth: CGFloat
    let controlContrastBoost: Double
    let controlScale: CGFloat
    let artworkSize: CGFloat
    let artworkHandedOff: Bool
    let animateArtworkOnFirstAppear: Bool
    let primaryContentVisible: Bool
    let secondaryContentVisible: Bool
    let transportRevealed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RegularArtworkTile(
                model: model,
                artworkSize: artworkSize,
                handedOff: artworkHandedOff,
                animateOnFirstAppear: animateArtworkOnFirstAppear
            )

            VStack(alignment: .leading, spacing: 6) {
                RegularMetadataColumn(
                    model: model,
                    laneWidth: marqueeLaneWidth,
                    controlContrastBoost: controlContrastBoost,
                    primaryContentVisible: primaryContentVisible
                )
                .padding(.top, playerClusterReservedHeight)

                Spacer(minLength: 0)

                RegularControlsColumn(
                    model: model,
                    controlContrastBoost: controlContrastBoost,
                    controlScale: controlScale,
                    transportRevealed: transportRevealed,
                    secondaryContentVisible: secondaryContentVisible
                )
            }
            .frame(maxWidth: .infinity, minHeight: artworkSize, maxHeight: artworkSize, alignment: .leading)
        }
    }
}

struct RegularArtworkTile: View {
    @ObservedObject var model: NowPlayingModel
    let artworkSize: CGFloat
    let handedOff: Bool
    let animateOnFirstAppear: Bool

    /// Identifies this artwork to the motion system. Both the view and its motion modifier must
    /// agree on it, so it is derived once here rather than spelled out twice.
    private var motionSeed: String {
        "regular|\(model.provider.rawValue)|\(model.artist)|\(model.albumArtist)|\(model.album)|\(model.title)"
    }

    var body: some View {
        if handedOff {
            // Handed off to the shared morph node. Left out of the tree entirely rather
            // than hidden: `.opacity(0)` still rasterises, and this subtree carries two
            // blurs that the morph cannot afford to keep paying for. The placeholder
            // holds the same frame, so the anchor stays measurable and the surrounding
            // layout does not reflow.
            Color.clear
                .frame(width: artworkSize, height: artworkSize)
                .modeArtworkAnchor(.regular, in: modeRegularBranchSpace)
        } else {
            AnimatedArtworkView(
                image: model.artwork,
                tint: model.glassTint,
                isEnabled: false,
                seed: motionSeed,
                style: model.artworkMotionStyle,
                animatedArtworkURL: model.effectiveAnimatedArtworkURL,
                animatedArtworkIsVisible: model.isPopoverVisible,
                cropAnimatedArtworkToSquare: model.cropAnimatedArtworkToSquare,
                animateOnFirstAppear: animateOnFirstAppear
            )
            .frame(width: artworkSize, height: artworkSize)
            .animatedArtworkMotion(
                isEnabled: model.animatedArtworkEnabled,
                seed: motionSeed,
                style: model.artworkMotionStyle,
                isPlaying: model.isPlaying,
                hasAnimatedStream: model.effectiveAnimatedArtworkURL != nil,
                tint: model.glassTint,
                artworkImage: model.artwork
            )
            .modeArtworkAnchor(.regular, in: modeRegularBranchSpace)
        }
    }
}

struct RegularMetadataColumn: View {
    @ObservedObject var model: NowPlayingModel
    let laneWidth: CGFloat
    let controlContrastBoost: Double
    let primaryContentVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // The text block is re-identified per track so a new song crosses rather than
            // swapping in place — the outgoing lines rise and fade as the incoming ones
            // arrive from below, on the same signal the artwork crossfade already uses.
            TrackTextLines(model: model, laneWidth: laneWidth)
                .trackChangeTransition(
                    identity: model.trackIdentity,
                    isEnabled: model.slideTitleOnChange && !reduceMotion
                )

            PlaybackProgressBlock(
                contrastBoost: controlContrastBoost,
                onSeek: { model.seek(to: $0) }
            )
            .padding(.top, 8)
        }
        .opacity(primaryContentVisible ? 1 : 0)
        .offset(y: primaryContentVisible ? 0 : 8)
        .animation(modePrimaryRevealAnimation, value: primaryContentVisible)
    }
}

/// Title, artist, album — three lines, three steps down.
///
/// These were once 15pt title and 15pt "artist • album" separated by weight alone,
/// both carrying drop shadows so they could survive a fully saturated surface. The
/// surface is quiet now, so the type carries the hierarchy on its own.
struct TrackTextLines: View {
    @ObservedObject var model: NowPlayingModel
    let laneWidth: CGFloat

    private var accessibleTrackDescription: String {
        var parts = [model.displayTitle.isEmpty ? "Nothing playing" : model.displayTitle]
        if !model.artist.isEmpty { parts.append(model.artist) }
        if !model.album.isEmpty { parts.append(model.album) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: { model.openProviderApp() }) {
                NowPlayingTitleMarquee(
                    text: model.displayTitle,
                    enabled: true,
                    isVisible: model.isPopoverVisible,
                    laneWidth: laneWidth
                )
                .foregroundStyle(.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NowPlayingSecondaryMarquee(
                text: model.metadataArtistLine,
                enabled: true,
                isVisible: model.isPopoverVisible,
                laneWidth: laneWidth,
                textOpacity: 0.68
            )

            if !model.album.isEmpty {
                NowPlayingSecondaryMarquee(
                    text: model.album,
                    enabled: true,
                    isVisible: model.isPopoverVisible,
                    laneWidth: laneWidth,
                    fontWeight: .regular,
                    textOpacity: 0.44
                )
            }
        }
        // One element rather than three marquees read in sequence, and activating it does
        // what clicking the title does.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibleTrackDescription))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Opens \(model.idleTargetProvider.displayName)"))
        .accessibilityAction { model.openProviderApp() }
    }
}

struct RegularControlsColumn: View {
    @ObservedObject var model: NowPlayingModel
    let controlContrastBoost: Double
    let controlScale: CGFloat
    /// Same pointer signal the top-row cluster uses, so the whole window brightens on one
    /// hover instead of the transport and the cluster waking up independently. Resolved by the
    /// caller, which already folds in the coachmark override — a walkthrough pointing at these
    /// controls cannot leave them dimmed.
    let transportRevealed: Bool
    let secondaryContentVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                ControlsRow(
                    isPlaying: model.isPlaying,
                    isShuffleEnabled: model.isShuffleEnabled,
                    repeatMode: model.repeatMode,
                    controlsEnabled: model.canControlPlayback,
                    onShuffle: { model.toggleShuffle() },
                    onPrev: { model.previousTrack() },
                    onPlayPause: { model.playPause() },
                    onNext: { model.nextTrack() },
                    onRepeat: { model.cycleRepeatMode() },
                    contrastBoost: controlContrastBoost,
                    controlScale: controlScale,
                    secondariesRevealed: transportRevealed
                )
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            OutputControlsRow(
                model: model,
                contrastBoost: controlContrastBoost,
                controlScale: controlScale,
                showFavorite: model.canFavoriteCurrentTrack,
                favoriteIsActive: model.isCurrentTrackFavorited,
                favoritePulseToken: model.favoriteActionPulseToken,
                onFavorite: { _ = model.toggleCurrentTrackFavorite() }
            )
            .padding(.top, 4)
        }
        .opacity(secondaryContentVisible ? 1 : 0)
        .offset(y: secondaryContentVisible ? 0 : 10)
        .animation(modeSecondaryRevealAnimation, value: secondaryContentVisible)
    }
}
