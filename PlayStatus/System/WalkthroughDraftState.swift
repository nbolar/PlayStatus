import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class WalkthroughDraftState {
    var enableMusic: Bool
    var enableSpotify: Bool
    var preferredProvider: PreferredProvider
    var providerPriority: ProviderPriority
    var menuBarTextMode: MenuBarTextMode
    var themeStyle: ThemeStyle
    var animatedArtworkEnabled: Bool
    var launchAtLoginEnabled: Bool

    init(model: NowPlayingModel) {
        enableMusic = model.enableMusic
        enableSpotify = model.enableSpotify
        preferredProvider = model.preferredProvider
        providerPriority = model.providerPriority
        menuBarTextMode = model.menuBarTextMode
        themeStyle = model.themeStyle
        animatedArtworkEnabled = model.animatedArtworkEnabled
        launchAtLoginEnabled = model.launchAtLoginEnabled
    }

    var previewProvider: NowPlayingProvider {
        switch preferredProvider {
        case .spotify:
            return .spotify
        case .music, .automatic:
            return .music
        }
    }

    func reload(from model: NowPlayingModel) {
        enableMusic = model.enableMusic
        enableSpotify = model.enableSpotify
        preferredProvider = model.preferredProvider
        providerPriority = model.providerPriority
        menuBarTextMode = model.menuBarTextMode
        themeStyle = model.themeStyle
        animatedArtworkEnabled = model.animatedArtworkEnabled
        launchAtLoginEnabled = model.launchAtLoginEnabled
    }

    func apply(to model: NowPlayingModel) {
        if model.enableMusic != enableMusic {
            model.enableMusic = enableMusic
        }
        if model.enableSpotify != enableSpotify {
            model.enableSpotify = enableSpotify
        }
        if model.preferredProvider != preferredProvider {
            model.preferredProvider = preferredProvider
        }
        if model.providerPriority != providerPriority {
            model.providerPriority = providerPriority
        }
        if model.menuBarTextMode != menuBarTextMode {
            model.menuBarTextMode = menuBarTextMode
        }
        if model.themeStyle != themeStyle {
            model.themeStyle = themeStyle
        }
        if model.animatedArtworkEnabled != animatedArtworkEnabled {
            model.animatedArtworkEnabled = animatedArtworkEnabled
        }
        if model.launchAtLoginEnabled != launchAtLoginEnabled {
            model.setLaunchAtLogin(enabled: launchAtLoginEnabled)
        }
    }
}

struct WalkthroughPreviewArtworkKey: Hashable, Equatable {
    let provider: NowPlayingProvider
    let variant: Int
}

@MainActor
final class WalkthroughPreviewAssets {
    static let shared = WalkthroughPreviewAssets()

    private let imageSize = NSSize(width: 560, height: 560)
    private var cache: [WalkthroughPreviewArtworkKey: NSImage] = [:]

    private init() {}

    func image(for key: WalkthroughPreviewArtworkKey) -> NSImage {
        if let cached = cache[key] {
            return cached
        }

        let resolvedProvider: NowPlayingProvider = key.provider == .spotify ? .spotify : .music
        let image = Self.makeArtwork(
            provider: resolvedProvider,
            variant: key.variant,
            size: imageSize
        )
        cache[key] = image
        return image
    }

    func prewarm() {
        for provider in [NowPlayingProvider.music, .spotify] {
            for variant in 0..<4 {
                let key = WalkthroughPreviewArtworkKey(provider: provider, variant: variant)
                if cache[key] == nil {
                    cache[key] = Self.makeArtwork(provider: provider, variant: variant, size: imageSize)
                }
            }
        }
    }

    func clearMemory() {
        cache.removeAll(keepingCapacity: false)
    }

