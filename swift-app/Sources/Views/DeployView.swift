import SwiftUI

struct DeployView: View {
    let selectedProject: String?
    let onProjectUsed: () -> Void

    enum Phase {
        case select, confirm, processing, complete, error
    }

    @State private var phase: Phase = .select
    @State private var folderPath = ""
    @State private var metadata: KeynoteMetadata?
    @State private var projectName = ""
    @State private var steps = ProcessingStep.allSteps
    @State private var result: PipelineResult?
    @State private var errorMessage = ""
    @State private var secureEmbed = true
    @State private var isDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch phase {
                case .select:
                    selectPhase
                case .confirm:
                    confirmPhase
                case .processing:
                    processingPhase
                case .complete:
                    completePhase
                case .error:
                    errorPhase
                }
            }
            .padding(32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Deploy")
    }

    // MARK: - Select Phase

    private var selectPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deploy Keynote")
                .font(.title2.weight(.semibold))
            Text("Select a Keynote HTML export folder to process and deploy.")
                .foregroundStyle(.secondary)

            // Drop zone
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("Click to browse or drag & drop")
                    .font(.body.weight(.medium))
                Text("Select the exported Keynote folder containing assets/player/main.js")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isDropTargeted ? Color.accentColor : .secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6]))
            }
            .contentShape(Rectangle())
            .onTapGesture { selectFolder() }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Confirm Phase

    private var confirmPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm & Deploy")
                .font(.title2.weight(.semibold))

            if let metadata {
                GroupBox {
                    LabeledContent("Title", value: metadata.title)
                    LabeledContent("Slides", value: "\(metadata.slideCount)")
                    LabeledContent("Dimensions", value: "\(metadata.width) x \(metadata.height)")
                }

                TextField("Project Name", text: $projectName)
                    .textFieldStyle(.roundedBorder)

                Toggle("Secure Embed", isOn: $secureEmbed)
                    .toggleStyle(.switch)

                HStack(spacing: 12) {
                    Button("Back") { reset() }
                    Button("Process & Deploy") {
                        // TODO: Implement pipeline
                        phase = .processing
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(projectName.isEmpty)
                }
            }
        }
    }

    // MARK: - Processing Phase

    private var processingPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deploying...")
                .font(.title2.weight(.semibold))
            Text("Applying fixes and deploying to Vercel.")
                .foregroundStyle(.secondary)

            DeployProgressView(steps: steps)
        }
    }

    // MARK: - Complete Phase

    private var completePhase: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Deployed Successfully")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.green)

            if let result {
                Text("\(result.fixesApplied) fixes applied, \(result.fixesSkipped) skipped")
                    .foregroundStyle(.secondary)

                GroupBox {
                    HStack {
                        Text(result.url)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Spacer()
                        Button("Copy URL") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(result.url, forType: .string)
                        }
                    }
                }
            }

            Button("Deploy Another") { reset() }
        }
    }

    // MARK: - Error Phase

    private var errorPhase: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.red)
            Text("Deployment Failed")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.red)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.callout.monospaced())
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                Button("Start Over") { reset() }
                Button("Retry") {
                    // TODO: Retry pipeline
                    phase = .processing
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Select Keynote HTML Export Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        validateFolder(url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                validateFolder(url)
            }
        }
        return true
    }

    private func validateFolder(_ url: URL) {
        // TODO: Call FileOperations.validateKeynoteFolder
        folderPath = url.path
        errorMessage = ""
    }

    private func reset() {
        phase = .select
        folderPath = ""
        metadata = nil
        projectName = ""
        steps = ProcessingStep.allSteps
        result = nil
        errorMessage = ""
        onProjectUsed()
    }
}
