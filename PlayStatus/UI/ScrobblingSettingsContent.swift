import SwiftUI
import AppKit
import Combine

/// The Scrobbling pane. Built from the shared `SettingsCard` components so it speaks the same
/// dialect as every other tab.
struct ScrobblingSettingsContent: View {
    @ObservedObject var scrobbler: ScrobbleService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            accountCard

            if scrobbler.isConfigured {
                behaviourCard
                queueCard
            }
        }
    }

    // MARK: Account

    @ViewBuilder
    private var accountCard: some View {
        SettingsCard {
            switch scrobbler.connectionState {
            case .notConfigured:
                SettingsStackedRow(
                    title: "Last.fm",
                    caption: "This build of PlayStatus was compiled without Last.fm credentials, so scrobbling is unavailable. Official releases include them."
                ) {
                    SettingsStatusBadge(text: "Unavailable")
                }

            case .disconnected:
                SettingsStackedRow(
                    title: "Last.fm account",
                    caption: "Scrobble what you listen to. PlayStatus opens Last.fm in your browser to sign in — your password is never entered here."
                ) {
                    HStack(spacing: 10) {
                        Spacer(minLength: 8)
                        Button("Connect") { scrobbler.connect() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }

            case .awaitingApproval:
                SettingsStackedRow(
                    title: "Last.fm account",
                    caption: "Approve PlayStatus in the browser window that just opened, then come back here."
                ) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for approval…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        Button("Cancel") { scrobbler.cancelConnect() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

            case .connected(let username):
                SettingsStackedRow(
                    title: "Last.fm account",
                    caption: "Connected. Tracks are scrobbled once you've heard half of them, or four minutes, whichever comes first."
                ) {
                    HStack(spacing: 10) {
                        Button {
                            if let url = URL(string: "https://www.last.fm/user/\(username)") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label(username, systemImage: "person.crop.circle")
                        }
                        .buttonStyle(.link)
                        .controlSize(.small)

                        Spacer(minLength: 8)

                        Button("Disconnect") { scrobbler.disconnect() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

            case .failed(let message):
                SettingsStackedRow(
                    title: "Last.fm account",
                    caption: message
                ) {
                    HStack(spacing: 10) {
                        SettingsStatusBadge(text: "Not connected", tint: .orange)
                        Spacer(minLength: 8)
                        Button("Try Again") { scrobbler.connect() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: Behaviour

    private var behaviourCard: some View {
        SettingsCard {
            SettingsSwitchRow(
                title: "Scrobble to Last.fm",
                caption: "Turn off to stop sending plays without disconnecting your account",
                isOn: $scrobbler.scrobblingEnabled
            )

            SettingsRowDivider()

            SettingsSwitchRow(
                title: "Scrobble from Music",
                isOn: $scrobbler.scrobbleFromMusic
            )
            .disabled(!scrobbler.scrobblingEnabled)

            SettingsRowDivider()

            SettingsSwitchRow(
                title: "Scrobble from Spotify",
                isOn: $scrobbler.scrobbleFromSpotify
            )
            .disabled(!scrobbler.scrobblingEnabled)

            SettingsRowDivider()

            SettingsSwitchRow(
                title: "Send “now playing” updates",
                caption: "Shows the current track on your Last.fm profile as it plays",
                isOn: $scrobbler.sendNowPlayingUpdates
            )
            .disabled(!scrobbler.scrobblingEnabled)

            SettingsRowDivider()

            SettingsRow(
                title: "Ignore tracks shorter than",
                caption: "Last.fm never accepts anything under 30 seconds"
            ) {
                Picker("", selection: $scrobbler.minimumTrackSeconds) {
                    Text("30 seconds").tag(30)
                    Text("45 seconds").tag(45)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .disabled(!scrobbler.scrobblingEnabled)
            }
        }
    }

    // MARK: Queue

    private var queueCard: some View {
        SettingsCard {
            SettingsRow(
                title: "Scrobbled",
                caption: acceptedCaption
            ) {
                Text(acceptedCountText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            SettingsRowDivider()

            SettingsStackedRow(
                title: "Pending scrobbles",
                caption: "Plays are kept on this Mac while Last.fm is unreachable and sent when it comes back"
            ) {
                HStack(spacing: 10) {
                    Text(pendingText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Button("Retry Now") { scrobbler.retryNow() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(scrobbler.pendingCount == 0)
                }
            }

            if !scrobbler.lastStatusMessage.isEmpty {
                SettingsCardNote(text: scrobbler.lastStatusMessage)
            }
        }
    }

    private var acceptedCountText: String {
        scrobbler.acceptedCount == 1 ? "1 track" : "\(scrobbler.acceptedCount) tracks"
    }

    /// Names the window the number actually covers. Never "since you connected" — an account
    /// linked before this counter existed has scrobbles it never saw — and never a lifetime
    /// Last.fm total, which lives on the profile and is larger.
    private var acceptedCaption: String {
        var parts: [String] = []
        if let since = scrobbler.countingSince {
            parts.append("Accepted by Last.fm since \(since.formatted(date: .abbreviated, time: .omitted))")
        } else {
            parts.append("Accepted by Last.fm, counted from now on")
        }
        if let last = scrobbler.lastAcceptedAt {
            let relative = RelativeDateTimeFormatter.scrobbleShared.localizedString(for: last, relativeTo: Date())
            parts.append("most recent \(relative)")
        }
        return parts.joined(separator: " · ")
    }

    private var pendingText: String {
        switch scrobbler.pendingCount {
        case 0: return "Nothing waiting"
        case 1: return "1 waiting"
        default: return "\(scrobbler.pendingCount) waiting"
        }
    }
}

private extension RelativeDateTimeFormatter {
    static let scrobbleShared: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
