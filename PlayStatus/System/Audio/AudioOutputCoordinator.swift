import Foundation
import Combine
import CoreAudio

/// Owns the app's view of the system audio output — device list, volume, mute — and the
/// resume volume ramp.
///
/// The ramp exists because resuming playback at whatever volume the system was left at can be
/// jarring: this drops the output to a gentler level, sends play, then eases back to the user's
/// chosen volume. That means the app is briefly driving the system volume itself, so every
/// control that touches volume has to cancel an in-flight ramp before acting — otherwise the
/// ramp's next step overwrites what the user just did.
///
/// `AudioOutputController` is the stateless Core Audio wrapper; this is the state and policy
/// on top of it.
@MainActor
final class AudioOutputCoordinator: ObservableObject {
    private struct ResumeVolumeRampState {
        let deviceID: AudioDeviceID
        let targetVolume: Double
    }

    private enum ResumeVolumeRamp {
        static let duration: TimeInterval = 2
        static let steps: Int = 9
        static let minimumTargetVolume: Double = 0.14
        static let startFraction: Double = 0.18
        static let floorVolume: Double = 0.025
    }

    @Published private(set) var availableOutputDevices: [AudioOutputDevice] = []
    @Published private(set) var selectedOutputDeviceID: AudioDeviceID = 0
    @Published private(set) var outputVolume: Double = 1.0
    @Published private(set) var outputMuted: Bool = false

    private var resumeVolumeRampTask: Task<Void, Never>?
    private var activeResumeVolumeRamp: ResumeVolumeRampState?
    private let queue = DispatchQueue(label: "com.nikhilbolar.playstatus.audio", qos: .utility)

    /// Whether a resume ramp is currently driving the system volume.
    var isRamping: Bool { activeResumeVolumeRamp != nil }

    deinit {
        resumeVolumeRampTask?.cancel()
    }

    // MARK: - Reading state

    func refreshState() {
        queue.async { [weak self] in
            let state = AudioOutputController.currentState()
            Task { @MainActor [weak self] in
                self?.apply(state)
            }
        }
    }

    func apply(_ state: AudioOutputState) {
        availableOutputDevices = state.devices
        selectedOutputDeviceID = state.selectedDeviceID
        outputMuted = state.isMuted

        // While ramping, the system volume is mid-sweep and not what the user asked for, so the
        // rail keeps showing the ramp's destination instead of tracking each step.
        if let ramp = activeResumeVolumeRamp {
            guard ramp.deviceID == state.selectedDeviceID else {
                cancelResumeRamp(restoreTargetVolume: false)
                outputVolume = state.volume
                return
            }
            outputVolume = ramp.targetVolume
            if state.isMuted {
                cancelResumeRamp(restoreTargetVolume: false)
            }
            return
        }

        outputVolume = state.volume
    }

    // MARK: - User controls

    func setOutputDevice(_ id: AudioDeviceID) {
        cancelResumeRamp(restoreTargetVolume: false)
        AudioOutputController.setDefaultOutputDevice(id)
        refreshState()
    }

    func setOutputVolume(_ value: Double) {
        cancelResumeRamp(restoreTargetVolume: false)
        let clamped = min(max(value, 0), 1)
        outputVolume = clamped
        AudioOutputController.setVolume(Float32(clamped), for: selectedOutputDeviceID == 0 ? nil : selectedOutputDeviceID)
    }

    func toggleOutputMute() {
        cancelResumeRamp(restoreTargetVolume: false)
        let newMuted = !outputMuted
        outputMuted = newMuted
        AudioOutputController.setMuted(newMuted, for: selectedOutputDeviceID == 0 ? nil : selectedOutputDeviceID)
    }

    // MARK: - Resume volume ramp

    /// Whether the audio side permits a ramp. The caller adds its own playback-side gating —
    /// this only knows about the output device.
    func canRamp(using audioState: AudioOutputState) -> Bool {
        !audioState.isMuted &&
        audioState.selectedDeviceID != 0 &&
        audioState.volume >= ResumeVolumeRamp.minimumTargetVolume
    }

    /// Drops to a gentler level, runs `sendPlayCommand`, then eases back to `audioState.volume`.
    ///
    /// The play command is issued *after* the drop so the first audible moment is already at the
    /// lower level — sending it first lets a frame through at full volume.
    func startResumeRamp(using audioState: AudioOutputState, sendPlayCommand: () -> Void) {
        cancelResumeRamp(restoreTargetVolume: true)

        let targetVolume = min(max(audioState.volume, 0), 1)
        let deviceID = audioState.selectedDeviceID
        let startingVolume = min(
            targetVolume,
            max(ResumeVolumeRamp.floorVolume, targetVolume * ResumeVolumeRamp.startFraction)
        )

        activeResumeVolumeRamp = ResumeVolumeRampState(deviceID: deviceID, targetVolume: targetVolume)

        AudioOutputController.setVolume(Float32(startingVolume), for: deviceID)
        sendPlayCommand()

        let stepDelay = UInt64((ResumeVolumeRamp.duration / Double(ResumeVolumeRamp.steps)) * 1_000_000_000)
        resumeVolumeRampTask = Task { [weak self] in
            for step in 1...ResumeVolumeRamp.steps {
                try? await Task.sleep(nanoseconds: stepDelay)
                guard !Task.isCancelled else { return }

                let progress = Double(step) / Double(ResumeVolumeRamp.steps)
                let easedProgress = 1 - pow(1 - progress, 3)
                let steppedVolume = startingVolume + ((targetVolume - startingVolume) * easedProgress)
                AudioOutputController.setVolume(Float32(steppedVolume), for: deviceID)
            }

            guard !Task.isCancelled else { return }
            self?.finishResumeRamp(deviceID: deviceID, targetVolume: targetVolume)
        }
    }

    private func finishResumeRamp(deviceID: AudioDeviceID, targetVolume: Double) {
        guard let ramp = activeResumeVolumeRamp,
              ramp.deviceID == deviceID else {
            return
        }

        activeResumeVolumeRamp = nil
        resumeVolumeRampTask = nil
        outputVolume = targetVolume
    }

    /// Stops an in-flight ramp. `restoreTargetVolume` jumps the output straight to the ramp's
    /// destination — what the user's volume was before the ramp borrowed it — which is right when
    /// the ramp is being abandoned mid-sweep, and wrong when the volume is about to be set by
    /// something else anyway.
    func cancelResumeRamp(restoreTargetVolume: Bool) {
        let ramp = activeResumeVolumeRamp
        resumeVolumeRampTask?.cancel()
        resumeVolumeRampTask = nil
        activeResumeVolumeRamp = nil

        guard restoreTargetVolume, let ramp else { return }
        AudioOutputController.setVolume(Float32(ramp.targetVolume), for: ramp.deviceID)
        outputVolume = ramp.targetVolume
    }
}
