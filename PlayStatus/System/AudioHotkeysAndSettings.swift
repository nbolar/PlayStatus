import SwiftUI
import AppKit
import CoreAudio
import Carbon

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

struct AudioOutputState {
    let devices: [AudioOutputDevice]
    let selectedDeviceID: AudioDeviceID
    let volume: Double
    let isMuted: Bool
}

enum AudioOutputController {
    static func currentState() -> AudioOutputState {
        let devices = outputDevices()
        let selected = defaultOutputDeviceID() ?? devices.first?.id ?? 0
        let volume = Double(volume(for: selected))
        let isMuted = muted(for: selected)
        return AudioOutputState(
            devices: devices,
            selectedDeviceID: selected,
            volume: min(max(volume, 0), 1),
            isMuted: isMuted
        )
    }

    static func setDefaultOutputDevice(_ deviceID: AudioDeviceID) {
        var mutableID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &mutableID
        )
    }

    static func setVolume(_ normalized: Float32, for deviceID: AudioDeviceID? = nil) {
        let target = min(max(normalized, 0), 1)
        guard let deviceID = deviceID ?? defaultOutputDeviceID() else { return }

        var masterAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableVolume = target
        let size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(deviceID, &masterAddress) {
            _ = AudioObjectSetPropertyData(deviceID, &masterAddress, 0, nil, size, &mutableVolume)
            return
        }

        let preferredChannels = preferredStereoChannels(for: deviceID)
        if !preferredChannels.isEmpty {
            for channel in preferredChannels {
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: channel
                )
                if AudioObjectHasProperty(deviceID, &address) {
                    _ = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &mutableVolume)
                }
            }
            return
        }

        for channel: UInt32 in [1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            if AudioObjectHasProperty(deviceID, &address) {
                _ = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &mutableVolume)
            }
        }
    }

    static func setMuted(_ muted: Bool, for deviceID: AudioDeviceID? = nil) {
        guard let deviceID = deviceID ?? defaultOutputDeviceID() else { return }
        var muteValue: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)

        var virtualAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &virtualAddress) {
            _ = AudioObjectSetPropertyData(deviceID, &virtualAddress, 0, nil, size, &muteValue)
            return
        }

        var channelAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1
        )
        if AudioObjectHasProperty(deviceID, &channelAddress) {
            _ = AudioObjectSetPropertyData(deviceID, &channelAddress, 0, nil, size, &muteValue)
        }
    }

    private static func outputDevices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }

        return ids.compactMap { id in
            guard hasOutputChannels(deviceID: id) else { return nil }
            return AudioOutputDevice(id: id, name: deviceName(id) ?? "Output \(id)")
        }
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private static func volume(for deviceID: AudioDeviceID) -> Float32 {
        var masterAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Float32 = 1
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(deviceID, &masterAddress),
           AudioObjectGetPropertyData(deviceID, &masterAddress, 0, nil, &dataSize, &value) == noErr {
            return value
        }

        let preferredChannels = preferredStereoChannels(for: deviceID)
        if !preferredChannels.isEmpty {
            var sum: Float32 = 0
            var count: Float32 = 0
            for channel in preferredChannels {
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: channel
                )
                var channelValue: Float32 = 0
                var channelSize = UInt32(MemoryLayout<Float32>.size)
                if AudioObjectHasProperty(deviceID, &address),
                   AudioObjectGetPropertyData(deviceID, &address, 0, nil, &channelSize, &channelValue) == noErr {
                    sum += channelValue
                    count += 1
                }
            }
            if count > 0 {
                return sum / count
            }
        }

        for channel: UInt32 in [1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            var channelValue: Float32 = 0
            var channelSize = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(deviceID, &address),
               AudioObjectGetPropertyData(deviceID, &address, 0, nil, &channelSize, &channelValue) == noErr {
                return channelValue
            }
        }

        return 1
    }

    private static func preferredStereoChannels(for deviceID: AudioDeviceID) -> [UInt32] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var channels: [UInt32] = [0, 0]
        var size = UInt32(MemoryLayout<UInt32>.size * channels.count)
        guard AudioObjectHasProperty(deviceID, &address),
              AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &channels) == noErr else {
            return []
        }
        return channels.filter { $0 != 0 }
    }

    private static func muted(for deviceID: AudioDeviceID) -> Bool {
        var virtualAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(deviceID, &virtualAddress),
           AudioObjectGetPropertyData(deviceID, &virtualAddress, 0, nil, &dataSize, &value) == noErr {
            return value != 0
        }

        var channelAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1
        )
        if AudioObjectHasProperty(deviceID, &channelAddress),
           AudioObjectGetPropertyData(deviceID, &channelAddress, 0, nil, &dataSize, &value) == noErr {
            return value != 0
        }
        return false
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &unmanagedName)
        guard status == noErr, let unmanagedName else { return nil }
        return unmanagedName.takeRetainedValue() as String
    }

    private static func hasOutputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return false
        }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, raw) == noErr else {
            return false
        }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        let bufferList = UnsafeMutableAudioBufferListPointer(list)
        let channels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
        return channels > 0
    }
}

