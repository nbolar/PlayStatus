import AppKit
import Combine
import SwiftUI

enum ProviderConnectionStatus: Equatable {
    case unknown
    case checking
    case connected(String)
    case needsApproval(String)
    case blocked(String)
    case appNotRunning(String)
    case notInstalled(String)
    case failed(String)

    var label: String {
        switch self {
        case .unknown:
            return "Not checked yet"
        case .checking:
            return "Checking connection..."
        case .connected(let message),
             .needsApproval(let message),
             .blocked(let message),
             .appNotRunning(let message),
             .notInstalled(let message),
             .failed(let message):
            return message
        }
    }

    var tint: Color {
        switch self {
        case .unknown, .notInstalled:
            return .secondary
        case .checking:
            return Color(red: 0.43, green: 0.72, blue: 0.98)
        case .connected:
            return Color(red: 0.38, green: 0.78, blue: 0.57)
        case .needsApproval, .appNotRunning:
            return Color(red: 0.98, green: 0.72, blue: 0.36)
        case .blocked, .failed:
            return Color(red: 0.95, green: 0.47, blue: 0.42)
        }
    }

    var systemImage: String {
        switch self {
        case .unknown:
            return "circle.dashed"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .connected:
            return "checkmark.seal.fill"
        case .needsApproval:
            return "questionmark.circle.fill"
        case .appNotRunning:
            return "moon.zzz.fill"
        case .blocked:
            return "hand.raised.fill"
        case .notInstalled:
            return "slash.circle"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var isChecking: Bool {
        self == .checking
    }

    var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }

    var isInstalled: Bool {
        if case .notInstalled = self { return false }
        return true
    }
}

/// Reports whether PlayStatus can actually drive Music and Spotify through AppleScript,
/// so the Settings window can confirm the Automation handshake instead of leaving it to
/// the onboarding walkthrough.
@MainActor
final class ProviderConnectionInspector: ObservableObject {
    static let shared = ProviderConnectionInspector()

    @Published private(set) var musicStatus: ProviderConnectionStatus = .unknown
    @Published private(set) var spotifyStatus: ProviderConnectionStatus = .unknown

    private let probeQueue = DispatchQueue(
        label: "com.bolar.PlayStatus.connection-inspector",
        qos: .userInitiated
    )
    private let launchSettleDelay: TimeInterval = 0.75
    private let launchRetryDelay: TimeInterval = 0.75
    private let launchMaximumAttempts = 8

    private init() {}

    func status(for provider: NowPlayingProvider) -> ProviderConnectionStatus {
        switch provider {
        case .music, .none:
            return musicStatus
        case .spotify:
            return spotifyStatus
        }
    }

    func isRunning(_ provider: NowPlayingProvider) -> Bool {
        Self.isRunning(bundleIdentifier: Self.bundleIdentifier(for: provider))
    }

    func isInstalled(_ provider: NowPlayingProvider) -> Bool {
        Self.applicationURL(for: provider) != nil
    }

    /// Passive check used when Settings appears: never launches an app and never triggers
    /// the macOS Automation prompt.
    func refresh(_ provider: NowPlayingProvider) {
        guard !status(for: provider).isChecking else { return }
        setStatus(.checking, for: provider)
        probe(provider, promptIfNeeded: false)
    }

    func refreshAll() {
        refresh(.music)
        refresh(.spotify)
    }

    /// Explicit check driven by the Verify button: opens the player when it is not running
    /// and lets macOS show the Automation prompt if consent has never been given.
    func verify(
        _ provider: NowPlayingProvider,
        completion: ((ProviderConnectionStatus) -> Void)? = nil
    ) {
        guard !status(for: provider).isChecking else { return }

        guard isInstalled(provider) else {
            let status = ProviderConnectionStatus.notInstalled(
                "\(Self.displayName(for: provider)) is not installed on this Mac."
            )
            setStatus(status, for: provider)
            completion?(status)
            return
        }

        setStatus(.checking, for: provider)

        guard isRunning(provider) else {
            openProvider(provider)
            probeAfterLaunch(provider, attempt: 0, completion: completion)
            return
        }

        probe(provider, promptIfNeeded: true, completion: completion)
    }

    func openProvider(_ provider: NowPlayingProvider) {
        guard let url = Self.applicationURL(for: provider) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }

    func openAutomationPrivacySettings() {
        OnboardingCoordinator.shared.openAutomationPrivacySettings()
    }

    private func probe(
        _ provider: NowPlayingProvider,
        promptIfNeeded: Bool,
        completion: ((ProviderConnectionStatus) -> Void)? = nil
    ) {
        probeQueue.async { [weak self] in
            let status = Self.evaluate(provider: provider, promptIfNeeded: promptIfNeeded)
            DispatchQueue.main.async {
                self?.setStatus(status, for: provider)
                completion?(status)
            }
        }
    }

