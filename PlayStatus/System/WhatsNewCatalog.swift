import Foundation
import SwiftUI

/// A marketing version, ordered the way a human orders releases.
///
/// Only the numeric components decide precedence. A pre-release suffix (`3.1.1-beta2`)
/// sorts below the same numbers without one, so a beta tester who has seen `3.1.1-beta2`
/// is still shown nothing extra when `3.1.1` proper arrives.
struct ReleaseVersion: Comparable, Hashable, CustomStringConvertible {
    let components: [Int]
    let prerelease: String?

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let split = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        guard let numeric = split.first else { return nil }

        let parsed = numeric.split(separator: ".").map { Int($0) ?? 0 }
        guard !parsed.isEmpty, numeric.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }

        components = parsed
        prerelease = split.count > 1 ? String(split[1]) : nil
    }

    var description: String {
        let numeric = components.map(String.init).joined(separator: ".")
        guard let prerelease else { return numeric }
        return "\(numeric)-\(prerelease)"
    }

    /// The version without its pre-release suffix, which is the release whose notes a
    /// beta build should be considered to be showing.
    var releaseLine: ReleaseVersion {
        ReleaseVersion(components: components, prerelease: nil)
    }

    private init(components: [Int], prerelease: String?) {
        self.components = components
        self.prerelease = prerelease
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, _?):
            // A shipped release outranks any pre-release of the same numbers.
            return false
        case (_?, nil):
            return true
        case let (left?, right?):
            return left < right
        }
    }
}

enum WhatsNewAccent {
    case blue
    case amber
    case pink
    case green
    case violet

    var color: Color {
        switch self {
        case .blue:
            return Color(red: 0.43, green: 0.72, blue: 0.98)
        case .amber:
            return Color(red: 0.98, green: 0.72, blue: 0.34)
        case .pink:
            return Color(red: 0.87, green: 0.55, blue: 0.77)
        case .green:
            return Color(red: 0.52, green: 0.84, blue: 0.62)
        case .violet:
            return Color(red: 0.66, green: 0.58, blue: 0.95)
        }
    }
}

struct WhatsNewHighlight: Identifiable {
    let symbolName: String
    let title: String
    let message: String
    let accent: WhatsNewAccent

    var id: String { title }
}

struct WhatsNewRelease: Identifiable {
    let version: ReleaseVersion
    let headline: String
    let summary: String
    let highlights: [WhatsNewHighlight]

    var id: String { version.description }
    var displayVersion: String { version.description }
}

