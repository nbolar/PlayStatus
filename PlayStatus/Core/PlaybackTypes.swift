import AppKit

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
}
