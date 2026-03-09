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
    case toggleDetachedMode = 6

    var label: String {
        switch self {
        case .playPause: return "Play/Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .togglePopover: return "Toggle Popover"
        case .likeSong: return "Toggle Favorite"
        case .toggleDetachedMode: return "Toggle Detached Mode"
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
        case .toggleDetachedMode: return HotkeyBinding(keyCode: UInt32(kVK_ANSI_D), modifiers: mods)
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
    @State private var hovering = false

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                SettingsLink {
                    label()
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                )
            } else {
                Button(action: openSettingsWindow) {
                    label()
                }
            }
        }
        .scaleEffect(hovering ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.16), value: hovering)
        .onHover { isHovering in
            hovering = isHovering
        }
    }
}
