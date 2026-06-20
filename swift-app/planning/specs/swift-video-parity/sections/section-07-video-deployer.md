I have all the context needed. Now I'll write the section content.

# section-07-video-deployer

## Goal

Build the orchestrator that ties the whole Swift video-deploy pipeline together: `VideoDeployer.deploy(...)`. It runs probe → derive → encode → generate `index.html` → deploy to Vercel, emitting 4 progress steps, and returns a `VideoDeployResult`. Encoder selection (AVFoundation default vs ffmpeg fallback) and the actual Vercel deploy are **injected via seams** so the orchestration is fully unit-testable offline with zero network / encoding / disk-encode work.

This is the integration seam between the pure/algorithmic sections (02–06) and the UI (section-08). The View — not the deployer — owns `HistoryEntry` persistence and clipboard auto-copy.

## Background (everything you need to know)

**Keynote Deployer** turns a Keynote deck into an embeddable web viewer on Vercel. The **video path** deploys an H.264 `deck.mp4` + a self-contained `index.html` single-`<video>` viewer that plays real transitions and pauses crisply on each slide. Slide boundaries can't be recovered from video pixels alone, so the user supplies one **still image per slide**; the still count IS the slide count, and each still is DP-matched to the video frame it appears on to derive that slide's timestamp. Stills are a build-time input only — never deployed. The deployed artifact is `deck.mp4` + `index.html`.

This section assembles that flow. It reuses the existing Swift Vercel infrastructure (`VercelDeployer`, `VercelAPI`) **unchanged**.

### Dependencies (assume these exist — DO NOT re-implement)

From **section-01** (`Sources/Models/`):

```swift
struct VideoDeployRequest: Sendable {
    let videoPath: String      // H.264 .mp4/.mov/.m4v
    let stillPaths: [String]   // one image per slide, natural-sorted
    let fps: Double            // constant export frame rate (default 30)
    let projectName: String
    let title: String
    let secureEmbed: Bool
}

struct VideoAnalysis: Sendable {
    let frames: [Int]; let timestamps: [Double]; let slideCount: Int
    let width: Int; let height: Int; let fps: Double
}
```

From **section-04** (`Sources/Services/VideoEncoding.swift`):

```swift
protocol VideoEncoder: Sendable {
    func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double)
    func sampleGrids(url: URL) async throws -> [[Double]]
    func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double]) async throws
}
```
Plus `AVFoundationVideoEncoder` (section-04, the default impl) and `FFmpegVideoEncoder` (section-05, the fallback impl). Both conform to `VideoEncoder`.

From **section-06** (`Sources/Services/VideoTimestampDeriver.swift`):

```swift
enum VideoTimestampDeriver {
    static func derive(encoder: VideoEncoder, videoURL: URL, stillURLs: [URL], fps: Double,
                       onProgress: (@Sendable (Double) -> Void)?) async throws -> VideoAnalysis
}
```

From **section-03** (`Sources/Services/VideoViewerGenerator.swift`):

```swift
enum VideoViewerGenerator {
    static func generate(videoFilename: String, secureEmbed: Bool,
                         timestamps: [Double], videoWidth: Int, videoHeight: Int) -> String
}
```

**Existing, reused unchanged** (already on `main`):

- `Sources/Models/ProcessingStep.swift`:
  ```swift
  enum StepStatus: String, Codable, Sendable { case pending, active, completed, skipped, error }
  struct ProcessingStep: Identifiable, Sendable {
      let id: Int; let label: String; var detail: String; var status: StepStatus; var error: String?
  }
  ```
- `Sources/Services/VercelDeployer.swift` — `enum VercelDeployer`:
  ```swift
  static func deploy(folderPath: String, projectId: String, token: String, teamId: String,
                     secureEmbed: Bool, embedAllowedDomains: String,
                     onProgress: @Sendable (ProcessingStep) -> Void) async throws -> DeployResult
  // struct DeployResult: Sendable { let success: Bool; let url: String; let error: String? }
  ```
  Note: `deploy` itself writes `vercel.json` (CSP headers) into the folder when `secureEmbed` is on, shells out to the `vercel` CLI, and returns `success`/`error` (its `url` field is empty — the real URL comes from `resolveProductionUrl`).