enum AppHotkeyAction: UInt32, CaseIterable {
    case playPause = 1
    case nextTrack = 2
    case previousTrack = 3
    case togglePopover = 4
    case likeSong = 5

    var label: String {
        switch self {
        case .playPause: return "Play/Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .togglePopover: return "Toggle Popover"
        case .likeSong: return "Like Song"
        }
    }
    
    var defaultBinding: HotkeyBinding {
        let mods = UInt32(controlKey | optionKey | cmdKey)
        switch self {
        case .playPause: return HotkeyBinding(keyCode: UInt32(kVK_ANSI_P), modifiers: mods)
        case .nextTrack: return HotkeyBinding(keyCode: UInt32(kVK_ANSI_N), modifiers: mods)
        case .previousTrack: return HotkeyBinding(keyCode: UInt32(kVK_ANSI_B), modifiers: mods)
        case .togglePopover: return HotkeyBinding(keyCode: UInt32(kVK_ANSI_O), modifiers: mods)
        case .likeSong: return HotkeyBinding(keyCode: UInt32(kVK_ANSI_L), modifiers: mods)
        }
    }
}

struct HotkeyBinding: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
}

enum HotkeyStore {
    static func binding(for action: AppHotkeyAction) -> HotkeyBinding {
        let defaults = UserDefaults.standard
        let keyCodeKey = "hotkey.\(action.rawValue).keyCode"
        let modifiersKey = "hotkey.\(action.rawValue).modifiers"
        if defaults.object(forKey: keyCodeKey) == nil || defaults.object(forKey: modifiersKey) == nil {
            return action.defaultBinding
        }
        let keyCode = UInt32(defaults.integer(forKey: keyCodeKey))
        let modifiers = UInt32(defaults.integer(forKey: modifiersKey))
        return HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
    }

    static func setBinding(_ binding: HotkeyBinding, for action: AppHotkeyAction) {
        let defaults = UserDefaults.standard
        defaults.set(Int(binding.keyCode), forKey: "hotkey.\(action.rawValue).keyCode")
        defaults.set(Int(binding.modifiers), forKey: "hotkey.\(action.rawValue).modifiers")
    }

    static func resetBinding(for action: AppHotkeyAction) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "hotkey.\(action.rawValue).keyCode")
        defaults.removeObject(forKey: "hotkey.\(action.rawValue).modifiers")
    }

    static func allBindings() -> [AppHotkeyAction: HotkeyBinding] {
        Dictionary(uniqueKeysWithValues: AppHotkeyAction.allCases.map { ($0, binding(for: $0)) })
    }
}

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var result: UInt32 = 0
    if flags.contains(.command) { result |= UInt32(cmdKey) }
    if flags.contains(.option) { result |= UInt32(optionKey) }
    if flags.contains(.control) { result |= UInt32(controlKey) }
    if flags.contains(.shift) { result |= UInt32(shiftKey) }
    return result
}

func hotkeyDisplayString(_ binding: HotkeyBinding) -> String {
    var pieces: [String] = []
    if (binding.modifiers & UInt32(controlKey)) != 0 { pieces.append("⌃") }
    if (binding.modifiers & UInt32(optionKey)) != 0 { pieces.append("⌥") }
    if (binding.modifiers & UInt32(shiftKey)) != 0 { pieces.append("⇧") }
    if (binding.modifiers & UInt32(cmdKey)) != 0 { pieces.append("⌘") }
    pieces.append(keyLabel(for: binding.keyCode))
    return pieces.joined()
}

