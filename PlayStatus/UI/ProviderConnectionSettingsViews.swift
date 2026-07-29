import SwiftUI

struct ProviderConnectionSection: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var inspector: ProviderConnectionInspector

    var body: some View {
        SettingsCard(header: "Connections") {
            Button {
                inspector.refreshAll()
            } label: {
                Label("Check Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(inspector.musicStatus.isChecking && inspector.spotifyStatus.isChecking)
        } content: {
            ProviderConnectionRow(
                provider: .music,
                isEnabled: $model.enableMusic,
                inspector: inspector
            )

            SettingsRowDivider()

            ProviderConnectionRow(
                provider: .spotify,
                isEnabled: $model.enableSpotify,
                inspector: inspector
            )

            SettingsCardNote(
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
    @Binding var isEnabled: Bool
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
        HStack(alignment: .center, spacing: 11) {
            ProviderIconView(icon: provider.iconKind, size: 15, weight: .semibold)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 13, weight: .semibold))

                Label(status.label, systemImage: status.systemImage)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(isEnabled ? status.tint : .secondary)
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
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(status.isChecking || !status.isInstalled)

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(Text("Enable \(displayName)"))
            }
            .opacity(isEnabled ? 1.0 : 0.55)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.18), value: status)
    }
}
