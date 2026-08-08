import SwiftUI
import AppKit

// MARK: - Grouped card container

/// Inset grouped card, the macOS 13+ settings convention. Rows are composed by the
/// caller and separated with `SettingsRowDivider` so each card decides its own grouping.
struct SettingsCard<Content: View, Accessory: View>: View {
    let header: String?
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                HStack(alignment: .center, spacing: 10) {
                    Text(header.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    accessory()
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 2)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                )
        )
    }
}

extension SettingsCard where Accessory == EmptyView {
    init(header: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(header: header, accessory: { EmptyView() }, content: content)
    }
}

/// Full-bleed separator between rows inside a card.
struct SettingsRowDivider: View {
    var body: some View {
        Divider().opacity(0.6)
    }
}

// MARK: - Rows

/// A label/caption pair with a trailing control. `isEmphasized` tints the row so a
/// master switch reads as the parent of the rows beneath it.
struct SettingsRow<Control: View>: View {
    let title: String
    var caption: String? = nil
    var isEmphasized: Bool = false
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SettingsRowLabel(title: title, caption: caption)
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(isEmphasized ? Color.primary.opacity(0.05) : Color.clear)
    }
}

/// Label/caption pair stacked above a full-width control, for anything too wide to sit inline.
struct SettingsStackedRow<Control: View>: View {
    let title: String
    var caption: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRowLabel(title: title, caption: caption)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRowLabel: View {
    let title: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSwitchRow: View {
    let title: String
    var caption: String? = nil
    var isEmphasized: Bool = false
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, caption: caption, isEmphasized: isEmphasized) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(Text(title))
        }
    }
}

/// Segmented control for short option sets — replaces a pop-up menu wherever the
/// whole choice fits on one line.
struct SettingsSegmentedRow<Value: Hashable>: View {
    let title: String
    var caption: String? = nil
    @Binding var selection: Value
    let options: [Value]
    let optionLabel: (Value) -> String
    var controlWidth: CGFloat? = nil

    var body: some View {
        SettingsRow(title: title, caption: caption) {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(optionLabel(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(width: controlWidth, alignment: .trailing)
            .accessibilityLabel(Text(title))
        }
    }
}

/// Inline slider with a trailing value pill, so the readout sits with the control
/// rather than above it.
struct SettingsInlineSliderRow: View {
    let title: String
    var caption: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String
    var sliderWidth: CGFloat = 230

    var body: some View {
        SettingsRow(title: title, caption: caption) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                    .frame(width: sliderWidth)
                    .accessibilityLabel(Text(title))

                Text(valueText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 58)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
        }
    }
}

/// Trailing note inside a card, for the rare caveat that genuinely needs a sentence.
struct SettingsCardNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 12)
    }
}

// MARK: - Menu bar preview

/// Live preview of the menu bar item. Uses the model's own formatting and width so
/// what it shows is what the menu bar will render.
struct MenuBarPreviewStrip: View {
    @ObservedObject var model: NowPlayingModel

    private var previewTitle: String {
        model.menuBarTextMode == .iconOnly ? "" : model.menuBarTitle
    }

    private var measuredWidth: CGFloat {
        guard !previewTitle.isEmpty else { return 0 }
        // Must match StatusBarMarqueeView, which measures and draws with the
        // proportional system font — not the monospaced face.
        return measuredTextWidth(previewTitle, font: model.statusBarTitleFont)
    }

    /// Mirrors `StatusBarMarqueeView.update`: `textWidth > laneWidth + 1`.
    private var overflows: Bool {
        measuredWidth > model.statusTextWidth + 1
    }

    /// Mirrors the status item's two-tone title: song at full strength, artist dimmed.
    private var previewLabel: Text {
        let parts = model.menuBarTitleParts
        guard let secondary = parts.secondary else { return Text(previewTitle) }
        return Text(parts.primary)
            + Text(model.menuBarTitleSeparator + secondary).foregroundStyle(.secondary)
    }

    private var captionText: String {
        if model.menuBarTextMode == .iconOnly {
            return "Icon only — the menu bar shows just the glyph."
        }
        if overflows {
            return model.scrollableTitle
            ? "Needs \(Int(measuredWidth)) px, so this title will scroll."
            : "Needs \(Int(measuredWidth)) px, so this title will truncate."
        }
        return "Fits within \(Int(model.statusTextWidth)) px, so it won't scroll."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    // The real status item draws the provider glyph, not a transport
                    // symbol — the preview is only useful if it shows what you will get.
                    ProviderIconView(icon: model.statusIcon, size: 13, weight: .regular)
                        .frame(width: 13, alignment: .center)

                    if !previewTitle.isEmpty {
                        previewLabel
                            .font(.system(size: 13, weight: .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: model.statusTextWidth + 20, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)

                Text("100%")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    )
            )

            Text("Live preview · \(captionText)")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
        }
    }
}

// MARK: - Appearance mode picker

struct AppearanceModePicker: View {
    @Binding var selection: AppAppearanceMode

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                let isSelected = selection == mode

                Button {
                    selection = mode
                } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(mode.previewGradient)
                            .frame(width: 88, height: 56)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.accentColor, lineWidth: isSelected ? 2.5 : 0)
                            )

                        Text(mode.displayName)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(mode.displayName))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }

            Spacer(minLength: 0)
        }
    }
}

