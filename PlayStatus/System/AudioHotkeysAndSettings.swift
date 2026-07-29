import SwiftUI
import AppKit

struct PlayStatusSettingsView: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var onboarding: OnboardingCoordinator
    @ObservedObject private var connectionInspector = ProviderConnectionInspector.shared
    @State private var selectedTab: SettingsTab = .menuBar
    @State private var tabDirection: SettingsTabDirection = .forward
    @State private var showAnimatedStreamPreview = false
    @State private var showHoverMotionStylePreview = false
    @State private var settingsContentLoaded = false
    @State private var isAdvancedExpanded = false
    @State private var isLicenseExpanded = false

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
                .background(Color(nsColor: .windowBackgroundColor))
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
        SettingsTab.windowSize
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .menuBar:
            menuBarContent
        case .playerWindow:
            playerWindowContent
        case .appearance:
            appearanceContent
        case .artworkMotion:
            artworkMotionContent
        case .sources:
            sourcesContent
        case .shortcuts:
            shortcutsContent
        case .general:
            generalContent
        case .about:
            aboutContent
        }
    }

    // MARK: - Look

    private var menuBarContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            MenuBarPreviewStrip(model: model)

            SettingsCard {
                SettingsSegmentedRow(
                    title: "Show",
                    selection: Binding(
                        get: { model.menuBarTextMode },
                        set: { model.menuBarTextMode = $0 }
                    ),
                    options: MenuBarTextMode.allCases,
                    optionLabel: { $0.displayName }
                )

                SettingsRowDivider()

                SettingsSwitchRow(
                    title: "Hide text in parentheses",
                    caption: "“Get Lucky (Radio Edit)” → “Get Lucky”",
                    isOn: $model.ignoreParentheses
                )
            }

            SettingsCard {
                SettingsSwitchRow(
                    title: "Scroll long titles",
                    caption: "Only applies when the title exceeds the maximum width",
                    isOn: $model.scrollableTitle
                )

                SettingsRowDivider()

                SettingsSwitchRow(
                    title: "Slide in on track change",
                    isOn: $model.slideTitleOnChange
                )

                SettingsRowDivider()

                SettingsInlineSliderRow(
                    title: "Maximum width",
                    value: Binding(
                        get: { model.statusTextWidthValue },
                        set: { model.statusTextWidthValue = $0 }
                    ),
                    range: 80...320,
                    valueText: "\(Int(model.statusTextWidthValue)) px"
                )
            }
        }
    }

    private var playerWindowContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(header: "From the menu bar") {
                SettingsSegmentedRow(
                    title: "Popover size",
                    selection: Binding(
                        get: { model.popoverSizePreset },
                        set: { model.popoverSizePreset = $0 }
                    ),
                    options: PopoverSizePreset.allCases,
                    optionLabel: { $0.displayName }
                )
            }

            SettingsCard(header: "Detached window") {
                SettingsSegmentedRow(
                    title: "Size",
                    selection: Binding(
                        get: { model.detachedWindowSizePreset },
                        set: { model.detachedWindowSizePreset = $0 }
                    ),
                    options: DetachedWindowSizePreset.allCases,
                    optionLabel: { $0.displayName }
                )

                SettingsRowDivider()

                SettingsSwitchRow(
                    title: "Float above other windows",
                    isOn: $model.detachedWindowAlwaysOnTop
                )
            }

            SettingsCard(header: "Lyrics & credits") {
                SettingsSwitchRow(
                    title: "Open the details pane for new tracks",
                    isOn: $model.expandLyricsByDefault
                )

                SettingsRowDivider()

                SettingsSegmentedRow(
                    title: "Pane height",
                    selection: Binding(
                        get: { model.lyricsPaneSizePreset },
                        set: { model.lyricsPaneSizePreset = $0 }
                    ),
                    options: LyricsPaneSizePreset.allCases,
                    optionLabel: { $0.displayName }
                )

                SettingsRowDivider()

                SettingsSegmentedRow(
                    title: "Text size",
                    selection: Binding(
                        get: { model.lyricsFontSizePreset },
                        set: { model.lyricsFontSizePreset = $0 }
                    ),
                    options: LyricsFontSizePreset.allCases,
                    optionLabel: { $0.displayName }
                )

                SettingsRowDivider()

                SettingsInlineSliderRow(
                    title: "Custom size",
                    caption: "Moving this switches the preset to Custom",
                    value: Binding(
                        get: { model.lyricsCustomFontSize },
                        set: { model.lyricsCustomFontSize = $0 }
                    ),
                    range: LyricsFontSizePreset.customSizeRange,
                    valueText: String(format: "%.1f pt", model.lyricsCustomFontSize)
                )
                .opacity(model.lyricsFontSizePreset == .custom ? 1.0 : 0.4)
            }
        }
    }

    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsStackedRow(
                    title: "Windows",
                    caption: "Applies to Settings and the player chrome. Themes below still control the player's own styling."
                ) {
                    AppearanceModePicker(
                        selection: Binding(
                            get: { model.appAppearanceMode },
                            set: { model.appAppearanceMode = $0 }
                        )
                    )
                }
            }

            SettingsCard(header: "Player theme") {
                ThemeSwatchGrid(
                    selection: Binding(
                        get: { model.themeStyle },
                        set: { model.themeStyle = $0 }
                    )
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 12)

                SettingsRowDivider()

                SettingsInlineSliderRow(
                    title: "Album colour blend",
                    caption: model.themeStyle == .artworkAdaptive
                    ? "Artwork Adaptive already uses the album's colours in full."
                    : "Mixes the current album's colours into \(model.themeStyle.displayName).",
                    value: Binding(
                        get: { model.themeArtworkBlend },
                        set: { model.themeArtworkBlend = $0 }
                    ),
                    range: 0...1,
                    valueText: "\(Int(model.themeArtworkBlend * 100))%"
                )
                .opacity(model.themeStyle == .artworkAdaptive ? 0.4 : 1.0)
                .disabled(model.themeStyle == .artworkAdaptive)
            }

            SettingsCard {
                SettingsInlineSliderRow(
                    title: "Artwork colour intensity",
                    caption: "How strongly album colours tint the player surfaces",
                    value: Binding(
                        get: { model.artworkColorIntensity },
                        set: { model.artworkColorIntensity = $0 }
                    ),
                    range: 0.5...1.8,
                    valueText: "\(Int(model.artworkColorIntensity * 100))%"
                )
            }
        }
    }

    private var artworkMotionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsSwitchRow(
                    title: "Animated artwork",
                    caption: "Adds motion to album art in the player",
                    isEmphasized: true,
                    isOn: $model.animatedArtworkEnabled
                )
            }

            Group {
                SettingsCard(header: "Motion style") {
                    MotionStyleTiles(model: model)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    SettingsRowDivider()

                    SettingsRow(
                        title: "Compare styles side by side",
                        caption: "Opens a larger preview using the current artwork"
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

                SettingsCard {
                    SettingsSwitchRow(
                        title: "Use Apple Music video streams",
                        caption: "When an album has an editorial loop. Increases media cache usage.",
                        isEmphasized: true,
                        isOn: $model.animatedArtworkStreamsEnabled
                    )

                    Group {
                        SettingsRowDivider()

                        SettingsSegmentedRow(
                            title: "Quality",
                            selection: Binding(
                                get: { model.animatedArtworkQualityPolicy },
                                set: { model.animatedArtworkQualityPolicy = $0 }
                            ),
                            options: AnimatedArtworkQualityPolicy.allCases,
                            optionLabel: { $0.displayName }
                        )

                        SettingsRowDivider()

                        SettingsSwitchRow(
                            title: "Crop to square",
                            caption: "Off shows the complete video frame with bars",
                            isOn: $model.cropAnimatedArtworkToSquare
                        )

                        SettingsRowDivider()

                        SettingsRow(title: "This track") {
                            HStack(spacing: 8) {
                                VStack(alignment: .trailing, spacing: 3) {
                                    SettingsStatusBadge(text: model.animatedArtworkStatusMessage)

                                    if !model.animatedArtworkLastError.isEmpty {
                                        Text(model.animatedArtworkLastError)
                                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 240, alignment: .trailing)
                                    }
                                }

                                Button {
                                    showAnimatedStreamPreview = true
                                } label: {
                                    Label("Preview", systemImage: "play.rectangle")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .opacity(model.animatedArtworkStreamsEnabled ? 1.0 : 0.4)
                    .disabled(!model.animatedArtworkStreamsEnabled)
                }
            }
            .opacity(model.animatedArtworkEnabled ? 1.0 : 0.4)
            .disabled(!model.animatedArtworkEnabled)
        }
    }

    // MARK: - Behavior

    private var sourcesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsSegmentedRow(
                    title: "Follow",
                    caption: "Which player the menu bar tracks",
                    selection: Binding(
                        get: { model.preferredProvider },
                        set: { model.preferredProvider = $0 }
                    ),
                    options: PreferredProvider.allCases,
                    optionLabel: { $0 == .automatic ? "Whatever's playing" : $0.displayName }
                )

                SettingsRowDivider()

                SettingsSegmentedRow(
                    title: "If both are playing, prefer",
                    selection: Binding(
                        get: { model.providerPriority },
                        set: { model.providerPriority = $0 }
                    ),
                    options: ProviderPriority.allCases,
                    optionLabel: { $0 == .musicFirst ? "Music" : "Spotify" }
                )
                .opacity(model.preferredProvider == .automatic ? 1.0 : 0.4)
                .disabled(model.preferredProvider != .automatic)
            }

            ProviderConnectionSection(model: model, inspector: connectionInspector)
        }
    }

    private var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
                ForEach(Array(AppHotkeyAction.allCases.enumerated()), id: \.element) { index, action in
                    if index > 0 {
                        SettingsRowDivider()
                    }
                    HotkeyRecorderRow(action: action)
                }
            }

            Text("Shortcuts work anywhere in macOS. Recording a combination that another app already owns will simply fail to register.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - App

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsSwitchRow(
                    title: "Open at login",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin(enabled: $0) }
                    )
                )

                SettingsRowDivider()

                SettingsRow(
                    title: "Updates",
                    caption: "Check for newer PlayStatus builds through Sparkle"
                ) {
                    Button {
                        SparkleUpdater.shared.checkForUpdates(nil)
                    } label: {
                        Label("Check Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            SettingsCard {
                SettingsStackedRow(
                    title: "Media cache",
                    caption: "Lyrics and artwork stored on this Mac"
                ) {
                    HStack(spacing: 10) {
                        Text(model.persistentCacheUsageText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        if model.isClearingPersistentCache {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Button("Empty") {
                            model.clearPersistentCache()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.isClearingPersistentCache)
                    }
                }

                SettingsRowDivider()

                SettingsSwitchRow(
                    title: "Free memory when the player is closed",
                    caption: "Artwork and streams reload on reopen, so they may appear a moment late",
                    isOn: $model.reduceHiddenMemoryUsage
                )
            }

            SettingsCard {
                SettingsRow(
                    title: "Walkthrough",
                    caption: "Replay the setup tour or re-open the shorter update tour"
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
                            Label("What's New", systemImage: "arrow.clockwise.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                SettingsCard {
                    SettingsSwitchRow(
                        title: "Re-arm player coachmarks",
                        caption: "Dismissals stay in this debug session only while this is on",
                        isOn: Binding(
                            get: { onboarding.debugCoachmarksEnabled },
                            set: { onboarding.setDebugCoachmarksEnabled($0) }
                        )
                    )
                }
                .padding(.top, 8)
            } label: {
                Text("Advanced")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            model.refreshPersistentCacheStats()
        }
    }

    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image("SettingsAppIcon")
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 2) {
                    Text("PlayStatus")
                        .font(.system(size: 16, weight: .semibold))
                    Text(aboutVersionText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)

            SettingsCard(header: "Lyrics attribution and disclaimer") {
                Text(lrclibAttributionAndDisclaimerText)
                    .textSelection(.enabled)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
            }

            DisclosureGroup(isExpanded: $isLicenseExpanded) {
                Text(mitLicenseText)
                    .textSelection(.enabled)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                            )
                    )
                    .padding(.top, 8)
            } label: {
                Text("Licence and disclaimers")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aboutVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "Version \(version) (\(build))"
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
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
