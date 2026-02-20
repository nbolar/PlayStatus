import Foundation
import Sparkle

@MainActor
final class SparkleUpdater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = SparkleUpdater()

    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }()

    override init() {
        super.init()
        _ = updaterController
        // Remove any legacy Sparkle feed URL persisted by deprecated APIs.
        updaterController.updater.clearFeedURLFromUserDefaults()
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func checkForUpdates(_ sender: Any? = nil) {
        updaterController.checkForUpdates(sender)
    }
}