private extension AppAppearanceMode {
    var previewGradient: LinearGradient {
        switch self {
        case .light:
            return LinearGradient(
                colors: [Color(white: 1.0), Color(white: 0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [Color(white: 0.22), Color(white: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .system:
            return LinearGradient(
                stops: [
                    .init(color: Color(white: 1.0), location: 0.0),
                    .init(color: Color(white: 1.0), location: 0.5),
                    .init(color: Color(white: 0.11), location: 0.5),
                    .init(color: Color(white: 0.11), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Theme swatches

/// Six theme names tell you nothing about six themes, so each one shows the palette
/// it actually applies.
struct ThemeSwatchGrid: View {
    @Binding var selection: ThemeStyle

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(ThemeStyle.allCases, id: \.self) { style in
                let isSelected = selection == style

                Button {
                    selection = style
                } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(style.swatchFill)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.accentColor, lineWidth: isSelected ? 2.5 : 0)
                            )

                        Text(style.displayName)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2, reservesSpace: true)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(style.displayName))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

private extension ThemeStyle {
    /// Mirrors the base palette each preset applies in `NowPlayingThemeEngine`.
    var swatchFill: AnyShapeStyle {
        switch self {
        case .artworkAdaptive:
            return AnyShapeStyle(
                AngularGradient(
                    colors: [
                        Color(red: 1.00, green: 0.54, blue: 0.36),
                        Color(red: 0.85, green: 0.31, blue: 0.55),
                        Color(red: 0.42, green: 0.36, blue: 0.96),
                        Color(red: 0.22, green: 0.71, blue: 0.77),
                        Color(red: 1.00, green: 0.54, blue: 0.36)
                    ],
                    center: .center
                )
            )
        case .frosted:
            return AnyShapeStyle(gradient(
                Color(red: 0.97, green: 0.99, blue: 1.00),
                Color(red: 0.73, green: 0.82, blue: 0.95)
            ))
        case .midnight:
            return AnyShapeStyle(gradient(
                Color(red: 0.25, green: 0.30, blue: 0.46),
                Color(red: 0.12, green: 0.15, blue: 0.24)
            ))
        case .warmStudio:
            return AnyShapeStyle(gradient(
                Color(red: 0.93, green: 0.64, blue: 0.34),
                Color(red: 0.44, green: 0.19, blue: 0.12)
            ))
        case .highContrast:
            return AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.92, green: 0.95, blue: 0.99), location: 0.5),
                        .init(color: Color(red: 0.04, green: 0.05, blue: 0.08), location: 0.5)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .graphite:
            return AnyShapeStyle(gradient(
                Color(red: 0.62, green: 0.66, blue: 0.72),
                Color(red: 0.18, green: 0.19, blue: 0.22)
            ))
        }
    }

    private func gradient(_ top: Color, _ bottom: Color) -> LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Motion style tiles

/// One tile per motion style, showing the motion it applies using the same pipeline
/// the popover uses.
struct MotionStyleTiles: View {
    @ObservedObject var model: NowPlayingModel

    /// Square so the motion overlays register with the artwork; leaves room for the
    /// film-grain drift, which scales to 1.06 of the tile.
    private static let tileSide: CGFloat = 72

    private var tileArtwork: NSImage? {
        model.artwork
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(ArtworkMotionStyle.allCases, id: \.self) { style in
                let isSelected = model.artworkMotionStyle == style

                Button {
                    model.artworkMotionStyle = style
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        // The motion overlays size themselves from the view's
                        // shorter side and centre on its bounds, so the frame has
                        // to be square or the vinyl disc lands off the artwork.
                        AnimatedArtworkView(
                            image: tileArtwork,
                            tint: model.glassTint,
                            isEnabled: false,
                            seed: "settings-motion-tile-\(style.rawValue)",
                            style: style,
                            animatedArtworkURL: nil,
                            animatedArtworkIsVisible: false,
                            cropAnimatedArtworkToSquare: model.cropAnimatedArtworkToSquare
                        )
                        .frame(width: Self.tileSide, height: Self.tileSide)
                        .animatedArtworkMotion(
                            isEnabled: true,
                            seed: "settings-motion-tile-\(style.rawValue)",
                            style: style,
                            isPlaying: true,
                            hasAnimatedStream: false,
                            tint: model.glassTint,
                            artworkImage: tileArtwork
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 6)

                        Text(style.tileTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)

                        Text(style.tileCaption)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(style.displayName))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

private extension ArtworkMotionStyle {
    /// Short enough to survive a quarter-width tile; `displayName` is spelled out in
    /// the side-by-side preview sheet where there is room for it.
    var tileTitle: String {
        switch self {
        case .noMotion: return "None"
        case .parallaxByPointer: return "Parallax"
        case .vinylSpin: return "Vinyl"
        case .filmGrainDrift: return "Grain"
        }
    }

    var tileCaption: String {
        switch self {
        case .noMotion: return "Stays still"
        case .parallaxByPointer: return "Follows pointer"
        case .vinylSpin: return "Spins on play"
        case .filmGrainDrift: return "Drifting texture"
        }
    }
}

// MARK: - Status badge

struct SettingsStatusBadge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}
