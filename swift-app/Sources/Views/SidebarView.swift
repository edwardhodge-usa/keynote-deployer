import SwiftUI

struct SidebarView: View {
    @Binding var selectedTab: NavigationTab

    var body: some View {
        List(NavigationTab.allCases, selection: $selectedTab) { tab in
            Label(tab.label, systemImage: tab.systemImage)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .navigationTitle("Keynote Deployer")
    }
}
