import SwiftUI

struct ProjectsView: View {
    let onSelectProject: (String) -> Void

    @State private var projects: [VercelProject] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var confirmingDelete: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading projects...")
            } else if !errorMessage.isEmpty {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { loadProjects() }
                }
            } else if projects.isEmpty {
                ContentUnavailableView {
                    Label("No Projects", systemImage: "cube.transparent")
                } description: {
                    Text("Deploy your first Keynote presentation!")
                }
            } else {
                projectList
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    loadProjects()
                }
                .disabled(isLoading)
            }
        }
        .task { loadProjects() }
    }

    private var projectList: some View {
        List {
            ForEach(Array(projects), id: \.id) { (project: VercelProject) in
                ProjectRow(
                    project: project,
                    onUpdate: { onSelectProject(project.name) },
                    onDelete: { confirmingDelete = project.id }
                )
            }
        }
    }

    private func loadProjects() {
        isLoading = true
        errorMessage = ""
        // TODO: Call VercelAPI.fetchProjects
        isLoading = false
    }
}

// MARK: - Project Row

private struct ProjectRow: View {
    let project: VercelProject
    let onUpdate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor(for: project.latestDeployment?.state))
                        .frame(width: 8, height: 8)
                    Text(project.name)
                        .font(.body.weight(.medium))
                    if let deploy = project.latestDeployment {
                        Text(formatDate(deploy.createdAt))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let url = project.productionUrl {
                    Text("https://\(url)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Update", action: onUpdate)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func dotColor(for state: DeploymentState?) -> Color {
        switch state {
        case .ready: .green
        case .error: .red
        case .building, .queued: .yellow
        case .canceled, nil: .gray
        }
    }

    private func formatDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp / 1000))
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
