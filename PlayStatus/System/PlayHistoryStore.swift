import Foundation
import AppKit

/// One play, as recorded.
struct PlayHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let track: PlayedTrack
    let playedAt: Date
    let listenedSeconds: Double
    /// Whether the play met the scrobble threshold. `false` marks a skip, which is shown
    /// differently in the list and never scrobbled.
    let completed: Bool
    /// Key into `PersistentMediaCache`'s artwork namespace, not image data. Empty when no
    /// artwork was on screen when the play ended.
    let artworkKey: String

    /// What the row shows, and what a replay searches for.
    var displayTitle: String { track.title }
    var displaySubtitle: String {
        track.artist.isEmpty ? track.album : track.artist
    }

    var provider: NowPlayingProvider {
        NowPlayingProvider(rawValue: track.provider) ?? .none
    }

    /// What counts as "the same track" when collapsing repeats.
    ///
    /// Persistent ID where the provider gave one — a library can hold the same song twice as
    /// genuinely different files, and those should stay distinct rows.
    var collapseIdentity: String {
        if !track.trackIdentity.isEmpty {
            return "\(track.provider)|\(track.trackIdentity)"
        }
        return "\(track.provider)|\(track.title)|\(track.artist)"
    }
}

/// The local record of what has been played.
///
/// Mirrors `PersistentMediaCache`: an actor owning a directory under Application Support, with
/// its own on-disk format and its own eviction policy. Artwork is deliberately not stored here
/// — thumbnails live in the media cache, which already has size caps, JPEG encoding, and LRU
/// eviction, and this file stays small enough to read and rewrite whole.
actor PlayHistoryStore {
    static let shared = PlayHistoryStore()

    /// Hard ceiling. The retention setting can lower the effective limit but not raise it
    /// past this, so the file cannot grow without bound however the preference is set.
    static let maximumRetainedEntries = 5000

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let fileURL: URL

    /// Newest first. The whole list is held in memory: 5,000 metadata-only entries is roughly
    /// 1 MB, which is cheaper than paging and makes search and trimming trivial.
    private var entries: [PlayHistoryEntry] = []
    private var loaded = false
    private var retentionLimit = PlayHistoryStore.maximumRetainedEntries

    /// Writes are debounced because a play ends at most every few minutes, but a clear or a
    /// burst of skips can produce several mutations in a second.
    private var pendingWrite: Task<Void, Never>?
    private let writeDebounce: Duration = .seconds(2)

    init(directoryName: String = "History") {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        rootURL = supportURL
            .appendingPathComponent("PlayStatus", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        fileURL = rootURL.appendingPathComponent("play-history.json", isDirectory: false)
    }

    // MARK: Reading

    func allEntries() -> [PlayHistoryEntry] {
        ensureLoaded()
        return entries
    }

    func recentEntries(limit: Int) -> [PlayHistoryEntry] {
        ensureLoaded()
        return Array(entries.prefix(max(0, limit)))
    }

    func entryCount() -> Int {
        ensureLoaded()
        return entries.count
    }

    // MARK: Writing

    func setRetentionLimit(_ limit: Int) {
        ensureLoaded()
        let clamped = max(1, min(limit, Self.maximumRetainedEntries))
        guard clamped != retentionLimit else { return }
        retentionLimit = clamped
        if trimToLimit() {
            scheduleWrite()
        }
    }

    /// Records a finished play and returns the resulting list, newest first.
    @discardableResult
    func record(_ play: CompletedPlay, artworkKey: String) -> [PlayHistoryEntry] {
        ensureLoaded()

        let entry = PlayHistoryEntry(
            id: UUID(),
            track: play.track,
            playedAt: play.startedAt,
            listenedSeconds: play.listenedSeconds,
            completed: play.reachedScrobbleThreshold,
            artworkKey: artworkKey
        )

        entries.insert(entry, at: 0)
        _ = trimToLimit()
        scheduleWrite()
        return entries
    }

    @discardableResult
    func remove(id: UUID) -> [PlayHistoryEntry] {
        ensureLoaded()
        entries.removeAll { $0.id == id }
        scheduleWrite()
        return entries
    }

    @discardableResult
    func clear() -> [PlayHistoryEntry] {
        ensureLoaded()
        entries.removeAll()
        scheduleWrite()
        return entries
    }

    /// Writes immediately, bypassing the debounce. Call before termination.
    func flush() {
        pendingWrite?.cancel()
        pendingWrite = nil
        guard loaded else { return }
        persist()
    }

    // MARK: Persistence

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true

        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? Self.decoder.decode([PlayHistoryEntry].self, from: data) else {
            // A truncated or older-format file is not worth failing over. Start clean rather
            // than leaving the app unable to record anything for the rest of its life.
            #if DEBUG
            NSLog("PlayStatus history: could not decode %@, starting empty", fileURL.lastPathComponent)
            #endif
            return
        }

        entries = decoded.sorted { $0.playedAt > $1.playedAt }
        _ = trimToLimit()
    }

    @discardableResult
    private func trimToLimit() -> Bool {
        let limit = min(retentionLimit, Self.maximumRetainedEntries)
        guard entries.count > limit else { return false }
        entries.removeLast(entries.count - limit)
        return true
    }

    private func scheduleWrite() {
        pendingWrite?.cancel()
        pendingWrite = Task { [writeDebounce] in
            try? await Task.sleep(for: writeDebounce)
            guard !Task.isCancelled else { return }
            await self.persist()
        }
    }

    private func persist() {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(entries)
            // `.atomic` writes to a temporary file and renames, so a crash mid-write leaves the
            // previous file intact rather than a truncated one.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            NSLog("PlayStatus history: write failed %@", String(describing: error))
            #endif
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Artwork

enum PlayHistoryArtwork {
    /// Thumbnails are stored in the media cache rather than in the history file, so they are
    /// covered by its existing 50 MB ceiling and LRU eviction. An evicted thumbnail degrades to
    /// the provider glyph; it never blocks a row from rendering.
    static let thumbnailPixelSize: CGFloat = 96

    static func cacheKey(for track: PlayedTrack) -> String {
        if !track.trackIdentity.isEmpty {
            return "history|\(track.provider)|id:\(track.trackIdentity)"
        }
        return "history|\(track.provider)|\(track.artist)|\(track.album)|\(track.title)"
    }

    /// Downscales to a row-sized thumbnail. Full-size covers are ~1500px square; storing those
    /// per play would exhaust the cache in a few dozen tracks.
    static func thumbnail(from image: NSImage) -> NSImage {
        let side = thumbnailPixelSize
        let target = NSSize(width: side, height: side)
        let thumbnail = NSImage(size: target)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()
        return thumbnail
    }
}
