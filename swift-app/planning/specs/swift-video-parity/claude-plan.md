# Implementation Plan — Swift Video-Deploy Parity → Sunset Electron

## 1. Background (for an unfamiliar reader)

**Keynote Deployer** is a macOS app that turns a Keynote presentation into a shareable, embeddable web viewer hosted on Vercel. It exists as two parallel builds sharing one settings file: an Electron app (primary, being retired) and a Swift/SwiftUI app (becoming the sole app).

Historically the app had two deploy paths: (a) the **HTML** path (process a Keynote HTML export with 7 HiDPI fixes, deploy), and (b) a **GIF** path (deploy an animated GIF of the slides as an interactive viewer). The GIF path was abandoned because GIF compositing ghosts on held-build / constant-background decks and GIF is 256-color. It was replaced by a **VIDEO** path: deploy an H.264 movie export of the deck as a single-`<video>` slide viewer that plays the real transitions and pauses crisply on each slide.

The Electron app has the video path (shipped). The Swift app has the HTML path at 100% parity but **no** video path. This plan adds the video path to Swift so Electron can be deprecated.

**Why video needs per-slide stills:** slide boundaries cannot be recovered from video pixels alone (a build/fade step looks identical to a real slide on a constant background). The user exports one still image per slide; the count of stills IS the slide count, and each still is matched to the video frame it appears on to derive that slide's timestamp. The stills are a **build-time input only** — never inserted into the video, never deployed. The deployed artifact is `deck.mp4` + `index.html`.

## 2. Goal & non-goals

**Goal:** A `Deploy Video` tab in the Swift app where the user drops an H.264 video, picks the per-slide stills folder, sets the frame rate, and deploys an interactive video slide viewer to Vercel — at parity with the Electron `VideoViewer.tsx`. Then ship Swift (notarized, Sparkle) and deprecate Electron.

**Non-goals:** Do not merge the shelved `feat/gif-deploy-swift` branch. Do not add a GIF deploy UI to Swift (Electron removed it). Do not regress the HTML deploy path. Do not bundle ffmpeg in the shipping binary unless the quality gate forces the fallback. Do not remove Electron code this weekend (deprecate only; leave one release as a safety net).

## 3. Key decisions (locked)

1. **Encode = AVFoundation-native, ffmpeg fallback.** The shipping path uses only Apple frameworks (no bundled binary). The encode/sample operations sit behind a protocol with two implementations; the AVFoundation one is the default, the ffmpeg shell-out one is a fallback selected only if the human quality gate rejects AVFoundation output. ffmpeg is NOT bundled unless that happens.
2. **Sunset = parity + ship + deprecate** (Electron code stays one release).
3. **Quality gate = human side-by-side** on the real 39-slide ILS Quals deck.

**Why AVFoundation-native:** eliminates the bundled-binary problem entirely (no nested-binary codesigning/notarization/hardened-runtime surface, smaller app, cleaner sunset). Apple supports the hard requirement — a forced keyframe at each arbitrary slide timestamp — via `kCMSampleBufferAttachmentKey_ForceKeyFrame` on individual sample buffers during an `AVAssetReader → AVAssetWriter` re-encode. The known risk is that VideoToolbox's H.264 encoder is less quality-efficient than `libx264 -crf 18`; this is mitigated with a high bitrate / High profile and gated by human review, with the ffmpeg fallback as the escape hatch.

## 4. Architecture overview

The Swift video path mirrors the Electron flow (`videoDeckPipeline.ts` + `videoViewerGenerator.ts` + `deploy-video` IPC + `VideoViewer.tsx`) and reuses the existing Swift deploy infrastructure unchanged.

```
swift-app/Sources/
  Models/
    VideoDeployRequest.swift     # request struct (new)
    VideoAnalysis.swift          # {timestamps:[Double], slideCount:Int, width,height,fps} (new)
  Services/
    VideoEncoding.swift          # protocol VideoEncoder + shared types (new)
    AVFoundationVideoEncoder.swift  # default impl (new)
    FFmpegVideoEncoder.swift     # fallback impl, shell-out (new)
    GridSampler.swift            # downscale image/frame -> [Double] grid (salvage from gif branch)
    StillsMatch.swift            # DP match stills->frames (new, port of stillsMatch.ts)
    VideoTimestampDeriver.swift  # sample + match -> VideoAnalysis (new)
    VideoViewerGenerator.swift   # bundled-template fill (new)
    VideoDeployer.swift          # orchestrator + VideoDeployerSeams (new, salvage gif seam pattern)
  Resources/
    video-viewer-template.html   # extracted from videoViewerGenerator.ts (new bundled resource)
  Views/
    VideoDeployView.swift        # phase machine UI (new)
  (reused unchanged) VercelDeployer, VercelAPI, FileOperations, HistoryEntry,
   DeployProgressView, AppSettings, NavigationTab, SidebarView, ContentView
Tests/                          # new Swift Testing target (none on main today)
```

