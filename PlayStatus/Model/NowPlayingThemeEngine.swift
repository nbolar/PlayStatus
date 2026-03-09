import AppKit

struct NowPlayingThemeSpec {
    let tint: NSColor
    let palette: [NSColor]
    let contrastBoost: Double
}

enum NowPlayingThemeEngine {
    static func resolveTheme(
        style: ThemeStyle,
        image: NSImage?,
        artworkColorIntensity: Double,
        artworkBlend: Double
    ) -> NowPlayingThemeSpec {
        let adaptiveSpec = adaptiveThemeSpec(from: image, artworkColorIntensity: artworkColorIntensity)
        switch style {
        case .artworkAdaptive:
            return adaptiveSpec
        case .frosted, .midnight, .warmStudio, .highContrast, .graphite:
            let presetSpec = presetThemeSpec(
                for: style,
                image: image,
                artworkColorIntensity: artworkColorIntensity
            )
            guard image != nil, artworkBlend > 0 else {
                return presetSpec
            }
            return blendedThemeSpec(base: presetSpec, artwork: adaptiveSpec, amount: artworkBlend)
        }
    }

    private static func controlContrastBoost(for color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let luminance = (0.2126 * Double(rgb.redComponent))
            + (0.7152 * Double(rgb.greenComponent))
            + (0.0722 * Double(rgb.blueComponent))
        return min(max((luminance - 0.56) / 0.30, 0), 1)
    }

    private static func adaptiveThemeSpec(from image: NSImage?, artworkColorIntensity: Double) -> NowPlayingThemeSpec {
        guard let image else {
            let neutral = NSColor.white
            return NowPlayingThemeSpec(
                tint: neutral,
                palette: [
                    themedColor(neutral, alpha: 0.24, artworkColorIntensity: artworkColorIntensity),
                    themedColor(neutral, alpha: 0.20, artworkColorIntensity: artworkColorIntensity),
                    themedColor(neutral, alpha: 0.16, artworkColorIntensity: artworkColorIntensity),
                    themedColor(neutral, alpha: 0.10, artworkColorIntensity: artworkColorIntensity)
                ],
                contrastBoost: controlContrastBoost(for: neutral)
            )
        }

        let average = image.averageColor() ?? NSColor.white
        if let palette = image.artworkPalette() {
            let opacities: [Double] = [0.62, 0.56, 0.48, 0.40, 0.32, 0.24, 0.18]
            return NowPlayingThemeSpec(
                tint: average,
                palette: zip(palette, opacities).map { color, alpha in
                    themedColor(color, alpha: alpha, artworkColorIntensity: artworkColorIntensity)
                },
                contrastBoost: controlContrastBoost(for: average)
            )
        }

        return NowPlayingThemeSpec(
            tint: average,
            palette: [
                themedColor(average, alpha: 0.55, artworkColorIntensity: artworkColorIntensity),
                themedColor(average, alpha: 0.45, artworkColorIntensity: artworkColorIntensity),
                themedColor(average, alpha: 0.34, artworkColorIntensity: artworkColorIntensity),
                themedColor(average, alpha: 0.24, artworkColorIntensity: artworkColorIntensity)
            ],
            contrastBoost: controlContrastBoost(for: average)
        )
    }