/// What each release actually changed, in the order it shipped.
///
/// This is the upgrade walkthrough's only source of content. Adding a release here is the
/// whole job of teaching the walkthrough about a new version — the coordinator works out
/// who has seen what on its own.
enum WhatsNewCatalog {
    /// Ascending by version. Keep it that way; the lookup below relies on the order.
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: ReleaseVersion("3.0.0")!,
            headline: "The SwiftUI relaunch",
            summary: "PlayStatus was rebuilt from the ground up around a single layered player.",
            highlights: [
                WhatsNewHighlight(
                    symbolName: "rectangle.on.rectangle",
                    title: "One player, three sizes",
                    message: "Mini, regular, and detached modes share the same design language instead of competing with each other.",
                    accent: .blue
                ),
                WhatsNewHighlight(
                    symbolName: "text.magnifyingglass",
                    title: "Lyrics, credits, and search moved into the player",
                    message: "They are part of the surface you already have open rather than separate utility flows.",
                    accent: .pink
                ),
                WhatsNewHighlight(
                    symbolName: "gearshape.2.fill",
                    title: "Settings reorganized",
                    message: "Display, playback, hotkeys, and system controls are grouped where you would look for them.",
                    accent: .green
                )
            ]
        ),
        WhatsNewRelease(
            version: ReleaseVersion("3.0.2")!,
            headline: "Shuffle, repeat, and a lyrics pane you can size",
            summary: "Playback controls caught up with the players, and the details pane learned to fit your screen.",
            highlights: [
                WhatsNewHighlight(
                    symbolName: "shuffle",
                    title: "Shuffle and repeat controls",
                    message: "In both players, with live state read back from Apple Music and Spotify.",
                    accent: .blue
                ),
                WhatsNewHighlight(
                    symbolName: "textformat.size",
                    title: "Lyrics sizing and app appearance",
                    message: "Compact, Standard, and Tall panes, custom lyric font sizes, and a Follow System / Always Light / Always Dark setting.",
                    accent: .pink
                ),
                WhatsNewHighlight(
                    symbolName: "photo.artframe",
                    title: "Steadier artwork",
                    message: "Animated artwork can be cropped or shown whole, and covers from the previous song no longer linger after a track change.",
                    accent: .amber
                )
            ]
        ),
        WhatsNewRelease(
            version: ReleaseVersion("3.0.4")!,
            headline: "Homebrew, and a player you can resize",
            summary: "An official install path, plus size controls for the menu bar player.",
            highlights: [
                WhatsNewHighlight(
                    symbolName: "terminal",
                    title: "Install with Homebrew",
                    message: "brew install --cask nbolar/playstatus/playstatus",
                    accent: .green
                ),
                WhatsNewHighlight(
                    symbolName: "arrow.up.left.and.arrow.down.right",
                    title: "Small, Medium, or Large",
                    message: "Set the player size in Settings. Popover and detached sizing are tuned independently.",
                    accent: .blue
                )
            ]
        ),
        WhatsNewRelease(
            version: ReleaseVersion("3.0.5")!,
            headline: "Long menu bar titles stay visible",
            summary: "A fix for titles wider than the space you gave them.",
            highlights: [
                WhatsNewHighlight(
                    symbolName: "text.alignleft",
                    title: "Truncation instead of disappearance",
                    message: "With Scrollable title off, a title past your Title Width now ends in an ellipsis rather than vanishing.",
                    accent: .amber
                )
            ]
        ),
        WhatsNewRelease(
            version: ReleaseVersion("3.1.0")!,
            headline: "History, scrobbling, Shortcuts, and a rebuilt player",
            summary: "The largest release since the relaunch. If you skipped a few versions, this is the one worth reading.",
            highlights: [
                WhatsNewHighlight(
                    symbolName: "clock.arrow.circlepath",
                    title: "Play history",
                    message: "A third tab beside Lyrics and Credits. Click a row to play it again; skips are recorded too. Stored on this Mac only, never uploaded.",
                    accent: .violet
                ),
                WhatsNewHighlight(
                    symbolName: "waveform.badge.plus",
                    title: "Last.fm scrobbling",
                    message: "Sign in on Last.fm's own site — your password never touches PlayStatus. Offline plays queue up and go out later.",
                    accent: .pink
                ),
                WhatsNewHighlight(
                    symbolName: "app.connected.to.app.below.fill",
                    title: "Shortcuts, Spotlight, and a URL scheme",
                    message: "Drive PlayStatus from Shortcuts, Raycast, Alfred, Stream Deck, or a shell script. Nothing needs enabling first.",
                    accent: .green
                ),
                WhatsNewHighlight(
                    symbolName: "playpause.fill",
                    title: "Transport buttons in the menu bar",
                    message: "Optional previous / play-pause / next beside the track title, drawn to match the bar. Turn them on in Settings.",
                    accent: .blue
                ),
                WhatsNewHighlight(
                    symbolName: "keyboard",
                    title: "The player answers the keyboard",
                    message: "Space, arrows for seek and volume, L / C / H for the panes, M to switch layouts, and ⌘F for search.",
                    accent: .amber
                ),
                WhatsNewHighlight(
                    symbolName: "sidebar.left",
                    title: "Settings, rebuilt",
                    message: "Nine focused panes in three groups, a searchable sidebar that still matches the old names, and one frame that stops resizing as you switch.",
                    accent: .violet
                )
            ]
        ),
        WhatsNewRelease(
            version: ReleaseVersion("3.1.1")!,
            headline: "Updated the mini player's idle state",
            summary: "A follow-up to 3.1.0 for the moments when nothing is playing.",
            highlights: [
                WhatsNewHighlight(
                    symbolName: "play.circle",
                    title: "Idle offers a way to start playing",
                    message: "The mini card now shows the same one-tap start or open-the-app button the full player does.",
                    accent: .green
                ),
                WhatsNewHighlight(
                    symbolName: "square.dashed",
                    title: "No more ghost artwork at rest",
                    message: "Idle shows a plain plate instead of a blurred wash of whatever stopped playing.",
                    accent: .blue
                ),
                WhatsNewHighlight(
                    symbolName: "arrow.triangle.branch",
                    title: "Automatic picks the player that is actually running",
                    message: "A Spotify-only Mac is no longer offered Apple Music by the idle button.",
                    accent: .amber
                )
            ]
        ),
        WhatsNewRelease(
            version: ReleaseVersion("3.1.2")!,
            headline: "Paused songs in the menu bar, and a steadier player",
            summary: "Your paused song can keep its place in the menu bar, PlayStatus uses a fraction of the CPU it used to, and the menu bar controls work again on macOS 27.",
            highlights: [
                WhatsNewHighlight(
                    symbolName: "pause.circle",
                    title: "Paused songs can stay in the menu bar",
                    message: "Turn on Show title when paused in Settings › Menu Bar. The title stays dimmed and still, so you can see what Play will resume.",
                    accent: .violet
                ),
                WhatsNewHighlight(
                    symbolName: "leaf",
                    title: "Far less CPU at rest",
                    message: "PlayStatus kept drawing the player after you closed it, and the menu bar title the slow way. With a song playing and the player closed, it now uses about 0.5% of a CPU core, down from 9%.",
                    accent: .green
                ),
                WhatsNewHighlight(
                    symbolName: "hourglass",
                    title: "Never stuck waiting on your player",
                    message: "Play, pause and skip were sent from the thread that draws the menu bar, with no time limit, so a busy Music could freeze PlayStatus. They now go out on their own.",
                    accent: .violet
                ),
                WhatsNewHighlight(
                    symbolName: "textformat",
                    title: "Dim the artist",
                    message: "With Artist + Song titles, the artist can be drawn quieter than the song. Also in Settings › Menu Bar.",
                    accent: .blue
                ),
                WhatsNewHighlight(
                    symbolName: "shuffle",
                    title: "No more Play button that does nothing",
                    message: "When Music is showing a catalog page, Play can't start anything. The player now says so and offers to shuffle your library instead.",
                    accent: .pink
                ),
                WhatsNewHighlight(
                    symbolName: "playpause.fill",
                    title: "Menu bar controls that know what works",
                    message: "They work again on macOS 27, hide when no player is open, and grey out a button that would do nothing.",
                    accent: .blue
                ),
                WhatsNewHighlight(
                    symbolName: "checkmark.shield",
                    title: "Two crashes fixed",
                    message: "One could hit on macOS 26 while the player resized; the other when hovering the menu bar controls.",
                    accent: .amber
                )
            ]
        )
    ]

    static var latest: WhatsNewRelease? { releases.last }

    /// Releases a user on `lastSeen` has not been told about yet, newest first.
    ///
    /// `currentVersion` bounds the answer so a build cannot advertise a release it does not
    /// contain — which is what happens to anyone running an older build than the catalog.
    static func unseenReleases(
        lastSeen: ReleaseVersion?,
        currentVersion: ReleaseVersion?
    ) -> [WhatsNewRelease] {
        let ceiling = currentVersion?.releaseLine
        let unseen = releases
            .filter { release in
                if let ceiling, release.version > ceiling { return false }
                guard let lastSeen else { return true }
                return release.version > lastSeen.releaseLine
            }
        return Array(unseen.reversed())
    }
}
