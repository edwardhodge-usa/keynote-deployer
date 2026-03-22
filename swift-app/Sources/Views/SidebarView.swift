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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            versionFooter
        }
    }

    private var versionFooter: some View {
        HStack {
            Text("v\(appVersion)")
                .font(.caption2)
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