    private func probeAfterLaunch(
        _ provider: NowPlayingProvider,
        attempt: Int,
        completion: ((ProviderConnectionStatus) -> Void)? = nil
    ) {
        let delay = attempt == 0 ? launchSettleDelay : launchRetryDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }

            self.probeQueue.async {
                let status = Self.evaluate(provider: provider, promptIfNeeded: true)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }

                    if case .appNotRunning = status, attempt < self.launchMaximumAttempts {
                        self.probeAfterLaunch(provider, attempt: attempt + 1, completion: completion)
                        return
                    }

                    self.setStatus(status, for: provider)
                    completion?(status)
                }
            }
        }
    }

    private func setStatus(_ status: ProviderConnectionStatus, for provider: NowPlayingProvider) {
        switch provider {
        case .music, .none:
            musicStatus = status
        case .spotify:
            spotifyStatus = status
        }
    }

    // MARK: - Probing

    private nonisolated static func evaluate(
        provider: NowPlayingProvider,
        promptIfNeeded: Bool
    ) -> ProviderConnectionStatus {
        let name = displayName(for: provider)
        let bundleIdentifier = bundleIdentifier(for: provider)

        guard applicationURL(for: provider) != nil else {
            return .notInstalled("\(name) is not installed on this Mac.")
        }

        var permission = automationPermission(for: bundleIdentifier, askUserIfNeeded: false)
        if permission == OSStatus(errAEEventWouldRequireUserConsent), promptIfNeeded {
            permission = automationPermission(for: bundleIdentifier, askUserIfNeeded: true)
        }

        switch permission {
        case noErr:
            guard isRunning(bundleIdentifier: bundleIdentifier) else {
                return .connected("Connected. \(name) is not running right now.")
            }
            return playerStateStatus(for: provider)
        case OSStatus(errAEEventNotPermitted):
            return .blocked("macOS is blocking Automation access to \(name). Turn PlayStatus back on under Privacy & Security → Automation.")
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .needsApproval("\(name) has not been approved yet. Run Verify and allow the macOS Automation prompt.")
        case OSStatus(procNotFound):
            return .appNotRunning("\(name) is not running, so macOS cannot confirm access yet. Open it and verify again.")
        default:
            return .failed("Couldn't verify \(name). AppleScript error \(permission).")
        }
    }

    private nonisolated static func playerStateStatus(for provider: NowPlayingProvider) -> ProviderConnectionStatus {
        let name = displayName(for: provider)
        let script = #"tell application id "\#(bundleIdentifier(for: provider))" to get player state as string"#

        var error: NSDictionary?
        let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&error)

        guard let descriptor, error == nil else {
            let errorNumber = (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            if errorNumber == Int(errAEEventNotPermitted) {
                return .blocked("macOS is blocking Automation access to \(name). Turn PlayStatus back on under Privacy & Security → Automation.")
            }

            let errorMessage = (error?[NSAppleScript.errorMessage] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let errorMessage, !errorMessage.isEmpty {
                return .failed("Couldn't read playback from \(name). \(errorMessage)")
            }
            if let errorNumber {
                return .failed("Couldn't read playback from \(name). AppleScript error \(errorNumber).")
            }
            return .failed("Couldn't read playback from \(name).")
        }

        let playerState = descriptor.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch playerState {
        case "playing":
            return .connected("Connected. \(name) is playing right now.")
        case "paused":
            return .connected("Connected. \(name) is paused right now.")
        default:
            return .connected("Connected. \(name) is open but not playing anything.")
        }
    }

    private nonisolated static func automationPermission(
        for bundleIdentifier: String,
        askUserIfNeeded: Bool
    ) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        guard let descriptor = target.aeDesc else {
            return OSStatus(errAENotAEDesc)
        }

        return AEDeterminePermissionToAutomateTarget(
            descriptor,
            typeWildCard,
            typeWildCard,
            askUserIfNeeded
        )
    }

    nonisolated static func displayName(for provider: NowPlayingProvider) -> String {
        switch provider {
        case .music, .none:
            return "Apple Music"
        case .spotify:
            return "Spotify"
        }
    }

    private nonisolated static func bundleIdentifier(for provider: NowPlayingProvider) -> String {
        switch provider {
        case .music, .none:
            return "com.apple.Music"
        case .spotify:
            return "com.spotify.client"
        }
    }

    private nonisolated static func applicationURL(for provider: NowPlayingProvider) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier(for: provider))
    }

    private nonisolated static func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
