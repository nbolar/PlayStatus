import AppKit
import Observation
import SwiftUI

private enum WalkthroughFeature: String, CaseIterable, Identifiable {
    case modes
    case search
    case lyrics
    case detached

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modes: return "Mini + Full"
        case .search: return "Search"
        case .lyrics: return "Lyrics"
        case .detached: return "Detached"
        }
    }

    var headline: String {
        switch self {
        case .modes:
            return "A player that can shrink or breathe"
        case .search:
            return "Search without leaving the menu bar"
        case .lyrics:
            return "Lyrics and credits stay in context"
        case .detached:
            return "Detach it when music should stay visible"
        }
    }

    var body: String {
        switch self {
        case .modes:
            return "Move between the compact mini player and the richer regular view without losing the feeling of the current track."
        case .search:
            return "Use provider-aware search from the player. Music can jump into your library, while Spotify opens the matching search."
        case .lyrics:
            return "Reveal synced lyrics or credits from the same surface instead of breaking your flow."
        case .detached:
            return "Pop the player into a floating window, pin it above your work, then snap back to the menu bar when you are done."
        }
    }

    var accentColor: Color {
        switch self {
        case .modes:
            return Color(red: 0.43, green: 0.72, blue: 0.98)
        case .search:
            return Color(red: 0.98, green: 0.72, blue: 0.34)
        case .lyrics:
            return Color(red: 0.87, green: 0.55, blue: 0.77)
        case .detached:
            return Color(red: 0.52, green: 0.84, blue: 0.62)
        }
    }
}

private enum ProviderConnectionState: Equatable {
    case idle
    case testing
    case connected(String)
    case attention(String)

    var label: String {
        switch self {
        case .idle:
            return "Not checked yet"
        case .testing:
            return "Checking connection..."
        case .connected(let message):
            return message
        case .attention(let message):
            return message
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            return .secondary
        case .testing:
            return Color(red: 0.43, green: 0.72, blue: 0.98)
        case .connected:
            return Color(red: 0.38, green: 0.78, blue: 0.57)
        case .attention:
            return Color(red: 0.98, green: 0.63, blue: 0.36)
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "circle.dashed"
        case .testing:
            return "arrow.triangle.2.circlepath"
        case .connected:
            return "checkmark.seal.fill"
        case .attention:
            return "exclamationmark.triangle.fill"
        }
    }
}

private struct WalkthroughPreviewState: Equatable {
    let provider: NowPlayingProvider
    let title: String
    let artist: String
    let album: String
    let artworkKey: WalkthroughPreviewArtworkKey
    let progress: Double
    let isPlaying: Bool
    let searchText: String
    let lyricsLines: [String]

    static func make(feature: WalkthroughFeature, preferredProvider: PreferredProvider) -> WalkthroughPreviewState {
        let provider: NowPlayingProvider
        switch preferredProvider {
        case .spotify:
            provider = .spotify
        case .music, .automatic:
            provider = .music
        }

        switch feature {
        case .modes:
            return WalkthroughPreviewState(
                provider: provider,
                title: "Afterlight Avenue",
                artist: provider == .spotify ? "Slow Orbit" : "Amber Signal",
                album: "City Glass",
                artworkKey: WalkthroughPreviewArtworkKey(provider: provider, variant: 0),
                progress: 0.42,
                isPlaying: true,
                searchText: "amber signal",
                lyricsLines: [
                    "Silver lights across the avenue",
                    "You keep the skyline moving",
                    "Every window hums in tune"
                ]
            )
        case .search:
            return WalkthroughPreviewState(
                provider: provider,
                title: "Summer Echo",
                artist: provider == .spotify ? "Lumen Coast" : "North Harbour",
                album: "Open Tides",
                artworkKey: WalkthroughPreviewArtworkKey(provider: provider, variant: 1),
                progress: 0.26,
                isPlaying: true,
                searchText: provider == .spotify ? "open tides" : "North Harbour",
                lyricsLines: [
                    "Search the next song from here",
                    "Then stay in the player"
                ]
            )
        case .lyrics:
            return WalkthroughPreviewState(
                provider: provider,
                title: "Paper Satellites",
                artist: provider == .spotify ? "Midnight Array" : "Glass Almanac",
                album: "Blue Catalogue",
                artworkKey: WalkthroughPreviewArtworkKey(provider: provider, variant: 2),
                progress: 0.61,
                isPlaying: true,
                searchText: "paper satellites",
                lyricsLines: [
                    "Paper satellites in shallow blue",
                    "We wrote our names in turning light",
                    "Nothing in the room stayed still for long",
                    "Everything looked made for midnight"
                ]
            )
        case .detached:
            return WalkthroughPreviewState(
                provider: provider,
                title: "Static Bloom",
                artist: provider == .spotify ? "Velvet Modern" : "Signal Harbour",
                album: "Open Window",
                artworkKey: WalkthroughPreviewArtworkKey(provider: provider, variant: 3),
                progress: 0.79,
                isPlaying: false,
                searchText: "static bloom",
                lyricsLines: [
                    "Keep the player floating nearby"
                ]
            )
        }
    }
}

