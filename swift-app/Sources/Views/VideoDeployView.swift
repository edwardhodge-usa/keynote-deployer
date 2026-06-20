import SwiftUI
import SwiftData
import AVKit
import UniformTypeIdentifiers

/// Pure, SwiftUI-free logic for `VideoDeployView` — extracted so it's unit-testable
/// offline (section-08 tests call these directly).
enum VideoDeployLogic {
    /// Project name = prefix + kebab(filename without extension). Reuses the same
    /// `AppConfig.toKebabCase` the HTML path uses — no new normalization rules.
    static func projectName(prefix: String, filename: String) -> String {
        let base = (filename as NSString).lastPathComponent
        let noExt = (base as NSString).deletingPathExtension
        return prefix + AppConfig.toKebabCase(noExt)
    }

    /// A8: keep only entries whose UTType conforms to `.image`, natural-sorted
    /// (section-02). Drops `.DS_Store`, `Icon\r`, `.txt`, etc.
    static func filterImages(_ urls: [URL]) -> [String] {
        let images = urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        }
        return StillsMatch.naturalSort(images.map(\.path))
    }

    /// Deploy enabled only with a video, at least one still, and a non-blank name.
    static func canDeploy(videoPath: String?, stillCount: Int, projectName: String) -> Bool {
        videoPath != nil && stillCount > 0 &&
            !projectName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Responsive Framer embed using the PROBED aspect ratio — mirrors the Electron
    /// GifViewer.tsx embed (`aspect-ratio:${w}/${h}`, not a hardcoded 16/9).
    static func framerEmbed(url: String, width: Int, height: Int) -> String {
        "<div style=\"position:relative;width:100%;aspect-ratio:\(width)/\(height)\">"
        + "<iframe src=\"\(url)\" style=\"position:absolute;inset:0;width:100%;height:100%;border:none\""
        + " loading=\"lazy\" allowfullscreen></iframe></div>"
    }

    static func humanSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// The video-deck deploy front door: drop an H.264 video + a per-slide stills
/// folder → deploy an interactive video viewer to Vercel. Mirrors the Electron
/// video path and the existing Swift `DeployView` conventions (drop zone,
/// NSOpenPanel, settings reads, HistoryEntry persistence, NSPasteboard auto-copy).
struct VideoDeployView: View {
    @Environment(\.modelContext) private var modelContext

    enum Phase { case drop, confirm, deploying, complete, error }

    // Build the 4 video-pipeline steps (ids 1–4) the deployer emits.
    private static func freshSteps() -> [ProcessingStep] {
        [
            ProcessingStep(id: 1, label: "Analyze video", detail: "", status: .pending),
            ProcessingStep(id: 2, label: "Encode video", detail: "", status: .pending),
            ProcessingStep(id: 3, label: "Generate viewer", detail: "", status: .pending),
            ProcessingStep(id: 4, label: "Deploy to Vercel", detail: "", status: .pending),
        ]
    }

    @State private var phase: Phase = .drop
    @State private var videoPath: String?
    @State private var videoSizeBytes: Int64?
    @State private var videoWidth: Int?
    @State private var videoHeight: Int?
    @State private var player: AVPlayer?      // built once per video (not per render)
    @State private var stillPaths: [String] = []
    @State private var fps: Double = 30
    @State private var projectName = ""
    @State private var secureEmbed = true
    @State private var steps = freshSteps()
    @State private var result: VideoDeployResult?
    @State private var errorMessage = ""
    @State private var probeError: String?
    @State private var isProbing = false
    @State private var isDropTargeted = false
    @State private var copied: String?
    @State private var deployTask: Task<Void, Never>?

    private var slideCount: Int { stillPaths.count }
    private var canDeploy: Bool {
        VideoDeployLogic.canDeploy(videoPath: videoPath, stillCount: slideCount, projectName: projectName)
            && probeError == nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch phase {
                case .drop: dropPhase
                case .confirm: confirmPhase
                case .deploying: deployingPhase
                case .complete: completePhase
                case .error: errorPhase
                }
            }
            .padding(32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Deploy Video")
        .onDisappear { deployTask?.cancel() }
    }

    // MARK: - Drop Phase

    private var dropPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deploy Video Deck")
                .font(.title2.weight(.semibold))
            Text("Drop an H.264 video and a folder of per-slide stills to deploy an interactive slide viewer.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Image(systemName: "film.stack")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("Click to browse or drag & drop")
                    .font(.body.weight(.medium))
                Text("Select an exported H.264 video (.mp4, .mov, .m4v)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isDropTargeted ? Color.accentColor : .secondary.opacity(0.3),
                                  style: StrokeStyle(lineWidth: 1, dash: [6]))
            }
            .contentShape(Rectangle())
            .onTapGesture { chooseVideo() }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }

            if !errorMessage.isEmpty {
                inlineError(errorMessage)
            }
        }
    }

    // MARK: - Confirm Phase

    private var confirmPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure & Deploy")
                .font(.title2.weight(.semibold))

            if let player {
                VideoPlayer(player: player)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            GroupBox {
                LabeledContent("File") {
                    Text((videoPath as NSString?)?.lastPathComponent ?? "—")
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let videoSizeBytes {
                    LabeledContent("Size", value: VideoDeployLogic.humanSize(videoSizeBytes))
                }
                LabeledContent("Dimensions") {
                    if isProbing {
                        ProgressView().controlSize(.small)
                    } else if let w = videoWidth, let h = videoHeight {
                        Text("\(w) × \(h)")
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                LabeledContent("Slides", value: "\(slideCount)")
            }

            Button {
                pickStills()
            } label: {
                Label(stillPaths.isEmpty ? "Pick Stills Folder…" : "Stills: \(slideCount) slides",
                      systemImage: "photo.stack")
            }

            if !errorMessage.isEmpty {
                inlineError(errorMessage)
            }

            HStack {
                Text("Frame rate")
                Spacer()
                TextField("fps", value: $fps, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                Stepper("", value: $fps, in: 1...120, step: 1).labelsHidden()
            }

            TextField("Project Name", text: $projectName)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())

            Toggle("Secure Embed — disable downloads, restrict embedding to portal", isOn: $secureEmbed)
                .toggleStyle(.switch)
                .font(.caption)

            if let probeError {
                inlineError(probeError)
            }

            HStack(spacing: 12) {
                Button("Back") { reset() }
                Button("Deploy") { startDeploy() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canDeploy)
            }
        }
    }

    // MARK: - Deploying Phase

    private var deployingPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deploying…")
                .font(.title2.weight(.semibold))
            Text("Analyzing, encoding, and deploying to Vercel.")
                .foregroundStyle(.secondary)

            DeployProgressView(steps: steps)

            Button("Cancel") { deployTask?.cancel() }
                .controlSize(.small)
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
                Text("\(result.slideCount) slides")
                    .foregroundStyle(.secondary)

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
                                let embed = VideoDeployLogic.framerEmbed(
                                    url: result.url,
                                    width: result.width,
                                    height: result.height)
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
                inlineError(errorMessage, monospaced: true)
            }

            HStack(spacing: 12) {
                Button("Start Over") { reset() }
                Button("Retry") { startDeploy() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Shared bits

    private func inlineError(_ text: String, monospaced: Bool = false) -> some View {
        Text(text)
            .font(monospaced ? .callout.monospaced() : .callout)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Select an H.264 Video"
        var types: [UTType] = [.mpeg4Movie, .quickTimeMovie]
        if let m4v = UTType(filenameExtension: "m4v") { types.append(m4v) }
        panel.allowedContentTypes = types

        guard panel.runModal() == .OK, let url = panel.url else { return }
        acceptVideo(url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { acceptVideo(url) }
        }
        return true
    }

    private func acceptVideo(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["mp4", "mov", "m4v"].contains(ext) else {
            errorMessage = "That isn't a supported video. Drop an H.264 .mp4, .mov, or .m4v."
            return
        }
        errorMessage = ""
        // A new video must not inherit the previous deck's stills / result.
        stillPaths = []
        result = nil
        videoPath = url.path
        videoSizeBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64
        player = AVPlayer(url: url)

        let settings = (try? FileOperations.loadSettings()) ?? .default
        projectName = VideoDeployLogic.projectName(prefix: settings.projectNamePrefix, filename: url.lastPathComponent)
        secureEmbed = settings.secureEmbed

        phase = .confirm
        probeDimensions(url, settings: settings)
    }

    private func probeDimensions(_ url: URL, settings: AppSettings) {
        isProbing = true
        probeError = nil
        videoWidth = nil
        videoHeight = nil
        let encoder = VideoDeployerSeams.live(settings: settings).encoder
        Task {
            do {
                let (w, h, probedFps) = try await encoder.probe(url: url)
                await MainActor.run {
                    videoWidth = w; videoHeight = h; isProbing = false
                    // Default the fps field to the ACTUAL probed rate (Electron derives
                    // timestamps from the real fps). Leaving it at a hardcoded 30 when the
                    // export is e.g. 25/29.97 would misplace every forced keyframe.
                    if probedFps > 0 { fps = (probedFps).rounded() }
                }
            } catch {
                await MainActor.run {
                    probeError = error.localizedDescription
                    isProbing = false
                }
            }
        }
    }

    private func pickStills() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Select the Per-Slide Stills Folder"

        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        stillPaths = VideoDeployLogic.filterImages(contents)
        if stillPaths.isEmpty {
            errorMessage = "No image files found in that folder."
        } else {
            errorMessage = ""
        }
    }

    private func startDeploy() {
        guard let videoPath else { return }

        // Mirror DeployView: pre-check the token with an actionable error.
        let settings = (try? FileOperations.loadSettings()) ?? .default
        guard !settings.vercelToken.isEmpty else {
            errorMessage = "Vercel token not configured. Go to Settings first."
            phase = .error
            return
        }

        phase = .deploying
        steps = Self.freshSteps()
        errorMessage = ""

        let cleanTitle = ((videoPath as NSString).lastPathComponent as NSString).deletingPathExtension
        let request = VideoDeployRequest(
            videoPath: videoPath,
            stillPaths: stillPaths,
            fps: max(1, fps),                                  // guard fps<=0 (TextField bypasses the Stepper range)
            projectName: projectName.trimmingCharacters(in: .whitespaces),
            title: cleanTitle,
            secureEmbed: secureEmbed)

        deployTask = Task {
            do {
                let r = try await VideoDeployer.deploy(
                    request,
                    settings: settings,
                    seams: .live(settings: settings),
                    onProgress: { step in
                        Task { @MainActor in updateStep(step) }
                    })
                await MainActor.run { finish(r, settings: settings) }
            } catch is CancellationError {
                await MainActor.run { phase = .confirm }   // coherent state preserved (video+stills+name intact)
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

    @MainActor
    private func finish(_ r: VideoDeployResult, settings: AppSettings) {
        // Persist history exactly like the HTML view: folderPath = source video path,
        // fixesApplied = 0 (no HiDPI fixes on the video path).
        let entry = HistoryEntry(
            projectName: r.projectName,
            title: r.title,
            slideCount: r.slideCount,
            url: r.url,
            folderPath: r.folderPath,
            fixesApplied: 0)
        modelContext.insert(entry)

        if settings.autoCopyUrl {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(r.url, forType: .string)
        }

        result = r
        phase = .complete
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
        deployTask?.cancel()
        phase = .drop
        videoPath = nil
        videoSizeBytes = nil
        videoWidth = nil
        videoHeight = nil
        player = nil
        stillPaths = []
        fps = 30
        projectName = ""
        secureEmbed = true
        steps = Self.freshSteps()
        result = nil
        errorMessage = ""
        probeError = nil
        isProbing = false
        copied = nil
    }
}
