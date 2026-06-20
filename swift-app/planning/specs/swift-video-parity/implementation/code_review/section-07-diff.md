swift-app/Sources/Services/VideoDeployer.swift | 165 +++++++++++++++++++++
 swift-app/Tests/VideoDeployerTests.swift       | 198 +++++++++++++++++++++++++
 2 files changed, 363 insertions(+)

--- Changes ---

swift-app/Sources/Services/VideoDeployer.swift
  @@ -0,0 +1,165 @@
  +import Foundation
  +
  +/// Orchestrates the Swift video-deploy pipeline: probe → derive → encode →
  +/// generate `index.html` → deploy to Vercel. Mirrors the Electron `deploy-video`
  +/// IPC. Emits 4 progress steps and returns a `VideoDeployResult`.
  +///
  +/// Encoder selection (AVFoundation default vs ffmpeg fallback) and the actual
  +/// Vercel deploy are injected via `VideoDeployerSeams` so the whole orchestration
  +/// is unit-testable offline (no network / real encode / disk-encode work). The
  +/// View — not this deployer — owns `HistoryEntry` persistence and clipboard copy.
  +enum VideoDeployer {
  +
  +    static func deploy(_ request: VideoDeployRequest,
  +                       settings: AppSettings,
  +                       seams: VideoDeployerSeams,
  +                       onProgress: @Sendable (ProcessingStep) -> Void) async throws -> VideoDeployResult {
  +        let videoURL = URL(fileURLWithPath: request.videoPath)
  +        let stillURLs = request.stillPaths.map { URL(fileURLWithPath: $0) }
  +
  +        // ── Step 1 — Analyze ────────────────────────────────────────────────
  +        // Temp dir under the literal /tmp (matches Electron). Install cleanup
  +        // IMMEDIATELY (A4): a throw or cancel must not strand GB of video in /tmp.
  +        let tempDir = "/tmp/keynote-deployer-video-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
  +        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
  +        defer { try? FileManager.default.removeItem(atPath: tempDir) }
  +
  +        onProgress(ProcessingStep(id: 1, label: "Analyze video", detail: "Probing video…", status: .active))
  +        // probe rejects VFR / corrupt / no-track inputs (section-04); propagate.
  +        _ = try await seams.encoder.probe(url: videoURL)
  +        let analysis = try await VideoTimestampDeriver.derive(
  +            encoder: seams.encoder,
  +            videoURL: videoURL,
  +            stillURLs: stillURLs,
  +            fps: request.fps,
  +            // Capture nothing mutable (Swift 6 @Sendable): rebuild the step each tick.
  +            onProgress: { p in
  +                onProgress(ProcessingStep(
  +                    id: 1, label: "Analyze video",
  +                    detail: "Analyzing video frames… \(Int((p * 100).rounded()))%",
  +                    status: .active))
  +            })
  +        let slideCount = analysis.slideCount
  +        onProgress(ProcessingStep(
  +            id: 1, label: "Analyze video",
  +            detail: "\(slideCount) slide\(slideCount == 1 ? "" : "s")",
  +            status: .completed))
  +
  +        // ── Step 2 — Encode ─────────────────────────────────────────────────
  +        var step2 = ProcessingStep(id: 2, label: "Encode video", detail: "Re-encoding with per-slide keyframes…", status: .active)
  +        onProgress(step2)
  +        let outputURL = URL(fileURLWithPath: tempDir).appendingPathComponent("deck.mp4")
  +        try await seams.encoder.encodeWithKeyframes(input: videoURL, output: outputURL, timestamps: analysis.timestamps)
  +        step2.status = .completed
  +        onProgress(step2)
  +
  +        // ── Step 3 — Generate ───────────────────────────────────────────────
  +        var step3 = ProcessingStep(id: 3, label: "Generate viewer", detail: "Building index.html…", status: .active)
  +        onProgress(step3)
  +        let html = VideoViewerGenerator.generate(
  +            videoFilename: "deck.mp4",
  +            secureEmbed: request.secureEmbed,
  +            timestamps: analysis.timestamps,
  +            videoWidth: analysis.width,
  +            videoHeight: analysis.height)
  +        let indexURL = URL(fileURLWithPath: tempDir).appendingPathComponent("index.html")
  +        try html.write(to: indexURL, atomically: true, encoding: .utf8)
  +        step3.status = .completed
  +        onProgress(step3)
  +
  +        // ── Step 4 — Deploy ─────────────────────────────────────────────────
  +        var step4 = ProcessingStep(id: 4, label: "Deploy to Vercel", detail: "Deploying…", status: .active)
  +        // Guard the token BEFORE any deploy work fires.
  +        guard !settings.vercelToken.isEmpty else {
  +            step4.status = .error
  +            step4.error = VideoDeployError.missingVercelToken.errorDescription
  +            onProgress(step4)
  +            throw VideoDeployError.missingVercelToken
  +        }
  +        onProgress(step4)
  +        let url = try await seams.ensureProjectAndDeploy(tempDir, request.projectName, request.secureEmbed, onProgress)
  +        step4.detail = url
  +        step4.status = .completed
  +        onProgress(step4)
  +
  +        // folderPath = the SOURCE video path (the temp dir is deleted); the View
  +        // sets HistoryEntry.folderPath = videoPath, fixesApplied = 0.
  +        return VideoDeployResult(
  +            url: url,
  +            projectName: request.projectName,
  +            title: request.title,
  +            slideCount: analysis.slideCount,
  +            folderPath: request.videoPath)
  +    }
  +}
  +
  +/// Injectable seams for `VideoDeployer.deploy` — the encoder and the Vercel
  +/// deploy. `.live(settings:)` provides the production wiring; tests inject fakes.
  +struct VideoDeployerSeams: Sendable {
  +    var encoder: VideoEncoder
  +
  ... (65 lines truncated)
  +165 -0

swift-app/Tests/VideoDeployerTests.swift
  @@ -0,0 +1,198 @@
  +import Testing
  +import Foundation
  +@testable import KeynoteDeployer
  +
  +/// Section 7 — VideoDeployer orchestration. Fully offline: a stub encoder (no real
  +/// probe/sample/encode) + a stub deploy seam (no network). `derive` runs for real
  +/// over the stub's canned grids, so frame matching is deterministic.
  +// Serialized: the A4 temp-dir tests observe the shared /tmp namespace, so they
  +// must not run concurrently with each other (or count snapshots race).
  +@Suite("Section 7 — VideoDeployer", .serialized)
  +struct VideoDeployerTests {
  +
  +    /// Stub encoder. Distinguishes the video URL (→ frameGrids) from still URLs
  +    /// (→ one grid keyed by path) so `derive` yields a known monotonic match.
  +    /// Records call order (thread-safe; sampleGrids may run off the test executor).
  +    final class StubEncoder: VideoEncoder, @unchecked Sendable {
  +        let videoURL: URL
  +        let frameGrids: [[Double]]
  +        let stillGridByPath: [String: [Double]]
  +        var probeDims: (width: Int, height: Int, fps: Double) = (1920, 1080, 30)
  +        var encodeError: Error?
  +
  +        private let lock = NSLock()
  +        private var _calls: [String] = []
  +        var calls: [String] { lock.lock(); defer { lock.unlock() }; return _calls }
  +        private func record(_ s: String) { lock.lock(); _calls.append(s); lock.unlock() }
  +
  +        init(videoURL: URL, frameGrids: [[Double]], stillGridByPath: [String: [Double]]) {
  +            self.videoURL = videoURL
  +            self.frameGrids = frameGrids
  +            self.stillGridByPath = stillGridByPath
  +        }
  +
  +        func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double) {
  +            record("probe"); return probeDims
  +        }
  +        func sampleGrids(url: URL) async throws -> [[Double]] {
  +            record("sample")
  +            if url == videoURL { return frameGrids }
  +            return [stillGridByPath[url.path] ?? []]
  +        }
  +        func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double]) async throws {
  +            record("encode")
  +            if let e = encodeError { throw e }
  +            // Write a 0-byte deck.mp4 so the generate/write step proceeds.
  +            FileManager.default.createFile(atPath: output.path, contents: Data())
  +        }
  +    }
  +
  +    /// Thread-safe flag recording whether the deploy seam was invoked.
  +    final class DeployFlag: @unchecked Sendable {
  +        private let lock = NSLock()
  +        private var _called = false
  +        var called: Bool { lock.lock(); defer { lock.unlock() }; return _called }
  +        func mark() { lock.lock(); _called = true; lock.unlock() }
  +    }
  +
  +    // Fixture: video URL + 2 stills that match frames 0 and 2 of a 3-frame video.
  +    private static let videoURL = URL(fileURLWithPath: "/tmp/kd-sec7/deck.mov")
  +    private static func stillURL(_ n: String) -> URL { URL(fileURLWithPath: "/tmp/kd-sec7/\(n)") }
  +
  +    private static func makeStub(flag: DeployFlag? = nil, encodeError: Error? = nil) -> StubEncoder {
  +        let s1 = stillURL("slide-1.jpeg"); let s2 = stillURL("slide-2.jpeg")
  +        let enc = StubEncoder(
  +            videoURL: videoURL,
  +            frameGrids: [[0], [10], [20]],
  +            stillGridByPath: [s1.path: [0.0], s2.path: [20.0]])
  +        if let encodeError { enc.encodeError = encodeError }
  +        return enc
  +    }
  +
  +    private static func request(secureEmbed: Bool = false) -> VideoDeployRequest {
  +        VideoDeployRequest(
  +            videoPath: videoURL.path,
  +            stillPaths: [stillURL("slide-1.jpeg").path, stillURL("slide-2.jpeg").path],
  +            fps: 30,
  +            projectName: "my-deck",
  +            title: "My Deck",
  +            secureEmbed: secureEmbed)
  +    }
  +
  +    private static func settings(token: String = "tok") -> AppSettings {
  +        var s = AppSettings.default
  +        s.vercelToken = token
  +        s.vercelTeamId = "team_x"
  +        return s
  +    }
  +
  +    /// Set of this pipeline's temp dirs currently in /tmp. Set-difference (not a
  +    /// count) so a pre-existing dir from another test can't perturb the assertion.
  +    private static func tempDirs() -> Set<String> {
  +        let contents = (try? FileManager.default.contentsOfDirectory(atPath: "/tmp")) ?? []
  +        return Set(contents.filter { $0.hasPrefix("keynote-deployer-video-") })
  +    }
  +
  +    @Test("step order + result fields + exactly 4 completed progress steps")
  +    func deploy_happyPath() async throws {
  +        let enc = Self.makeStub()
  +        let flag = DeployFlag()
  +        let seams = VideoDeployerSeams(encoder: enc) { folder, name, _, _ in
  ... (98 lines truncated)
  +198 -0
[full diff: rtk git diff --no-compact]