struct OnboardingWalkthroughView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @Bindable var draft: WalkthroughDraftState

    @Environment(\.openSettings) private var openSettings
    @State private var selectedFeature: WalkthroughFeature = .modes
    @State private var musicConnectionState: ProviderConnectionState = .idle
    @State private var spotifyConnectionState: ProviderConnectionState = .idle

    private var mode: OnboardingMode {
        coordinator.resolvedMode
    }

    private var currentPreview: WalkthroughPreviewState {
        WalkthroughPreviewState.make(
            feature: selectedFeature,
            preferredProvider: draft.preferredProvider
        )
    }

    private var accentStyle: WalkthroughAccentStyle {
        WalkthroughAccentStyle.make(step: coordinator.currentStep)
    }

    var body: some View {
        WalkthroughShellView(
            mode: mode,
            currentStep: coordinator.currentStep,
            accentStyle: accentStyle,
            canGoBack: !coordinator.isFirstStep(coordinator.currentStep),
            nextButtonTitle: coordinator.nextStepTitle(),
            onSelectStep: { coordinator.jump(to: $0) },
            onSkip: { coordinator.skipWalkthrough() },
            onBack: { coordinator.goBack() },
            onContinue: { coordinator.advanceStep() }
        ) {
            walkthroughContent
        }
        .onChange(of: coordinator.currentStep, initial: false) { _, newStep in
            if newStep != .explore {
                selectedFeature = .modes
            }
        }
    }

    @ViewBuilder
    private var walkthroughContent: some View {
        switch coordinator.currentStep {
        case .welcome:
            WalkthroughWelcomeStep(draft: draft, accentStyle: accentStyle)
        case .welcomeBack:
            WalkthroughUpgradeStep(accentStyle: accentStyle)
        case .connect:
            WalkthroughConnectStep(
                draft: draft,
                musicConnectionState: musicConnectionState,
                spotifyConnectionState: spotifyConnectionState,
                isMusicInstalled: coordinator.providerIsInstalled(.music),
                isSpotifyInstalled: coordinator.providerIsInstalled(.spotify),
                onOpenMusic: { coordinator.openProvider(.music) },
                onOpenSpotify: { coordinator.openProvider(.spotify) },
                onConnectMusic: { connect(.music) },
                onConnectSpotify: { connect(.spotify) },
                onOpenPrivacyHelp: { coordinator.openAutomationPrivacySettings() },
                onVerifyEnabledApps: { runQuickVerification() }
            )
        case .explore:
            WalkthroughExploreStep(
                selectedFeature: $selectedFeature,
                preview: currentPreview
            )
        case .personalize:
            WalkthroughPersonalizeStep(
                draft: draft,
                onOpenSettings: { coordinator.openSettingsFromWalkthrough(using: openSettings) }
            )
        case .finish:
            WalkthroughFinishStep(
                mode: mode,
                onOpenSettings: { coordinator.openSettingsFromWalkthrough(using: openSettings) },
                onReplayFullWalkthrough: { coordinator.replayFullWalkthrough() },
                onReplayUpgradeWalkthrough: { coordinator.presentUpgradeWalkthrough() }
            )
        }
    }

    private func connect(_ provider: NowPlayingProvider) {
        setConnectionState(.testing, for: provider)
        coordinator.openProvider(provider)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            let connected = coordinator.probeAutomation(for: provider)
            if connected {
                setConnectionState(.connected("Connected and ready for \(provider.displayName)."), for: provider)
            } else if !coordinator.providerIsInstalled(provider) {
                setConnectionState(.attention("\(provider.displayName) is not installed on this Mac."), for: provider)
            } else {
                setConnectionState(
                    .attention("Access still needs attention. Retry once, then check Privacy & Security > Automation."),
                    for: provider
                )
            }
        }
    }

    private func runQuickVerification() {
        if draft.enableMusic {
            connect(.music)
        }
        if draft.enableSpotify {
            connect(.spotify)
        }
    }

    private func setConnectionState(_ state: ProviderConnectionState, for provider: NowPlayingProvider) {
        switch provider {
        case .music, .none:
            musicConnectionState = state
        case .spotify:
            spotifyConnectionState = state
        }
    }
}

private struct WalkthroughAccentStyle {
    let tint: Color
    let softFill: Color
    let line: Color

    static func make(step: OnboardingStep) -> WalkthroughAccentStyle {
        let tint: Color
        switch step {
        case .welcome:
            tint = Color(red: 0.44, green: 0.71, blue: 0.97)
        case .welcomeBack:
            tint = Color(red: 0.86, green: 0.60, blue: 0.74)
        case .connect:
            tint = Color(red: 0.98, green: 0.67, blue: 0.34)
        case .explore:
            tint = WalkthroughFeature.modes.accentColor
        case .personalize:
            tint = Color(red: 0.98, green: 0.60, blue: 0.42)
        case .finish:
            tint = Color(red: 0.53, green: 0.83, blue: 0.63)
        }

        return WalkthroughAccentStyle(
            tint: tint,
            softFill: tint.opacity(0.14),
            line: tint.opacity(0.28)
        )
    }
}

private struct WalkthroughShellView<Content: View>: View {
    let mode: OnboardingMode
    let currentStep: OnboardingStep
    let accentStyle: WalkthroughAccentStyle
    let canGoBack: Bool
    let nextButtonTitle: String
    let onSelectStep: (OnboardingStep) -> Void
    let onSkip: () -> Void
    let onBack: () -> Void
    let onContinue: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stepCountLabel: String {
        let stepIndex = (mode.steps.firstIndex(of: currentStep) ?? 0) + 1
        return "Step \(stepIndex) of \(mode.steps.count)"
    }

