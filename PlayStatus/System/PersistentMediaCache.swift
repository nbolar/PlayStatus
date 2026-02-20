import Foundation
import AppKit
import CryptoKit

enum PersistentLyricsCacheValue: Equatable {
    case available(LyricsPayload)
    case unavailable
}

actor PersistentMediaCache {
    static let shared = PersistentMediaCache()

    private struct LyricsDiskLineRecord: Codable {
        let text: String
        let startTime: Double?
    }

    private struct LyricsDiskRecord: Codable {
        enum State: String, Codable {
            case available
            case unavailable
        }

        let state: State
        let source: String?
        let rawText: String?
        let isTimed: Bool?
        let lines: [LyricsDiskLineRecord]?

        static func available(from payload: LyricsPayload) -> LyricsDiskRecord {
            LyricsDiskRecord(
                state: .available,
                source: payload.source.rawValue,
                rawText: payload.rawText,
                isTimed: payload.isTimed,
                lines: payload.lines.map { LyricsDiskLineRecord(text: $0.text, startTime: $0.startTime) }
            )
        }

        static func unavailable() -> LyricsDiskRecord {
            LyricsDiskRecord(
                state: .unavailable,
                source: nil,
                rawText: nil,
                isTimed: nil,
                lines: nil
            )
        }

        func toCacheValue() -> PersistentLyricsCacheValue {
            guard state == .available else { return .unavailable }
            let resolvedSource = LyricsSource(rawValue: source ?? "") ?? .none
            let payloadLines = (lines ?? []).map { LyricsLine(text: $0.text, startTime: $0.startTime) }
            guard !payloadLines.isEmpty || !(rawText ?? "").isEmpty else {
                return .unavailable
            }
            return .available(
                LyricsPayload(
                    source: resolvedSource,
                    rawText: rawText ?? "",
                    lines: payloadLines,
                    isTimed: isTimed ?? false
                )
            )
        }
    }

    private enum CacheNamespace: String, Codable, CaseIterable {
        case lyrics
        case artwork
    }

    private enum CacheEntryKind: String, Codable {
        case lyricsAvailable
        case lyricsUnavailable
        case artworkImage
    }

    private struct CacheEntry: Codable {
        let key: String
        let namespace: CacheNamespace
        let filename: String
        let byteSize: Int
        let createdAt: Date
        var lastAccessAt: Date
        let expiresAt: Date?
        let kind: CacheEntryKind
    }

    private struct CacheIndex: Codable {
        let entries: [CacheEntry]
    }

    private let maxTotalBytes = 50 * 1024 * 1024
    private let maxEntries = 1500
    private let maxLyricsObjectBytes = 256 * 1024
    private let maxArtworkObjectBytes = 2 * 1024 * 1024
    private let lyricsAvailableTTL: TimeInterval = 30 * 24 * 60 * 60
    private let lyricsUnavailableTTL: TimeInterval = 24 * 60 * 60
    private let artworkTTL: TimeInterval = 14 * 24 * 60 * 60
    private let artworkJPEGCompression: CGFloat = 0.82

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let indexURL: URL
    private var initialized = false
    private var entriesByLookupKey: [String: CacheEntry] = [:]

    init() {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        rootURL = supportURL
            .appendingPathComponent("PlayStatus", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("index.json", isDirectory: false)
    }

    func fetchLyrics(forKey key: String) -> PersistentLyricsCacheValue? {
        ensureInitialized()
        let normalized = normalizeLyricsKey(key)
        let lookupKey = lookupKey(namespace: .lyrics, normalizedKey: normalized)
        guard var entry = entriesByLookupKey[lookupKey] else { return nil }

        let now = Date()
        guard !isExpired(entry, at: now) else {
            removeEntry(lookupKey: lookupKey)
            persistIndex()
            return nil
        }

        let fileURL = fileURL(for: entry)
        guard let data = try? Data(contentsOf: fileURL),
              let record = try? JSONDecoder().decode(LyricsDiskRecord.self, from: data) else {
            removeEntry(lookupKey: lookupKey)
            persistIndex()
            return nil
        }

        entry.lastAccessAt = now
        entriesByLookupKey[lookupKey] = entry
        persistIndex()
        logCacheEvent("lyrics hit key=\(entry.key) bytes=\(entry.byteSize)")
        return record.toCacheValue()
    }

    func storeLyricsAvailable(_ payload: LyricsPayload, forKey key: String) {
        ensureInitialized()
        let record = LyricsDiskRecord.available(from: payload)
        guard let data = try? JSONEncoder().encode(record),
              data.count <= maxLyricsObjectBytes else {
            return
        }

        upsert(
            namespace: .lyrics,
            normalizedKey: normalizeLyricsKey(key),
            kind: .lyricsAvailable,
            data: data,
            fileExtension: "json",
            expiresAt: Date().addingTimeInterval(lyricsAvailableTTL)
        )
    }

    func storeLyricsUnavailable(forKey key: String) {
        ensureInitialized()
        let record = LyricsDiskRecord.unavailable()
        guard let data = try? JSONEncoder().encode(record),
              data.count <= maxLyricsObjectBytes else {
            return
        }

        upsert(
            namespace: .lyrics,
            normalizedKey: normalizeLyricsKey(key),
            kind: .lyricsUnavailable,
            data: data,
            fileExtension: "json",
            expiresAt: Date().addingTimeInterval(lyricsUnavailableTTL)
        )
    }

    func fetchArtworkData(forKey key: String) -> Data? {
        ensureInitialized()
        let normalized = normalizeArtworkKey(key)
        let lookupKey = lookupKey(namespace: .artwork, normalizedKey: normalized)
        guard var entry = entriesByLookupKey[lookupKey] else { return nil }

        let now = Date()
        guard !isExpired(entry, at: now) else {
            removeEntry(lookupKey: lookupKey)
            persistIndex()
            return nil
        }

        let fileURL = fileURL(for: entry)
        guard let data = try? Data(contentsOf: fileURL) else {
            removeEntry(lookupKey: lookupKey)
            persistIndex()
            return nil
        }

        entry.lastAccessAt = now
        entriesByLookupKey[lookupKey] = entry
        persistIndex()
        logCacheEvent("artwork hit key=\(entry.key) bytes=\(entry.byteSize)")
        return data
    }

    func storeArtworkImage(_ image: NSImage, forKey key: String) {
        ensureInitialized()
        guard let encoded = encodeArtwork(image) else { return }
        guard encoded.data.count <= maxArtworkObjectBytes else { return }

        upsert(
            namespace: .artwork,
            normalizedKey: normalizeArtworkKey(key),
            kind: .artworkImage,
            data: encoded.data,
            fileExtension: encoded.fileExtension,
            expiresAt: Date().addingTimeInterval(artworkTTL)
        )
    }

    func clearAll() {
        do {
            if fileManager.fileExists(atPath: rootURL.path) {
                try fileManager.removeItem(at: rootURL)
                logCacheEvent("clear all")
            }
        } catch {
            NSLog("PlayStatus cache clear failed: %@", error.localizedDescription)
        }

        initialized = false
        entriesByLookupKey.removeAll()
        ensureInitialized()
    }

    func usageText() -> String {
        ensureInitialized()
        let bytes = totalBytes()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func ensureInitialized() {
        guard !initialized else { return }
        initialized = true

        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            for namespace in CacheNamespace.allCases {
                try fileManager.createDirectory(at: namespaceDirectoryURL(namespace), withIntermediateDirectories: true)
            }
        } catch {
            NSLog("PlayStatus cache init directory failure: %@", error.localizedDescription)
        }

        entriesByLookupKey.removeAll()
        if let data = try? Data(contentsOf: indexURL),
           let index = try? JSONDecoder().decode(CacheIndex.self, from: data) {
            for entry in index.entries {
                let lookup = lookupKey(namespace: entry.namespace, keyHash: entry.key)
                if entriesByLookupKey[lookup] == nil {
                    entriesByLookupKey[lookup] = entry
                }
            }
        }

        pruneAndPersist()
    }

    private func upsert(
        namespace: CacheNamespace,
        normalizedKey: String,
        kind: CacheEntryKind,
        data: Data,
        fileExtension: String,
        expiresAt: Date?
    ) {
        let now = Date()
        let keyHash = sha256(normalizedKey)
        let lookup = lookupKey(namespace: namespace, keyHash: keyHash)
        let filename = "\(keyHash).\(fileExtension)"

        if let existing = entriesByLookupKey[lookup], existing.filename != filename {
            deleteFileIfPresent(fileURL(for: existing))
        }

        let entry = CacheEntry(
            key: keyHash,
            namespace: namespace,
            filename: filename,
            byteSize: data.count,
            createdAt: now,
            lastAccessAt: now,
            expiresAt: expiresAt,
            kind: kind
        )

        let targetURL = fileURL(for: entry)
        do {
            try fileManager.createDirectory(at: namespaceDirectoryURL(namespace), withIntermediateDirectories: true)
            try data.write(to: targetURL, options: .atomic)
            entriesByLookupKey[lookup] = entry
            logCacheEvent("\(namespace.rawValue) store kind=\(kind.rawValue) key=\(keyHash) bytes=\(data.count)")
        } catch {
            NSLog("PlayStatus cache write failure: %@", error.localizedDescription)
            return
        }

        pruneAndPersist()
    }

    private func pruneAndPersist() {
        let now = Date()
        var didMutate = false

        for (lookup, entry) in entriesByLookupKey {
            if isExpired(entry, at: now) {
                removeEntry(lookupKey: lookup)
                didMutate = true
                continue
            }
            if !fileManager.fileExists(atPath: fileURL(for: entry).path) {
                entriesByLookupKey.removeValue(forKey: lookup)
                didMutate = true
            }
        }

        while entriesByLookupKey.count > maxEntries || totalBytes() > maxTotalBytes {
            guard let lru = entriesByLookupKey.min(by: { $0.value.lastAccessAt < $1.value.lastAccessAt }) else {
                break
            }
            removeEntry(lookupKey: lru.key)
            didMutate = true
        }

        if didMutate {
            persistIndex()
        } else if !fileManager.fileExists(atPath: indexURL.path) {
            persistIndex()
        }
    }

    private func removeEntry(lookupKey: String) {
        guard let entry = entriesByLookupKey.removeValue(forKey: lookupKey) else { return }
        deleteFileIfPresent(fileURL(for: entry))
        logCacheEvent("\(entry.namespace.rawValue) evict key=\(entry.key) bytes=\(entry.byteSize)")
    }

    private func totalBytes() -> Int {
        entriesByLookupKey.values.reduce(0) { $0 + max(0, $1.byteSize) }
    }

    private func persistIndex() {
        let index = CacheIndex(entries: Array(entriesByLookupKey.values))
        do {
            let data = try JSONEncoder().encode(index)
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("PlayStatus cache index persist failed: %@", error.localizedDescription)
        }
    }

    private func isExpired(_ entry: CacheEntry, at date: Date) -> Bool {
        guard let expiresAt = entry.expiresAt else { return false }
        return expiresAt <= date
    }

    private func fileURL(for entry: CacheEntry) -> URL {
        namespaceDirectoryURL(entry.namespace).appendingPathComponent(entry.filename, isDirectory: false)
    }

    private func namespaceDirectoryURL(_ namespace: CacheNamespace) -> URL {
        rootURL.appendingPathComponent(namespace.rawValue, isDirectory: true)
    }

    private func lookupKey(namespace: CacheNamespace, normalizedKey: String) -> String {
        lookupKey(namespace: namespace, keyHash: sha256(normalizedKey))
    }

    private func lookupKey(namespace: CacheNamespace, keyHash: String) -> String {
        "\(namespace.rawValue)|\(keyHash)"
    }

    private func normalizeLyricsKey(_ key: String) -> String {
        key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func normalizeArtworkKey(_ key: String) -> String {
        key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func deleteFileIfPresent(_ url: URL) {
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            NSLog("PlayStatus cache file removal failed: %@", error.localizedDescription)
        }
    }

    private func encodeArtwork(_ image: NSImage) -> (data: Data, fileExtension: String)? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }

        if let jpeg = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: artworkJPEGCompression]
        ) {
            return (jpeg, "jpg")
        }

        if let png = bitmap.representation(using: .png, properties: [:]) {
            return (png, "png")
        }

        return nil
    }

    private func logCacheEvent(_ message: String) {
        NSLog("PlayStatus cache: %@", message)
    }
}