## 5. Components

### 5.1 Models

```swift
struct VideoDeployRequest: Sendable {
    let videoPath: String      // H.264 .mp4/.mov/.m4v
    let stillPaths: [String]   // one image per slide, natural-sorted (boundary/count source)
    let fps: Double            // constant export frame rate (default 30)
    let projectName: String
    let title: String
    let secureEmbed: Bool
}

struct VideoAnalysis: Sendable {
    let frames: [Int]          // matched video-frame index per slide
    let timestamps: [Double]   // frame/fps, rounded 3dp
    let slideCount: Int        // == stillPaths.count
    let width: Int
    let height: Int
    let fps: Double
}
```

### 5.2 GridSampler (salvage)

Port the GIF branch's `GridSampler` (an `enum` with static methods). Responsibility: downscale a `CGImage` (a decoded still, or a decoded video frame) to a fixed grid and return a flat `[Double]` of channel values. The grid MUST match the Electron sampler so cross-engine match parity holds: Electron uses 32×18 RGB (1728 values). Use 32×18×3 to match exactly (note: the gif branch used a different grid for GIF; for video parity match the Electron video sampler's 32×18).

```swift
enum GridSampler {
    /// Downscale a CGImage to a 32x18 RGB grid -> 1728 Doubles (0..255), row-major RGB.
    static func sample(_ image: CGImage) -> [Double]
}
```

### 5.3 StillsMatch (port of `src/utils/stillsMatch.ts`)

Pure, dependency-free, fully unit-testable. Faithful port of the DP matcher.

```swift
enum StillsMatch {
    /// Mean absolute difference of two equal-length grids.
    static func meanAbs(_ a: [Double], _ b: [Double]) -> Double

    /// Natural (numeric-aware) sort of file names/paths.
    static func naturalSort(_ names: [String]) -> [String]

    /// DP-match N stills to M frames with strictly-increasing frame indices.
    /// Returns one matched frame index per still (length N). Monotonic by construction.
    static func matchStillsToFrames(_ stills: [[Double]], _ frames: [[Double]]) -> [Int]
}
```

Behavior to preserve exactly: cost = `meanAbs(still_i, frame_f)`; `dp[i][f]` = min cumulative cost with still `i` on frame `f` and each subsequent still on a strictly greater frame; backtrack from the minimal end state; output is per-slide frame indices. Edge cases: empty stills → `[]`; single still → the globally-cheapest frame; N stills require M ≥ N (document behavior if violated — clamp/throw).

### 5.4 VideoEncoder protocol + two impls

```swift
protocol VideoEncoder: Sendable {
    /// Probe container/stream for dimensions + constant frame rate.
    func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double)

    /// Decode `url` to per-frame 32x18 RGB grids (downscaled), in order.
    /// Used for both the video (many frames) and a still (one frame).
    func sampleGrids(url: URL) async throws -> [[Double]]

    /// Re-encode `input` to web-safe H.264 with a forced keyframe at each timestamp.
    /// Output: yuv420p, High profile, no audio, moov-atom-at-front (faststart).
    func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double]) async throws
}
```

**AVFoundationVideoEncoder (default):**
- `probe`: `AVURLAsset` → first video track → `naturalSize` + `nominalFrameRate` (fallback 30 / 1920×1080).
- `sampleGrids`: `AVAssetImageGenerator` with a downscaled `maximumSize` (or read via `AVAssetReader` + downscale through a `CGContext`), one grid per frame at the video's frame cadence; for a still image, decode via `CGImageSource` → one grid. Reuse `GridSampler.sample`. Must sample stills and frames to the SAME grid.
- `encodeWithKeyframes`: `AVAssetReader` reads the source video samples; for each output sample whose presentation time is at/just past a slide timestamp, attach `kCMSampleBufferAttachmentKey_ForceKeyFrame = true`; write through `AVAssetWriterInput` configured: codec `AVVideoCodecTypeH264`, `AVVideoProfileLevelKey = High AutoLevel`, `AVVideoAllowFrameReordering = false`, a high `AVVideoAverageBitRateKey` (or `kVTCompressionPropertyKey_Quality ≈ 0.95`), pixel format 4:2:0 8-bit (yuv420p); writer `shouldOptimizeForNetworkUse = true`. Match each forced timestamp to the nearest output frame (same rounding as ffmpeg `-force_key_frames`). Honor cancellation. Do not mutate/reuse a `CMSampleBuffer` after append.

