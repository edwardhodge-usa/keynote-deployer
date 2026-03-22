import Foundation
import Sparkle

/// Wraps Sparkle's SPUStandardUpdaterController for SwiftUI integration.
/// Provides observable state for "Check for Updates" menu item.
@MainActor
final class UpdaterService: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe the updater's canCheckForUpdates property
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
