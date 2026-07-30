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
                animatedArtworkIsVisible: true,
                cropAnimatedArtworkToSquare: model.cropAnimatedArtworkToSquare
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
                        cropAnimatedArtworkToSquare: model.cropAnimatedArtworkToSquare,
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
    let cropAnimatedArtworkToSquare: Bool
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
                animatedArtworkIsVisible: true,
                cropAnimatedArtworkToSquare: cropAnimatedArtworkToSquare
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

enum SettingsTabGroup: String, CaseIterable {
    case look
    case behavior
    case app

    var title: String {
        switch self {
        case .look: return "Look"
        case .behavior: return "Behavior"
        case .app: return "App"
        }
    }
}

enum SettingsTab: String, CaseIterable {
    case menuBar
    case playerWindow
    case appearance
    case artworkMotion
    case sources
    case shortcuts
    case general
    case about

    /// The window no longer resizes per tab — every pane shares one frame, sized for
    /// the tallest of them.
    static let windowSize = CGSize(width: 860, height: 640)

    var title: String {
        switch self {
        case .menuBar: return "Menu Bar"
        case .playerWindow: return "Player Window"
        case .appearance: return "Appearance"
        case .artworkMotion: return "Artwork Motion"
        case .sources: return "Sources"
        case .shortcuts: return "Shortcuts"
        case .general: return "General"
        case .about: return "About"
        }
    }

    var group: SettingsTabGroup {
        switch self {
        case .menuBar, .playerWindow, .appearance, .artworkMotion: return .look
        case .sources, .shortcuts: return .behavior
        case .general, .about: return .app
        }
    }

    var icon: String {
        switch self {
        case .menuBar: return "menubar.rectangle"
        case .playerWindow: return "macwindow"
        case .appearance: return "circle.lefthalf.filled"
        case .artworkMotion: return "waveform"
        case .sources: return "music.note.list"
        case .shortcuts: return "keyboard"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }

    var sortIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    /// Extra terms the sidebar filter matches, so a setting can be found by the name
    /// it had before it moved.
    var searchKeywords: [String] {
        switch self {
        case .menuBar:
            return ["display mode", "artist", "song", "icon only", "parentheses",
                    "scrollable title", "slide", "title width", "marquee", "status text"]
        case .playerWindow:
            return ["popover size", "detached", "always on top", "float", "lyrics",
                    "credits", "details pane", "font size", "expand"]
        case .appearance:
            return ["light", "dark", "follow system", "theme", "frosted", "midnight",
                    "warm studio", "high contrast", "graphite", "album colour blend",
                    "album color blend", "artwork colour intensity", "artwork color intensity"]
        case .artworkMotion:
            return ["animated artwork", "streams", "stream quality", "crop to square",
                    "parallax", "vinyl spin", "film grain", "motion style", "data saver"]
        case .sources:
            return ["preferred app", "music", "spotify", "priority", "automation",
                    "permissions", "connection", "verify"]
        case .shortcuts:
            return ["hotkey", "hotkeys", "keyboard", "play pause", "next track",
                    "previous track", "favourite", "favorite", "detached mode"]
        case .general:
            return ["launch at login", "startup", "updates", "sparkle", "media cache",
                    "memory", "walkthrough", "coachmarks", "advanced"]
        case .about:
            return ["version", "licence", "license", "mit", "lyrics attribution", "lrclib"]
        }
    }

    func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        if title.lowercased().contains(query) { return true }
        return searchKeywords.contains { $0.contains(query) }
    }
}

enum SettingsTabDirection {
    case forward
    case backward
}

struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab
    @ObservedObject var onboarding: OnboardingCoordinator
    @State private var searchText: String = ""

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    private var settingsNavigationCoachmarkBinding: Binding<Bool> {
        Binding(
            get: { onboarding.isCoachmarkActive(.settingsNavigation) },
            set: { isPresented in
                if !isPresented && onboarding.isCoachmarkActive(.settingsNavigation) {
                    onboarding.dismissCoachmark(.settingsNavigation)
                }
            }
        )
    }

    private func visibleTabs(in group: SettingsTabGroup) -> [SettingsTab] {
        SettingsTab.allCases.filter { $0.group == group && $0.matches(searchText: searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image("SettingsAppIcon")
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 0) {
                    Text("PlayStatus")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(versionText)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            SettingsSearchField(text: $searchText)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SettingsTabGroup.allCases, id: \.self) { group in
                        let tabs = visibleTabs(in: group)

                        if !tabs.isEmpty {
                            Text(group.title.uppercased())
                                .font(.system(size: 10.5, weight: .semibold))
                                .kerning(0.7)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 11)
                                .padding(.bottom, 4)

                            ForEach(tabs, id: \.self) { tab in
                                SettingsSidebarItem(tab: tab, selectedTab: $selectedTab)
                            }
                        }
                    }

                    if SettingsTab.allCases.allSatisfy({ !$0.matches(searchText: searchText) }) {
                        Text("No settings match “\(searchText)”.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)
            .popover(
                isPresented: settingsNavigationCoachmarkBinding,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .leading
            ) {
                CoachmarkBubble(
                    coachmark: .settingsNavigation,
                    accent: Color.accentColor
                ) {
                    onboarding.dismissCoachmark(.settingsNavigation)
                }
            }
            .onAppear {
                onboarding.registerCoachmark(.settingsNavigation, available: true)
            }
            .onDisappear {
                onboarding.registerCoachmark(.settingsNavigation, available: false)
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit PlayStatus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(10)
        }
        .frame(width: 218, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
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
            HStack(spacing: 9) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 16)

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }
}

struct SettingsPageHeader: View {
    let tab: SettingsTab

    var body: some View {
        Text(tab.title)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.primary)
            .padding(.bottom, 2)
    }
}