**FFmpegVideoEncoder (fallback, not bundled by default):**
- Shell out via `Process()` (reuse the `findVercelCli`-style binary-discovery pattern to locate `ffmpeg`/`ffprobe` on PATH; surface a clear error if absent). Reproduce the exact Electron args:
  - probe: `ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of default=noprint_wrappers=1`
  - sample: `ffmpeg -v error -i <in> -vf scale=32:18 -f rawvideo -pix_fmt rgb24 -` → split into 1728-float frames
  - encode: `ffmpeg -i <in> -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -force_key_frames "<csv>" -movflags +faststart -an <out>`
- Selection: the active encoder is chosen by a settings flag / build switch defaulting to AVFoundation; the fallback is only wired in if the quality gate rejects AVFoundation. (Document the one-line switch; do not bundle ffmpeg in the app target unless invoked.)

### 5.5 VideoTimestampDeriver

```swift
enum VideoTimestampDeriver {
    /// Derive per-slide timestamps by DP-matching stills to video frames.
    static func derive(encoder: VideoEncoder, videoURL: URL, stillURLs: [URL], fps: Double)
        async throws -> VideoAnalysis
}
```
Behavior: natural-sort stills; `encoder.sampleGrids(video)` and one grid per still; `StillsMatch.matchStillsToFrames`; `timestamps = frames.map { round(($0 / fps) * 1000) / 1000 }`; `slideCount = stills.count`. Off-main, cancellable.

### 5.6 VideoViewerGenerator + bundled template

