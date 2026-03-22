import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \HistoryEntry.date, order: .reverse) private var entries: [HistoryEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var confirmingDelete: String?
    @State private var deletingId: String?
    @State private var copiedId: String?
    @State private var deleteErrors: [String: String] = [:]

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No Deployments", systemImage: "clock")
                } description: {
                    Text("Deploy your first Keynote presentation!")
                }
            } else {
                historyList
            }
        }
        .navigationTitle("Deployment History")
    }

    private var historyList: some View {
        List(entries, id: \.id) { entry in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.title)
                        .font(.body.weight(.semibold))
                    Spacer()
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text("\(entry.projectName) \u{00B7} \(entry.slideCount) slides \u{00B7} \(entry.fixesApplied) fixes")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(entry.url)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()

                    Button(copiedId == entry.id ? "Copied!" : "Copy URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.url, forType: .string)
                        copiedId = entry.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if copiedId == entry.id { copiedId = nil }
                        }
                    }
                    .controlSize(.small)

                    Button("Open") {
                        if let url = URL(string: entry.url) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)

                    if confirmingDelete == entry.id {
                        Button("Cancel") {
                            confirmingDelete = nil
                        }
                        .controlSize(.small)
                        .disabled(deletingId == entry.id)

                        Button("Confirm Delete", role: .destructive) {
                            Task { await deleteEntry(entry) }
                        }
                        .controlSize(.small)
                        .disabled(deletingId == entry.id)
                    } else {
                        Button(role: .destructive) {
                            confirmingDelete = entry.id
                        } label: {
                            Image(systemName: "trash")
                        }
                        .controlSize(.small)
                    }
                }

                if confirmingDelete == entry.id {
                    Text("This will permanently delete \(entry.projectName).vercel.app")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let error = deleteErrors[entry.id] {
                    Text("\(error) — removed from history")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func deleteEntry(_ entry: HistoryEntry) async {
        deletingId = entry.id
        deleteErrors[entry.id] = nil

        // Try to delete from Vercel first
        do {
            let settings = try FileOperations.loadSettings()
            if !settings.vercelToken.isEmpty {
                let api = VercelAPI(token: settings.vercelToken, teamId: settings.vercelTeamId)
                try await api.deleteProject(id: entry.projectName)
            }
        } catch {
            // Vercel delete failed — still remove locally
            deleteErrors[entry.id] = "Vercel deletion failed"
        }

        // Always remove from local history
        modelContext.delete(entry)

        deletingId = nil
        confirmingDelete = nil
    }
}
