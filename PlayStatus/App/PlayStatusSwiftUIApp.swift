import SwiftUI

@main
struct PlayStatusSwiftUIApp: App {
    @NSApplicationDelegateAdaptor(StatusBarController.self) private var statusBarController
    @StateObject private var model = NowPlayingModel.shared
    private let onboarding = OnboardingCoordinator.shared

    var body: some Scene {
        Settings {
            PlayStatusSettingsView(model: model, onboarding: onboarding)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Show Walkthrough") {
                    onboarding.replayFullWalkthrough()
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }
    }
}