- `Sources/Services/VercelAPI.swift` — `struct VercelAPI` (init `VercelAPI(token:teamId:)`):
  ```swift
  func ensureProject(name: String) async throws -> VercelProject       // VercelProject has .id, .name
  func resolveProductionUrl(projectId: String) async throws -> String? // handles subdomain truncation
  ```
- `Sources/Models/AppSettings.swift` — `struct AppSettings` with `var vercelToken: String`, `var vercelTeamId: String`, `var embedAllowedDomains: String` (default `"*.imaginelabstudios.com *.framer.app"`), `var autoCopyUrl: Bool`.

**How the existing HTML `DeployView` does Vercel** (the pattern the default seam must mirror): `ensureProject(name:)` → `VercelDeployer.deploy(folderPath:projectId:token:teamId:secureEmbed:embedAllowedDomains:onProgress:)` → `resolveProductionUrl(projectId:)` with fallback `"https://\(projectName).vercel.app"`.

## Files to create

- `swift-app/Sources/Services/VideoDeployer.swift` — `VideoDeployer` enum, `VideoDeployerSeams` struct, `VideoDeployResult` struct.
- `swift-app/Tests/VideoDeployerTests.swift` — Swift Testing tests (offline, seam-injected). The test target was created in section-01; add this file to it.

## Public API

```swift
struct VideoDeployerSeams: Sendable {
    var encoder: VideoEncoder
    /// Resolves a Vercel project, deploys `folder`, and returns the resolved production URL.
    var ensureProjectAndDeploy: @Sendable (_ folder: String, _ projectName: String,
        _ secureEmbed: Bool, _ onProgress: @Sendable (ProcessingStep) -> Void) async throws -> String

    /// Default seam: encoder chosen by the hidden `useFfmpegEncoder` UserDefaults flag (A6),
    /// deploy wraps VercelAPI.ensureProject + VercelDeployer.deploy + resolveProductionUrl.
    static func live(settings: AppSettings) -> VideoDeployerSeams
}

enum VideoDeployer {
    static func deploy(_ request: VideoDeployRequest, settings: AppSettings,
                       seams: VideoDeployerSeams,
                       onProgress: @Sendable (ProcessingStep) -> Void)
        async throws -> VideoDeployResult
}

struct VideoDeployResult: Sendable {
    let url: String; let projectName: String; let title: String
    let slideCount: Int; let folderPath: String
}
```

## Flow (mirror the Electron `deploy-video` IPC)

`VideoDeployer.deploy` runs these steps in order, emitting **4 progress steps**. Number the `ProcessingStep.id`s 1–4 with labels matching the phases below; mark each `.active` on entry and `.completed` on exit (mirror how `VercelDeployer.deploy` toggles status).

