import SwiftUI
import AppKit

let defaultAnimatedArtworkDemoStreamURL = URL(string: "https://mvod.itunes.apple.com/itunes-assets/HLSVideo221/v4/47/66/7b/47667b69-3c94-1c08-4682-8ee19a77c3fd/P1218990906_Anull_video_gr290_sdr_1080x1080.m3u8")!

struct AnimatedArtworkStreamPreviewSheet: View {
    @ObservedObject var model: NowPlayingModel
    let demoStreamURL: URL
    @Environment(\.dismiss) private var dismiss

    private var previewStreamURL: URL {
        model.effectiveAnimatedArtworkURL ?? demoStreamURL
    }

    private var isUsingDemoStream: Bool {
        model.effectiveAnimatedArtworkURL == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Animated Stream Preview")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Text("Shows how the currently resolved animated stream renders in the artwork tile.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            ArtworkView(
                image: model.artwork,
                tint: model.glassTint,
                animatedArtworkURL: previewStreamURL,
                animatedArtworkIsVisible: true
            )
            .frame(width: 256, height: 256)
            .frame(maxWidth: .infinity, alignment: .center)

            if isUsingDemoStream {
                Text("No animated stream is available for the current track. Showing built-in demo stream.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text(previewStreamURL.absoluteString)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 390)
    }
}

struct HoverMotionStylePreviewSheet: View {
    @ObservedObject var model: NowPlayingModel
    @Environment(\.dismiss) private var dismiss

    private var previewArtwork: NSImage? {
        model.artwork ?? HoverMotionStylePreviewArtwork.image
    }

    private var previewTint: Color {
        if model.artwork != nil {
            return model.glassTint
        }
        return Color(red: 0.96, green: 0.38, blue: 0.20)
    }

    private var previewAnimatedArtworkURL: URL? {
        model.effectiveAnimatedArtworkURL
    }

    private var previewTileSide: CGFloat {
        min(max(model.artworkDisplaySize, 124), 220)
    }

    private var previewColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 220, maximum: 280), spacing: 14),
            GridItem(.flexible(minimum: 220, maximum: 280), spacing: 14)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Artwork Motion Style Preview")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Text("See how artwork motion behaves on the same artwork pipeline used in the popover.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: previewColumns, alignment: .center, spacing: 14) {
                ForEach(ArtworkMotionStyle.allCases, id: \.self) { style in
                    HoverMotionStylePreviewCard(
                        style: style,
                        image: previewArtwork,
                        tint: previewTint,
                        animatedArtworkURL: previewAnimatedArtworkURL,
                        tileSide: previewTileSide,
                        isSelected: model.artworkMotionStyle == style,
                        onSelect: {
                            model.artworkMotionStyle = style
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 560)
    }
}

struct HoverMotionStylePreviewCard: View {
    let style: ArtworkMotionStyle
    let image: NSImage?
    let tint: Color
    let animatedArtworkURL: URL?
    let tileSide: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AnimatedArtworkView(
                image: image,
                tint: tint,
                isEnabled: false,
                seed: "settings-motion-preview-\(style.rawValue)",
                style: style,
                animatedArtworkURL: animatedArtworkURL,
                animatedArtworkIsVisible: true
            )
            .frame(width: tileSide, height: tileSide)
            .animatedArtworkMotion(
                isEnabled: true,
                seed: "settings-motion-preview-\(style.rawValue)",
                style: style,
                isPlaying: true,
                hasAnimatedStream: animatedArtworkURL != nil,
                tint: tint,
                artworkImage: image
            )

            Text(style.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Text(style.previewCaption)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Button(isSelected ? "Selected" : "Use This Style") {
                onSelect()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isSelected)
        }
        .padding(10)
        .frame(width: 236, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? .white.opacity(0.28) : .white.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

private enum HoverMotionStylePreviewArtwork {
    static let image: NSImage = {
        let size = NSSize(width: 900, height: 900)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(origin: .zero, size: size)
        NSColor(calibratedWhite: 0.08, alpha: 1.0).setFill()
        bounds.fill()

        NSGradient(colors: [
            NSColor(calibratedRed: 0.06, green: 0.13, blue: 0.34, alpha: 1.0),
            NSColor(calibratedRed: 0.18, green: 0.10, blue: 0.35, alpha: 1.0),
            NSColor(calibratedRed: 0.34, green: 0.16, blue: 0.10, alpha: 1.0)
        ])?.draw(in: bounds, angle: 220)

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: size.width / 2, yBy: size.height / 2)
        transform.rotate(byDegrees: -28)
        transform.translateX(by: -(size.width / 2), yBy: -(size.height / 2))
        transform.concat()
        NSColor.white.withAlphaComponent(0.16).setFill()
        var stripeX: CGFloat = -220
        while stripeX < size.width + 220 {
            NSBezierPath(rect: NSRect(x: stripeX, y: 0, width: 110, height: size.height)).fill()
            stripeX += 210
        }
        NSGraphicsContext.restoreGraphicsState()

        let haloRect = bounds.insetBy(dx: 130, dy: 130)
        if let haloGradient = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.98, green: 0.48, blue: 0.22, alpha: 0.92), 0.0),
            (NSColor(calibratedRed: 0.98, green: 0.48, blue: 0.22, alpha: 0.42), 0.45),
            (NSColor(calibratedRed: 0.98, green: 0.48, blue: 0.22, alpha: 0.0), 1.0)
        ) {
            haloGradient.draw(in: NSBezierPath(ovalIn: haloRect), relativeCenterPosition: .zero)
        }

        let coreRect = bounds.insetBy(dx: 240, dy: 240)
        if let coreGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.99, green: 0.65, blue: 0.30, alpha: 1.0),
            NSColor(calibratedRed: 0.89, green: 0.25, blue: 0.18, alpha: 1.0)
        ]) {
            coreGradient.draw(in: NSBezierPath(ovalIn: coreRect), angle: 300)
        }

        let ringPath = NSBezierPath(ovalIn: coreRect.insetBy(dx: -16, dy: -16))
        ringPath.lineWidth = 10
        NSColor.white.withAlphaComponent(0.30).setStroke()
        ringPath.stroke()

        return image
    }()
}

