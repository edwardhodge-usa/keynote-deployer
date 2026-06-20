import Foundation

/// Orchestrates the Swift video-deploy pipeline: probe → derive → encode →
/// generate `index.html` → deploy to Vercel. Mirrors the Electron `deploy-video`
/// IPC. Emits 4 progress steps and returns a `VideoDeployResult`.
///
/// Encoder selection (AVFoundation default vs ffmpeg fallback) and the actual
/// Vercel deploy are injected via `VideoDeployerSeams` so the whole orchestration
/// is unit-testable offline (no network / real encode / disk-encode work). The
/// View — not this deployer — owns `HistoryEntry` persistence and clipboard copy.
enum VideoDeployer {

    static func deploy(_ request: VideoDeployRequest,
                       settings: AppSettings,
                       seams: VideoDeployerSeams,
                       onProgress: @Sendable (ProcessingStep) -> Void) async throws -> VideoDeployResult {
        let videoURL = URL(fileURLWithPath: request.videoPath)
        let stillURLs = request.stillPaths.map { URL(fileURLWithPath: $0) }

        // ── Step 1 — Analyze ────────────────────────────────────────────────
        // Temp dir under the literal /tmp (matches Electron). Install cleanup
        // IMMEDIATELY (A4): a throw or cancel must not strand GB of video in /tmp.
        let tempDir = "/tmp/keynote-deployer-video-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        onProgress(ProcessingStep(id: 1, label: "Analyze video", detail: "Probing video…", status: .active))
        // `derive` is the single probe site — it probes internally (its dims are the
        // ones used) and rejects VFR / corrupt / no-track inputs before any sampling,
        // so a standalone probe here would only duplicate work (an ffprobe subprocess
        // on the ffmpeg path). Spec §07 instructed an explicit probe; removed per
        // review (Important #2) as a redundant call.
        let analysis = try await VideoTimestampDeriver.derive(
            encoder: seams.encoder,
            videoURL: videoURL,
            stillURLs: stillURLs,
            fps: request.fps,
            // Capture nothing mutable (Swift 6 @Sendable): rebuild the step each tick.
            onProgress: { p in
                onProgress(ProcessingStep(
                    id: 1, label: "Analyze video",
                    detail: "Analyzing video frames… \(Int((p * 100).rounded()))%",
                    status: .active))
            })
        let slideCount = analysis.slideCount
        onProgress(ProcessingStep(
            id: 1, label: "Analyze video",
            detail: "\(slideCount) slide\(slideCount == 1 ? "" : "s")",
            status: .completed))

        // ── Step 2 — Encode ─────────────────────────────────────────────────
        var step2 = ProcessingStep(id: 2, label: "Encode video", detail: "Re-encoding with per-slide keyframes…", status: .active)
        onProgress(step2)
        let outputURL = URL(fileURLWithPath: tempDir).appendingPathComponent("deck.mp4")
        try await seams.encoder.encodeWithKeyframes(input: videoURL, output: outputURL, timestamps: analysis.timestamps)
        step2.status = .completed
        onProgress(step2)

        // ── Step 3 — Generate ───────────────────────────────────────────────
        var step3 = ProcessingStep(id: 3, label: "Generate viewer", detail: "Building index.html…", status: .active)
        onProgress(step3)
        let html = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4",
            secureEmbed: request.secureEmbed,
            timestamps: analysis.timestamps,
            videoWidth: analysis.width,
            videoHeight: analysis.height)
        let indexURL = URL(fileURLWithPath: tempDir).appendingPathComponent("index.html")
        try html.write(to: indexURL, atomically: true, encoding: .utf8)
        step3.status = .completed
        onProgress(step3)

        // ── Step 4 — Deploy ─────────────────────────────────────────────────
        var step4 = ProcessingStep(id: 4, label: "Deploy to Vercel", detail: "Deploying…", status: .active)
        // Guard the token BEFORE any deploy work fires.
        guard !settings.vercelToken.isEmpty else {
            step4.status = .error
            step4.error = VideoDeployError.missingVercelToken.errorDescription
            onProgress(step4)
            throw VideoDeployError.missingVercelToken
        }
        onProgress(step4)
        let url: String
        do {
            url = try await seams.ensureProjectAndDeploy(tempDir, request.projectName, request.secureEmbed, onProgress)
        } catch {
            // Don't leave Step 4 spinning .active on a real Vercel failure (review Minor #4).
            onProgress(ProcessingStep(id: 4, label: "Deploy to Vercel", detail: "Deploy failed",
                                      status: .error, error: error.localizedDescription))
            throw error
        }
        step4.detail = url
        step4.status = .completed
        onProgress(step4)

