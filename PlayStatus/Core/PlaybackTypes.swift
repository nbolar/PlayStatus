import AppKit

let modeTransitionDuration: Double = 0.95

enum NowPlayingProvider: String {
    case music
    case spotify
    case none

    var displayName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        case .none: return "Music"
        }
    }

    var icon: String {
        switch self {
        case .music: return "music.note"
        case .spotify: return "dot.radiowaves.left.and.right"
        case .none: return "music.note"
        }
    }
}

enum ProviderPriority: String, CaseIterable {
    case musicFirst
    case spotifyFirst

    var displayName: String {
        switch self {
        case .musicFirst: return "Music first"
        case .spotifyFirst: return "Spotify first"
        }
    }
}

enum MenuBarTextMode: String, CaseIterable {
    case artist
    case song
    case artistAndSong
    case iconOnly

    var displayName: String {
        switch self {
        case .artist: return "Artist"
        case .song: return "Song"
        case .artistAndSong: return "Artist + Song"
        case .iconOnly: return "Icon Only"
        }
    }
}

enum PreferredProvider: String, CaseIterable {
    case automatic
    case music
    case spotify

    var displayName: String {
        switch self {
        case .automatic: return "Auto"
        case .music: return "Music"
        case .spotify: return "Spotify"
        }
    }
}

enum ArtworkMotionStyle: String, CaseIterable {
    case parallaxByPointer
    case depthPulse

    var displayName: String {
        switch self {
        case .parallaxByPointer: return "Parallax by Pointer"
        case .depthPulse: return "Depth Pulse"
        }
    }
}

enum LyricsSource: String, Equatable {
    case musicApp
    case lrclib
    case none
}

enum LyricsState: Equatable {
    case idle
    case loading
    case available
    case unavailable
    case failed
}

enum LyricsLoadingStage: Int, CaseIterable, Equatable {
    case starting = 1
    case lrclibExact
    case lrclibSearch
    case musicFallback

    var displayTitle: String {
        switch self {
        case .starting: return "Preparing lyric request"
        case .lrclibExact: return "Checking LRCLIB exact match"
        case .lrclibSearch: return "Searching LRCLIB alternatives"
        case .musicFallback: return "Checking Music app lyrics"
        }
    }
}

struct LyricsLoadingProgress: Equatable {
    let attempt: Int
    let maxAttempts: Int
    let stage: LyricsLoadingStage
    let stageIndex: Int
    let stageCount: Int
}

struct LyricsLine: Equatable, Identifiable {
    let id: UUID
    let text: String
    let startTime: Double?

    nonisolated init(id: UUID = UUID(), text: String, startTime: Double?) {
        self.id = id
        self.text = text
        self.startTime = startTime
    }
}

struct LyricsPayload: Equatable {
    let source: LyricsSource
    let rawText: String
    let lines: [LyricsLine]
    let isTimed: Bool
}

struct NowPlayingSnapshot: Equatable {
    enum NativeArtworkState: Equatable {
        case available
        case pending
        case none
    }

    var provider: NowPlayingProvider
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    var artwork: NSImage?
    var nativeArtworkState: NativeArtworkState
    var elapsed: Double
    var duration: Double
    var canSeek: Bool
    var lyrics: LyricsPayload? = nil
    var lyricsState: LyricsState = .idle
}