    var body: some View {
        ZStack {
            WalkthroughBackdropView()
                .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar

                Divider()
                    .overlay(Color.white.opacity(0.08))

                mainPanel
            }
        }
        .frame(minWidth: 960, minHeight: 660)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image("SettingsAppIcon")
                        .renderingMode(.original)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 42, height: 42)
                        .clipShape(.rect(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 4)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("PlayStatus")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(mode == .freshInstall ? "Relaunch Walkthrough" : "What’s New")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(mode.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    Text(mode.subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(mode.steps.enumerated()), id: \.element) { index, step in
                    Button {
                        onSelectStep(step)
                    } label: {
                        WalkthroughStepSidebarItem(
                            index: index + 1,
                            step: step,
                            isSelected: step == currentStep,
                            isEnabled: step != currentStep,
                            accent: accentStyle.tint
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(step == currentStep)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            Spacer(minLength: 18)

            VStack(alignment: .leading, spacing: 10) {
                InfoBadgeLine(
                    title: "Setup first",
                    message: "Provider choices and permissions happen first so the app is useful before the feature tour."
                )
                InfoBadgeLine(
                    title: "Replay anytime",
                    message: "The walkthrough can be reopened from Settings or the app menu later."
                )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .frame(width: 300, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.16),
                    Color.black.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .overlay(Color.white.opacity(0.08))

            WalkthroughContentPane(
                stepID: currentStep.rawValue,
                reduceMotion: reduceMotion
            ) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
                .overlay(Color.white.opacity(0.08))

            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stepCountLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(accentStyle.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(accentStyle.softFill)
                )

            Text(currentStep.title)
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text(currentStep.subtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var footer: some View {
        HStack {
            Button("Skip", action: onSkip)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Back", action: onBack)
                .buttonStyle(.bordered)
                .disabled(!canGoBack)

            Button(nextButtonTitle, action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(accentStyle.tint)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }
}

private struct WalkthroughContentPane<Content: View>: View {
    let stepID: String
    let reduceMotion: Bool
    @ViewBuilder let content: Content

    private var transition: AnyTransition {
        reduceMotion ? .identity : .opacity
    }

    var body: some View {
        let pane = ZStack(alignment: .topLeading) {
            content
                .id(stepID)
                .transition(transition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        Group {
            if reduceMotion {
                pane
            } else {
                pane.animation(.linear(duration: 0.10), value: stepID)
            }
        }
    }
}

private struct WalkthroughBackdropView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.11, blue: 0.16),
                    Color(red: 0.15, green: 0.21, blue: 0.28),
                    Color(red: 0.11, green: 0.16, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    Color(red: 0.26, green: 0.33, blue: 0.56).opacity(0.26),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 420
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.06),
                    Color.black.opacity(0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct WalkthroughStepSidebarItem: View {
    let index: Int
    let step: OnboardingStep
    let isSelected: Bool
    let isEnabled: Bool
    let accent: Color

    @State private var isHovering = false

    private var circleFill: Color {
        if isSelected {
            return accent.opacity(0.92)
        }
        if isHovering {
            return accent.opacity(0.18)
        }
        return Color.secondary.opacity(0.12)
    }

    private var numberColor: Color {
        if isSelected {
            return .white
        }
        return isHovering ? accent : .secondary
    }

    private var trailingIconColor: Color {
        if isSelected {
            return accent
        }
        return isHovering ? accent.opacity(0.92) : Color.secondary.opacity(0.65)
    }

    private var backgroundFill: Color {
        if isSelected {
            return accent.opacity(0.12)
        }
        return isHovering ? Color.white.opacity(0.08) : .clear
    }

    private var borderColor: Color {
        if isSelected {
            return accent.opacity(0.24)
        }
        return isHovering ? Color.white.opacity(0.12) : .clear
    }

    var body: some View {
        HStack(spacing: 12) {
            indicator
            copyBlock

            Spacer(minLength: 0)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(trailingIconColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.smooth(duration: 0.12), value: isHovering)
        .onHover { hovering in
            guard isEnabled else {
                isHovering = false
                return
            }
            isHovering = hovering
        }
    }

    private var indicator: some View {
        ZStack {
            Circle()
                .fill(circleFill)
                .frame(width: 28, height: 28)

            Text("\(index)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(numberColor)
        }
    }

    private var copyBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(step.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected || isHovering ? Color.primary : Color.secondary)

            Text(step.subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct InfoBadgeLine: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(message)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.88))
        )
    }
}

private enum WalkthroughSurfaceProminence {
    case primary
    case subtle
}

private enum WalkthroughPalette {
    static let ink = Color.black.opacity(0.86)
    static let border = Color.black.opacity(0.08)
    static let primarySurfaceTop = Color.white.opacity(0.97)
    static let primarySurfaceBottom = Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.94)
    static let subtleSurfaceTop = Color.white.opacity(0.93)
    static let subtleSurfaceBottom = Color(red: 0.93, green: 0.93, blue: 0.95).opacity(0.88)
}

private struct WalkthroughSurfaceCard<Content: View>: View {
    var prominence: WalkthroughSurfaceProminence = .primary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .light)
        .foregroundStyle(WalkthroughPalette.ink)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(WalkthroughPalette.border.opacity(prominence == .primary ? 1 : 0.74), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 26))
        .shadow(color: .black.opacity(prominence == .primary ? 0.10 : 0.05), radius: 10, x: 0, y: 6)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: prominence == .primary
                        ? [WalkthroughPalette.primarySurfaceTop, WalkthroughPalette.primarySurfaceBottom]
                        : [WalkthroughPalette.subtleSurfaceTop, WalkthroughPalette.subtleSurfaceBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

private struct WalkthroughAdaptivePair<Primary: View, Secondary: View>: View {
    let primaryMinWidth: CGFloat
    let secondaryMinWidth: CGFloat
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 22) {
                primary
                    .frame(minWidth: primaryMinWidth, maxWidth: .infinity, alignment: .topLeading)
                secondary
                    .frame(minWidth: secondaryMinWidth, maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 22) {
                primary
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                secondary
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct WalkthroughSectionTitle: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }
}

private struct OnboardingToggleCard<Accessory: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(caption)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            accessory
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(WalkthroughPalette.border.opacity(0.65), lineWidth: 1)
                )
        )
    }
}

private struct WalkthroughPickerRow<Selection: Hashable & CaseIterable>: View where Selection.AllCases: RandomAccessCollection, Selection.AllCases.Element == Selection {
    let title: String
    let caption: String
    let selection: Binding<Selection>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))

                Text(caption)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Picker(title, selection: selection) {
                ForEach(Array(Selection.allCases), id: \.self) { value in
                    Text(displayName(for: value)).tag(value)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(WalkthroughPalette.border.opacity(0.65), lineWidth: 1)
                )
        )
    }

    private func displayName(for value: Selection) -> String {
        switch value {
        case let value as PreferredProvider:
            return value.displayName
        case let value as ProviderPriority:
            return value.displayName
        case let value as MenuBarTextMode:
            return value.displayName
        case let value as ThemeStyle:
            return value.displayName
        default:
            return String(describing: value)
        }
    }
}

private struct WalkthroughStepScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WalkthroughWelcomeStep: View {
    @Bindable var draft: WalkthroughDraftState
    let accentStyle: WalkthroughAccentStyle

    var body: some View {
        WalkthroughStepScrollView {
            WalkthroughAdaptivePair(
                primaryMinWidth: 360,
                secondaryMinWidth: 380
            ) {
                WalkthroughSurfaceCard {
                    VStack(alignment: .leading, spacing: 20) {
                        WalkthroughSectionTitle(
                            eyebrow: "Player setup",
                            title: "Choose the apps PlayStatus should listen to"
                        )

                        VStack(spacing: 14) {
                            OnboardingToggleCard(
                                title: "Enable Music",
                                caption: "Apple Music is great for library playback, favorites, and lyrics."
                            ) {
                                Toggle("", isOn: $draft.enableMusic)
                                    .labelsHidden()
                            }

                            OnboardingToggleCard(
                                title: "Enable Spotify",
                                caption: "Spotify works great for metadata, transport controls, and search handoff."
                            ) {
                                Toggle("", isOn: $draft.enableSpotify)
                                    .labelsHidden()
                            }
                        }

                        WalkthroughPickerRow(
                            title: "Preferred App",
                            caption: "When both apps are active, this one wins first.",
                            selection: $draft.preferredProvider
                        )

                        WalkthroughPickerRow(
                            title: "Automatic Priority",
                            caption: "If your preferred app is idle, this decides fallback order.",
                            selection: $draft.providerPriority
                        )
                    }
                }
            } secondary: {
                WalkthroughSurfaceCard(prominence: .subtle) {
                    WelcomeHeroCard(
                        accentStyle: accentStyle,
                        provider: draft.previewProvider,
                        preferredProvider: draft.preferredProvider
                    )
                }
            }
        }
    }
}

private struct WalkthroughUpgradeStep: View {
    let accentStyle: WalkthroughAccentStyle

    var body: some View {
        WalkthroughStepScrollView {
            WalkthroughAdaptivePair(
                primaryMinWidth: 360,
                secondaryMinWidth: 360
            ) {
                WalkthroughSurfaceCard {
                    VStack(alignment: .leading, spacing: 18) {
                        WalkthroughSectionTitle(
                            eyebrow: "Rebuilt experience",
                            title: "What changed since the last shipped version"
                        )

                        UpgradeHighlightCard(
                            title: "The player is now a modern SwiftUI surface",
                            message: "Mini mode, regular mode, detached mode, richer transitions, and better visual continuity across every surface.",
                            accent: WalkthroughFeature.modes.accentColor
                        )

                        UpgradeHighlightCard(
                            title: "Lyrics, credits, and provider-aware search are part of the main player",
                            message: "Search and discovery no longer feel like separate utility flows.",
                            accent: WalkthroughFeature.lyrics.accentColor
                        )

                        UpgradeHighlightCard(
                            title: "Settings are reorganized around display, playback, hotkeys, and system controls",
                            message: "The old utility-style layout has been replaced with a clearer native settings flow.",
                            accent: WalkthroughFeature.detached.accentColor
                        )
                    }
                }
            } secondary: {
                WalkthroughSurfaceCard(prominence: .subtle) {
                    UpgradeHeroCard(accentStyle: accentStyle)
                }
            }
        }
    }
}

private struct WalkthroughConnectStep: View {
    @Bindable var draft: WalkthroughDraftState
    let musicConnectionState: ProviderConnectionState
    let spotifyConnectionState: ProviderConnectionState
    let isMusicInstalled: Bool
    let isSpotifyInstalled: Bool
    let onOpenMusic: () -> Void
    let onOpenSpotify: () -> Void
    let onConnectMusic: () -> Void
    let onConnectSpotify: () -> Void
    let onOpenPrivacyHelp: () -> Void
    let onVerifyEnabledApps: () -> Void

    var body: some View {
        WalkthroughStepScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        ConnectionInstructionPill(
                            title: "What happens here",
                            message: "PlayStatus uses AppleScript to control Music or Spotify. macOS may ask whether the app can automate them."
                        )
                        .frame(minWidth: 280)

                        ConnectionInstructionPill(
                            title: "If a prompt does not appear",
                            message: "Retry once, then open Privacy & Security and check Automation if access still looks blocked."
                        )
                        .frame(minWidth: 280)
                    }

                    VStack(spacing: 14) {
                        ConnectionInstructionPill(
                            title: "What happens here",
                            message: "PlayStatus uses AppleScript to control Music or Spotify. macOS may ask whether the app can automate them."
                        )

                        ConnectionInstructionPill(
                            title: "If a prompt does not appear",
                            message: "Retry once, then open Privacy & Security and check Automation if access still looks blocked."
                        )
                    }
                }

                WalkthroughAdaptivePair(
                    primaryMinWidth: 330,
                    secondaryMinWidth: 330
                ) {
                    ProviderConnectCard(
                        provider: .music,
                        isEnabled: draft.enableMusic,
                        state: musicConnectionState,
                        isInstalled: isMusicInstalled,
                        onOpen: onOpenMusic,
                        onConnect: onConnectMusic
                    )
                } secondary: {
                    ProviderConnectCard(
                        provider: .spotify,
                        isEnabled: draft.enableSpotify,
                        state: spotifyConnectionState,
                        isInstalled: isSpotifyInstalled,
                        onOpen: onOpenSpotify,
                        onConnect: onConnectSpotify
                    )
                }

                WalkthroughSurfaceCard(prominence: .subtle) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Need help finding the privacy controls?")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))

                            Text("Open the relevant macOS privacy page, or keep going and retry later from the walkthrough or Settings.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Button {
                            onOpenPrivacyHelp()
                        } label: {
                            Label("Open Privacy Help", systemImage: "hand.raised")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            onVerifyEnabledApps()
                        } label: {
                            Label("Verify Enabled Apps", systemImage: "checkmark.shield")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

private struct WalkthroughExploreStep: View {
    @Binding var selectedFeature: WalkthroughFeature
    let preview: WalkthroughPreviewState

    var body: some View {
        WalkthroughStepScrollView {
            WalkthroughAdaptivePair(
                primaryMinWidth: 360,
                secondaryMinWidth: 480
            ) {
                WalkthroughSurfaceCard {
                    VStack(alignment: .leading, spacing: 18) {
                        WalkthroughSectionTitle(
                            eyebrow: "Feature tour",
                            title: preview.title
                        )

                        Text(preview.artist + " • " + preview.album)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(WalkthroughFeature.allCases) { feature in
                                FeatureChip(
                                    feature: feature,
                                    isSelected: selectedFeature == feature
                                ) {
                                    withAnimation(.smooth(duration: 0.12)) {
                                        selectedFeature = feature
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(selectedFeature.headline)
                                .font(.system(size: 20, weight: .bold, design: .rounded))

                            Text(selectedFeature.body)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        FeatureDetailsCard(feature: selectedFeature, provider: preview.provider)
                    }
                }
            } secondary: {
                WalkthroughSurfaceCard {
                    FeaturePreviewStage(
                        feature: selectedFeature,
                        preview: preview
                    )
                }
            }
        }
    }
}

private struct WalkthroughPersonalizeStep: View {
    @Bindable var draft: WalkthroughDraftState
    let onOpenSettings: () -> Void

    var body: some View {
        WalkthroughStepScrollView {
            WalkthroughAdaptivePair(
                primaryMinWidth: 360,
                secondaryMinWidth: 420
            ) {
                WalkthroughSurfaceCard {
                    VStack(alignment: .leading, spacing: 18) {
                        WalkthroughSectionTitle(
                            eyebrow: "Day one defaults",
                            title: "Tune the first-run feel before you close this window"
                        )

                        WalkthroughPickerRow(
                            title: "Display Mode",
                            caption: "Choose what the menu bar text emphasizes.",
                            selection: $draft.menuBarTextMode
                        )

                        WalkthroughPickerRow(
                            title: "Theme",
                            caption: "Set the general look of the player surfaces.",
                            selection: $draft.themeStyle
                        )

                        OnboardingToggleCard(
                            title: "Animated Artwork",
                            caption: "Adds subtle motion to album artwork when the current track supports it."
                        ) {
                            Toggle("", isOn: $draft.animatedArtworkEnabled)
                                .labelsHidden()
                        }

                        OnboardingToggleCard(
                            title: "Launch at login",
                            caption: "Keep PlayStatus ready as soon as you sign in."
                        ) {
                            Toggle("", isOn: $draft.launchAtLoginEnabled)
                                .labelsHidden()
                        }

                        Button {
                            onOpenSettings()
                        } label: {
                            Label("Open Hotkeys in Settings", systemImage: "keyboard")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } secondary: {
                WalkthroughSurfaceCard {
                    PersonalizationPreviewStage(draft: draft)
                }
            }
        }
    }
}

private struct WalkthroughFinishStep: View {
    let mode: OnboardingMode
    let onOpenSettings: () -> Void
    let onReplayFullWalkthrough: () -> Void
    let onReplayUpgradeWalkthrough: () -> Void

    var body: some View {
        WalkthroughStepScrollView {
            WalkthroughAdaptivePair(
                primaryMinWidth: 360,
                secondaryMinWidth: 360
            ) {
                WalkthroughSurfaceCard {
                    VStack(alignment: .leading, spacing: 18) {
                        WalkthroughSectionTitle(
                            eyebrow: "Quick habits",
                            title: "A few things worth remembering"
                        )

                        QuickHabitRow(
                            title: "Click the menu bar item for the main player",
                            message: "Use mini mode when you want something calmer and lighter."
                        )
                        QuickHabitRow(
                            title: "Open lyrics or credits only when you need them",
                            message: "The new details pane keeps the player tidy until you ask for more."
                        )
                        QuickHabitRow(
                            title: "Use Settings for deeper tuning",
                            message: "Display, playback, hotkeys, cache, updates, and launch behavior are all organized there now."
                        )
                    }
                }
            } secondary: {
                WalkthroughSurfaceCard {
                    VStack(alignment: .leading, spacing: 18) {
                        WalkthroughSectionTitle(
                            eyebrow: "Next actions",
                            title: "Jump straight into the parts you will revisit most"
                        )

                        FinishActionCard(
                            title: "Open Settings",
                            message: "Take the redesign further, wire up hotkeys, or change launch behavior.",
                            systemImage: "gearshape.2.fill",
                            accent: WalkthroughFeature.detached.accentColor,
                            action: onOpenSettings
                        )

                        FinishActionCard(
                            title: "Replay the full walkthrough",
                            message: "Bring this window back later if you want another guided pass through the app.",
                            systemImage: "arrow.clockwise.circle.fill",
                            accent: WalkthroughFeature.search.accentColor,
                            action: onReplayFullWalkthrough
                        )

                        if mode == .upgrade {
                            FinishActionCard(
                                title: "See the shorter update tour again",
                                message: "Keep the returning-user view handy if you mainly want the redesign highlights.",
                                systemImage: "sparkles.rectangle.stack.fill",
                                accent: WalkthroughFeature.lyrics.accentColor,
                                action: onReplayUpgradeWalkthrough
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct WelcomeHeroCard: View {
    let accentStyle: WalkthroughAccentStyle
    let provider: NowPlayingProvider
    let preferredProvider: PreferredProvider

    private var preferredCopy: String {
        switch preferredProvider {
        case .automatic:
            return "Auto can hand off to the best active player."
        case .music:
            return "Music is set to win when both apps are active."
        case .spotify:
            return "Spotify is set to win when both apps are active."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WalkthroughSectionTitle(
                eyebrow: "Visual direction",
                title: "Setup first, then explore one richer player"
            )

            Text("This relaunch is meant to be useful immediately: choose your sources now, then learn mini mode, search, lyrics, and detached mode from a single polished player surface.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            WalkthroughLightweightSurfaceStack(accent: accentStyle.tint, provider: provider)
                .frame(height: 218)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    FeaturePill(label: "Mini + Regular", color: WalkthroughFeature.modes.accentColor)
                    FeaturePill(label: "Lyrics + Credits", color: WalkthroughFeature.lyrics.accentColor)
                    FeaturePill(label: "Detached Window", color: WalkthroughFeature.detached.accentColor)
                }

                VStack(alignment: .leading, spacing: 8) {
                    FeaturePill(label: "Mini + Regular", color: WalkthroughFeature.modes.accentColor)
                    FeaturePill(label: "Lyrics + Credits", color: WalkthroughFeature.lyrics.accentColor)
                    FeaturePill(label: "Detached Window", color: WalkthroughFeature.detached.accentColor)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HeroNoteRow(
                    systemImage: "music.note.list",
                    title: "Provider-aware setup",
                    message: preferredCopy
                )
                HeroNoteRow(
                    systemImage: "sparkles",
                    title: "Faster first-run flow",
                    message: "The heavy feature preview now lives later in the tour so setup pages stay snappy."
                )
            }
        }
    }
}

private struct UpgradeHeroCard: View {
    let accentStyle: WalkthroughAccentStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WalkthroughSectionTitle(
                eyebrow: "Mental model",
                title: "Think of PlayStatus as one layered player now"
            )

            Text("Menu bar text, popover, details pane, and detached mode all follow the same design language. Search and discovery are now part of the player instead of separate utility flows.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            WalkthroughLightweightSurfaceStack(accent: accentStyle.tint, provider: .music)
                .frame(height: 218)

            VStack(alignment: .leading, spacing: 12) {
                HeroNoteRow(
                    systemImage: "sidebar.left",
                    title: "Cleaner navigation",
                    message: "Display, playback, hotkeys, and system controls are grouped where you expect them."
                )
                HeroNoteRow(
                    systemImage: "rectangle.on.rectangle",
                    title: "Richer surfaces",
                    message: "Mini mode, regular mode, and detached mode are all part of the same rebuilt experience."
                )
            }
        }
    }
}

private struct WalkthroughLightweightSurfaceStack: View {
    let accent: Color
    let provider: NowPlayingProvider

    private var providerLabel: String {
        provider == .spotify ? "Spotify ready" : "Music ready"
    }

    var body: some View {
        ZStack {
            WalkthroughBackdropCard(color: Color.black.opacity(0.10), size: CGSize(width: 260, height: 164), offset: CGSize(width: 34, height: 24))
            WalkthroughBackdropCard(color: accent.opacity(0.18), size: CGSize(width: 286, height: 176), offset: CGSize(width: 10, height: 8))

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .frame(width: 316, height: 188)
                .overlay(alignment: .topLeading) {
                    lightweightCardContent
                }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var lightweightCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            MenuBarChip(text: providerLabel, provider: provider)

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accent.opacity(0.22))
                    .frame(width: 96, height: 96)
                    .overlay(
                        ProviderIconView(icon: provider.iconKind, size: 34, weight: .semibold)
                            .foregroundStyle(accent)
                    )

                WalkthroughSurfaceSummaryColumn(accent: accent)
            }
        }
        .padding(20)
    }
}

private struct WalkthroughBackdropCard: View {
    let color: Color
    let size: CGSize
    let offset: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(color)
            .frame(width: size.width, height: size.height)
            .offset(x: offset.width, y: offset.height)
    }
}

private struct WalkthroughSurfaceSummaryColumn: View {
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.black.opacity(0.10))
                .frame(width: 124, height: 14)

            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .frame(width: 168, height: 10)

            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(accent.opacity(0.28))
                .frame(width: 144, height: 8)

            HStack(spacing: 10) {
                Circle().fill(Color.black.opacity(0.08)).frame(width: 26, height: 26)
                Circle().fill(accent.opacity(0.82)).frame(width: 32, height: 32)
                Circle().fill(Color.black.opacity(0.08)).frame(width: 26, height: 26)
            }
        }
    }
}

private struct HeroNoteRow: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.07))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CoachmarkBubble: View {
    let coachmark: CoachmarkID
    var accent: Color = Color.accentColor
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("New in PlayStatus")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .textCase(.uppercase)

                    Text(coachmark.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(coachmark.message)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Circle()
                    .fill(accent.opacity(0.88))
                    .frame(width: 6, height: 6)

                Text("Dismiss to keep exploring")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 200, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 6)
    }
}

private struct ConnectionInstructionPill: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))

                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .environment(\.colorScheme, .light)
        .foregroundStyle(WalkthroughPalette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(WalkthroughPalette.subtleSurfaceTop)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(WalkthroughPalette.border, lineWidth: 1)
                )
        )
    }
}

private struct ProviderConnectCard: View {
    let provider: NowPlayingProvider
    let isEnabled: Bool
    let state: ProviderConnectionState
    let isInstalled: Bool
    let onOpen: () -> Void
    let onConnect: () -> Void

    var body: some View {
        WalkthroughSurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProviderIconView(icon: provider.iconKind, size: 18, weight: .semibold)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.88))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text(isEnabled ? "Enabled in PlayStatus" : "Currently disabled in PlayStatus")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Open the app first if you want the Automation prompt to feel obvious. Then ask PlayStatus to verify the connection.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Label(state.label, systemImage: state.systemImage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(state.tint.opacity(0.10))
                    )

                HStack(spacing: 10) {
                    Button {
                        onOpen()
                    } label: {
                        Label("Open \(provider.displayName)", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isInstalled)

                    Button {
                        onConnect()
                    } label: {
                        Label(state == .testing ? "Checking..." : "Connect", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isEnabled || !isInstalled || state == .testing)
                }

                if !isInstalled {
                    Text("\(provider.displayName) is not currently installed on this Mac.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct FeatureChip: View {
    let feature: WalkthroughFeature
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(feature.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : feature.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? feature.accentColor : feature.accentColor.opacity(0.12))
                        .overlay(
                            Capsule()
                                .stroke(
                                    isSelected
                                        ? feature.accentColor.opacity(0.10)
                                        : feature.accentColor.opacity(isHovering ? 0.34 : 0.16),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .shadow(color: feature.accentColor.opacity(isHovering ? 0.18 : 0.0), radius: 8, x: 0, y: 4)
        .contentShape(Capsule())
        .animation(.smooth(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct FeaturePill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }
}

private struct FeatureDetailsCard: View {
    let feature: WalkthroughFeature
    let provider: NowPlayingProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why this matters")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            switch feature {
            case .modes:
                BenefitRow(text: "Mini mode is calmer for passive listening; regular mode is better for active control.")
                BenefitRow(text: "The same artwork and control language keeps both views feeling connected.")
            case .search:
                BenefitRow(text: "Spotify search opens instantly, while Music search can jump into your library.")
                BenefitRow(text: "The query follows whichever provider currently owns the player.")
            case .lyrics:
                BenefitRow(text: "Lyrics stay nearby instead of taking over the whole experience.")
                BenefitRow(text: provider == .music ? "Music can also expose favorites and stronger lyric flows." : "Credits remain available even when full lyrics are not.")
            case .detached:
                BenefitRow(text: "Detach the player for focused work, streaming, or coding sessions.")
                BenefitRow(text: "Keep it pinned on top or close it and return to the menu bar in one click.")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.74))
        )
    }
}

private struct BenefitRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.accentColor.opacity(0.92))
                .frame(width: 7, height: 7)
                .padding(.top, 5)

            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FinishActionCard: View {
    let title: String
    let message: String
    let systemImage: String
    let accent: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.16))
                        .frame(width: 44, height: 44)

                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(message)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isHovering ? accent : Color.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.76))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(accent.opacity(isHovering ? 0.34 : 0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .shadow(color: accent.opacity(isHovering ? 0.18 : 0.0), radius: 12, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.smooth(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct QuickHabitRow: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.74))
        )
    }
}

