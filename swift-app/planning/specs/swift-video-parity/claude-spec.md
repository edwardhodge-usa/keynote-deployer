# Spec — Swift Video-Deploy Parity → Sunset Electron

## Objective
Add the H.264 **video deck-deploy** path to the Swift/SwiftUI Keynote Deployer so it reaches parity with the updated Electron app, then ship Swift (notarized, Sparkle) and **deprecate** Electron. Deadline: this weekend.

## Locked decisions (from interview)
1. **Encode = AVFoundation-native, ffmpeg fallback.** Shipping path is pure-Apple (no bundled binary). `AVAssetReader → AVAssetWriter`, per-frame `kCMSampleBufferAttachmentKey_ForceKeyFrame` at each slide timestamp, `AVVideoAllowFrameReordering=false`, H.264 High profile, yuv420p, `shouldOptimizeForNetworkUse=true`. Frame sampling for the DP-match via `AVAssetImageGenerator` (downscaled). ffmpeg/ffprobe shell-out is implemented behind the SAME protocol as a **fallback**, selected only if the quality gate fails — not bundled unless that happens.
2. **Sunset = parity + ship + deprecate.** Notarize + DMG + Sparkle release Swift; mark Electron deprecated (stop building, doc note); leave Electron code in-repo one release. Full removal later.
3. **Quality gate = human side-by-side** on the 39-slide ILS Quals deck (ffmpeg baseline already live vs AVFoundation), Edward approves or we fall back.

## Architecture (mirror Electron, reuse Swift)
**New Swift components:**
- `VideoEncoder` protocol + two impls: `AVFoundationVideoEncoder` (default) and `FFmpegVideoEncoder` (fallback). Common ops: `probe(url) -> (w,h,fps)`, `sampleGrid(url|frames) -> [[Double]]`, `encodeWithKeyframes(input, output, timestamps)`.
- `StillsMatch` (enum): `matchStillsToFrames(_ stills:[[Double]], _ frames:[[Double]]) -> [Int]` + `meanAbs` + `naturalSort` — faithful port of `src/utils/stillsMatch.ts` (DP, monotonic). Pure, fully unit-testable.
- `GridSampler` (salvage from GIF branch): downscale image/frame → fixed 32-grid `[Double]`, shared by stills + video frames (same grid both sides — load-bearing for match correctness).
- `VideoTimestampDeriver`: orchestrates sample(stills) + sample(video frames) → `StillsMatch` → `{frames, timestamps (frame/fps, 3dp), slideCount}`.
- `VideoViewerGenerator` (enum): mirror `videoViewerGenerator.ts`; bundled `video-viewer-template.html` resource via `Bundle.main`, single-pass token fill (`{{VIDEO_FILENAME}}`,`{{TS}}`,`{{VW}}`,`{{VH}}`,`{{SECURE_EMBED_CSS}}`,`{{SECURE_EMBED_SCRIPT}}`). Byte-parity with Electron output.
- `VideoDeployer` (enum) + `VideoDeployerSeams` (salvage GIF seam pattern): orchestrate temp dir → probe → derive → encode → generate index.html → `VercelDeployer.deploy` → resolve URL → `HistoryEntry` → autoCopy → cleanup. Seams injectable for offline tests.
- `VideoDeployRequest` model: `{videoPath, stillPaths:[String], fps:Double, projectName, title, secureEmbed}`.
- `VideoDeployView` (SwiftUI): phase machine `{drop, confirm, deploying, complete, error}` mirroring `VideoViewer.tsx`. Drop video (.mp4/.mov/.m4v) + NSOpenPanel; confirm = preview + pick-stills-folder (native folder picker, filter+naturalSort images) + fps field + project name (kebab+prefix) + secure-embed toggle; deploying = `DeployProgressView` 4 steps; complete = Copy URL / Framer Embed / Open.

**Reuse UNCHANGED:** `VercelDeployer`, `VercelAPI.resolveProductionUrl`, `FileOperations`, `HistoryEntry`, `DeployProgressView`, `AppSettings`, `NavigationTab` (`.video` exists), sidebar routing.

**Invariant:** stills = build-time boundary/slide-count source only; never inserted, never shipped. Output = `deck.mp4` + `index.html`. H.264 only (never HEVC).

## Out of scope / do-not
- Do NOT merge `feat/gif-deploy-swift`. No GIF deploy UI in Swift (mirror Electron which removed it).
- Do NOT regress the HTML deploy path (100% parity holds).
- Do NOT bundle ffmpeg unless the quality gate forces the fallback.

## Verification (TDD-first, offline before live)
- **DP-match parity:** Swift `matchStillsToFrames` == TS output on a shared grid fixture (incl. empty/single-still edges, monotonicity).
- **Viewer byte-parity:** Swift `VideoViewerGenerator.generate(...)` == Electron `generateVideoViewerHtml(...)` for identical inputs (fixture extracted from Electron, like the GIF port did).
- **Encoder unit tests:** AVFoundation settings dict (codec H.264, profile High, yuv420p, allowFrameReordering=false, optimizeForNetworkUse) + forced-keyframe attachment placement at each ts; ffmpeg-fallback arg string parity with `videoDeckPipeline.ts`.
- **Timestamp derivation:** on the 39-still fixture → 39 slides, monotonic, frame/fps math correct.
- **Deploy orchestration:** seam-injected offline test (no network/encoder) verifies step order, HistoryEntry fields, cleanup.
- **Build:** `xcodegen generate && xcodebuild build/test -scheme KeynoteDeployer` exits 0, Swift 6 strict-concurrency clean.
- **Live gate (Edward):** deploy 39-slide ILS Quals deck via AVFoundation → reachable viewer URL with 39 baked stops → side-by-side vs the ffmpeg-baseline deploy → approve or fall back.
- **Runtime/Peekaboo:** dev-launch → Deploy Video tab → drop video → pick stills → deploy → complete URL.

## Cutover / sunset checklist
- Flip PARITY.md deck rows to the video path; retire GIF rows; confirm all other rows Done.
- Confirm shared `settings.json` compatibility during transition.
- `/notarize` Swift → DMG + Sparkle appcast; verify Gatekeeper-clean on a clean machine.
- Verify portal workflow (`/portal-deck` → Airtable `Deck URL` → Framer embed) works with a Swift-deployed video URL.
- Mark Electron deprecated in README + CLAUDE.md (stop-building note); schedule full code removal as a follow-up.

## Constraints
Swift 6.2, macOS 15+, strict concurrency (`@Sendable` progress, off-main `nonisolated async`, cancellable). Stateless services = `enum`+static. Bundled resources via `Bundle.main`. Build via apple-platform-build-tools / XcodeBuildMCP; visual gate via Peekaboo on fresh DerivedData. Asset for live gate: `…/Keynote Video for Portal/ILS_Quals 2026 V3.m4v` + `…/ILS_Quals 2026 V3/ILS_Quals 2026 V2/` (39 jpegs).