    private static func presetThemeSpec(
        for style: ThemeStyle,
        image: NSImage?,
        artworkColorIntensity: Double
    ) -> NowPlayingThemeSpec {
        switch style {
        case .artworkAdaptive:
            return adaptiveThemeSpec(from: image, artworkColorIntensity: artworkColorIntensity)
        case .frosted:
            return NowPlayingThemeSpec(
                tint: nsColor(red: 0.90, green: 0.95, blue: 1.00),
                palette: [
                    themedColor(nsColor(red: 0.97, green: 0.99, blue: 1.00), alpha: 0.42, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.83, green: 0.90, blue: 0.99), alpha: 0.34, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.73, green: 0.82, blue: 0.95), alpha: 0.28, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.93, green: 0.95, blue: 0.99), alpha: 0.22, artworkColorIntensity: artworkColorIntensity)
                ],
                contrastBoost: 0.72
            )
        case .midnight:
            return NowPlayingThemeSpec(
                tint: nsColor(red: 0.24, green: 0.30, blue: 0.46),
                palette: [
                    themedColor(nsColor(red: 0.12, green: 0.15, blue: 0.24), alpha: 0.74, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.17, green: 0.22, blue: 0.34), alpha: 0.64, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.25, green: 0.30, blue: 0.46), alpha: 0.56, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.34, green: 0.41, blue: 0.57), alpha: 0.40, artworkColorIntensity: artworkColorIntensity)
                ],
                contrastBoost: 0.18
            )
        case .warmStudio:
            return NowPlayingThemeSpec(
                tint: nsColor(red: 0.82, green: 0.47, blue: 0.24),
                palette: [
                    themedColor(nsColor(red: 0.24, green: 0.11, blue: 0.08), alpha: 0.82, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.44, green: 0.19, blue: 0.12), alpha: 0.64, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.78, green: 0.35, blue: 0.18), alpha: 0.48, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.93, green: 0.64, blue: 0.34), alpha: 0.30, artworkColorIntensity: artworkColorIntensity)
                ],
                contrastBoost: 0.44
            )
        case .highContrast:
            return NowPlayingThemeSpec(
                tint: nsColor(red: 0.92, green: 0.95, blue: 0.99),
                palette: [
                    themedColor(nsColor(red: 0.04, green: 0.05, blue: 0.08), alpha: 0.95, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.08, green: 0.10, blue: 0.16), alpha: 0.86, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.18, green: 0.22, blue: 0.30), alpha: 0.64, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.84, green: 0.90, blue: 0.99), alpha: 0.22, artworkColorIntensity: artworkColorIntensity)
                ],
                contrastBoost: 1.0
            )
        case .graphite:
            return NowPlayingThemeSpec(
                tint: nsColor(red: 0.70, green: 0.73, blue: 0.79),
                palette: [
                    themedColor(nsColor(red: 0.18, green: 0.19, blue: 0.22), alpha: 0.84, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.28, green: 0.30, blue: 0.34), alpha: 0.66, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.42, green: 0.45, blue: 0.50), alpha: 0.46, artworkColorIntensity: artworkColorIntensity),
                    themedColor(nsColor(red: 0.62, green: 0.66, blue: 0.72), alpha: 0.28, artworkColorIntensity: artworkColorIntensity)
                ],
                contrastBoost: 0.56
            )
        }
    }

    private static func blendedThemeSpec(
        base: NowPlayingThemeSpec,
        artwork: NowPlayingThemeSpec,
        amount: Double
    ) -> NowPlayingThemeSpec {
        let clampedAmount = CGFloat(min(max(amount, 0), 1))
        let paletteCount = max(base.palette.count, artwork.palette.count)

        let blendedPalette: [NSColor] = (0..<paletteCount).map { index in
            let baseColor = index < base.palette.count ? base.palette[index] : (base.palette.last ?? base.tint)
            let artworkColor = index < artwork.palette.count ? artwork.palette[index] : (artwork.palette.last ?? artwork.tint)
            return blend(baseColor, artworkColor, ratio: clampedAmount)
        }

        return NowPlayingThemeSpec(
            tint: blend(base.tint, artwork.tint, ratio: clampedAmount),
            palette: blendedPalette,
            contrastBoost: base.contrastBoost + ((artwork.contrastBoost - base.contrastBoost) * Double(clampedAmount))
        )
    }

    private static func themedColor(
        _ color: NSColor,
        alpha: Double,
        artworkColorIntensity: Double
    ) -> NSColor {
        let scaledAlpha = min(max(alpha * artworkColorIntensity, 0), 0.95)
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return NSColor(
            calibratedRed: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            alpha: CGFloat(scaledAlpha)
        )
    }

    private static func nsColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    private static func blend(_ lhs: NSColor, _ rhs: NSColor, ratio: CGFloat) -> NSColor {
        let clampedRatio = min(max(ratio, 0), 1)
        let left = lhs.usingColorSpace(.deviceRGB) ?? lhs
        let right = rhs.usingColorSpace(.deviceRGB) ?? rhs
        return NSColor(
            calibratedRed: left.redComponent * (1 - clampedRatio) + right.redComponent * clampedRatio,
            green: left.greenComponent * (1 - clampedRatio) + right.greenComponent * clampedRatio,
            blue: left.blueComponent * (1 - clampedRatio) + right.blueComponent * clampedRatio,
            alpha: left.alphaComponent * (1 - clampedRatio) + right.alphaComponent * clampedRatio
        )
    }
}