private extension ArtworkMotionStyle {
    var previewCaption: String {
        switch self {
        case .parallaxByPointer:
            return "Tilts and shifts with pointer position. Hover your cursor over the artwork"
        case .vinylSpin:
            return "Applies a record-inspired disc overlay that spins only while playback is active. Artwork Streaming takes precedence when enabled."
        case .filmGrainDrift:
            return "Adds a cinematic grain texture that slowly drifts across the artwork."
        }
    }
}

enum SettingsTab: String, CaseIterable {
    case display
    case playback
    case hotkeys
    case system
    case license

    var title: String {
        switch self {
        case .display: return "Display"
        case .playback: return "Playback"
        case .system: return "System"
        case .hotkeys: return "Hotkeys"
        case .license: return "License"
        }
    }

    var subtitle: String {
        switch self {
        case .display: return "Text, visuals, and animation"
        case .playback: return "Player source and priority"
        case .system: return "Startup and updates"
        case .hotkeys: return "Global keyboard shortcuts"
        case .license: return "Open-source terms"
        }
    }

    var icon: String {
        switch self {
        case .display: return "textformat"
        case .playback: return "waveform"
        case .system: return "gearshape.2"
        case .hotkeys: return "keyboard"
        case .license: return "doc.text"
        }
    }

    var sortIndex: Int {
        switch self {
        case .display: return 0
        case .playback: return 1
        case .hotkeys: return 2
        case .system: return 3
        case .license: return 4
        }
    }

    var preferredSize: CGSize {
        switch self {
        case .display:
            return CGSize(width: 780, height: 710)
        case .playback:
            return CGSize(width: 780, height: 560)
        case .hotkeys:
            return CGSize(width: 780, height: 520)
        case .system:
            return CGSize(width: 780, height: 520)
        case .license:
            return CGSize(width: 780, height: 620)
        }
    }
}

enum SettingsTabDirection {
    case forward
    case backward
}

struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab
    @ObservedObject var onboarding: OnboardingCoordinator

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "v\(version) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image("SettingsAppIcon")
                        .renderingMode(.original)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 32, height: 32)

                    Text("PlayStatus")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                Text(versionText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsSidebarItem(tab: tab, selectedTab: $selectedTab)
                }
            }
            .padding(10)
            .onAppear {
                onboarding.registerCoachmark(.settingsNavigation, available: true)
            }
            .onDisappear {
                onboarding.registerCoachmark(.settingsNavigation, available: false)
            }

            if onboarding.isCoachmarkActive(.settingsNavigation) {
                CoachmarkBubble(
                    coachmark: .settingsNavigation,
                    accent: Color.accentColor
                ) {
                    onboarding.dismissCoachmark(.settingsNavigation)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 10)

            Divider()

            Button {
                onboarding.replayFullWalkthrough()
            } label: {
                Label("Replay Walkthrough", systemImage: "sparkles")
                    .foregroundStyle(.primary)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.42))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.34), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit PlayStatus", systemImage: "power")
                    .foregroundStyle(Color.accentColor.opacity(0.95))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(12)
        }
        .frame(width: 230, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .underPageBackgroundColor).opacity(0.85),
                    Color(nsColor: .controlBackgroundColor).opacity(0.80)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct SettingsSidebarItem: View {
    let tab: SettingsTab
    @Binding var selectedTab: SettingsTab

    private var isSelected: Bool {
        selectedTab == tab
    }

    var body: some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .primary)

                    Text(tab.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                        ? Color.accentColor.opacity(0.92)
                        : Color.clear
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

struct SettingsPageHeader: View {
    let tab: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tab.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(tab.subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }
}

struct SettingsControlRow<Control: View>: View {
    let title: String
    let caption: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            control()
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(Text(title))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSliderRow: View {
    let title: String
    let caption: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(caption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
                Text(valueText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Slider(value: $value, in: range)
        }
    }
}

struct SettingsNoteCard: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
        )
    }
}