        // folderPath = the SOURCE video path (the temp dir is deleted); the View
        // sets HistoryEntry.folderPath = videoPath, fixesApplied = 0.
        return VideoDeployResult(
            url: url,
            projectName: request.projectName,
            title: request.title,
            slideCount: analysis.slideCount,
            width: analysis.width,
            height: analysis.height,
            folderPath: request.videoPath)
    }
}

/// Injectable seams for `VideoDeployer.deploy` — the encoder and the Vercel
/// deploy. `.live(settings:)` provides the production wiring; tests inject fakes.
struct VideoDeployerSeams: Sendable {
    var encoder: VideoEncoder

    /// Resolves a Vercel project, deploys `folder`, and returns the resolved
    /// production URL.
    var ensureProjectAndDeploy: @Sendable (_ folder: String,
                                           _ projectName: String,
                                           _ secureEmbed: Bool,
                                           _ onProgress: @Sendable (ProcessingStep) -> Void) async throws -> String

    /// Default seam. Encoder chosen by the hidden `useFfmpegEncoder` UserDefaults
    /// flag (A6, default = AVFoundation). Deploy mirrors the HTML `DeployView`:
    /// `ensureProject` → `VercelDeployer.deploy` → `resolveProductionUrl` with the
    /// established `https://<name>.vercel.app` fallback.
    static func live(settings: AppSettings) -> VideoDeployerSeams {
        let useFfmpeg = UserDefaults.standard.bool(forKey: "useFfmpegEncoder")
        let encoder: VideoEncoder = useFfmpeg ? FFmpegVideoEncoder() : AVFoundationVideoEncoder()

        let token = settings.vercelToken
        let teamId = settings.vercelTeamId
        let allowed = settings.embedAllowedDomains

        return VideoDeployerSeams(encoder: encoder) { folder, projectName, secureEmbed, onProgress in
            let api = VercelAPI(token: token, teamId: teamId)
            let project = try await api.ensureProject(name: projectName)
            // VercelDeployer.deploy emits its own id:13 steps. Remap them onto the
            // orchestrator's Step 4 so the 4-step (id 1–4) contract holds for the
            // View regardless of the underlying deployer (review Important #1).
            let result = try await VercelDeployer.deploy(
                folderPath: folder,
                projectId: project.id,
                token: token,
                teamId: teamId,
                secureEmbed: secureEmbed,
                embedAllowedDomains: allowed,
                onProgress: { step in
                    onProgress(ProcessingStep(
                        id: 4, label: "Deploy to Vercel",
                        detail: step.detail.isEmpty ? step.label : step.detail,
                        status: step.status == .error ? .error : .active))
                })
            guard result.success else {
                throw VideoDeployError.deployFailed(result.error ?? "Vercel deploy failed")
            }
            return (try? await api.resolveProductionUrl(projectId: project.id))
                ?? "https://\(projectName).vercel.app"
        }
    }
}

/// Result of a successful video deploy.
struct VideoDeployResult: Sendable {
    let url: String
    let projectName: String
    let title: String
    let slideCount: Int
    /// Probed video dimensions — the View uses these for the responsive Framer
    /// embed's aspect ratio (no separate, racy re-probe at the complete phase).
    let width: Int
    let height: Int
    /// The SOURCE video path (not the deleted temp dir) — the View persists this
    /// as `HistoryEntry.folderPath`.
    let folderPath: String
}

/// User-facing, actionable orchestration errors (encoder/deriver/Vercel errors
/// propagate from their own types).
enum VideoDeployError: Error, LocalizedError, Sendable, Equatable {
    case missingVercelToken
    case deployFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingVercelToken:
            return "No Vercel token configured. Add your Vercel token in Settings before deploying."
        case .deployFailed(let detail):
            return "Vercel deploy failed: \(detail)"
        }
    }
}
