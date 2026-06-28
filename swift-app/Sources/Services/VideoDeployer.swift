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

    /// Step 1 only: probe + DP-match the stills → seed `VideoAnalysis`. The seed
    /// timestamps become the initial markers the user reviews before encode.
    static func analyze(_ request: VideoDeployRequest,
                        seams: VideoDeployerSeams,
                        onProgress: @Sendable (ProcessingStep) -> Void) async throws -> VideoAnalysis {
        let videoURL = URL(fileURLWithPath: request.videoPath)
        let stillURLs = request.stillPaths.map { URL(fileURLWithPath: $0) }

        onProgress(ProcessingStep(id: 1, label: "Analyze video", detail: "Probing video…", status: .active))
        let analysis = try await VideoTimestampDeriver.derive(
            encoder: seams.encoder,
            videoURL: videoURL,
            stillURLs: stillURLs,
            fps: request.fps,
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
        return analysis
    }

    /// Steps 2–4: encode (forced keyframes at the EDITED markers) → generate the
    /// viewer (the same edited markers as {{TS}}) → deploy to Vercel. `width/height/
    /// fps` come from the seed `analysis`; the slide count follows the edited markers.
    static func deploy(_ request: VideoDeployRequest,
                       analysis: VideoAnalysis,
                       editedTimestamps: [Double],
                       settings: AppSettings,
                       seams: VideoDeployerSeams,
                       onProgress: @Sendable (ProcessingStep) -> Void) async throws -> VideoDeployResult {
        // Fix 5: defense-in-depth — guard the forced-keyframe / {{TS}} / poster path
        // against a future UI-gate regression. The editor button is already disabled
        // for non-monotonic inputs; this makes the deploy boundary explicit.
        guard !editedTimestamps.isEmpty else {
            throw VideoDeployError.invalidMarkers(
                "Marker list is empty — at least one slide is required.")
        }
        guard zip(editedTimestamps, editedTimestamps.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw VideoDeployError.invalidMarkers(
                "Marker list is not strictly increasing — re-open the marker editor.")
        }

        let videoURL = URL(fileURLWithPath: request.videoPath)

        let tempDir = "/tmp/keynote-deployer-video-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // ── Step 2 — Encode (forced keyframes at the edited markers) ────────────
        var step2 = ProcessingStep(id: 2, label: "Encode video", detail: "Re-encoding with per-slide keyframes…", status: .active)
        onProgress(step2)
        let outputURL = URL(fileURLWithPath: tempDir).appendingPathComponent("deck.mp4")
        try await seams.encoder.encodeWithKeyframes(input: videoURL, output: outputURL, timestamps: editedTimestamps, fps: analysis.fps)
        step2.status = .completed
        onProgress(step2)

        // ── Step 3 — Generate ───────────────────────────────────────────────────
        var step3 = ProcessingStep(id: 3, label: "Generate viewer", detail: "Building index.html…", status: .active)
        onProgress(step3)
        // Poster = slide 1's marker frame EXACTLY (REST_BIAS retired to 0 — the marker
        // IS the rest frame). Best-effort: a failure degrades to no-poster, never fails.
        var posterFilename: String? = nil
        if let firstTimestamp = editedTimestamps.first {
            let posterURL = URL(fileURLWithPath: tempDir).appendingPathComponent("poster.jpg")
            do {
                try await VideoPoster.extract(from: outputURL, atSeconds: max(0, firstTimestamp), to: posterURL)
                posterFilename = "poster.jpg"
            } catch {
                posterFilename = nil
            }
        }
        let html = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4",
            secureEmbed: request.secureEmbed,
            timestamps: editedTimestamps,
            videoWidth: analysis.width,
            videoHeight: analysis.height,
            posterFilename: posterFilename)
        let indexURL = URL(fileURLWithPath: tempDir).appendingPathComponent("index.html")
        try html.write(to: indexURL, atomically: true, encoding: .utf8)
        step3.status = .completed
        onProgress(step3)

        // ── Step 4 — Deploy ───────────────────────────────────────────────────────
        var step4 = ProcessingStep(id: 4, label: "Deploy to Vercel", detail: "Deploying…", status: .active)
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
            onProgress(ProcessingStep(id: 4, label: "Deploy to Vercel", detail: "Deploy failed",
                                      status: .error, error: error.localizedDescription))
            throw error
        }
        step4.detail = url
        step4.status = .completed
        onProgress(step4)

        return VideoDeployResult(
            url: url,
            projectName: request.projectName,
            title: request.title,
            slideCount: editedTimestamps.count,
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

    /// Default seam. Encoder = ffmpeg (constant-quality CRF16 x264, ~70% smaller +
    /// faster-loading decks) whenever ffmpeg is installed; falls back to the
    /// dependency-free AVFoundation encoder only when it isn't. The hidden
    /// `useFfmpegEncoder` flag force-selects ffmpeg even if the availability probe is
    /// imperfect. Deploy mirrors the HTML `DeployView`: `ensureProject` →
    /// `VercelDeployer.deploy` → `resolveProductionUrl` with the established
    /// `https://<name>.vercel.app` fallback.
    static func live(settings: AppSettings) -> VideoDeployerSeams {
        let forceFfmpeg = UserDefaults.standard.bool(forKey: "useFfmpegEncoder")
        let encoder: VideoEncoder = (forceFfmpeg || FFmpegVideoEncoder.isAvailable())
            ? FFmpegVideoEncoder() : AVFoundationVideoEncoder()

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
    /// The edited marker list is empty or not strictly increasing. The editor UI
    /// gate prevents this in normal use; this case guards against regressions.
    case invalidMarkers(String)

    var errorDescription: String? {
        switch self {
        case .missingVercelToken:
            return "No Vercel token configured. Add your Vercel token in Settings before deploying."
        case .deployFailed(let detail):
            return "Vercel deploy failed: \(detail)"
        case .invalidMarkers(let detail):
            return "Invalid marker list: \(detail)"
        }
    }
}
