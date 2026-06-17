import Foundation
import AppKit
import SwiftUI

let modeTransitionDuration: Double = 0.38
let miniLyricsTransitionDuration: Double = 0.26

enum NowPlayingSurfaceMode: String {
    case popover
    case detached
}

enum AppAppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Always Light"
        case .dark: return "Always Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

enum PlaybackRepeatMode: String, CaseIterable, Equatable {
    case off
    case all
    case one

    var displayName: String {
        switch self {
        case .off: return "Repeat Off"
        case .all: return "Repeat All"
        case .one: return "Repeat One"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .off: return "Off"
        case .all: return "All"
        case .one: return "One"
        }
    }

    var systemImageName: String {
        switch self {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    var isEnabled: Bool {
        self != .off
    }

    func next(for provider: NowPlayingProvider) -> PlaybackRepeatMode {
        switch provider {
        case .music:
            switch self {
            case .off: return .all
            case .all: return .one
            case .one: return .off
            }
        case .spotify:
            return self == .off ? .all : .off
        case .none:
            return .off
        }
    }

    static func musicAppleScriptMode(from rawValue: String) -> PlaybackRepeatMode {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "all": return .all
        case "one": return .one
        default: return .off
        }
    }

    var musicAppleScriptLiteral: String {
        switch self {
        case .off: return "off"
        case .all: return "all"
        case .one: return "one"
        }
    }
}

enum LyricsPaneSizePreset: String, CaseIterable {
    case compact
    case standard
    case tall

    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .tall: return "Tall"
        }
    }

    var regularContentHeight: CGFloat {
        switch self {
        case .compact: return 160
        case .standard: return 270
        case .tall: return 430
        }
    }

    var miniContentHeight: CGFloat {
        switch self {
        case .compact: return 120
        case .standard: return 205
        case .tall: return 320
        }
    }
}

enum LyricsFontSizePreset: String, CaseIterable {
    case small
    case standard
    case large
    case custom

    static let customSizeRange: ClosedRange<Double> = 10...28

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Standard"
        case .large: return "Large"
        case .custom: return "Custom"
        }
    }

    var regularInactiveSize: CGFloat {
        switch self {
        case .small: return 12
        case .standard: return 13
        case .large: return 15
        case .custom: return LyricsFontSizePreset.standard.regularInactiveSize
        }
    }

    var regularActiveSize: CGFloat {
        switch self {
        case .small: return 15
        case .standard: return 17
        case .large: return 20
        case .custom: return LyricsFontSizePreset.standard.regularActiveSize
        }
    }

    var miniInactiveSize: CGFloat {
        switch self {
        case .small: return 11
        case .standard: return 12
        case .large: return 14
        case .custom: return LyricsFontSizePreset.standard.miniInactiveSize
        }
    }

    var miniActiveSize: CGFloat {
        switch self {
        case .small: return 15
        case .standard: return 17
        case .large: return 20
        case .custom: return LyricsFontSizePreset.standard.miniActiveSize
        }
    }

    static func clampedCustomSize(_ size: Double) -> Double {
        min(max(size, customSizeRange.lowerBound), customSizeRange.upperBound)
    }

    static func regularInactiveSize(for customSize: Double) -> CGFloat {
        CGFloat(clampedCustomSize(customSize))
    }

    static func regularActiveSize(for customSize: Double) -> CGFloat {
        CGFloat(clampedCustomSize(customSize) + 4)
    }

    static func miniInactiveSize(for customSize: Double) -> CGFloat {
        CGFloat(max(9, clampedCustomSize(customSize) - 1))
    }

    static func miniActiveSize(for customSize: Double) -> CGFloat {
        regularActiveSize(for: customSize)
    }
}

enum DetachedWindowSizePreset: String, CaseIterable {
    case small
    case medium
    case large

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var miniScaleFactor: CGFloat {
        switch self {
        case .small: return 0.70
        case .medium: return 0.90
        case .large: return 1.15
        }
    }

    var regularScaleFactor: CGFloat {
        switch self {
        case .small: return 0.95
        case .medium: return 1.00
        case .large: return 1.08
        }
    }

    var regularControlScaleFactor: CGFloat {
        switch self {
        case .small: return 0.90
        case .medium: return 1.00
        case .large: return 1.08
        }
    }

    var miniControlScaleFactor: CGFloat {
        switch self {
        case .small: return 0.82
        case .medium: return 1.00
        case .large: return 1.12
        }
    }
}

enum ProviderIconKind: Equatable {
    case sfSymbol(String)
    case iconifyAsset(String)

    static let appleMusic: ProviderIconKind = .iconifyAsset("AppleMusicGlyph")
    static let spotify: ProviderIconKind = .iconifyAsset("SpotifyGlyph")
}

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

    var iconKind: ProviderIconKind {
        switch self {
        case .music: return .appleMusic
        case .spotify: return .spotify
        case .none: return .appleMusic
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
    case vinylSpin
    case filmGrainDrift

    var displayName: String {
        switch self {
        case .parallaxByPointer: return "Parallax by Pointer"
        case .vinylSpin: return "Vinyl Spin"
        case .filmGrainDrift: return "Film Grain Drift"
        }
    }
}

enum ThemeStyle: String, CaseIterable {
    case artworkAdaptive
    case frosted
    case midnight
    case warmStudio
    case highContrast
    case graphite

    var displayName: String {
        switch self {
        case .artworkAdaptive: return "Artwork Adaptive"
        case .frosted: return "Frosted"
        case .midnight: return "Midnight"
        case .warmStudio: return "Warm Studio"
        case .highContrast: return "High Contrast"
        case .graphite: return "Graphite"
        }
    }
}

enum AnimatedArtworkQualityPolicy: String, CaseIterable {
    case adaptive1080
    case maxQuality
    case dataSaver

    var displayName: String {
        switch self {
        case .adaptive1080: return "Adaptive 1080"
        case .maxQuality: return "Max Quality"
        case .dataSaver: return "Data Saver"
        }
    }
}

enum AnimatedArtworkState: String, Equatable {
    case none
    case loading
    case available
    case unavailable
    case failed
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

enum DetailsPaneTab: String, CaseIterable {
    case lyrics
    case credits

    var displayName: String {
        switch self {
        case .lyrics: return "Lyrics"
        case .credits: return "Credits"
        }
    }

    var systemImage: String {
        switch self {
        case .lyrics: return "quote.bubble"
        case .credits: return "info.circle"
        }
    }
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

struct CreditsRow: Equatable, Identifiable {
    let label: String
    let value: String

    var id: String { "\(label)|\(value)" }
}

struct CreditsSection: Equatable, Identifiable {
    let title: String
    let rows: [CreditsRow]

    var id: String { title }
}

struct CreditsPayload: Equatable {
    let sourceName: String
    let sections: [CreditsSection]

    var hasContent: Bool {
        sections.contains { !$0.rows.isEmpty }
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
    var albumArtist: String = ""
    var album: String
    var artwork: NSImage?
    var nativeArtworkState: NativeArtworkState
    var elapsed: Double
    var duration: Double
    var canSeek: Bool
    var isShuffleEnabled: Bool = false
    var repeatMode: PlaybackRepeatMode = .off
    var isFavorited: Bool = false
    var lyrics: LyricsPayload? = nil
    var lyricsState: LyricsState = .idle
    var credits: CreditsPayload? = nil
    var appleMusicAlbumURL: URL? = nil
    var animatedArtworkState: AnimatedArtworkState = .none
    var animatedArtworkHLSURL: URL? = nil
}