private struct UpgradeHighlightCard: View {
    let title: String
    let message: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(accent)
                    .frame(width: 22, height: 6)

                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }

            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.74))
        )
    }
}

private struct MenuBarChip: View {
    let text: String
    let provider: NowPlayingProvider

    var body: some View {
        HStack(spacing: 8) {
            ProviderIconView(icon: provider.iconKind, size: 12, weight: .semibold)
                .frame(width: 14, height: 14)

            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.76))
                .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
        )
    }
}


private struct FeaturePreviewStage: View, Equatable {
    let feature: WalkthroughFeature
    let preview: WalkthroughPreviewState

    var body: some View {
        switch feature {
        case .modes:
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 16) {
                    MiniPreviewCard(
                        artworkKey: preview.artworkKey,
                        provider: preview.provider,
                        title: preview.title
                    )
                    .frame(width: 190, height: 228)

                    RegularPreviewCard(preview: preview)
                        .frame(minWidth: 360, maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 16) {
                    MiniPreviewCard(
                        artworkKey: preview.artworkKey,
                        provider: preview.provider,
                        title: preview.title
                    )
                    .frame(width: 190, height: 228)

                    RegularPreviewCard(preview: preview)
                }
            }
        case .search:
            SearchPreviewCard(preview: preview)
        case .lyrics:
            LyricsPreviewCard(preview: preview)
        case .detached:
            DetachedPreviewCard(preview: preview)
        }
    }
}

