import SwiftUI
import SwiftData

struct ProjectsView: View {
    let onSelectProject: (String) -> Void
    var onSelectVideoProject: ((String) -> Void)? = nil

    @Query(sort: \HistoryEntry.date, order: .reverse) private var historyEntries: [HistoryEntry]

    /// Known NON-deck Vercel projects to hide by default (Vercel has no folders, so the
    /// team list mixes these in). Extend as new infra projects appear, or set a project
    /// name prefix in Settings for strict deck-only filtering instead.
    private static let infraProjects: Set<String> = [
        "fleet-dashboard", "cloud", "ils-portal-publish", "imaginelab-portal"
    ]

    @State private var projects: [VercelProject] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var confirmingDelete: String?
    @State private var deletingId: String?
    @State private var copiedId: String?
    /// Per-project security state (true=secure CSP, false=open, absent=probing/unknown).
    @State private var secure: [String: Bool] = [:]
    /// When on, list ALL Vercel projects (not just ones in local deploy history) so
    /// deployments made elsewhere can still be seen + deleted.
    @AppStorage("projectsShowAll") private var showAll = false
    /// Sort order for the project list (persisted). Name = A→Z; Created/Modified = newest first.
    @AppStorage("projectsSort") private var sortRaw = ProjectSort.modified.rawValue

    private var sortedProjects: [VercelProject] {
        switch ProjectSort(rawValue: sortRaw) ?? .modified {
        case .name:     return projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .created:  return projects.sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
        case .modified: return projects.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
        }
    }

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
            ToolbarItem(placement: .automatic) {
                Picker("Sort", selection: $sortRaw) {
                    ForEach(ProjectSort.allCases) { s in Text(s.label).tag(s.rawValue) }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .help("Sort projects by name, created date, or last modified")
            }
            ToolbarItem(placement: .automatic) {
                Toggle("Show all", isOn: $showAll)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("List every Vercel project, not just ones deployed from this app")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await loadProjects() }
                }
                .disabled(isLoading)
            }
        }
        .task { await loadProjects() }
        .onChange(of: showAll) { _, _ in Task { await loadProjects() } }
    }

    private var projectList: some View {
        List {
            ForEach(sortedProjects, id: \.id) { (project: VercelProject) in
                ProjectRow(
                    project: project,
                    isSecure: secure[project.id],
                    isConfirmingDelete: confirmingDelete == project.id,
                    isDeleting: deletingId == project.id,
                    copiedId: copiedId,
                    onUpdate: { routeUpdate(project) },
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

            // Vercel has no per-project folders; the whole team's projects come back in one
            // list (decks mixed with fleet-dashboard / cloud / portal). Scope the view to DECKS:
            //   • "Show all" ON  → every team project (to see/delete non-decks).
            //   • prefix SET     → STRICT container mode: only projects whose name starts with
            //     the Settings prefix (e.g. "ilsdeck-"). Robust once you adopt a prefix.
            //   • prefix EMPTY   → default: every project EXCEPT the known non-deck infra below.
            //     (Local deploy history is unreliable here — it's empty on this machine — so we
            //     don't depend on it. Add any new non-deck project to `infraProjects`.)
            let prefix = settings.projectNamePrefix.trimmingCharacters(in: .whitespaces)
            let fetched = try await api.fetchProjects(deployedNames: nil)

            projects = fetched
                .filter { p in
                    if showAll { return true }
                    if !prefix.isEmpty { return p.name.hasPrefix(prefix) }
                    return !Self.infraProjects.contains(p.name)
                }
                .sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        await probeSecurity(projects)   // fill 🔒/🔓 badges in the background
    }

    /// Concurrently probe each deck's live CSP header → security badge state.
    private func probeSecurity(_ items: [VercelProject]) async {
        await withTaskGroup(of: (String, Bool?).self) { group in
            for p in items {
                guard let u = p.productionUrl, !u.isEmpty else { continue }
                group.addTask { (p.id, await VercelAPI.probeSecure(url: u)) }
            }
            for await (id, val) in group where val != nil {
                secure[id] = val
            }
        }
    }

    /// Route "Update" to the right deploy flow: video decks (history folderPath is a
    /// video file) → Deploy Video with the project name preset; otherwise HTML Deploy.
    private func routeUpdate(_ project: VercelProject) {
        if let onSelectVideoProject,
           let entry = historyEntries.first(where: { $0.projectName == project.name }),
           VideoDeployLogic.isVideoDeck(folderPath: entry.folderPath) {
            onSelectVideoProject(project.name)
        } else {
            onSelectProject(project.name)
        }
    }

    private func deleteProject(_ project: VercelProject) async {
        deletingId = project.id
        do {
            let settings = try FileOperations.loadSettings()
            let api = VercelAPI(token: settings.vercelToken, teamId: settings.vercelTeamId)
            try await api.deleteProject(name: project.name)
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

/// Project list sort order (persisted via @AppStorage as the raw value).
enum ProjectSort: String, CaseIterable, Identifiable {
    case name, created, modified
    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: "Name"
        case .created: "Date Created"
        case .modified: "Date Modified"
        }
    }
}

private struct ProjectRow: View {
    let project: VercelProject
    /// true = Secure Embed (frame-ancestors CSP), false = open, nil = probing/unknown.
    var isSecure: Bool? = nil
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
                        if let isSecure {
                            Image(systemName: isSecure ? "lock.fill" : "lock.open.fill")
                                .font(.caption)
                                .foregroundStyle(isSecure ? .green : .orange)
                                .help(isSecure ? "Secure Embed — restricted to portal domains (frame-ancestors CSP)"
                                                : "Open — embeddable / downloadable anywhere")
                        }
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
