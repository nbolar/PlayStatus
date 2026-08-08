import SwiftUI
import AppKit

/// The player's one and only surface.
///
/// This used to be a near-transparent wash sitting behind a second, nearly identically
/// coloured `LiquidGlassCard` inset 14pt inside it — a 14pt band of the same brown
/// framing nothing, with two identical 18pt radii stacked on top of each other. The card
/// is gone; this view inherited its job, so the palette is applied here.
///
/// The palette sits over a dark ground, at whatever strength the theme engine asked for.
/// Album colour should tint the room, not paint it: the ground stays under everything so
/// the artwork — the one thing in the window that is supposed to be colourful — keeps
/// something to contrast against and white type survives without a drop shadow.
struct LiquidGlassBackground: View {
    let tint: Color
    var palette: [Color] = []
    /// Set by the theme engine, not by this view. See `NowPlayingThemeSpec.paletteStrength`.
    var paletteOpacity: Double = 1
    var readabilityBoost: Double = 0
    var transparencyMultiplier: Double = 1
    /// False in the detached window, where the `NSWindow` already casts a shadow — drawing a
    /// second one inside the frame only darkens the edges from the inside.
    var castsShadow: Bool = true

    private var primary: Color { palette.first ?? tint }
    private var secondary: Color { palette.dropFirst().first ?? primary }
    private var tertiary: Color { palette.dropFirst(2).first ?? secondary }

    private var clampedTransparencyMultiplier: Double {
        min(max(transparencyMultiplier, 0.35), 2.0)
    }

    private var clampedReadabilityBoost: Double {
        min(max(readabilityBoost, 0), 1)
    }

    /// How much of the palette reaches the surface.
    ///
    /// This was a hardcoded 0.45, applied on top of the alpha the theme engine had already
    /// baked into each colour — so the adaptive palette's leading stop landed at ~0.28 over
    /// a 0.62–0.86 ground and no album could move the surface far from charcoal. The engine
    /// owns that decision now and hands it down as `paletteOpacity`; the multiplier here is
    /// only the user's transparency setting.
    private var paletteStrength: Double {
        min(max(paletteOpacity, 0), 1) * clampedTransparencyMultiplier
    }

    /// The warm charcoal the palette sits on. Bright artwork pushes it darker, which is
    /// what keeps white type legible now that the type has no shadow of its own.
    private var groundOpacity: Double {
        min(0.86, 0.62 + (0.22 * clampedReadabilityBoost))
    }

    /// How colourful the album actually is.
    ///
    /// A monochrome cover — silver on black, a black-and-white photo — produces a palette
    /// with nothing to contribute, and the surface collapsed to flat grey: indistinguishable
    /// from any other dark panel, with none of the shape a tinted album gets.
    private var tintSaturation: Double {
        let base = NSColor(tint).usingColorSpace(.deviceRGB) ?? .white
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Double(saturation)
    }

    /// The album's overall lightness, used to shape an achromatic surface.
    private var tintBrightness: Double {
        let base = NSColor(tint).usingColorSpace(.deviceRGB) ?? .white
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Double(brightness)
    }

    /// 1 when the album has no usable hue, 0 once it does. Ramped rather than switched so a
    /// nearly-grey cover does not pop between two different surfaces as the artwork changes.
    private var achromatic: Double {
        let threshold = 0.16
        guard tintSaturation < threshold else { return 0 }
        return (threshold - tintSaturation) / threshold
    }

    /// Shape without hue: a light-to-dark sweep derived from how bright the album is, so a
    /// monochrome cover still gets a surface that reads as lit rather than as flat fill.
    private var luminanceSweep: LinearGradient {
        let lift = 0.05 + (0.07 * tintBrightness)
        return LinearGradient(
            colors: [
                Color.white.opacity(lift),
                Color.white.opacity(lift * 0.35),
                Color.black.opacity(0.10)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var sheenOpacity: Double {
        max(0.06, 0.18 - (0.10 * clampedReadabilityBoost))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: playerSurfaceCornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape.fill(playerSurfaceGroundColor.opacity(groundOpacity))

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            primary.opacity(paletteStrength),
                            secondary.opacity(paletteStrength * 0.86),
                            tertiary.opacity(paletteStrength * 0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            shape
                .fill(luminanceSweep)
                .opacity(achromatic)

            shape
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.16), .clear],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: 320
                    )
                )
                .blendMode(.screen)
                .opacity(sheenOpacity * (1 - (achromatic * 0.5)))

            shape.stroke(.white.opacity(playerHairlineOpacity), lineWidth: playerHairlineWidth)
        }
        .shadow(color: .black.opacity(castsShadow ? 0.16 : 0), radius: 16, x: 0, y: 8)
    }
}