Mirror `videoViewerGenerator.ts`. Extract its full HTML/CSS/JS into `Sources/Resources/video-viewer-template.html` verbatim, replacing the interpolated values with placeholder tokens. Load via `Bundle.main`, fill in a single pass (no re-scan of injected values — matches the GIF port's parity discipline).

```swift
enum VideoViewerGenerator {
    /// Returns the deployable index.html for the video viewer.
    static func generate(videoFilename: String, secureEmbed: Bool,
                         timestamps: [Double], videoWidth: Int, videoHeight: Int) -> String
}
```
Tokens: `{{VIDEO_FILENAME}}`, `{{TS}}` (JSON array, must match JS `JSON.stringify` formatting — no spaces, to keep byte-parity), `{{VW}}`, `{{VH}}`, `{{SECURE_EMBED_CSS}}`, `{{SECURE_EMBED_SCRIPT}}`. Secure-embed strings must match Electron exactly: CSS `body { user-select: none; } #deck video { pointer-events: none; }`, script `document.addEventListener('contextmenu', function(e){ e.preventDefault(); });`. Preserve the iframe-fill responsive behavior and the `kd-viewer-height` postMessage.

### 5.7 VideoDeployer + seams

Salvage the GIF branch's injectable-seam pattern.

```swift
struct VideoDeployerSeams: Sendable {
    var encoder: VideoEncoder
    var ensureProjectAndDeploy: @Sendable (_ folder: String, _ projectName: String,
        _ secureEmbed: Bool, _ onProgress: @Sendable (ProcessingStep) -> Void) async throws -> String  // returns resolved URL
}

enum VideoDeployer {
    static func deploy(_ request: VideoDeployRequest, settings: AppSettings,
                       seams: VideoDeployerSeams,
                       onProgress: @Sendable (ProcessingStep) -> Void)
        async throws -> VideoDeployResult
}

struct VideoDeployResult: Sendable {
    let url: String; let projectName: String; let title: String; let slideCount: Int; let folderPath: String
}
```
Flow (mirror `deploy-video` IPC): create temp dir `/tmp/keynote-deployer-video-<ts>` → `encoder.probe` → `VideoTimestampDeriver.derive` → `encoder.encodeWithKeyframes` → write `deck.mp4` → `VideoViewerGenerator.generate` → write `index.html` → guard `settings.vercelToken` → deploy (default seam wraps `VercelDeployer.deploy(...)` + `VercelAPI.resolveProductionUrl`) → 4 progress steps → cleanup temp. The **View** (not the deployer) persists the `HistoryEntry` (folderPath = videoPath, fixesApplied = 0) and auto-copies the URL if enabled, matching how the Swift GIF/Deploy views handle history.

### 5.8 VideoDeployView

Phase machine mirroring `VideoViewer.tsx`:
```swift
enum Phase { case drop, confirm, deploying, complete, error }
```
- **drop:** drop zone (`.onDrop(of: [.fileURL])`) + “Choose Video…” `NSOpenPanel` filtered to mp4/mov/m4v. On select: stash path + size, advance to confirm.
- **confirm:** a video preview (`AVKit.VideoPlayer` or an `NSViewRepresentable` `AVPlayerView`), filename/size/dimensions, a **Pick Stills Folder** button (native folder picker → filter images → naturalSort → store paths + show count = slide count), an **fps** numeric field (default 30), project name (kebab-case of filename + settings prefix), secure-embed `Toggle` (default on). Deploy disabled until video + stills.count > 0 + projectName non-empty. Back / Deploy.
- **deploying:** `DeployProgressView` driven by `VideoDeployer` progress (4 steps).
- **complete:** URL field, Copy URL, Copy Framer Embed (aspect from probed dims), Open in Browser, “Deploy Another”.
- **error:** message + Retry / Start Over.

### 5.9 Navigation + parity cleanup

`NavigationTab` already has `.video`. Add `case .video: VideoDeployView()` in `ContentView`; ensure `SidebarView` lists it (label “Deploy Video”). Sidebar order to match Electron: Deploy HTML, Deploy Video, Projects, History, Settings. No GIF tab.

### 5.10 project.yml

Add a `Sources/Resources` resources entry (bundle `video-viewer-template.html`). Add a Swift Testing **test target** (none on main; the GIF branch did this via xcodegen — follow that precedent). Bump `CURRENT_PROJECT_VERSION` for the release.

## 6. Build sequence (suggested sections)

1. **Models + project.yml** — `VideoDeployRequest`, `VideoAnalysis`, resources + test target wiring. (Foundation; compiles, no behavior.)
2. **StillsMatch + GridSampler** — pure algorithms + their parity tests (DP-match fixture vs TS output; grid sampler shape). Highest-value offline gate, no AV/ffmpeg needed.
3. **VideoViewerGenerator + bundled template** — extraction + single-pass fill + byte-parity test vs Electron output fixture.
4. **VideoEncoder protocol + AVFoundationVideoEncoder** — probe/sampleGrids/encodeWithKeyframes; unit tests on the writer settings + forced-keyframe placement; a small real-asset integration check.
5. **FFmpegVideoEncoder (fallback)** — arg-string parity tests vs `videoDeckPipeline.ts`; gated behind the encoder switch (not bundled).
6. **VideoTimestampDeriver** — derive on the 39-still fixture → 39 monotonic timestamps.
7. **VideoDeployer + seams** — seam-injected offline orchestration test (step order, result fields, cleanup).
8. **VideoDeployView + nav wiring** — UI phase machine; remove any GIF tab; runtime/Peekaboo gate.
9. **PARITY.md + CLAUDE.md + sunset** — flip rows, deprecate Electron note, notarize/Sparkle release, portal-workflow verify.

## 7. Verification

Offline (TDD, before live):
- DP-match parity vs TS (incl. empty/single/monotonic edges).
- Viewer byte-parity vs Electron `generateVideoViewerHtml`.
- Encoder settings/args unit tests (AV writer dict + forced-keyframe placement; ffmpeg arg parity).
- Timestamp derivation on the 39-still fixture → 39 slides, monotonic.
- Deploy orchestration via injected seams (no network/encoder).
- `xcodegen generate && xcodebuild build/test -scheme KeynoteDeployer -destination "platform=macOS"` exit 0, Swift 6 strict-concurrency clean.

Live (final acceptance):
- Deploy the 39-slide ILS Quals deck via AVFoundation → reachable viewer URL with 39 baked stops.
- **Quality gate:** side-by-side vs the ffmpeg-baseline deploy (already live); Edward approves AVFoundation OR we switch to the bundled-ffmpeg fallback (then bundle + notarize ffmpeg).
- Runtime/Peekaboo: dev-launch → Deploy Video tab → drop video → pick stills → deploy → complete URL.

## 8. Sunset / cutover checklist

- Flip PARITY.md deck rows to the video path; retire GIF rows; confirm all non-deck rows remain Done on both.
- Confirm shared `settings.json` stays compatible during transition.
- `/notarize` Swift → DMG + Sparkle appcast; verify Gatekeeper-clean on a clean machine.
- Verify the portal workflow (`/portal-deck` → Airtable `Deck URL` → Framer embed) renders a Swift-deployed video URL.
- Mark Electron deprecated in README + CLAUDE.md (stop-building note); leave code one release; schedule full removal as a follow-up.

## 9. Risks & mitigations

- **VideoToolbox H.264 quality < libx264** → high bitrate/High profile + human quality gate + ffmpeg fallback ready.
- **Forced-keyframe timing precision** (rounds to nearest output frame) → derive timestamps against the actual output frame grid; re-derive per export.
- **Grid mismatch between stills and frames** would corrupt the DP-match → both sampled through the identical `GridSampler` 32×18 path; covered by parity tests.
- **JSON formatting drift** in `{{TS}}` would break viewer byte-parity → emit compact JSON matching JS `JSON.stringify`; byte-parity test guards it.
- **Deadline** → sections 1–3 (pure, offline) land first and de-risk the bulk; AVFoundation encode (4) is the only novel-risk section and has the ffmpeg fallback.

## 10. Review amendments (Gemini iteration-1 — amendment wins on conflict)

These refine §3/§5/§7/§8 above; where they conflict with an earlier section, the amendment governs.

- **A1 [security] ffmpeg fallback uses argument-array `Process`, never a shell.** `process.executableURL = <ffmpeg/ffprobe>`, `process.arguments = [...]`. NEVER `/bin/sh -c "<interpolated paths>"`. Filenames are untrusted → no string interpolation into a command line. (Applies to §5.4 FFmpegVideoEncoder.)
- **A2 [correctness] Reject VFR input.** `VideoEncoder.probe` detects variable frame rate by sampling several consecutive `CMSampleBufferGetPresentationTimeStamp` deltas; if not (near-)constant, throw a descriptive error telling the user to re-export at constant frame rate. Rationale: `frame/fps` timestamping assumes CFR; Keynote exports CFR, but a dropped non-Keynote file could be VFR and would mis-match every slide. (Option A — reject; the full CMTime-grid retime is out of scope.)
- **A3 [correctness] Normalize color space in `GridSampler`.** Draw each source `CGImage` (still or frame) into an explicit **sRGB** `CGContext` before sampling, so stills (often Display P3) and frames (sRGB) are compared in one space. Does not change the DP-match parity test (that runs on a shared precomputed grid fixture, not live sampling). (§5.2.)
- **A4 [robustness] `defer` temp cleanup.** In `VideoDeployer.deploy`, immediately after creating the temp dir, `defer { try? FileManager.default.removeItem(atPath: tempDir) }` so a throw/cancel cannot strand GB of video in `/tmp`. (§5.7.)
- **A5 [UX] Analysis progress.** `VideoTimestampDeriver.derive` accepts a progress handler (report every N frames sampled); `VideoDeployView` shows an "Analyzing video frames…" state during the sample/match pass so it doesn't read as hung. (§5.5, §5.8.)
- **A6 [clarity] ffmpeg-fallback trigger = hidden `UserDefaults` flag** (e.g. `defaults write <bundleid> useFfmpegEncoder -bool YES`), read by `VideoDeployerSeams` to inject `FFmpegVideoEncoder` instead of `AVFoundationVideoEncoder`. Not a compile-time flag (would need a full release to flip) and not a user-facing setting (clutter). Default = AVFoundation. (§3, §5.4, §5.7.)
- **A7 [process] Quality-gate checklist** (objective, transferable): (a) no transition blockiness/artifacts on the ILS deck; (b) slide text crisp/readable; (c) colors match the source Keynote; (d) paused keyframes clean — no shimmer from the prior frame. Edward signs off against this list. (§7.)
- **A8 [robustness] Input validation:** `probe` throws a clear error on a corrupt file or a file with no video track; the stills picker filters `UTType.image` (ignores non-image files like `.DS_Store`/`Icon`); warn if a still's aspect ratio differs markedly from the video. (§5.4, §5.8.)
- **A9 [devex] README ffmpeg note:** to develop/test the fallback, install ffmpeg+ffprobe on PATH (Homebrew). (§8.)
- **A10 [code] naturalSort = `String.compare(options: .numeric)`** rather than a hand-port; the parity test must confirm it orders the still names (`…001.jpeg`…`…039.jpeg`) identically to the TS `naturalSort`. (§5.3.)
