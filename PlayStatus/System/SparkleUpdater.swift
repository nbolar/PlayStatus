import Foundation
import Sparkle

@MainActor
final class SparkleUpdater: NSObject {
    static let shared = SparkleUpdater()

    private let updaterController: SPUStandardUpdaterController

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func checkForUpdates(_ sender: Any? = nil) {
        updaterController.checkForUpdates(sender)
    }
}
