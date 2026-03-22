import SwiftUI

struct ContentView: View {
    @State private var selectedTab: NavigationTab = .deploy
    @State private var selectedProject: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab)
        } detail: {
            switch selectedTab {
            case .deploy:
                DeployView(
                    selectedProject: selectedProject,
                    onProjectUsed: { selectedProject = nil }
                )
            case .projects:
                ProjectsView(onSelectProject: { name in
                    selectedProject = name
                    selectedTab = .deploy
                })
            case .history:
                HistoryView()
            case .settings:
                SettingsView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTab)) { notification in
            if let tab = notification.object as? NavigationTab {
                selectedTab = tab
            }
        }
    }
}
