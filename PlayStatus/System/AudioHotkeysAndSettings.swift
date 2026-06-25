import SwiftUI
import AppKit

struct PlayStatusSettingsView: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var onboarding: OnboardingCoordinator
    @State private var selectedTab: SettingsTab = .display
    @State private var tabDirection: SettingsTabDirection = .forward
    @State private var showAnimatedStreamPreview = false
    @State private var showHoverMotionStylePreview = false
    @State private var settingsContentLoaded = false

    var body: some View {
        Group {
            if settingsContentLoaded {
                settingsContent
                    .sheet(isPresented: $showAnimatedStreamPreview) {
                        AnimatedArtworkStreamPreviewSheet(
                            model: model,
                            demoStreamURL: defaultAnimatedArtworkDemoStreamURL
                        )
                    }
                    .sheet(isPresented: $showHoverMotionStylePreview) {
                        HoverMotionStylePreviewSheet(model: model)
                    }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: settingsWindowSize.width, height: settingsWindowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            SettingsSceneVisibilityBridge(
                targetSize: settingsWindowSize,
                appearanceMode: model.appAppearanceMode,
                isContentLoaded: $settingsContentLoaded
            )
        )
        .onChange(of: settingsContentLoaded) { _, isLoaded in
            guard !isLoaded else { return }
            showAnimatedStreamPreview = false
            showHoverMotionStylePreview = false
        }
        .environment(\.controlActiveState, .key)
        .preferredColorScheme(model.appAppearanceMode.colorScheme)
    }

    private var settingsContent: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selectedTab: tabSelection, onboarding: onboarding)

            Divider()

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear
                            .frame(height: 0)
                            .id("settings-top")

                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 18) {
                                SettingsPageHeader(tab: selectedTab)
                                tabContent
                            }
                            .id(selectedTab.rawValue)
                            .transition(tabTransition)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: selectedTab)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: selectedTab) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo("settings-top", anchor: .top)
                    }
                }
                .background(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor),
                            Color(nsColor: .underPageBackgroundColor).opacity(0.65)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    private var tabSelection: Binding<SettingsTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                guard newValue != selectedTab else { return }
                tabDirection = newValue.sortIndex >= selectedTab.sortIndex ? .forward : .backward
                selectedTab = newValue
            }
        )
    }

    private var tabTransition: AnyTransition {
        let insertion: Edge = tabDirection == .forward ? .trailing : .leading
        let removal: Edge = tabDirection == .forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }

    private var settingsWindowSize: CGSize {
        let widths = SettingsTab.allCases.map(\.preferredSize.width)
        let heights = SettingsTab.allCases.map(\.preferredSize.height)
        return CGSize(width: widths.max() ?? 780, height: heights.max() ?? 640)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .display:
            displayContent
        case .playback:
            playbackContent
        case .hotkeys:
            hotkeysContent
        case .system:
            systemContent
        case .license:
            licenseContent
        }
    }

    private var displayContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsControlRow(
                title: "Display Mode",
                caption: "Changes the status text format in the menubar."
            ) {
                Picker("Display Mode", selection: Binding(
                    get: { model.menuBarTextMode },
                    set: { model.menuBarTextMode = $0 }
                )) {
                    ForEach(MenuBarTextMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            Divider().padding(.vertical, 2)

            SettingsToggleRow(
                title: "Ignore (...) in title",
                caption: "Removes parenthetical fragments from song titles.",
                isOn: $model.ignoreParentheses
            )
            SettingsToggleRow(
                title: "Scrollable title",
                caption: "Allows long track names to scroll in the menu bar.",
                isOn: $model.scrollableTitle
            )
            SettingsToggleRow(
                title: "Slide title on new song",
                caption: "Animates title transitions when tracks change.",
                isOn: $model.slideTitleOnChange
            )
            SettingsToggleRow(
                title: "Detached window stays on top",
                caption: "Keeps the detached now-playing window floating above normal windows.",
                isOn: $model.detachedWindowAlwaysOnTop
            )

            SettingsControlRow(
                title: "Detached window size",
                caption: "Chooses the standalone detached window size preset."
            ) {
                Picker("Detached window size", selection: Binding(
                    get: { model.detachedWindowSizePreset },
                    set: { model.detachedWindowSizePreset = $0 }
                )) {
                    ForEach(DetachedWindowSizePreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            Divider().padding(.vertical, 2)

            SettingsSliderRow(
                title: "Title Width",
                caption: "Maximum width before menu bar text truncates/scrolls (if enabled).",
                value: Binding(
                    get: { model.statusTextWidthValue },
                    set: { model.statusTextWidthValue = $0 }
                ),
                range: 80...320,
                valueText: "\(Int(model.statusTextWidthValue)) px"
            )

            Divider().padding(.vertical, 2)

            SettingsSliderRow(
                title: "Artwork Color Intensity",
                caption: "Controls how strongly theme colors tint the popover and detached player.",
                value: Binding(
                    get: { model.artworkColorIntensity },
                    set: { model.artworkColorIntensity = $0 }
                ),
                range: 0.5...1.8,
                valueText: "\(Int(model.artworkColorIntensity * 100))%"
            )

            Divider().padding(.vertical, 2)

            SettingsControlRow(
                title: "Appearance",
                caption: "Controls light or dark rendering for PlayStatus windows; themes still control player styling."
            ) {
                Picker("Appearance", selection: Binding(
                    get: { model.appAppearanceMode },
                    set: { model.appAppearanceMode = $0 }
                )) {
                    ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            Divider().padding(.vertical, 2)

            SettingsControlRow(
                title: "Theme",
                caption: "Chooses the visual treatment used for the player surfaces."
            ) {
                Picker("Theme", selection: Binding(
                    get: { model.themeStyle },
                    set: { model.themeStyle = $0 }
                )) {
                    ForEach(ThemeStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            if model.themeStyle != .artworkAdaptive {
                SettingsSliderRow(
                    title: "Album Color Blend",
                    caption: "Mixes the current artwork colors into the selected theme preset.",
                    value: Binding(
                        get: { model.themeArtworkBlend },
                        set: { model.themeArtworkBlend = $0 }
                    ),
                    range: 0...1,
                    valueText: "\(Int(model.themeArtworkBlend * 100))%"
                )
            }

            Divider().padding(.vertical, 2)

            SettingsToggleRow(
                title: "Animated Artwork",
                caption: "Adds subtle motion to album artwork in the popover.",
                isOn: $model.animatedArtworkEnabled
            )

            if model.animatedArtworkEnabled {
                SettingsToggleRow(
                    title: "Animated Artwork Streams",
                    caption: "Uses Apple Music editorial video streams when available. This can increase media cache usage.",
                    isOn: $model.animatedArtworkStreamsEnabled
                )

                if model.animatedArtworkStreamsEnabled {
                    SettingsToggleRow(
                        title: "Crop Streams to Square",
                        caption: "Fills the artwork tile by cropping the edges of non-square animated streams. Turn this off to show the complete video frame.",
                        isOn: $model.cropAnimatedArtworkToSquare
                    )

                    Divider().padding(.vertical, 2)

                    SettingsControlRow(
                        title: "Animated Stream Quality",
                        caption: "Sets default playback quality for animated artwork streams."
                    ) {
                        Picker("Animated Stream Quality", selection: Binding(
                            get: { model.animatedArtworkQualityPolicy },
                            set: { model.animatedArtworkQualityPolicy = $0 }
                        )) {
                            ForEach(AnimatedArtworkQualityPolicy.allCases, id: \.self) { policy in
                                Text(policy.displayName).tag(policy)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 220, alignment: .trailing)
                    }

                    SettingsControlRow(
                        title: "Animated Stream Status",
                        caption: "Current lookup status from public Apple Music album pages."
                    ) {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(model.animatedArtworkStatusMessage)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)

                            if !model.animatedArtworkLastError.isEmpty {
                                Text(model.animatedArtworkLastError)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 260, alignment: .trailing)
                            }
                        }
                    }

                    SettingsControlRow(
                        title: "Stream Preview",
                        caption: "Opens a help preview using the current stream, or a built-in demo stream when unavailable."
                    ) {
                        VStack(alignment: .trailing, spacing: 4) {
                            Button {
                                showAnimatedStreamPreview = true
                            } label: {
                                Label("Open Preview", systemImage: "play.rectangle")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if model.effectiveAnimatedArtworkURL == nil {
                                Text("Current track has no animated stream. Preview will show a built-in demo.")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 260, alignment: .trailing)
                            }
                        }
                    }
                }

                Divider().padding(.vertical, 2)

                SettingsControlRow(
                    title: "Artwork Motion Style",
                    caption: "Sets the character of motion applied to album artwork."
                ) {
                    Picker("Motion Style", selection: Binding(
                        get: { model.artworkMotionStyle },
                        set: { model.artworkMotionStyle = $0 }
                    )) {
                        ForEach(ArtworkMotionStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }

                SettingsControlRow(
                    title: "Motion Style Preview",
                    caption: "Opens a help preview showing how each artwork motion style behaves."
                ) {
                    Button {
                        showHoverMotionStylePreview = true
                    } label: {
                        Label("Open Preview", systemImage: "rectangle.stack")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var playbackContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsControlRow(
                title: "Preferred App",
                caption: "Used when multiple players are running."
            ) {
                Picker("Preferred App", selection: Binding(
                    get: { model.preferredProvider },
                    set: { model.preferredProvider = $0 }
                )) {
                    ForEach(PreferredProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            Divider().padding(.vertical, 2)

            SettingsControlRow(
                title: "Automatic Priority",
                caption: "Fallback ordering when no preferred source is active."
            ) {
                Picker("Automatic Priority", selection: Binding(
                    get: { model.providerPriority },
                    set: { model.providerPriority = $0 }
                )) {
                    ForEach(ProviderPriority.allCases, id: \.self) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            Divider().padding(.vertical, 2)

            SettingsToggleRow(
                title: "Enable Music",
                caption: "Allow Apple Music to provide now playing data.",
                isOn: $model.enableMusic
            )
            SettingsToggleRow(
                title: "Enable Spotify",
                caption: "Allow Spotify to provide now playing data.",
                isOn: $model.enableSpotify
            )

            Divider().padding(.vertical, 2)

            SettingsToggleRow(
                title: "Expand Details by Default",
                caption: "Opens the lower details pane automatically for new tracks.",
                isOn: $model.expandLyricsByDefault
            )

            SettingsControlRow(
                title: "Lyrics Pane Size",
                caption: "Controls how much vertical space lyrics and credits get in the player."
            ) {
                Picker("Lyrics Pane Size", selection: Binding(
                    get: { model.lyricsPaneSizePreset },
                    set: { model.lyricsPaneSizePreset = $0 }
                )) {
                    ForEach(LyricsPaneSizePreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            SettingsControlRow(
                title: "Lyrics Font Preset",
                caption: "Quickly switches between common lyric text sizes."
            ) {
                Picker("Lyrics Font Size", selection: Binding(
                    get: { model.lyricsFontSizePreset },
                    set: { model.lyricsFontSizePreset = $0 }
                )) {
                    ForEach(LyricsFontSizePreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            SettingsSliderRow(
                title: "Custom Lyrics Font Size",
                caption: "Fine-tunes lyric text size; moving this slider switches the preset to Custom.",
                value: Binding(
                    get: { model.lyricsCustomFontSize },
                    set: { model.lyricsCustomFontSize = $0 }
                ),
                range: LyricsFontSizePreset.customSizeRange,
                valueText: String(format: "%.1f pt", model.lyricsCustomFontSize)
            )
        }
    }

    private var systemContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsControlRow(
                title: "Walkthrough",
                caption: "Replay the relaunch setup tour or re-open the shorter update tour."
            ) {
                HStack(spacing: 8) {
                    Button {
                        onboarding.replayFullWalkthrough()
                    } label: {
                        Label("Replay Full Tour", systemImage: "sparkles.rectangle.stack")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        onboarding.presentUpgradeWalkthrough()
                    } label: {
                        Label("What’s New", systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider().padding(.vertical, 2)

            SettingsToggleRow(
                title: "Debug Coachmarks",
                caption: "Temporarily re-arms the player coachmarks, opens the main popover, and lets you inspect the live UI hints again.",
                isOn: Binding(
                    get: { onboarding.debugCoachmarksEnabled },
                    set: { onboarding.setDebugCoachmarksEnabled($0) }
                )
            )

            if onboarding.debugCoachmarksEnabled {
                SettingsNoteCard(
                    text: "Dismissals stay in this debug session only while this toggle is enabled. Turn it off and back on to restart the player sequence from the main popover."
                )
            }

            Divider().padding(.vertical, 2)

            SettingsToggleRow(
                title: "Launch at login",
                caption: "Start PlayStatus automatically when you sign in.",
                isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin(enabled: $0) }
                )
            )

            Divider().padding(.vertical, 2)

            SettingsControlRow(
                title: "App Updates",
                caption: "Check for newer PlayStatus builds through Sparkle."
            ) {
                Button {
                    SparkleUpdater.shared.checkForUpdates(nil)
                } label: {
                    Label("Check Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Divider().padding(.vertical, 2)

            SettingsControlRow(
                title: "Media Cache",
                caption: "Stores lyrics and artwork locally (max 50 MB). Animated artwork streams can increase usage."
            ) {
                HStack(spacing: 10) {
                    Text(model.persistentCacheUsageText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button("Clear Cache") {
                        model.clearPersistentCache()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isClearingPersistentCache)

                    if model.isClearingPersistentCache {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Divider().padding(.vertical, 2)

            SettingsToggleRow(
                title: "Reduce Hidden Memory Usage",
                caption: "Releases artwork, animated streams, and transient image caches when all PlayStatus surfaces are closed.",
                isOn: $model.reduceHiddenMemoryUsage
            )

            SettingsNoteCard(
                text: "When enabled, reopening the popover or detached window can briefly show placeholder artwork while visuals reload. Animated artwork may take an extra moment to come back on paused or recently hidden tracks."
            )
        }
        .onAppear {
            model.refreshPersistentCacheStats()
        }
    }

    private var hotkeysContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(AppHotkeyAction.allCases, id: \.self) { action in
                HotkeyRecorderRow(action: action)
            }
        }
    }

    private var licenseContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            Text("Lyrics Attribution and Disclaimer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Text(lrclibAttributionAndDisclaimerText)
                .textSelection(.enabled)
                .font(.system(size: 12, weight: .regular,design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.10), lineWidth: 1)
                        )
                )
            
            Divider()
                .foregroundStyle(.separator)
            Text("PlayStatus is distributed under the MIT License.")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
            
            Text(mitLicenseText)
                .textSelection(.enabled)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
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

    private var lrclibAttributionAndDisclaimerText: String {
        """
        PlayStatus may fetch lyrics from LRCLIB (https://lrclib.net) using LRCLIB's public API.

        Lyrics are provided by third-party sources and may be inaccurate, incomplete, or unavailable. You are solely responsible for ensuring your use of lyrics complies with all applicable laws, licenses, and third-party terms.

        By using PlayStatus lyrics features, you assume all risk. To the fullest extent permitted by law, the PlayStatus author and contributors disclaim liability for any claims, damages, losses, or legal issues arising from the fetching, display, storage, or use of third-party lyrics.
        """
    }

    private var mitLicenseText: String {
        """
        MIT License

        Copyright (c) 2019-2026 Nikhil Bolar

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """
    }
}


private struct HotkeyRecorderRow: View {
    let action: AppHotkeyAction

    @State private var binding: HotkeyBinding
    @State private var isRecording = false
    @State private var monitor: Any?

    init(action: AppHotkeyAction) {
        self.action = action
        _binding = State(initialValue: HotkeyStore.binding(for: action))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(action.label)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)

            Text(hotkeyDisplayString(binding))
                .foregroundStyle(.secondary)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())

            Button(isRecording ? "Press keys..." : "Record") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Clear") {
                HotkeyStore.resetBinding(for: action)
                binding = action.defaultBinding
                stopRecording()
                HotkeyManager.shared.registerAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let modifiers = carbonModifiers(from: flags)
            if modifiers == 0 {
                NSSound.beep()
                return nil
            }
            let captured = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            HotkeyStore.setBinding(captured, for: action)
            binding = captured
            stopRecording()
            HotkeyManager.shared.registerAll()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

private struct SettingsSceneVisibilityBridge: NSViewRepresentable {
    let targetSize: CGSize
    let appearanceMode: AppAppearanceMode
    @Binding var isContentLoaded: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isContentLoaded: $isContentLoaded,
            targetSize: targetSize,
            appearanceMode: appearanceMode
        )
    }

    func makeNSView(context: Context) -> SettingsSceneBridgeView {
        let view = SettingsSceneBridgeView(frame: .zero)
        view.onWindowChanged = { window in
            context.coordinator.attach(to: window)
        }
        DispatchQueue.main.async {
            context.coordinator.update(targetSize: targetSize, appearanceMode: appearanceMode)
        }
        return view
    }

    func updateNSView(_ nsView: SettingsSceneBridgeView, context: Context) {
        nsView.onWindowChanged = { window in
            context.coordinator.attach(to: window)
        }
        DispatchQueue.main.async {
            context.coordinator.update(targetSize: targetSize, appearanceMode: appearanceMode)
        }
    }

    final class Coordinator {
        private var windowObservers: [NSObjectProtocol] = []
        private weak var window: NSWindow?
        private var isContentLoaded: Binding<Bool>
        private var targetSize: CGSize
        private var appearanceMode: AppAppearanceMode
        var lastAppliedSize: CGSize?

        init(
            isContentLoaded: Binding<Bool>,
            targetSize: CGSize,
            appearanceMode: AppAppearanceMode
        ) {
            self.isContentLoaded = isContentLoaded
            self.targetSize = targetSize
            self.appearanceMode = appearanceMode
        }

        deinit {
            removeObservers()
        }

        func update(targetSize: CGSize, appearanceMode: AppAppearanceMode) {
            self.targetSize = targetSize
            self.appearanceMode = appearanceMode
            refresh()
        }

        func attach(to newWindow: NSWindow?) {
            guard window !== newWindow else {
                refresh()
                return
            }

            removeObservers()
            window = newWindow
            lastAppliedSize = nil

            guard let newWindow else {
                updateContentLoaded(false)
                return
            }

            let center = NotificationCenter.default
            windowObservers = [
                center.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: newWindow,
                    queue: .main
                ) { [weak self] _ in
                    self?.refresh()
                },
                center.addObserver(
                    forName: NSWindow.didDeminiaturizeNotification,
                    object: newWindow,
                    queue: .main
                ) { [weak self] _ in
                    self?.refresh()
                },
                center.addObserver(
                    forName: NSWindow.didMiniaturizeNotification,
                    object: newWindow,
                    queue: .main
                ) { [weak self] _ in
                    self?.refresh()
                },
                center.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: newWindow,
                    queue: .main
                ) { [weak self] _ in
                    self?.updateContentLoaded(false)
                }
            ]

            refresh()
        }

        func refresh() {
            guard let window else {
                updateContentLoaded(false)
                return
            }

            applyConfiguration(to: window)
            updateContentLoaded(window.isVisible && !window.isMiniaturized)
        }

        private func applyConfiguration(to window: NSWindow) {
            window.appearance = appearanceMode.nsAppearance
            window.contentView?.appearance = appearanceMode.nsAppearance
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.remove(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isHidden = false
            resizeWindowIfNeeded(window: window, targetSize: targetSize)
        }

        private func resizeWindowIfNeeded(window: NSWindow, targetSize: CGSize) {
            guard lastAppliedSize != targetSize else { return }

            var frame = window.frame
            let oldHeight = frame.height
            frame.size = targetSize
            frame.origin.y += oldHeight - targetSize.height

            if lastAppliedSize == nil {
                window.setFrame(frame, display: true)
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.24
                    context.allowsImplicitAnimation = true
                    window.animator().setFrame(frame, display: true)
                }
            }

            lastAppliedSize = targetSize
        }

        private func updateContentLoaded(_ newValue: Bool) {
            guard isContentLoaded.wrappedValue != newValue else { return }
            isContentLoaded.wrappedValue = newValue
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            for observer in windowObservers {
                center.removeObserver(observer)
            }
            windowObservers.removeAll(keepingCapacity: false)
        }
    }
}

private final class SettingsSceneBridgeView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.onWindowChanged?(self?.window)
        }
    }
}