private func keyLabel(for keyCode: UInt32) -> String {
    switch keyCode {
    case UInt32(kVK_Return): return "↩"
    case UInt32(kVK_Tab): return "⇥"
    case UInt32(kVK_Space): return "Space"
    case UInt32(kVK_Delete): return "⌫"
    case UInt32(kVK_ForwardDelete): return "⌦"
    case UInt32(kVK_Escape): return "⎋"
    case UInt32(kVK_LeftArrow): return "←"
    case UInt32(kVK_RightArrow): return "→"
    case UInt32(kVK_UpArrow): return "↑"
    case UInt32(kVK_DownArrow): return "↓"
    case UInt32(kVK_ANSI_0): return "0"
    case UInt32(kVK_ANSI_1): return "1"
    case UInt32(kVK_ANSI_2): return "2"
    case UInt32(kVK_ANSI_3): return "3"
    case UInt32(kVK_ANSI_4): return "4"
    case UInt32(kVK_ANSI_5): return "5"
    case UInt32(kVK_ANSI_6): return "6"
    case UInt32(kVK_ANSI_7): return "7"
    case UInt32(kVK_ANSI_8): return "8"
    case UInt32(kVK_ANSI_9): return "9"
    case UInt32(kVK_ANSI_A): return "A"
    case UInt32(kVK_ANSI_B): return "B"
    case UInt32(kVK_ANSI_C): return "C"
    case UInt32(kVK_ANSI_D): return "D"
    case UInt32(kVK_ANSI_E): return "E"
    case UInt32(kVK_ANSI_F): return "F"
    case UInt32(kVK_ANSI_G): return "G"
    case UInt32(kVK_ANSI_H): return "H"
    case UInt32(kVK_ANSI_I): return "I"
    case UInt32(kVK_ANSI_J): return "J"
    case UInt32(kVK_ANSI_K): return "K"
    case UInt32(kVK_ANSI_L): return "L"
    case UInt32(kVK_ANSI_M): return "M"
    case UInt32(kVK_ANSI_N): return "N"
    case UInt32(kVK_ANSI_O): return "O"
    case UInt32(kVK_ANSI_P): return "P"
    case UInt32(kVK_ANSI_Q): return "Q"
    case UInt32(kVK_ANSI_R): return "R"
    case UInt32(kVK_ANSI_S): return "S"
    case UInt32(kVK_ANSI_T): return "T"
    case UInt32(kVK_ANSI_U): return "U"
    case UInt32(kVK_ANSI_V): return "V"
    case UInt32(kVK_ANSI_W): return "W"
    case UInt32(kVK_ANSI_X): return "X"
    case UInt32(kVK_ANSI_Y): return "Y"
    case UInt32(kVK_ANSI_Z): return "Z"
    default: return "Key\(keyCode)"
    }
}

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var callbacks: [AppHotkeyAction: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    func configure(callbacks: [AppHotkeyAction: () -> Void]) {
        self.callbacks = callbacks
    }

    func registerAll() {
        unregisterAll()
        installHandlerIfNeeded()
        let bindings = HotkeyStore.allBindings()

        for action in AppHotkeyAction.allCases {
            guard let binding = bindings[action] else { continue }
            let hotKeyID = EventHotKeyID(signature: fourCharCode("PSTS"), id: action.rawValue)
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.keyCode,
                binding.modifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr {
                hotKeyRefs.append(hotKeyRef)
            }
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleEvent(event)
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        if status != noErr {
            eventHandlerRef = nil
        }
    }

    private func handleEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              let action = AppHotkeyAction(rawValue: hotKeyID.id),
              let callback = callbacks[action] else {
            return noErr
        }
        DispatchQueue.main.async { callback() }
        return noErr
    }

    private func fourCharCode(_ value: String) -> OSType {
        var result: UInt32 = 0
        for scalar in value.utf8.prefix(4) {
            result = (result << 8) + UInt32(scalar)
        }
        return result
    }
}

func openSettingsWindow() {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    NSApp.activate(ignoringOtherApps: true)
}


struct SettingsOpenControl<Label: View>: View {
    @ViewBuilder var label: () -> Label

    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                label()
            }
        } else {
            Button(action: openSettingsWindow) {
                label()
            }
        }
    }
}