1. **Step 1 — Analyze.** Create a temp dir at `/tmp/keynote-deployer-video-<unix-ts>` (use `FileManager`/`NSTemporaryDirectory()`; the literal `/tmp` prefix matches Electron). **Immediately** install cleanup: `defer { try? FileManager.default.removeItem(atPath: tempDir) }` (A4 — a throw or cancel must not strand GB of video in `/tmp`). Then:
   - `let (w, h, fps) = try await seams.encoder.probe(url: videoURL)` — note `probe` rejects VFR / corrupt / no-track inputs (handled in section-04); just propagate the throw.
   - `let analysis = try await VideoTimestampDeriver.derive(encoder: seams.encoder, videoURL:, stillURLs:, fps: request.fps, onProgress: ...)`. (Forward derive's `Double` progress into the step `detail`, e.g. "Analyzing video frames…", for the A5 UX. The View renders it.)
2. **Step 2 — Encode.** `let outputURL = tempDir/"deck.mp4"`; `try await seams.encoder.encodeWithKeyframes(input: videoURL, output: outputURL, timestamps: analysis.timestamps)`.
3. **Step 3 — Generate.** `let html = VideoViewerGenerator.generate(videoFilename: "deck.mp4", secureEmbed: request.secureEmbed, timestamps: analysis.timestamps, videoWidth: analysis.width, videoHeight: analysis.height)`; write it to `tempDir/"index.html"`.
4. **Step 4 — Deploy.** **Guard the token first:** `guard !settings.vercelToken.isEmpty else { throw ... }` (a clear, actionable error) — this must fire **before** any deploy work. Then `let url = try await seams.ensureProjectAndDeploy(tempDir, request.projectName, request.secureEmbed, onProgress)`.

Return `VideoDeployResult(url: url, projectName: request.projectName, title: request.title, slideCount: analysis.slideCount, folderPath: request.videoPath)`.

Notes:
- `folderPath` in the result is the **source video path** (not the temp dir, which is deleted) — the View sets `HistoryEntry.folderPath = videoPath`, `fixesApplied = 0`.
- Off-main / cancellable: `derive` and `encodeWithKeyframes` are `async` and honor cancellation (sections 04/06); `deploy` is `async throws`, so a `Task.cancel()` surfaces as `CancellationError` and `defer` still cleans up.
- Use absolute string paths consistently with the existing services (they pass `folderPath: String`).

## The `.live` seam (default, production)

```swift
extension VideoDeployerSeams {
    static func live(settings: AppSettings) -> VideoDeployerSeams {
        // A6: encoder selected by hidden UserDefaults flag, default = AVFoundation.
        let useFfmpeg = UserDefaults.standard.bool(forKey: "useFfmpegEncoder")
        let encoder: VideoEncoder = useFfmpeg ? FFmpegVideoEncoder() : AVFoundationVideoEncoder()

        let token = settings.vercelToken
        let teamId = settings.vercelTeamId
        let allowed = settings.embedAllowedDomains

        return VideoDeployerSeams(encoder: encoder) { folder, projectName, secureEmbed, onProgress in
            let api = VercelAPI(token: token, teamId: teamId)
            let project = try await api.ensureProject(name: projectName)
            let result = try await VercelDeployer.deploy(
                folderPath: folder, projectId: project.id, token: token, teamId: teamId,
                secureEmbed: secureEmbed, embedAllowedDomains: allowed, onProgress: onProgress)
            guard result.success else { throw /* VercelDeployer error using result.error */ }
            return (try? await api.resolveProductionUrl(projectId: project.id))
                ?? "https://\(projectName).vercel.app"
        }
    }
}
```

A6 reminder: the ffmpeg trigger is the hidden default `useFfmpegEncoder` (set via `defaults write <bundleid> useFfmpegEncoder -bool YES`). It is NOT a compile-time flag and NOT a user-facing setting. Default = AVFoundation.

## Tests (write FIRST)

Use **Swift Testing** (`import Testing`), `@Test`/`#expect`. All tests are **offline** — inject fake seams so no network, no real encoder, no real disk-encode runs. Provide a stub `VideoEncoder` (returns canned probe dims + does nothing in `encodeWithKeyframes`; `sampleGrids` can return a tiny fixture if a test path needs `derive`, otherwise inject a deriver-friendly fixture). Note: `derive` is called for real, so the stub encoder's `sampleGrids` must return grids that produce a deterministic match — keep the fixture small (e.g. 2 stills, a few frames).

Required cases (from the plan's TDD spec):

```swift
import Testing
import Foundation
@testable import KeynoteDeployer

// Test: step order + result fields + 4 progress steps.
//   deploy() invokes probe → derive → encode → generate → deploy in order;
//   captures order via a recorder in the stub encoder + a flag in ensureProjectAndDeploy.
//   Returns VideoDeployResult with the resolved URL (from the stubbed seam) and
//   slideCount == stillPaths.count. Exactly 4 ProcessingSteps reach .completed.

// Test: missing vercelToken → guarded error BEFORE any deploy.
//   settings.vercelToken == "" → deploy() throws, and the ensureProjectAndDeploy
//   seam was NEVER called (assert a "deployCalled" flag stays false).

// Test (A4): temp dir removed on success AND on a thrown error.
//   Inject a temp-dir path you can observe (or assert no leftover
//   /tmp/keynote-deployer-video-* dirs after each run). Force a throw via a stub
//   encoder that throws in encodeWithKeyframes → assert the temp dir is gone.

// Test (A6): UserDefaults flag selects the encoder in the .live seam.
//   With useFfmpegEncoder=true → VideoDeployerSeams.live(...).encoder is FFmpegVideoEncoder;
//   default/unset → AVFoundationVideoEncoder. (Use a uniquely-named UserDefaults suite or
//   set/restore the key so the test is isolated. Assert via `is` type check.)
```

Stub shape:

```swift
final class StubEncoder: VideoEncoder, @unchecked Sendable {
    var probeDims: (Int, Int, Double) = (1920, 1080, 30)
    var stillGrids: [[Double]] = []       // returned by sampleGrids for stills
    var videoGrids: [[Double]] = []       // returned by sampleGrids for the video
    var encodeError: Error? = nil
    private(set) var calls: [String] = []
    func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double) { calls.append("probe"); return probeDims }
    func sampleGrids(url: URL) async throws -> [[Double]] { calls.append("sample"); /* return video vs still grids based on extension/url */ }
    func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double]) async throws {
        calls.append("encode"); if let e = encodeError { throw e }
        // write a 0-byte deck.mp4 so the generate/write steps proceed
        FileManager.default.createFile(atPath: output.path, contents: Data())
    }
}
```

Tip: differentiate video vs still grids in `sampleGrids` by URL (the video URL is the request `videoPath`; still URLs come from `stillPaths`) so `derive` returns deterministic, monotonic frame indices for the fixture.

## Verification

- Tests pass: `cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -quiet` → exit 0.
- Swift 6 strict-concurrency clean (the `@Sendable` closures and `Sendable` structs are load-bearing here — `VideoDeployerSeams` must be `Sendable`).
- Do not regress existing HTML-path tests.
- Settle the verdict on the explicit exit code, not stdout. Force a fresh result bundle if a stale `.xcresult` is suspected.

## Out of scope (other sections)

- `VideoDeployView` UI / phase machine / nav wiring, HistoryEntry persistence, clipboard auto-copy → **section-08**.
- The encoder impls, `derive`, `VideoViewerGenerator`, models, project.yml/test-target wiring → sections 01–06.
- PARITY.md / CLAUDE.md / notarize / sunset → section-09.

---

Section content written. Key implementation files:

- Create `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/VideoDeployer.swift` (the `VideoDeployer` enum + `VideoDeployerSeams` + `VideoDeployResult`).
- Create `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/VideoDeployerTests.swift`.

Load-bearing signatures I confirmed against the live `main` source (so the `.live` seam matches reality):
- `VercelDeployer.deploy(folderPath:projectId:token:teamId:secureEmbed:embedAllowedDomains:onProgress:) -> DeployResult` where `DeployResult.url` is empty and `.success`/`.error` carry the verdict.
- `VercelAPI(token:teamId:)` → `ensureProject(name:) -> VercelProject` (`.id`, `.name`) and `resolveProductionUrl(projectId:) -> String?`, with the established fallback `"https://\(projectName).vercel.app"`.
- `AppSettings` exposes `vercelToken`, `vercelTeamId`, `embedAllowedDomains`, `autoCopyUrl`.
- `ProcessingStep(id:label:detail:status:error:)` with `StepStatus` cases `.active`/`.completed`/`.error`.