private struct PersonalizationPreviewStage: View {
    @Bindable var draft: WalkthroughDraftState

    private var titleLine: String {
        switch draft.menuBarTextMode {
        case .artist:
            return "Glass Almanac"
        case .song:
            return "Paper Satellites"
        case .artistAndSong:
            return "Glass Almanac — Paper Satellites"
        case .iconOnly:
            return "PlayStatus"
        }
    }

    private var themeDescription: String {
        switch draft.themeStyle {
        case .artworkAdaptive:
            return "Artwork tinting will drive the palette."
        case .frosted:
            return "Frosted surfaces keep the player airy and bright."
        case .midnight:
            return "Midnight leans darker and more cinematic."
        case .warmStudio:
            return "Warm Studio adds a softer amber studio glow."
        case .highContrast:
            return "High Contrast sharpens edges and text clarity."
        case .graphite:
            return "Graphite keeps everything neutral and understated."
        }
    }

    private var themeAccent: LinearGradient {
        switch draft.themeStyle {
        case .artworkAdaptive:
            return LinearGradient(colors: [Color(red: 0.33, green: 0.59, blue: 0.96), Color(red: 0.66, green: 0.44, blue: 0.91)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .frosted:
            return LinearGradient(colors: [Color(red: 0.76, green: 0.88, blue: 0.98), Color(red: 0.63, green: 0.79, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .midnight:
            return LinearGradient(colors: [Color(red: 0.12, green: 0.14, blue: 0.24), Color(red: 0.24, green: 0.31, blue: 0.47)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .warmStudio:
            return LinearGradient(colors: [Color(red: 0.72, green: 0.43, blue: 0.28), Color(red: 0.94, green: 0.72, blue: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .highContrast:
            return LinearGradient(colors: [Color.black, Color(red: 0.24, green: 0.24, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .graphite:
            return LinearGradient(colors: [Color(red: 0.38, green: 0.41, blue: 0.45), Color(red: 0.57, green: 0.60, blue: 0.66)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 10) {
                MenuBarChip(text: titleLine, provider: draft.previewProvider)
                Spacer()
                FeaturePill(label: draft.menuBarTextMode.displayName, color: summaryAccent)
            }

            PersonalizationThemeHero(
                artworkKey: WalkthroughPreviewArtworkKey(provider: draft.previewProvider, variant: 2),
                provider: draft.previewProvider,
                themeStyle: draft.themeStyle,
                themeDescription: themeDescription,
                accent: themeAccent
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    PersonalizationSummaryTile(
                        title: "Display Mode",
                        value: draft.menuBarTextMode.displayName,
                        message: "Shapes the menu bar label you see most often.",
                        accent: summaryAccent
                    )
                    PersonalizationSummaryTile(
                        title: "Artwork Motion",
                        value: draft.animatedArtworkEnabled ? "On" : "Off",
                        message: draft.animatedArtworkEnabled ? "Animated artwork stays expressive." : "Motion stays calmer by default.",
                        accent: Color(red: 0.87, green: 0.55, blue: 0.77)
                    )
                    PersonalizationSummaryTile(
                        title: "Launch Behavior",
                        value: draft.launchAtLoginEnabled ? "Start at login" : "Manual launch",
                        message: draft.launchAtLoginEnabled ? "PlayStatus is ready when you sign in." : "Startup stays lighter until you open it.",
                        accent: Color(red: 0.53, green: 0.83, blue: 0.63)
                    )
                }

                VStack(spacing: 12) {
                    PersonalizationSummaryTile(
                        title: "Display Mode",
                        value: draft.menuBarTextMode.displayName,
                        message: "Shapes the menu bar label you see most often.",
                        accent: summaryAccent
                    )
                    PersonalizationSummaryTile(
                        title: "Artwork Motion",
                        value: draft.animatedArtworkEnabled ? "On" : "Off",
                        message: draft.animatedArtworkEnabled ? "Animated artwork stays expressive." : "Motion stays calmer by default.",
                        accent: Color(red: 0.87, green: 0.55, blue: 0.77)
                    )
                    PersonalizationSummaryTile(
                        title: "Launch Behavior",
                        value: draft.launchAtLoginEnabled ? "Start at login" : "Manual launch",
                        message: draft.launchAtLoginEnabled ? "PlayStatus is ready when you sign in." : "Startup stays lighter until you open it.",
                        accent: Color(red: 0.53, green: 0.83, blue: 0.63)
                    )
                }
            }
        }
    }

    private var summaryAccent: Color {
        switch draft.themeStyle {
        case .artworkAdaptive:
            return Color(red: 0.33, green: 0.59, blue: 0.96)
        case .frosted:
            return Color(red: 0.63, green: 0.79, blue: 0.93)
        case .midnight:
            return Color(red: 0.24, green: 0.31, blue: 0.47)
        case .warmStudio:
            return Color(red: 0.94, green: 0.72, blue: 0.42)
        case .highContrast:
            return Color.black.opacity(0.88)
        case .graphite:
            return Color(red: 0.57, green: 0.60, blue: 0.66)
        }
    }
}

private struct PersonalizationThemeHero: View {
    let artworkKey: WalkthroughPreviewArtworkKey
    let provider: NowPlayingProvider
    let themeStyle: ThemeStyle
    let themeDescription: String
    let accent: LinearGradient

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(accent)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
            .frame(height: 176)
            .overlay(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 16) {
                    artworkCard
                    themeSummary
                    Spacer(minLength: 0)
                }
                .padding(18)
            }
            .overlay(alignment: .bottomTrailing) {
                trailingThemeCard
                    .padding(16)
            }
    }

    private var artworkCard: some View {
        WalkthroughArtworkSnapshot(artworkKey: artworkKey, cornerRadius: 20)
            .frame(width: 108, height: 108)
            .shadow(color: .black.opacity(0.20), radius: 10, x: 0, y: 6)
    }

    private var themeSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProviderIconView(icon: provider.iconKind, size: 13, weight: .bold)
                    .frame(width: 16, height: 16)
                Text("Theme Preview")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .textCase(.uppercase)
            }

            Text(themeStyle.displayName)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.98))

            Text(themeDescription)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                PreviewSmallControl(systemImage: "music.note")
                PreviewSmallControl(systemImage: "waveform")
                PreviewSmallControl(systemImage: "sparkles")
            }
        }
    }

    private var trailingThemeCard: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.18))
            .frame(width: 148, height: 64)
            .overlay(
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.82))
                        .frame(width: 88, height: 8)
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.46))
                        .frame(width: 120, height: 6)
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 72, height: 6)
                }
                .padding(14)
            )
    }
}

