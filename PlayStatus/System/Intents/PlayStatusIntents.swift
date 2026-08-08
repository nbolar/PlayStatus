import AppIntents
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// PlayStatus is an LSUIElement app: it has no windows and no Dock tile, and running a
// Shortcut must never bring it forward. Every intent below therefore sets
// `openAppWhenRun = false`.
//
// `NowPlayingModel` is not `@MainActor`, so each `perform()` hops explicitly rather than
// relying on inherited isolation.

// MARK: - Shared plumbing

/// Runs a block against the shared model on the main actor.
@MainActor
private func withModel<T>(_ body: (NowPlayingModel) -> T) -> T {
    body(NowPlayingModel.shared)
}

enum PlayStatusIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noActivePlayer
    case favoritesUnsupported
    case noCurrentTrack

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noActivePlayer:
            return "PlayStatus isn't connected to Music or Spotify right now."
        case .favoritesUnsupported:
            return "Favorites are only available for Apple Music tracks."
        case .noCurrentTrack:
            return "Nothing is playing."
        }
    }
}

// MARK: - Track entity

/// The current or a previously played track, in a form Shortcuts can carry between actions.
struct NowPlayingTrackEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Track" }
    static var defaultQuery = NowPlayingTrackQuery()

    var id: String
    @Property(title: "Title") var title: String
    @Property(title: "Artist") var artist: String
    @Property(title: "Album") var album: String
    @Property(title: "Source") var source: String
    @Property(title: "Duration") var duration: Double
    @Property(title: "Is Playing") var isPlaying: Bool
    @Property(title: "Played At") var playedAt: Date?

    /// Carried separately from the properties so Shortcuts can pass the cover into actions
    /// that take a file, rather than only displaying it.
    var artworkFile: IntentFile?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(artist)",
            image: artworkFile.map { .init(data: $0.data) }
        )
    }

    init(
        id: String,
        title: String,
        artist: String,
        album: String,
        source: String,
        duration: Double,
        isPlaying: Bool,
        playedAt: Date? = nil,
        artworkFile: IntentFile? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.source = source
        self.duration = duration
        self.isPlaying = isPlaying
        self.playedAt = playedAt
        self.artworkFile = artworkFile
    }
}

/// Entities here are snapshots of playback rather than a browsable catalogue, so the query
/// only ever resolves what is playing now.
struct NowPlayingTrackQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [NowPlayingTrackEntity] {
        let current = await MainActor.run { NowPlayingTrackEntity.current() }
        guard let current, identifiers.contains(current.id) else { return [] }
        return [current]
    }

    func suggestedEntities() async throws -> [NowPlayingTrackEntity] {
        guard let current = await MainActor.run(body: { NowPlayingTrackEntity.current() }) else {
            return []
        }
        return [current]
    }
}

extension NowPlayingTrackEntity {
    @MainActor
    static func current() -> NowPlayingTrackEntity? {
        let model = NowPlayingModel.shared
        guard model.provider != .none, !model.title.isEmpty else { return nil }

        return NowPlayingTrackEntity(
            id: model.title + "|" + model.artist + "|" + model.album,
            title: model.title,
            artist: model.artist,
            album: model.album,
            source: model.provider.displayName,
            duration: model.duration,
            isPlaying: model.isPlaying,
            artworkFile: model.artwork.flatMap { artworkFile(from: $0, name: model.title) }
        )
    }

    static func from(_ entry: PlayHistoryEntry, artwork: NSImage?) -> NowPlayingTrackEntity {
        NowPlayingTrackEntity(
            id: entry.id.uuidString,
            title: entry.track.title,
            artist: entry.track.artist,
            album: entry.track.album,
            source: entry.provider.displayName,
            duration: entry.track.duration,
            isPlaying: false,
            playedAt: entry.playedAt,
            artworkFile: artwork.flatMap { artworkFile(from: $0, name: entry.track.title) }
        )
    }

    private static func artworkFile(from image: NSImage, name: String) -> IntentFile? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        let safeName = name.isEmpty ? "artwork" : name
        return IntentFile(data: png, filename: "\(safeName).png", type: .png)
    }
}

// MARK: - Transport

struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Toggles playback in Music or Spotify.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        try await MainActor.run {
            let model = NowPlayingModel.shared
            guard model.provider != .none else { throw PlayStatusIntentError.noActivePlayer }
            model.playPause()
        }
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var description = IntentDescription("Skips to the next track.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        try await MainActor.run {
            let model = NowPlayingModel.shared
            guard model.provider != .none else { throw PlayStatusIntentError.noActivePlayer }
            model.nextTrack()
        }
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Track"
    static var description = IntentDescription("Goes back to the previous track.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        try await MainActor.run {
            let model = NowPlayingModel.shared
            guard model.provider != .none else { throw PlayStatusIntentError.noActivePlayer }
            model.previousTrack()
        }
        return .result()
    }
}

struct ToggleShuffleIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Shuffle"
    static var description = IntentDescription("Turns shuffle on or off.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let enabled = try await MainActor.run { () -> Bool in
            let model = NowPlayingModel.shared
            guard model.provider != .none else { throw PlayStatusIntentError.noActivePlayer }
            model.toggleShuffle()
            return model.isShuffleEnabled
        }
        return .result(value: enabled)
    }
}

struct CycleRepeatIntent: AppIntent {
    static var title: LocalizedStringResource = "Cycle Repeat Mode"
    static var description = IntentDescription("Steps through repeat off, all, and one.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let mode = try await MainActor.run { () -> String in
            let model = NowPlayingModel.shared
            guard model.provider != .none else { throw PlayStatusIntentError.noActivePlayer }
            model.cycleRepeatMode()
            return model.repeatMode.displayName
        }
        return .result(value: mode)
    }
}

struct ToggleFavoriteIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Favorite"
    static var description = IntentDescription("Favorites or unfavorites the current Apple Music track.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let favorited = try await MainActor.run { () -> Bool in
            let model = NowPlayingModel.shared
            guard model.provider != .none else { throw PlayStatusIntentError.noActivePlayer }
            // Spotify's AppleScript dictionary has no equivalent, so this is a hard no rather
            // than a silent no-op — a Shortcut that quietly does nothing is undebuggable.
            guard model.provider == .music else { throw PlayStatusIntentError.favoritesUnsupported }
            _ = model.toggleCurrentTrackFavorite()
            return model.isCurrentTrackFavorited
        }
        return .result(value: favorited)
    }
}

struct SetVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Output Volume"
    static var description = IntentDescription("Sets the system output volume.")
    static var openAppWhenRun = false

    @Parameter(title: "Level", description: "0 to 100.", inclusiveRange: (0, 100))
    var level: Int

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NowPlayingModel.shared.setOutputVolume(Double(level) / 100.0)
        }
        return .result()
    }
}

struct TogglePlayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Show or Hide Player"
    static var description = IntentDescription("Opens or closes the PlayStatus player.")
    // The one intent that deliberately surfaces UI — but still via the status item, so the
    // app does not steal focus as a foreground application.
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NowPlayingModel.shared.requestTogglePlayerSurface()
        }
        return .result()
    }
}

// MARK: - Queries

struct GetCurrentTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Current Track"
    static var description = IntentDescription("Returns what is playing right now.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<NowPlayingTrackEntity> {
        let entity = try await MainActor.run { () -> NowPlayingTrackEntity in
            guard let current = NowPlayingTrackEntity.current() else {
                throw PlayStatusIntentError.noCurrentTrack
            }
            return current
        }
        return .result(value: entity)
    }
}

struct GetRecentTracksIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Recently Played"
    static var description = IntentDescription("Returns the tracks you have listened to most recently, newest first.")
    static var openAppWhenRun = false

    @Parameter(title: "Limit", description: "How many tracks to return.", default: 10, inclusiveRange: (1, 100))
    var limit: Int

    func perform() async throws -> some IntentResult & ReturnsValue<[NowPlayingTrackEntity]> {
        let entries = await MainActor.run {
            Array(NowPlayingModel.shared.playHistory.prefix(limit))
        }

        var entities: [NowPlayingTrackEntity] = []
        for entry in entries {
            // Reuses the thumbnails the History pane already caches; a miss simply yields a
            // track with no artwork rather than a failed action.
            let data = entry.artworkKey.isEmpty
                ? nil
                : await PersistentMediaCache.shared.fetchArtworkData(forKey: entry.artworkKey)
            entities.append(NowPlayingTrackEntity.from(entry, artwork: data.flatMap { NSImage(data: $0) }))
        }
        return .result(value: entities)
    }
}