struct PlayStatusSettingsView: View {
    @ObservedObject var model: NowPlayingModel
    @State private var selectedTab: SettingsTab = .display
    @State private var tabDirection: SettingsTabDirection = .forward

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selectedTab: tabSelection)

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
                .onChange(of: selectedTab) { _ in
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
        .frame(width: settingsWindowSize.width, height: settingsWindowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(SettingsWindowChromeConfigurator(targetSize: settingsWindowSize))
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
        case .system:
            systemContent
        case .hotkeys:
            hotkeysContent
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
                caption: "Controls how strongly artwork colors tint the popover.",
                value: Binding(
                    get: { model.artworkColorIntensity },
                    set: { model.artworkColorIntensity = $0 }
                ),
                range: 0.5...1.8,
                valueText: "\(Int(model.artworkColorIntensity * 100))%"
            )

            Divider().padding(.vertical, 2)

            SettingsToggleRow(
                title: "Animated Artwork",
                caption: "Adds subtle motion to album artwork in the popover.",
                isOn: $model.animatedArtworkEnabled
            )

            if model.animatedArtworkEnabled {
                SettingsControlRow(
                    title: "Motion Style",
                    caption: "Sets the character of artwork motion."
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
                title: "Show Lyrics Panel",
                caption: "Displays an expandable lyrics section in the popover.",
                isOn: $model.showLyricsPanel
            )
            SettingsToggleRow(
                title: "Expand Lyrics by Default",
                caption: "Opens the lyrics section automatically for new tracks.",
                isOn: $model.expandLyricsByDefault
            )
        }
    }

    private var systemContent: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        }
    }

    private var hotkeysContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(AppHotkeyAction.allCases, id: \.self) { action in
                HotkeyRecorderRow(action: action)
            }
        }
    }
}

private enum SettingsTab: String, CaseIterable {
    case display
    case playback
    case system
    case hotkeys

    var title: String {
        switch self {
        case .display: return "Display"
        case .playback: return "Playback"
        case .system: return "System"
        case .hotkeys: return "Hotkeys"
        }
    }

    var subtitle: String {
        switch self {
        case .display: return "Text, visuals, and animation"
        case .playback: return "Player source and priority"
        case .system: return "Startup and updates"
        case .hotkeys: return "Global keyboard shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .display: return "textformat"
        case .playback: return "waveform"
        case .system: return "gearshape.2"
        case .hotkeys: return "keyboard"
        }
    }

    var sortIndex: Int {
        switch self {
        case .display: return 0
        case .playback: return 1
        case .system: return 2
        case .hotkeys: return 3
        }
    }

    var preferredSize: CGSize {
        switch self {
        case .display:
            return CGSize(width: 780, height: 640)
        case .playback:
            return CGSize(width: 780, height: 560)
        case .system:
            return CGSize(width: 780, height: 430)
        case .hotkeys:
            return CGSize(width: 780, height: 520)
        }
    }
}

private enum SettingsTabDirection {
    case forward
    case backward
}

private struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab

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

            Spacer(minLength: 10)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit PlayStatus", systemImage: "power")
                    .foregroundStyle(Color.accentColor.opacity(0.95))
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

private struct SettingsSidebarItem: View {
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

private struct SettingsPageHeader: View {
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

private struct SettingsControlRow<Control: View>: View {
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

private struct SettingsToggleRow: View {
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

private struct SettingsSliderRow: View {
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

private struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    let targetSize: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            applyConfiguration(from: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyConfiguration(from: nsView, coordinator: context.coordinator)
        }
    }

    private func applyConfiguration(from view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.remove(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        resizeWindowIfNeeded(window: window, coordinator: coordinator)

        if !coordinator.didActivateWindow {
            coordinator.didActivateWindow = true
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else if !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func resizeWindowIfNeeded(window: NSWindow, coordinator: Coordinator) {
        guard coordinator.lastAppliedSize != targetSize else { return }

        var frame = window.frame
        let oldHeight = frame.height
        frame.size = targetSize
        frame.origin.y += oldHeight - targetSize.height

        if coordinator.lastAppliedSize == nil {
            window.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.allowsImplicitAnimation = true
                window.animator().setFrame(frame, display: true)
            }
        }

        coordinator.lastAppliedSize = targetSize
    }

    final class Coordinator {
        var didActivateWindow = false
        var lastAppliedSize: CGSize?
    }
}