private struct PersonalizationSummaryTile: View {
    let title: String
    let value: String
    let message: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent.opacity(0.88))
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))

            Text(message)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.74))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accent.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct WalkthroughArtworkSnapshot: View, Equatable {
    let artworkKey: WalkthroughPreviewArtworkKey
    var cornerRadius: CGFloat = 22

    var body: some View {
        Image(nsImage: WalkthroughPreviewAssets.shared.image(for: artworkKey))
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

private struct MiniPreviewCard: View, Equatable {
    let artworkKey: WalkthroughPreviewArtworkKey
    let provider: NowPlayingProvider
    let title: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WalkthroughArtworkSnapshot(artworkKey: artworkKey, cornerRadius: 24)

            LinearGradient(
                colors: [.clear, .black.opacity(0.70)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(.rect(cornerRadius: 24))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProviderIconView(icon: provider.iconKind, size: 14, weight: .semibold)
                        .frame(width: 15, height: 15)
                    Text("Mini Mode")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.95))

                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.98))

                Text("Hover to expand controls")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(16)
        }
        .clipShape(.rect(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
    }
}

private struct RegularPreviewCard: View, Equatable {
    let preview: WalkthroughPreviewState

    var body: some View {
        VStack(spacing: 0) {
            WalkthroughArtworkMetadataLayout(
                artworkKey: preview.artworkKey,
                artworkSize: 142,
                cornerRadius: 20,
                horizontalSpacing: 18
            ) {
                previewMetadata
            }
            .padding(20)

            Divider()

            previewToolbar
        }
        .background(RegularPreviewCardChrome())
        .clipShape(.rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 6)
    }

