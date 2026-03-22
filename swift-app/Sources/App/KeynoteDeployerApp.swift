import SwiftUI
import SwiftData

@main
struct KeynoteDeployerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [HistoryEntry.self])
        .windowStyle(.titleBar)
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
        }
    }
}

extension Notification.Name {
    static let navigateToTab = Notification.Name("navigateToTab")
}
