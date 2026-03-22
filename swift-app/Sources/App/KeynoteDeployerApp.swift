import SwiftUI
import SwiftData

@main
struct KeynoteDeployerApp: App {
    @StateObject private var updater = UpdaterService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(updater)
        }
        .modelContainer(for: [HistoryEntry.self])
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 1000)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Deployment") {
                    NotificationCenter.default.post(
                        name: .navigateToTab,
                        object: NavigationTab.deploy
                    )
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings\u{2026}") {
                    NotificationCenter.default.post(
                        name: .navigateToTab,
                        object: NavigationTab.settings
                    )
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}

extension Notification.Name {
    static let navigateToTab = Notification.Name("navigateToTab")
}
