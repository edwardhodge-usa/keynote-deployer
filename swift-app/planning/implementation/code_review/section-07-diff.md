# Section 07 — View + Navigation: staged diff

```diff
diff --git a/swift-app/Sources/Models/GifDeploy.swift b/swift-app/Sources/Models/GifDeploy.swift
index a941544..8334e47 100644
--- a/swift-app/Sources/Models/GifDeploy.swift
+++ b/swift-app/Sources/Models/GifDeploy.swift
@@ -62,3 +62,21 @@ enum GifDeployError: Error {
     case fileNotFound(path: String)
     case vercelDeployFailed(underlying: Error)
 }
+
+extension GifDeployError {
+    /// User-facing message shown in `GifDeployView`'s error phase. Unit-tested.
+    var userMessage: String {
+        switch self {
+        case .invalidGifFile:
+            return "The selected file does not appear to be a valid GIF."
+        case .tooFewFrames(let count):
+            return "This GIF has too few frames (\(count)) to detect slides."
+        case .decodingFailed(let reason):
+            return "Could not decode the GIF: \(reason)."
+        case .fileNotFound:
+            return "The selected file could not be found."
+        case .vercelDeployFailed(let underlying):
+            return "Deployment failed: \(underlying.localizedDescription)."
+        }
+    }
+}
diff --git a/swift-app/Sources/Models/NavigationTab.swift b/swift-app/Sources/Models/NavigationTab.swift
index 6fa36ac..2fa8816 100644
--- a/swift-app/Sources/Models/NavigationTab.swift
+++ b/swift-app/Sources/Models/NavigationTab.swift
@@ -2,6 +2,7 @@ import Foundation
 
 enum NavigationTab: String, CaseIterable, Identifiable, Sendable {
     case deploy
+    case gifDeploy
     case projects
     case history
     case settings
@@ -11,6 +12,7 @@ enum NavigationTab: String, CaseIterable, Identifiable, Sendable {
     var label: String {
         switch self {
         case .deploy: "Deploy"
+        case .gifDeploy: "GIF Deploy"
         case .projects: "Projects"
         case .history: "History"
         case .settings: "Settings"
@@ -20,6 +22,7 @@ enum NavigationTab: String, CaseIterable, Identifiable, Sendable {
     var systemImage: String {
         switch self {
         case .deploy: "cube"
+        case .gifDeploy: "photo.stack"
         case .projects: "rectangle.grid.1x2"
         case .history: "clock"
         case .settings: "gearshape"
diff --git a/swift-app/Sources/Views/ContentView.swift b/swift-app/Sources/Views/ContentView.swift
index 763a3bf..0b28f9c 100644
--- a/swift-app/Sources/Views/ContentView.swift
+++ b/swift-app/Sources/Views/ContentView.swift
@@ -14,6 +14,8 @@ struct ContentView: View {
                     selectedProject: selectedProject,
                     onProjectUsed: { selectedProject = nil }
                 )
+            case .gifDeploy:
+                GifDeployView()
             case .projects:
                 ProjectsView(onSelectProject: { name in
                     selectedProject = name
diff --git a/swift-app/Sources/Views/GifDeployView.swift b/swift-app/Sources/Views/GifDeployView.swift
new file mode 100644
index 0000000..5b4358f
--- /dev/null
+++ b/swift-app/Sources/Views/GifDeployView.swift
@@ -0,0 +1,498 @@
+import SwiftUI
+import SwiftData
+import UniformTypeIdentifiers
+
+/// Sendable carrier for the off-main pipeline result. `CGImage` is not formally
+/// Sendable; the thumbnails are produced once off-main and only read (for display)
+/// after the hop to `@MainActor`, so `@unchecked Sendable` is safe here.
+private struct PipelineOutput: @unchecked Sendable {
+    let slides: [DetectedSlide]
+    let thumbnails: [Int: CGImage]
+}
+
+struct GifDeployView: View {
+    @Environment(\.modelContext) private var modelContext
+
+    enum Phase {
+        case selectGif, loading, confirm, processing, complete, error
+    }
+
+    @State private var phase: Phase = .selectGif
+    @State private var gifPath = ""
+    @State private var slides: [DetectedSlide] = []
+    @State private var thumbnails: [Int: CGImage] = [:]
+    @State private var projectName = ""
+    @State private var secureEmbed = true
+    @State private var steps: [ProcessingStep] = GifDeployView.gifSteps
+    @State private var result: GifDeployResult?
+    @State private var errorMessage = ""
+    @State private var isDropTargeted = false
+    @State private var copied: String?
+
+    /// Whether the last error happened during the detection pipeline (Retry → re-run
+    /// the pipeline) vs. during deploy (Retry → re-run deploy).
+    @State private var errorDuringDeploy = false
+
+    /// Handle to the running detection pipeline so Cancel / re-selection can abort it.
+    @State private var pipelineTask: Task<Void, Never>?
+
+    /// GIF-deploy progress steps (subset of the 16-step pipeline that the GIF path emits).
+    static let gifSteps: [ProcessingStep] = [
+        ProcessingStep(id: 12, label: "Vercel project", detail: "", status: .pending),
+        ProcessingStep(id: 13, label: "Deploy", detail: "", status: .pending),
+        ProcessingStep(id: 16, label: "Complete", detail: "", status: .pending),
+    ]
+
+    var body: some View {
+        ScrollView {
+            VStack(spacing: 0) {
+                switch phase {
+                case .selectGif:  selectGifPhase
+                case .loading:    loadingPhase
+                case .confirm:    confirmPhase
+                case .processing: processingPhase
+                case .complete:   completePhase
+                case .error:      errorPhase
+                }
+            }
+            .padding(32)
+            .frame(maxWidth: 520)
+            .frame(maxWidth: .infinity)
+        }
+        .navigationTitle("GIF Deploy")
+    }
+
+    // MARK: - Select GIF Phase
+
+    private var selectGifPhase: some View {
+        VStack(alignment: .leading, spacing: 16) {
+            Text("Deploy a Keynote GIF")
+                .font(.title2.weight(.semibold))
+            Text("Select a Keynote-exported animated GIF to deploy as an interactive slide viewer.")
+                .foregroundStyle(.secondary)
+
+            VStack(spacing: 12) {
+                Image(systemName: "photo.badge.plus")
+                    .font(.system(size: 36))
+                    .foregroundStyle(.tertiary)
+                Text("Click to browse or drag & drop")
+                    .font(.body.weight(.medium))
+                Text("Select a single animated .gif exported from Keynote")
+                    .font(.caption)
+                    .foregroundStyle(.tertiary)
+            }
+            .frame(maxWidth: .infinity)
+            .padding(.vertical, 40)
+            .background {
+                RoundedRectangle(cornerRadius: 10)
+                    .strokeBorder(isDropTargeted ? Color.accentColor : .secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6]))
+            }
+            .contentShape(Rectangle())
+            .onTapGesture { selectGif() }
+            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
+                handleDrop(providers)
+            }
+
+            if !errorMessage.isEmpty {
+                Text(errorMessage)
+                    .font(.callout)
+                    .foregroundStyle(.red)
+                    .padding(12)
+                    .frame(maxWidth: .infinity, alignment: .leading)
+                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
+            }
+        }
+    }
+
+    // MARK: - Loading Phase
+
+    private var loadingPhase: some View {
+        VStack(spacing: 16) {
+            ProgressView()
+                .controlSize(.large)
+            Text("Decoding frames and detecting slides…")
+                .font(.body.weight(.medium))
+            Text("This runs in the background — the app stays responsive.")
+                .font(.caption)
+                .foregroundStyle(.secondary)
+            Button("Cancel") {
+                pipelineTask?.cancel()
+                resetToSelect()
+            }
+            .controlSize(.large)
+        }
+        .frame(maxWidth: .infinity)
+        .padding(.vertical, 40)
+    }
+
+    // MARK: - Confirm Phase
+
+    private var confirmPhase: some View {
+        VStack(alignment: .leading, spacing: 16) {
+            Text("Confirm & Deploy")
+                .font(.title2.weight(.semibold))
+
+            // Thumbnail preview — exactly slides.count images.
+            ScrollView(.horizontal, showsIndicators: true) {
+                HStack(spacing: 8) {
+                    ForEach(Array(slides.enumerated()), id: \.offset) { _, slide in
+                        if let cg = thumbnails[slide.restFrame] {
+                            Image(decorative: cg, scale: 1, orientation: .up)
+                                .resizable()
+                                .aspectRatio(contentMode: .fit)
+                                .frame(width: 120)
+                                .background(Color.black.opacity(0.2))
+                                .clipShape(RoundedRectangle(cornerRadius: 6))
+                        } else {
+                            RoundedRectangle(cornerRadius: 6)
+                                .fill(.secondary.opacity(0.15))
+                                .frame(width: 120, height: 68)
+                                .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
+                        }
+                    }
+                }
+                .padding(.vertical, 4)
+            }
+
+            Text("Automatic detection is a best-effort preview; precise Still-image matching is coming in a later update.")
+                .font(.caption)
+                .foregroundStyle(.secondary)
+
+            GroupBox {
+                LabeledContent("Slides", value: "\(slides.count)")
+                LabeledContent("GIF") {
+                    Text(gifPath)
+                        .font(.caption.monospaced())
+                        .lineLimit(1)
+                        .truncationMode(.middle)
+                }
+            }
+
+            TextField("Project Name", text: $projectName)
+                .textFieldStyle(.roundedBorder)
+                .font(.callout.monospaced())
+
+            if !projectName.isEmpty {
+                Text("URL will be: https://\(projectName).vercel.app")
+                    .font(.caption)
+                    .foregroundStyle(.tertiary)
+            }
+
+            Toggle("Secure Embed — disable downloads, restrict embedding to portal", isOn: $secureEmbed)
+                .toggleStyle(.switch)
+                .font(.caption)
+
+            HStack(spacing: 12) {
+                Button("Back") { resetToSelect() }
+                Button("Deploy") { startDeploy() }
+                    .buttonStyle(.borderedProminent)
+                    .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
+            }
+        }
+    }
+
+    // MARK: - Processing Phase
+
+    private var processingPhase: some View {
+        VStack(alignment: .leading, spacing: 16) {
+            Text("Deploying…")
+                .font(.title2.weight(.semibold))
+            Text("Generating the viewer and deploying to Vercel.")
+                .foregroundStyle(.secondary)
+
+            DeployProgressView(steps: steps)
+        }
+    }
+
+    // MARK: - Complete Phase
+
+    private var completePhase: some View {
+        VStack(spacing: 16) {
+            Image(systemName: "checkmark.circle")
+                .font(.system(size: 44))
+                .foregroundStyle(.green)
+            Text("Deployed Successfully")
+                .font(.title2.weight(.semibold))
+                .foregroundStyle(.green)
+
+            if let result {
+                Text("\(result.slideCount) slides")
+                    .foregroundStyle(.secondary)
+
+                GroupBox {
+                    VStack(spacing: 12) {
+                        HStack {
+                            Text(result.url)
+                                .font(.caption.monospaced())
+                                .textSelection(.enabled)
+                            Spacer()
+                            Button(copied == "url" ? "Copied!" : "Copy URL") {
+                                copyText(result.url, label: "url")
+                            }
+                            .controlSize(.small)
+                        }
+
+                        Divider()
+
+                        HStack(spacing: 8) {
+                            Button(copied == "embed" ? "Copied!" : "Copy Framer Embed") {
+                                let embed = "<iframe src=\"\(result.url)\" style=\"width:100%;height:100%;border:none\" allowfullscreen></iframe>"
+                                copyText(embed, label: "embed")
+                            }
+                            .controlSize(.small)
+
+                            Spacer()
+
+                            Button("Open in Browser") {
+                                if let url = URL(string: result.url) {
+                                    NSWorkspace.shared.open(url)
+                                }
+                            }
+                            .controlSize(.small)
+                        }
+                    }
+                }
+            }
+
+            Button("Deploy Another") { resetToSelect() }
+        }
+    }
+
+    // MARK: - Error Phase
+
+    private var errorPhase: some View {
+        VStack(spacing: 16) {
+            Image(systemName: "xmark.circle")
+                .font(.system(size: 44))
+                .foregroundStyle(.red)
+            Text("Couldn't Continue")
+                .font(.title2.weight(.semibold))
+                .foregroundStyle(.red)
+
+            if errorDuringDeploy {
+                DeployProgressView(steps: steps)
+            }
+
+            if !errorMessage.isEmpty {
+                Text(errorMessage)
+                    .font(.callout.monospaced())
+                    .foregroundStyle(.red)
+                    .padding(12)
+                    .frame(maxWidth: .infinity, alignment: .leading)
+                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
+            }
+
+            HStack(spacing: 12) {
+                Button("Start Over") { resetToSelect() }
+                Button("Retry") {
+                    if errorDuringDeploy { startDeploy() } else { startPipeline() }
+                }
+                .buttonStyle(.borderedProminent)
+            }
+        }
+    }
+
+    // MARK: - Selection
+
+    private func selectGif() {
+        let panel = NSOpenPanel()
+        panel.canChooseFiles = true
+        panel.canChooseDirectories = false
+        panel.allowsMultipleSelection = false
+        panel.allowedContentTypes = [.gif]
+        panel.title = "Select a Keynote-exported GIF"
+
+        guard panel.runModal() == .OK, let url = panel.url else { return }
+        accept(url)
+    }
+
+    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
+        guard let provider = providers.first else { return false }
+        provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
+            guard let data = item as? Data,
+                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
+            DispatchQueue.main.async {
+                accept(url)
+            }
+        }
+        return true
+    }
+
+    /// Validate the selection is a .gif, seed state, and start the pipeline.
+    private func accept(_ url: URL) {
+        guard url.pathExtension.lowercased() == "gif" else {
+            errorMessage = "The selected file does not appear to be a valid GIF."
+            return
+        }
+        errorMessage = ""
+        gifPath = url.path
+
+        let settings = (try? FileOperations.loadSettings()) ?? .default
+        let base = url.deletingPathExtension().lastPathComponent
+        projectName = settings.projectNamePrefix + AppConfig.toKebabCase(base)
+        secureEmbed = settings.secureEmbed
+
+        startPipeline()
+    }
+
+    // MARK: - Pipeline (off-main)
+
+    private func startPipeline() {
+        pipelineTask?.cancel()
+        phase = .loading
+        slides = []
+        thumbnails = [:]
+        errorMessage = ""
+
+        let path = gifPath
+        pipelineTask = Task {
+            do {
+                let output = try await Self.runPipeline(gifPath: path)
+                try Task.checkCancellation()
+                await MainActor.run {
+                    slides = output.slides
+                    thumbnails = output.thumbnails
+                    phase = .confirm
+                }
+            } catch is CancellationError {
+                await MainActor.run { resetToSelect() }
+            } catch let err as GifDeployError {
+                await MainActor.run {
+                    errorMessage = err.userMessage
+                    errorDuringDeploy = false
+                    phase = .error
+                }
+            } catch {
+                await MainActor.run {
+                    errorMessage = error.localizedDescription
+                    errorDuringDeploy = false
+                    phase = .error
+                }
+            }
+        }
+    }
+
+    /// Heavy decode → sample → detect → targeted-thumbnail pass. `nonisolated async`
+    /// so it provably runs OFF the main actor (a nonisolated async function hops to
+    /// the global executor) while staying inside the pipeline Task's tree, so
+    /// `Task.checkCancellation()` inside GridSampler propagates a user Cancel.
+    /// Streams frames for detection (bounded memory), then a second targeted decode
+    /// pass for only the N rest frames.
+    nonisolated private static func runPipeline(gifPath: String) async throws -> PipelineOutput {
+        let url = URL(fileURLWithPath: gifPath)
+        let source = try GifFrameSource(gifURL: url)          // throws .tooFewFrames
+        try Task.checkCancellation()
+
+        let diffs = try GridSampler.frameDiffs(source)        // streaming; checks cancellation
+        try Task.checkCancellation()
+
+        let detected = SlideDetector.detectSlides(diffs)      // pure array math
+
+        // Separate targeted thumbnail pass — bounded memory (only N rest frames).
+        let restFrames = detected.map { $0.restFrame }
+        let thumbs = source.frames(at: restFrames)
+        try Task.checkCancellation()
+
+        return PipelineOutput(slides: detected, thumbnails: thumbs)
+    }
+
+    // MARK: - Deploy
+
+    private func startDeploy() {
+        phase = .processing
+        steps = Self.gifSteps
+        errorMessage = ""
+
+        let request = GifDeployRequest(
+            gifPath: gifPath,
+            projectName: projectName,
+            slideCount: slides.count,
+            title: URL(fileURLWithPath: gifPath).deletingPathExtension().lastPathComponent,
+            secureEmbed: secureEmbed,
+            slides: slides
+        )
+
+        Task {
+            do {
+                let settings = try FileOperations.loadSettings()
+                guard !settings.vercelToken.isEmpty else {
+                    await MainActor.run {
+                        errorMessage = "Vercel token not configured. Go to Settings first."
+                        errorDuringDeploy = true
+                        phase = .error
+                    }
+                    return
+                }
+
+                let deployResult = try await GifDeployer.deploy(request, settings: settings) { step in
+                    Task { @MainActor in updateStep(step) }
+                }
+
+                await MainActor.run {
+                    // GifDeployer returns the payload; the view persists history (it has modelContext).
+                    let entry = HistoryEntry(
+                        projectName: deployResult.projectName,
+                        title: deployResult.title,
+                        slideCount: deployResult.slideCount,
+                        url: deployResult.url,
+                        folderPath: deployResult.folderPath,
+                        fixesApplied: deployResult.fixesApplied
+                    )
+                    modelContext.insert(entry)
+
+                    if settings.autoCopyUrl {
+                        NSPasteboard.general.clearContents()
+                        NSPasteboard.general.setString(deployResult.url, forType: .string)
+                    }
+                    result = deployResult
+                    phase = .complete
+                }
+            } catch let err as GifDeployError {
+                await MainActor.run {
+                    errorMessage = err.userMessage
+                    errorDuringDeploy = true
+                    phase = .error
+                }
+            } catch {
+                await MainActor.run {
+                    errorMessage = error.localizedDescription
+                    errorDuringDeploy = true
+                    phase = .error
+                }
+            }
+        }
+    }
+
+    // MARK: - Helpers
+
+    @MainActor
+    private func updateStep(_ step: ProcessingStep) {
+        if let index = steps.firstIndex(where: { $0.id == step.id }) {
+            steps[index] = step
+        }
+    }
+
+    private func copyText(_ text: String, label: String) {
+        NSPasteboard.general.clearContents()
+        NSPasteboard.general.setString(text, forType: .string)
+        copied = label
+        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
+            if copied == label { copied = nil }
+        }
+    }
+
+    private func resetToSelect() {
+        pipelineTask?.cancel()
+        pipelineTask = nil
+        phase = .selectGif
+        gifPath = ""
+        slides = []
+        thumbnails = [:]
+        projectName = ""
+        steps = Self.gifSteps
+        result = nil
+        errorMessage = ""
+        errorDuringDeploy = false
+        copied = nil
+    }
+}
diff --git a/swift-app/Tests/NavigationRoutingTests.swift b/swift-app/Tests/NavigationRoutingTests.swift
new file mode 100644
index 0000000..f40026f
--- /dev/null
+++ b/swift-app/Tests/NavigationRoutingTests.swift
@@ -0,0 +1,34 @@
+import Testing
+import Foundation
+@testable import KeynoteDeployer
+
+@Suite("Navigation + GIF error messaging")
+struct NavigationRoutingTests {
+
+    @Test("NavigationTab includes .gifDeploy with non-empty label + systemImage")
+    func gifDeployTabPresent() {
+        #expect(NavigationTab.allCases.contains(.gifDeploy))
+        #expect(!NavigationTab.gifDeploy.label.isEmpty)
+        #expect(!NavigationTab.gifDeploy.systemImage.isEmpty)
+        // Sits next to the HTML-deploy tab.
+        let cases = NavigationTab.allCases
+        let deployIdx = try! cases.firstIndex(of: .deploy)!
+        let gifIdx = try! cases.firstIndex(of: .gifDeploy)!
+        #expect(gifIdx == deployIdx + 1)
+    }
+
+    @Test("each GifDeployError maps to its intended user-facing message")
+    func errorMessages() {
+        #expect(GifDeployError.invalidGifFile(path: "/x.txt").userMessage
+            == "The selected file does not appear to be a valid GIF.")
+        #expect(GifDeployError.tooFewFrames(count: 1).userMessage
+            == "This GIF has too few frames (1) to detect slides.")
+        #expect(GifDeployError.decodingFailed(reason: "boom").userMessage
+            == "Could not decode the GIF: boom.")
+        #expect(GifDeployError.fileNotFound(path: "/x.gif").userMessage
+            == "The selected file could not be found.")
+
+        let wrapped = GifDeployError.vercelDeployFailed(underlying: VercelError.fetchFailed("nope"))
+        #expect(wrapped.userMessage.hasPrefix("Deployment failed:"))
+    }
+}
```
