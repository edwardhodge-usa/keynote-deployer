import SwiftUI
import SwiftData

struct DeployView: View {
    let selectedProject: String?
    let onProjectUsed: () -> Void

    @Environment(\.modelContext) private var modelContext

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
    @State private var isValidating = false
    @State private var copied: String?

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
                if isValidating {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Validating folder...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Click to browse or drag & drop")
                        .font(.body.weight(.medium))
                    Text("Select the exported Keynote folder containing assets/player/main.js")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
                    LabeledContent("Folder") {
                        Text(folderPath)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                TextField("Project Name", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())

                if !projectName.isEmpty {
                    Text(selectedProject != nil
                        ? "Updating existing project: \(projectName)"
                        : "URL will be: https://\(projectName).vercel.app")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Toggle("Secure Embed — disable downloads, restrict embedding to portal", isOn: $secureEmbed)
                    .toggleStyle(.switch)
                    .font(.caption)

                HStack(spacing: 12) {
                    Button("Back") { reset() }
                    Button("Process & Deploy") {
                        startDeploy()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
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

                // URL + Copy
                GroupBox {
                    VStack(spacing: 12) {
                        HStack {
                            Text(result.url)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Spacer()
                            Button(copied == "url" ? "Copied!" : "Copy URL") {
                                copyText(result.url, label: "url")
                            }
                            .controlSize(.small)
                        }

                        Divider()

                        HStack(spacing: 8) {
                            Button(copied == "embed" ? "Copied!" : "Copy Framer Embed") {
                                let embed = "<iframe src=\"\(result.url)\" style=\"width:100%;height:100%;border:none\" allowfullscreen></iframe>"
                                copyText(embed, label: "embed")
                            }
                            .controlSize(.small)

                            Spacer()

                            Button("Open in Browser") {
                                if let url = URL(string: result.url) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .controlSize(.small)
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

            DeployProgressView(steps: steps)

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
                Button("Retry") { startDeploy() }
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
        isValidating = true
        errorMessage = ""

        do {
            let validation = try FileOperations.validateKeynoteFolder(url.path)
            isValidating = false

            if validation.valid, let meta = validation.metadata {
                folderPath = url.path
                metadata = meta

                // Load settings once for prefix + secure embed default
                let settings = (try? FileOperations.loadSettings()) ?? .default

                // Use selectedProject if provided, otherwise generate from title
                if let selectedProject {
                    projectName = selectedProject
                    onProjectUsed()
                } else {
                    projectName = settings.projectNamePrefix + AppConfig.toKebabCase(meta.title)
                }

                secureEmbed = settings.secureEmbed

                phase = .confirm
            } else {
                errorMessage = validation.error ?? "Invalid folder"
            }
        } catch {
            isValidating = false
            errorMessage = "Validation failed: \(error.localizedDescription)"
        }
    }

    private func startDeploy() {
        guard let metadata else { return }
        phase = .processing
        steps = ProcessingStep.allSteps

        Task {
            do {
                let settings = try FileOperations.loadSettings()
                guard !settings.vercelToken.isEmpty else {
                    await MainActor.run {
                        errorMessage = "Vercel token not configured. Go to Settings first."
                        phase = .error
                    }
                    return
                }

                // Steps 1-11: Process keynote folder
                let processor = KeynoteProcessor()
                let processResult = try await processor.process(
                    folderPath: folderPath,
                    metadata: metadata,
                    secureEmbed: secureEmbed,
                    onProgress: { step in
                        Task { @MainActor in
                            updateStep(step)
                        }
                    }
                )

                // Step 12: Ensure Vercel project
                await MainActor.run {
                    updateStep(ProcessingStep(id: 12, label: "Vercel project", detail: "Creating or finding project...", status: .active))
                }

                let api = VercelAPI(token: settings.vercelToken, teamId: settings.vercelTeamId)
                let project = try await api.ensureProject(name: projectName)

                await MainActor.run {
                    updateStep(ProcessingStep(id: 12, label: "Vercel project", detail: "Project: \(project.name)", status: .completed))
                }

                // Step 13: Deploy via CLI
                let deployResult = try await VercelDeployer.deploy(
                    folderPath: folderPath,
                    projectId: project.id,
                    token: settings.vercelToken,
                    teamId: settings.vercelTeamId,
                    secureEmbed: secureEmbed,
                    embedAllowedDomains: settings.embedAllowedDomains,
                    onProgress: { step in
                        Task { @MainActor in
                            updateStep(step)
                        }
                    }
                )

                guard deployResult.success else {
                    await MainActor.run {
                        errorMessage = deployResult.error ?? "Deployment failed"
                        phase = .error
                    }
                    return
                }

                // Resolve actual production URL
                let prodUrl = (try? await api.resolveProductionUrl(projectId: project.id))
                    ?? "https://\(projectName).vercel.app"

                // Step 14: Verify deployment (static file check)
                let verification = await DeploymentVerifier.verify(
                    deployUrl: prodUrl,
                    onProgress: { step in
                        Task { @MainActor in
                            updateStep(step)
                        }
                    }
                )

                // Step 15: Runtime verification (skipped — no Puppeteer equivalent)
                await MainActor.run {
                    updateStep(ProcessingStep(id: 15, label: "Runtime verification", detail: "Skipped (native app)", status: .skipped))
                    updateStep(ProcessingStep(id: 16, label: "Complete", detail: prodUrl, status: .completed))
                }

                // Save to SwiftData history
                let entry = HistoryEntry(
                    projectName: projectName,
                    title: metadata.title,
                    slideCount: metadata.slideCount,
                    url: prodUrl,
                    folderPath: folderPath,
                    fixesApplied: processResult.fixesApplied
                )

                await MainActor.run {
                    modelContext.insert(entry)

                    // Auto-copy URL if enabled
                    if settings.autoCopyUrl {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(prodUrl, forType: .string)
                    }

                    result = PipelineResult(
                        success: true,
                        projectName: projectName,
                        title: metadata.title,
                        slideCount: metadata.slideCount,
                        url: prodUrl,
                        fixesApplied: processResult.fixesApplied,
                        fixesSkipped: processResult.fixesSkipped,
                        verification: verification,
                        error: nil
                    )
                    phase = .complete
                }

                // Save last folder path
                var updatedSettings = settings
                updatedSettings.lastFolderPath = folderPath
                try? FileOperations.saveSettings(updatedSettings)

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    phase = .error
                }
            }
        }
    }

    @MainActor
    private func updateStep(_ step: ProcessingStep) {
        if let index = steps.firstIndex(where: { $0.id == step.id }) {
            steps[index] = step
        }
    }

    private func copyText(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = label
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copied == label { copied = nil }
        }
    }

    private func reset() {
        phase = .select
        folderPath = ""
        metadata = nil
        projectName = ""
        steps = ProcessingStep.allSteps
        result = nil
        errorMessage = ""
        copied = nil
        onProjectUsed()
    }
}
