import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \HistoryEntry.date, order: .reverse) private var entries: [HistoryEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var confirmingDelete: String?

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

                    Button("Copy URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.url, forType: .string)
                    }
                    .controlSize(.small)

                    Button("Open") {
                        if let url = URL(string: entry.url) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)

                    Button(role: .destructive) {
                        modelContext.delete(entry)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