    private var previewToolbar: some View {
        HStack {
            SearchCapsulePreview(text: preview.provider == .spotify ? "Search Spotify" : "Search Music")
            Spacer()
            PreviewSmallControl(systemImage: "quote.bubble")
            PreviewSmallControl(systemImage: "info.circle")
            PreviewSmallControl(systemImage: "gearshape.fill")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var previewMetadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProviderIconView(icon: preview.provider.iconKind, size: 14, weight: .semibold)
                    .frame(width: 16, height: 16)
                Text(preview.provider.displayName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text(preview.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text(preview.artist + " • " + preview.album)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.accentColor.opacity(0.82))
                        .frame(width: 120, height: 6)
                }

            HStack(spacing: 16) {
                PreviewTransportButton(systemImage: "backward.fill")
                PreviewTransportButton(systemImage: preview.isPlaying ? "pause.fill" : "play.fill", prominence: .prominent)
                PreviewTransportButton(systemImage: "forward.fill")
            }
        }
    }
}

private struct RegularPreviewCardChrome: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct SearchPreviewCard: View, Equatable {
    let preview: WalkthroughPreviewState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                SearchCapsulePreview(text: preview.provider == .spotify ? "Search Spotify" : "Search Music")
                Button("Open") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            }

            HStack(alignment: .top, spacing: 16) {
                WalkthroughArtworkSnapshot(artworkKey: preview.artworkKey, cornerRadius: 20)
                    .frame(width: 136, height: 136)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProviderIconView(icon: preview.provider.iconKind, size: 14, weight: .semibold)
                            .frame(width: 16, height: 16)
                        Text(preview.provider.displayName + " search handoff")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Text(preview.searchText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text(preview.provider == .spotify ? "Spotify opens the matching search immediately." : "Music can play from your local library when the query matches.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.80))
            )
        }
    }
}

