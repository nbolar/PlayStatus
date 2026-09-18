import Foundation

/// One-time repairs to stored defaults for releases that change what a setting means.
///
/// A default that flips from off to on lands on two different populations. A fresh install
/// should simply get the new behaviour. Someone who has been running PlayStatus for a year
/// has a menu bar they are used to, and a title lane that stops collapsing on pause is a
/// change they never asked for — so their answer is pinned to the old behaviour and left
/// for them to change in Settings, where the switch is now visible.
///
/// Each migration owns a marker key and runs at most once, so a user who turns the setting
/// on afterwards is never quietly overruled on the next launch.
@MainActor
enum DefaultsMigrations {
    private static let showTitleWhenPausedMarker = "playstatus.migration.showTitleWhenPaused.v1"

    static func runIfNeeded(defaults: UserDefaults = .standard) {
        migrateShowTitleWhenPaused(defaults: defaults)
    }

    /// `showTitleWhenPaused` shipped defaulting to off and now defaults to on. Existing
    /// installs keep the old behaviour; fresh ones fall through to the new default.
    private static func migrateShowTitleWhenPaused(defaults: UserDefaults) {
        guard !defaults.bool(forKey: showTitleWhenPausedMarker) else { return }
        // Marked before the work, not after: a migration that cannot decide anything useful
        // this launch will not decide anything useful on the next one either, and retrying
        // it forever risks overwriting a choice made in between.
        defaults.set(true, forKey: showTitleWhenPausedMarker)

        // An explicit answer already on file outranks anything decided here — including one
        // written by a build that shipped between the two defaults.
        guard defaults.object(forKey: NowPlayingModel.showTitleWhenPausedKey) == nil else { return }
        guard isExistingInstall(defaults: defaults) else { return }
        defaults.set(false, forKey: NowPlayingModel.showTitleWhenPausedKey)
    }

    /// The same question the onboarding coordinator asks to tell an upgrade from a first
    /// run, plus the marker it writes once the walkthrough has been seen. Either one means
    /// this machine has a PlayStatus the user is already used to.
    private static func isExistingInstall(defaults: UserDefaults) -> Bool {
        if defaults.string(forKey: OnboardingCoordinator.completionVersionKey) != nil { return true }
        return OnboardingCoordinator.settingsMarkerKeys.contains { defaults.object(forKey: $0) != nil }
    }
}
