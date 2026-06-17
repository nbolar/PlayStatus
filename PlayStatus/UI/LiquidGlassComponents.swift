import SwiftUI
import AppKit

struct LiquidGlassBackground: View {
    let tint: Color
    var readabilityBoost: Double = 0
    var transparencyMultiplier: Double = 1

    private var clampedTransparencyMultiplier: Double {
        min(max(transparencyMultiplier, 0.35), 2.0)
    }

    private var clampedReadabilityBoost: Double {
        min(max(readabilityBoost, 0), 1)
    }

    private var darkenOpacity: Double {
        min(0.22, 0.01 + (0.18 * clampedReadabilityBoost))
    }

    private var sheenOpacity: Double {
        max(0.14, 0.50 - (0.26 * clampedReadabilityBoost))
    }

    private var strokeOpacity: Double {
        min(0.24, 0.10 + (0.10 * clampedReadabilityBoost))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.10 * clampedTransparencyMultiplier),
                            tint.opacity(0.06 * clampedTransparencyMultiplier),
                            tint.opacity(0.09 * clampedTransparencyMultiplier)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(darkenOpacity * clampedTransparencyMultiplier))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.14 * clampedTransparencyMultiplier), .clear],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: 300
                    )
                )
                .blendMode(.screen)
                .opacity(sheenOpacity)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(strokeOpacity), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 8)
    }
}

struct LiquidGlassCard<Content: View>: View {
    let tint: Color
    let palette: [Color]
    var readabilityBoost: Double = 0
    var transparencyMultiplier: Double = 1
    @ViewBuilder var content: Content

    private var primary: Color { palette.first ?? tint }
    private var secondary: Color { palette.dropFirst().first ?? tint }
    private var tertiary: Color { palette.dropFirst(2).first ?? tint }
    private var clampedReadabilityBoost: Double {
        min(max(readabilityBoost, 0), 1)
    }
    private var darkenOpacity: Double {
        min(0.24, 0.02 + (0.20 * clampedReadabilityBoost))
    }
    private var sheenOpacity: Double {
        max(0.10, 0.26 - (0.12 * clampedReadabilityBoost))
    }
    private var strokeOpacity: Double {
        min(0.26, 0.12 + (0.10 * clampedReadabilityBoost))
    }
    private var clampedTransparencyMultiplier: Double {
        min(max(transparencyMultiplier, 0.35), 2.0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            primary.opacity(0.90),
                            secondary.opacity(0.84),
                            tertiary.opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.90 * clampedTransparencyMultiplier)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(darkenOpacity * clampedTransparencyMultiplier))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.10), .white.opacity(0.03), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)
                .opacity(sheenOpacity * clampedTransparencyMultiplier)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(strokeOpacity * clampedTransparencyMultiplier), lineWidth: 1)

            content
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RegularPopoverBackdrop: View {
    let tint: Color
    let palette: [Color]
    let artwork: NSImage?

    var body: some View {
        ZStack {
            tint.opacity(0.10)

            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .saturation(1.04)
                    .blur(radius: 52)
                    .scaleEffect(1.10)
                    .opacity(0.14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
    }
}

struct OuterCardBleedMask: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black)
                .padding(7)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}