private struct LyricsPreviewCard: View, Equatable {
    let preview: WalkthroughPreviewState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                WalkthroughArtworkSnapshot(artworkKey: preview.artworkKey, cornerRadius: 20)
                    .frame(width: 126, height: 126)

                VStack(alignment: .leading, spacing: 8) {
                    Text(preview.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(preview.artist + " • " + preview.album)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        FeaturePill(label: "Lyrics", color: WalkthroughFeature.lyrics.accentColor)
                        FeaturePill(label: "Credits", color: WalkthroughFeature.search.accentColor)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(preview.lyricsLines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: index == 1 ? 14 : 12, weight: index == 1 ? .bold : .medium, design: .rounded))
                        .foregroundStyle(index == 1 ? Color.primary : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(index == 1 ? WalkthroughFeature.lyrics.accentColor.opacity(0.16) : Color.white.opacity(0.70))
                        )
                }
            }
        }
    }
}

private struct DetachedPreviewCard: View, Equatable {
    let preview: WalkthroughPreviewState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.06))

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    WalkthroughTrafficLights()
                    Spacer()
                    Text("Detached Player")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    PreviewSmallControl(systemImage: "pin.fill")
                    PreviewSmallControl(systemImage: "xmark")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.74))

                WalkthroughArtworkMetadataLayout(
                    artworkKey: preview.artworkKey,
                    artworkSize: 140,
                    cornerRadius: 20,
                    horizontalSpacing: 16
                ) {
                    detachedMetadata
                }
                .padding(22)
                .background(Color.white.opacity(0.80))
            }
            .clipShape(.rect(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .frame(minWidth: 320, idealWidth: 420, maxWidth: 420)
            .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 6)
        }
    }

    private var detachedMetadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(preview.artist + " • " + preview.album)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.black.opacity(0.10))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(WalkthroughFeature.detached.accentColor.opacity(0.86))
                        .frame(width: 150, height: 6)
                }
            HStack(spacing: 16) {
                PreviewTransportButton(systemImage: "backward.fill")
                PreviewTransportButton(systemImage: preview.isPlaying ? "pause.fill" : "play.fill", prominence: .prominent)
                PreviewTransportButton(systemImage: "forward.fill")
            }
        }
    }
}

private struct WalkthroughArtworkMetadataLayout<Metadata: View>: View {
    let artworkKey: WalkthroughPreviewArtworkKey
    let artworkSize: CGFloat
    let cornerRadius: CGFloat
    let horizontalSpacing: CGFloat
    @ViewBuilder let metadata: () -> Metadata

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: horizontalSpacing) {
                artwork
                metadata()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 16) {
                artwork
                metadata()
            }
        }
    }

    private var artwork: some View {
        WalkthroughArtworkSnapshot(artworkKey: artworkKey, cornerRadius: cornerRadius)
            .frame(width: artworkSize, height: artworkSize)
    }
}

private struct WalkthroughTrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red.opacity(0.82)).frame(width: 10, height: 10)
            Circle().fill(Color.orange.opacity(0.86)).frame(width: 10, height: 10)
            Circle().fill(Color.green.opacity(0.82)).frame(width: 10, height: 10)
        }
    }
}

private enum PreviewTransportProminence {
    case normal
    case prominent
}

private struct PreviewTransportButton: View {
    let systemImage: String
    var prominence: PreviewTransportProminence = .normal

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: prominence == .prominent ? 16 : 13, weight: .bold))
            .foregroundStyle(prominence == .prominent ? Color.white.opacity(0.96) : Color.primary.opacity(0.86))
            .frame(width: prominence == .prominent ? 42 : 34, height: prominence == .prominent ? 42 : 34)
            .background(
                Circle()
                    .fill(prominence == .prominent ? Color.accentColor.opacity(0.92) : Color.black.opacity(0.08))
            )
    }
}

private struct PreviewSmallControl: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.06))
            )
    }
}

private struct SearchCapsulePreview: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.07))
        )
    }
}
