import SwiftUI
import AppKit

/// What the player says when nothing is playing.
struct PlayerIdlePresentation {
    struct Action {
        enum Kind {
            /// Send play to a provider that is running but idle.
            case play
            /// Launch a provider that is installed but not running.
            case openApp
        }

        let title: String
        let systemImage: String
        let kind: Kind
    }

    let headline: String
    let detail: String
    let action: Action?
}

/// The regular player's idle surface.
///
/// Idle used to be the live layout with everything at 40% opacity — five transport controls,
/// a progress rail and a volume slider, none of which did anything. Five dimmed controls that
/// do nothing are worse than none, so this shows what is actually true and offers the one
/// action that is worth taking.
///
/// The artwork plate keeps its full size so arriving at a real track fills the frame instead
/// of reflowing it, and so the shared mode-morph anchor stays exactly where it was.
struct PlayerIdleView: View {
    @ObservedObject var model: NowPlayingModel
    let artworkSize: CGFloat
    let laneWidth: CGFloat

    private var presentation: PlayerIdlePresentation {
        model.idlePresentation
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            idlePlate

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.headline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))

                Text(presentation.detail)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
                    .fixedSize(horizontal: false, vertical: true)

                if let action = presentation.action {
                    Button {
                        perform(action)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 11, weight: .bold))
                            Text(action.title)
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(Color(red: 0.09, green: 0.10, blue: 0.11))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.94))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 15)
                }

                if model.resolvedSearchProvider != .none {
                    Text("or ⌘⇧/ to search your library")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.34))
                        .padding(.top, 12)
                }
            }
            .frame(width: laneWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(presentation.headline). \(presentation.detail)"))
    }

    /// Holds the artwork's frame so the transition into a real track is a fill, not a reflow.
    private var idlePlate: some View {
        RoundedRectangle(cornerRadius: regularArtworkCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.055), .white.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: max(34, artworkSize * 0.19), weight: .light))
                    .foregroundStyle(.white.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: regularArtworkCornerRadius, style: .continuous)
                    .stroke(.white.opacity(playerHairlineOpacity * 0.7), lineWidth: playerHairlineWidth)
            )
            .frame(width: artworkSize, height: artworkSize)
            .accessibilityHidden(true)
    }

    private func perform(_ action: PlayerIdlePresentation.Action) {
        switch action.kind {
        case .play:
            model.playPause()
        case .openApp:
            model.openProviderApp()
        }
    }
}
