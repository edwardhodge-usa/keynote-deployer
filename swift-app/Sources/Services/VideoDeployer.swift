import Foundation
import os

/// Orchestrates the Swift video-deploy pipeline: probe → derive → encode →
/// generate `index.html` → deploy to Vercel. Mirrors the Electron `deploy-video`
/// IPC. Emits 4 progress steps and returns a `VideoDeployResult`.
///
/// Encoder selection (AVFoundation default vs ffmpeg fallback) and the actual
/// Vercel deploy are injected via `VideoDeployerSeams` so the whole orchestration
/// is unit-testable offline (no network / real encode / disk-encode work). The
/// View — not this deployer — owns `HistoryEntry` persistence and clipboard copy.
enum VideoDeployer {

    /// Step 1 only: probe + DP-match the stills → seed `VideoAnalysis` + seed
    /// `[SlideMark]`. The seed marks become the initial markers the user reviews
    /// before encode.
    static func analyze(_ request: VideoDeployRequest,
                        seams: VideoDeployerSeams,
                        onProgress: @Sendable (ProcessingStep) -> Void) async throws -> (analysis: VideoAnalysis, marks: [SlideMark]) {
        let videoURL = URL(fileURLWithPath: request.videoPath)
        let stillURLs = request.stillPaths.map { URL(fileURLWithPath: $0) }

        onProgress(ProcessingStep(id: 1, label: "Analyze video", detail: "Probing video…", status: .active))
        let (analysis, marks) = try await VideoTimestampDeriver.derive(
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
        return (analysis, marks)
    }

    /// Steps 2–4: encode (forced keyframes at the union of holdStart+holdEnd frames)
    /// → generate the viewer (spans as {{TS}}) → deploy to Vercel. `width/height/fps`
    /// come from the seed `analysis`; the slide count follows the edited marks.
    static func deploy(_ request: VideoDeployRequest,
                       analysis: VideoAnalysis,
                       marks: [SlideMark],
                       settings: AppSettings,
                       seams: VideoDeployerSeams,
                       onProgress: @Sendable (ProcessingStep) -> Void) async throws -> VideoDeployResult {
        guard !marks.isEmpty else { throw VideoDeployError.invalidMarkers("no slide markers") }
        guard SlideMarkLogic.isValid(marks, frameCount: analysis.frameCount) else {
            throw VideoDeployError.invalidMarkers("markers overlap or are out of order")
        }
        let videoURL = URL(fileURLWithPath: request.videoPath)
        let tempDir = "/tmp/keynote-deployer-video-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let keyframes = forcedKeyframeSeconds(marks: marks, fps: analysis.fps)
        let spans = viewerSpans(marks: marks, fps: analysis.fps)

        var step2 = ProcessingStep(id: 2, label: "Encode video", detail: "Re-encoding with per-slide keyframes…", status: .active)
        onProgress(step2)
        let outputURL = URL(fileURLWithPath: tempDir).appendingPathComponent("deck.mp4")
        try await seams.encoder.encodeWithKeyframes(input: videoURL, output: outputURL, timestamps: keyframes, fps: analysis.fps)
        step2.status = .completed; onProgress(step2)

        var step3 = ProcessingStep(id: 3, label: "Generate viewer", detail: "Building index.html…", status: .active)
        onProgress(step3)
        var posterFilename: String? = nil
        if let firstHold = spans.first?.first {
            let posterURL = URL(fileURLWithPath: tempDir).appendingPathComponent("poster.jpg")
            do { try await VideoPoster.extract(from: outputURL, atSeconds: max(0, firstHold), to: posterURL); posterFilename = "poster.jpg" }
            catch { posterFilename = nil }
        }
        let html = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4", secureEmbed: request.secureEmbed,
            spans: spans, videoWidth: analysis.width, videoHeight: analysis.height, posterFilename: posterFilename)
        try html.write(to: URL(fileURLWithPath: tempDir).appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        step3.status = .completed; onProgress(step3)

        var step4 = ProcessingStep(id: 4, label: "Deploy to Vercel", detail: "Deploying…", status: .active)
        guard !settings.vercelToken.isEmpty else {
            step4.status = .error; step4.error = VideoDeployError.missingVercelToken.errorDescription; onProgress(step4)
            throw VideoDeployError.missingVercelToken
        }
        onProgress(step4)
        let url: String
        do { url = try await seams.ensureProjectAndDeploy(tempDir, request.projectName, request.secureEmbed, onProgress) }
        catch {
            onProgress(ProcessingStep(id: 4, label: "Deploy to Vercel", detail: "Deploy failed", status: .error, error: error.localizedDescription))
            throw error
        }
        step4.detail = url; step4.status = .completed; onProgress(step4)

        // Report the AUTHORITATIVE slide count (analysis.slideCount == stills count),
        // not marks.count. With the rewritten detector these always agree; a divergence
        // is a regression signal, so record it (non-fatal — the deploy still succeeds)
        // rather than silently shipping a wrong count.
        let countDiverged = marks.count != analysis.slideCount
        if countDiverged {
            Logger(subsystem: "com.imaginelabstudios.keynote-deployer", category: "VideoDeployer")
                .warning("mark/slide count divergence: marks=\(marks.count) slides=\(analysis.slideCount)")
        }
        return VideoDeployResult(url: url, projectName: request.projectName, title: request.title,
                                 slideCount: analysis.slideCount, width: analysis.width, height: analysis.height,
                                 folderPath: request.videoPath, countDiverged: countDiverged)
    }

    // MARK: - Helpers

    /// Sorted unique set of holdStart+holdEnd frame indices converted to seconds
    /// (3dp). These are the forced keyframes passed to the encoder.
    static func forcedKeyframeSeconds(marks: [SlideMark], fps: Double) -> [Double] {
        let frames = Set(marks.flatMap { [$0.holdStart, $0.holdEnd] })
        return frames.sorted().map { round((Double($0) / fps) * 1000) / 1000 }
    }

    /// Maps each `SlideMark` to `[holdStart, holdEnd]` in seconds (3dp). The viewer
    /// receives these as `{{TS}}` and uses them to seek and pause at each hold frame.
    static func viewerSpans(marks: [SlideMark], fps: Double) -> [[Double]] {
        marks.map { [round((Double($0.holdStart) / fps) * 1000) / 1000,
                     round((Double($0.holdEnd) / fps) * 1000) / 1000] }
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
    /// True when the produced marks count != the authoritative slide count. A
    /// regression signal (should never be true with the rewritten detector); the
    /// reported `slideCount` is always the authoritative count regardless.
    let countDiverged: Bool
}

/// User-facing, actionable orchestration errors (encoder/deriver/Vercel errors
/// propagate from their own types).
enum VideoDeployError: Error, LocalizedError, Sendable, Equatable {
    case missingVercelToken
    case deployFailed(String)
    /// The edited marker list is empty or invalid. The editor UI gate prevents this
    /// in normal use; this case guards against regressions.
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
