import SwiftUI
import SwiftData

struct ProjectsView: View {
    let onSelectProject: (String) -> Void

    @Query(sort: \HistoryEntry.date, order: .reverse) private var historyEntries: [HistoryEntry]

    @State private var projects: [VercelProject] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var confirmingDelete: String?
    @State private var deletingId: String?
    @State private var copiedId: String?

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
                    Button("Try Again") { Task { await loadProjects() } }
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
                    Task { await loadProjects() }
                }
                .disabled(isLoading)
            }
        }
        .task { await loadProjects() }
    }

    private var projectList: some View {
        List {
            ForEach(Array(projects), id: \.id) { (project: VercelProject) in
                ProjectRow(
                    project: project,
                    isConfirmingDelete: confirmingDelete == project.id,
                    isDeleting: deletingId == project.id,
                    copiedId: copiedId,
                    onUpdate: { onSelectProject(project.name) },
                    onCopyUrl: { copyUrl(for: project) },
                    onRequestDelete: { confirmingDelete = project.id },
                    onCancelDelete: { confirmingDelete = nil },
                    onConfirmDelete: { Task { await deleteProject(project) } }
                )
            }
        }
    }

    private func loadProjects() async {
        isLoading = true
        errorMessage = ""

        do {
            let settings = try FileOperations.loadSettings()
            guard !settings.vercelToken.isEmpty else {
                errorMessage = "Vercel token not configured. Go to Settings first."
                isLoading = false
                return
            }

            let api = VercelAPI(token: settings.vercelToken, teamId: settings.vercelTeamId)

            // Filter to only projects deployed by Keynote Deployer
            let deployedNames = Set(historyEntries.map(\.projectName))
            let fetched = try await api.fetchProjects(deployedNames: deployedNames)

            projects = fetched.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func deleteProject(_ project: VercelProject) async {
        deletingId = project.id
        do {
            let settings = try FileOperations.loadSettings()
            let api = VercelAPI(token: settings.vercelToken, teamId: settings.vercelTeamId)
            try await api.deleteProject(id: project.id)
            projects.removeAll { $0.id == project.id }
        } catch {
            // Deletion failed — leave in list
        }
        deletingId = nil
        confirmingDelete = nil
    }

    private func copyUrl(for project: VercelProject) {
        let url = "https://\(project.productionUrl ?? "\(project.name).vercel.app")"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        copiedId = project.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedId == project.id { copiedId = nil }
        }
    }
}

// MARK: - Project Row

private struct ProjectRow: View {
    let project: VercelProject
    let isConfirmingDelete: Bool
    let isDeleting: Bool
    let copiedId: String?
    let onUpdate: () -> Void
    let onCopyUrl: () -> Void
    let onRequestDelete: () -> Void
    let onCancelDelete: () -> Void
    let onConfirmDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                    if isConfirmingDelete {
                        Button("Cancel", action: onCancelDelete)
                            .controlSize(.small)
                            .disabled(isDeleting)

                        Button("Delete", role: .destructive) {
                            onConfirmDelete()
                        }
                        .controlSize(.small)
                        .disabled(isDeleting)
                    } else {
                        Button(copiedId == project.id ? "Copied!" : "Copy URL", action: onCopyUrl)
                            .controlSize(.small)

                        Button("Update", action: onUpdate)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                        Button(role: .destructive, action: onRequestDelete) {
                            Image(systemName: "trash")
                        }
                        .controlSize(.small)
                    }
                }
            }

            if isConfirmingDelete {
                Text("This will permanently delete \(project.name) from Vercel.")
                    .font(.caption)
                    .foregroundStyle(.red)
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
