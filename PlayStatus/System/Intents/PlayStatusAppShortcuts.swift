import AppIntents

/// Spoken phrases for the intents, so they surface in Spotlight without the user having to
/// build a Shortcut first.
///
/// Every phrase must contain `\(.applicationName)` — App Intents requires it, and it is also
/// what keeps generic verbs like "next track" from colliding with every other media app.
struct PlayStatusAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayPauseIntent(),
            phrases: [
                "Play or pause in \(.applicationName)",
                "Toggle playback in \(.applicationName)"
            ],
            shortTitle: "Play or Pause",
            systemImageName: "playpause.fill"
        )

        AppShortcut(
            intent: NextTrackIntent(),
            phrases: [
                "Next track in \(.applicationName)",
                "Skip this song in \(.applicationName)"
            ],
            shortTitle: "Next Track",
            systemImageName: "forward.end.fill"
        )

        AppShortcut(
            intent: PreviousTrackIntent(),
            phrases: [
                "Previous track in \(.applicationName)",
                "Go back a song in \(.applicationName)"
            ],
            shortTitle: "Previous Track",
            systemImageName: "backward.end.fill"
        )

        AppShortcut(
            intent: GetCurrentTrackIntent(),
            phrases: [
                "What's playing in \(.applicationName)",
                "Get the current track from \(.applicationName)"
            ],
            shortTitle: "Current Track",
            systemImageName: "music.note"
        )

        AppShortcut(
            intent: GetRecentTracksIntent(),
            phrases: [
                "Recently played in \(.applicationName)",
                "Get my listening history from \(.applicationName)"
            ],
            shortTitle: "Recently Played",
            systemImageName: "clock.arrow.circlepath"
        )

        AppShortcut(
            intent: ToggleFavoriteIntent(),
            phrases: [
                "Favorite this song in \(.applicationName)",
                "Toggle favorite in \(.applicationName)"
            ],
            shortTitle: "Toggle Favorite",
            systemImageName: "star.fill"
        )

        AppShortcut(
            intent: ToggleShuffleIntent(),
            phrases: [
                "Toggle shuffle in \(.applicationName)"
            ],
            shortTitle: "Toggle Shuffle",
            systemImageName: "shuffle"
        )

        AppShortcut(
            intent: TogglePlayerIntent(),
            phrases: [
                "Show the player in \(.applicationName)",
                "Open \(.applicationName)"
            ],
            shortTitle: "Show Player",
            systemImageName: "macwindow"
        )
    }
}