    private static func makeArtwork(provider: NowPlayingProvider, variant: Int, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        let colors = gradientColors(for: provider, variant: variant)
        let gradient = NSGradient(colors: colors) ?? NSGradient(starting: colors[0], ending: colors[1])!
        gradient.draw(in: rect, angle: 34)

        NSColor.white.withAlphaComponent(0.07).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 38, dy: 38), xRadius: 36, yRadius: 36).fill()

        let circleInset = rect.width * 0.18
        let circleRect = rect.insetBy(dx: circleInset, dy: circleInset)
        let circleColor = colors.last?.blended(withFraction: 0.38, of: .white) ?? NSColor.white
        circleColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        let symbolName = provider == .spotify ? "waveform.circle.fill" : "music.note.list"
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 150, weight: .regular)
            let rendered = symbol.withSymbolConfiguration(config) ?? symbol
            let tinted = rendered.tinted(with: NSColor.white.withAlphaComponent(0.82))
            let symbolRect = NSRect(
                x: rect.midX - 128,
                y: rect.midY - 60,
                width: 256,
                height: 256
            )
            tinted.draw(in: symbolRect)
        }

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.94)
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.72)
        ]

        NSString(string: provider == .spotify ? "LATE SIGNAL" : "NIGHT ROUTE")
            .draw(at: NSPoint(x: 46, y: 38), withAttributes: titleAttributes)
        NSString(string: provider == .spotify ? "Spotify Preview" : "Music Preview")
            .draw(at: NSPoint(x: 48, y: 14), withAttributes: subtitleAttributes)

        return image
    }

    private static func gradientColors(for provider: NowPlayingProvider, variant: Int) -> [NSColor] {
        let palettes: [[NSColor]]
        switch provider {
        case .spotify:
            palettes = [
                [NSColor(calibratedRed: 0.10, green: 0.50, blue: 0.34, alpha: 1), NSColor(calibratedRed: 0.11, green: 0.17, blue: 0.20, alpha: 1), NSColor(calibratedRed: 0.24, green: 0.72, blue: 0.48, alpha: 1)],
                [NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.31, alpha: 1), NSColor(calibratedRed: 0.09, green: 0.16, blue: 0.20, alpha: 1), NSColor(calibratedRed: 0.26, green: 0.63, blue: 0.50, alpha: 1)],
                [NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.40, alpha: 1), NSColor(calibratedRed: 0.06, green: 0.11, blue: 0.18, alpha: 1), NSColor(calibratedRed: 0.20, green: 0.76, blue: 0.63, alpha: 1)],
                [NSColor(calibratedRed: 0.11, green: 0.26, blue: 0.22, alpha: 1), NSColor(calibratedRed: 0.18, green: 0.12, blue: 0.18, alpha: 1), NSColor(calibratedRed: 0.32, green: 0.74, blue: 0.44, alpha: 1)]
            ]
        case .music, .none:
            palettes = [
                [NSColor(calibratedRed: 0.38, green: 0.25, blue: 0.68, alpha: 1), NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.34, alpha: 1), NSColor(calibratedRed: 0.91, green: 0.39, blue: 0.60, alpha: 1)],
                [NSColor(calibratedRed: 0.18, green: 0.33, blue: 0.72, alpha: 1), NSColor(calibratedRed: 0.17, green: 0.11, blue: 0.38, alpha: 1), NSColor(calibratedRed: 0.76, green: 0.39, blue: 0.73, alpha: 1)],
                [NSColor(calibratedRed: 0.72, green: 0.30, blue: 0.42, alpha: 1), NSColor(calibratedRed: 0.21, green: 0.14, blue: 0.34, alpha: 1), NSColor(calibratedRed: 0.95, green: 0.59, blue: 0.44, alpha: 1)],
                [NSColor(calibratedRed: 0.20, green: 0.47, blue: 0.75, alpha: 1), NSColor(calibratedRed: 0.18, green: 0.11, blue: 0.31, alpha: 1), NSColor(calibratedRed: 0.58, green: 0.43, blue: 0.86, alpha: 1)]
            ]
        }

        return palettes[variant % palettes.count]
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = copy() as? NSImage ?? self
        image.lockFocus()
        color.set()
        let bounds = NSRect(origin: .zero, size: image.size)
        bounds.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
