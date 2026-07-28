import SwiftUI

struct ProviderConnectionSection: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var inspector: ProviderConnectionInspector

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsControlRow(
                title: "Connection Status",
                caption: "Check that macOS lets PlayStatus control your players through Automation."
            ) {
                Button {
                    inspector.refreshAll()
                } label: {
                    Label("Check Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(inspector.musicStatus.isChecking && inspector.spotifyStatus.isChecking)
            }

            ProviderConnectionRow(
                provider: .music,
                isEnabledInApp: model.enableMusic,
                inspector: inspector
            )

            ProviderConnectionRow(
                provider: .spotify,
                isEnabledInApp: model.enableSpotify,
                inspector: inspector
            )

            SettingsNoteCard(
                text: "Verify opens the player if it is closed, then asks macOS to confirm access. If access was denied earlier, macOS will not ask again — turn PlayStatus back on in Privacy & Security → Automation."
            )
        }
        .onAppear {
            inspector.refreshAll()
        }
    }
}

private struct ProviderConnectionRow: View {
    let provider: NowPlayingProvider
    let isEnabledInApp: Bool
    @ObservedObject var inspector: ProviderConnectionInspector

    private var status: ProviderConnectionStatus {
        inspector.status(for: provider)
    }

    private var displayName: String {
        ProviderConnectionInspector.displayName(for: provider)
    }

    private var verifyTitle: String {
        if status.isChecking { return "Checking..." }
        return inspector.isRunning(provider) ? "Verify" : "Open & Verify"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ProviderIconView(icon: provider.iconKind, size: 15, weight: .semibold)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .semibold))

                    if !isEnabledInApp {
                        Text("Disabled")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.primary.opacity(0.08))
                            )
                    }
                }

                Label(status.label, systemImage: status.systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(status.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if status.isChecking {
                    ProgressView()
                        .controlSize(.small)
                }

                if status.isBlocked {
                    Button("Privacy Settings") {
                        inspector.openAutomationPrivacySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button(verifyTitle) {
                    inspector.verify(provider)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(status.isChecking || !status.isInstalled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(status.tint.opacity(0.22), lineWidth: 1)
                )
        )
        .animation(.smooth(duration: 0.18), value: status)
    }
}
