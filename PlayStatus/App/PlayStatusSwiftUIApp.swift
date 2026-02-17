import SwiftUI

@main
struct PlayStatusSwiftUIApp: App {
    @NSApplicationDelegateAdaptor(StatusBarController.self) private var statusBarController
    @StateObject private var model = NowPlayingModel.shared

    var body: some Scene {
        Settings {
            PlayStatusSettingsView(model: model)
        }
    }
}
