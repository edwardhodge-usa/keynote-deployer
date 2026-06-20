# Research — Swift Video-Deploy Parity

## A. Codebase map (Electron source + Swift reuse + GIF salvage)

### Electron video pipeline — `electron/videoDeckPipeline.ts`
- Constants: `SAMPLE_W=32`, `SAMPLE_H=18` (grid = 32×18×3 = 1728 floats/frame), `MAX_BUFFER=256MB`.
- `sampleGrids(ffmpegPath, input) → number[][]`: ffmpeg `-v error -i <in> -vf scale=32:18 -f rawvideo -pix_fmt rgb24 -` → split bytes into per-frame 1728-vectors. **Used for BOTH video frames and stills** (a still decodes to 1 frame) so they share the same grid.
- `deriveTimestamps({videoPath, stillPaths, fps}) → {frames, timestamps, slideCount}`: natural-sort stills → sampleGrids(each still) + sampleGrids(video) → `matchStillsToFrames(stillGrids, frameGrids)` → `timestamps = frames.map(f => round((f/fps)*1000)/1000)`, `slideCount = stillGrids.length`.
- `encodeWithKeyframes({input, output, timestamps, crf=18})`: ffmpeg `-i <in> -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -force_key_frames "<csv-seconds>" -movflags +faststart -an <out>`.
- `probeVideo({input}) → {width,height,fps}`: ffprobe `-v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of default=noprint_wrappers=1`; fps = num/denom (default 30); dims default 1920×1080.

### Stills→frame DP-match — `src/utils/stillsMatch.ts`
- `matchStillsToFrames(stills:number[][], frames:number[][]) → number[]` (length N stills):
  - cost[i][f] = `meanAbs(stills[i], frames[f])` (mean abs channel diff).
  - DP: `dp[i][f]` = min total cost matching stills 0..i with still i → frame f, **strictly increasing** frame index (monotonic); parent pointers in `back[][]`; backtrack from min endframe.
  - Output: per-slide matched frame index.
- `meanAbs(a,b)` = Σ|a-b|/len. `naturalSort(names)` = numeric-aware sort.
- **No Swift equivalent exists** (GIF branch only has quiet-run detection, not DP-match) → must port (pure function, ~30 lines).

### Viewer generator — `electron/videoViewerGenerator.ts`
- `generateVideoViewerHtml(videoFilename, secureEmbed, timestamps, w=1920, h=1080) → string`: self-contained single-`<video src="./<file>">`; `TS = JSON.stringify(timestamps)`; aspect-ratio from w/h.
- Nav model: rest = paused on slide keyframe (`settleOn`), Next = play to next ts then pause, Prev/dots = instant seek, arrows = prev/next.
- Secure-embed CSS: `body{user-select:none} #deck video{pointer-events:none}`; script: `contextmenu preventDefault`.
- iframe-fill responsive: detects `window.self!==window.top` → `body.in-iframe`, `clamp()` sizing, hides chrome, posts `kd-viewer-height` for parent resize.

### Electron deploy-video IPC — `electron/main.ts` (548–627)
- `deploy-video(request: VideoDeployRequest)`: temp `/tmp/keynote-deployer-video-<ts>` → probe → derive → encode → `generateVideoViewerHtml` → write index.html → guard token → `deployToVercel(tempFolder, projectName, token, teamId, noop, secureEmbed, domains)` → 4-step progress → `HistoryEntry{slideCount, folderPath=videoPath, fixesApplied:0}` → autoCopy → cleanup.
- `select-stills-folder`: dir picker → filter `.jpg/.jpeg/.png/.webp` → naturalSort → full paths.
- `VideoDeployRequest = {videoPath, stillPaths[], fps, projectName, title, secureEmbed}` (`src/types/index.ts:61`).

### Swift reuse (UNCHANGED) — `swift-app/Sources/`
- `VercelDeployer.deploy(folderPath, projectId, token, teamId, secureEmbed, embedAllowedDomains, onProgress) → DeployResult` — returns EMPTY url; caller resolves via `VercelAPI.resolveProductionUrl(projectId)`. Has a `findVercelCli()` binary-discovery pattern (reusable for ffmpeg lookup if we shell out).
- `FileOperations`: loadSettings/saveSettings/detectVercelToken/validateKeynoteFolder.
- `IndexHtmlGenerator.generate(slideCount, secureEmbed)` — the **HTML-export** wrapper (NOT the video viewer); reuse its **bundled-resource + token-fill pattern**, not its content.
- `HistoryEntry` @Model: id(unique)/projectName/title/slideCount/url/folderPath/date/fixesApplied — fits video as-is.
- `DeployProgressView(steps:[ProcessingStep])` — drives progress unchanged.
- `AppSettings`: vercelToken/vercelTeamId/theme/autoCopyUrl/enableRuntimeVerification/projectNamePrefix/lastFolderPath/secureEmbed/embedAllowedDomains — all present.
- `NavigationTab` enum already includes `.video`; sidebar (`NavigationSplitView`) routes by tab.
- `DeployView` phase machine: `enum Phase {select, confirm, processing, complete, error}` — template for VideoDeployView.

### GIF branch salvage — `feat/gif-deploy-swift` (DO NOT MERGE)
- `GifDeployer` + `GifDeployerSeams` — injectable-seam deploy orchestrator (deploy→ensure→resolve→history); **copy structure** for `VideoDeployer`.
- `GridSampler` (enum): `sample(CGImage)→[Double]` downscale grid; constants `samplePoints=1000, gridSize=32`. Reusable for native frame/still sampling.
- `GifFrameSource`: per-frame streaming/memory discipline pattern.
- `GifViewerGenerator.fill()` single-pass token substitution + `Bundle` resource load — pattern for `VideoViewerGenerator`.
- `SlideDetector` quiet-run — NOT reused (video boundaries come from DP-match, not pixels).

### project.yml / PARITY
- `project.yml`: macOS 15.0, Swift 6.2, app target `KeynoteDeployer`, Sparkle SPM 2.7. **No test target / no resources entry on main** → add both (GIF branch added a test target via xcodegen as precedent).
- `PARITY.md`: all 51 HTML-path rows Done on both; GIF rows are Electron-only; **no VIDEO row yet** → add VIDEO deploy rows, retire GIF rows.

## B. Encode dependency — ffmpeg vs AVFoundation (the architecture crux)

### AVFoundation/VideoToolbox: VIABLE for forced keyframes
- **Arbitrary per-slide forced keyframes — fully supported.** `kCMSampleBufferAttachmentKey_ForceKeyFrame=true` attached to the target `CMSampleBuffer`(s) via `AVAssetReader` → `AVAssetWriterInput`(H.264) emits an IDR at exactly those presentation times. (Lower-level equivalent: `kVTEncodeFrameOptionKey_ForceKeyFrame` per-frame to `VTCompressionSessionEncodeFrame`.) `AVVideoMaxKeyFrameIntervalKey/...DurationKey` are interval-only — NOT the mechanism (but set a large max to suppress extra keyframes).
- Set `AVVideoAllowFrameReordering = false` → clean closed-GOP boundaries (crisp paused frames). Forced ts rounds to nearest output frame (same as ffmpeg) → re-derive timestamps per export against the actual frame grid.
- **Web-safe H.264:** yuv420p 8-bit 4:2:0 is AVFoundation default; set `AVVideoProfileLevelKey = H264_High_AutoLevel`; explicit `AVVideoCodecTypeH264` (never HEVC). Browser-decodable on Chrome/FF/Safari.
- **faststart:** `AVAssetWriter.shouldOptimizeForNetworkUse = true` = moov-atom-at-front. One Boolean.
- **Native frame sampling** for DP-match: `AVAssetImageGenerator` (downscaled CGImage → GridSampler) replaces ffmpeg `scale=32:18` — enables a **zero-binary** pipeline.

### The caveat (primary risk)
- VideoToolbox H.264 encoder is materially less quality-efficient than `libx264 -crf 18 -preset medium` — documented artifacts on animated/blur content, ~2× bitrate to match. Slides-at-rest are high-scrutiny paused frames → must push `AVVideoAverageBitRateKey` high (or `kVTCompressionPropertyKey_Quality≈0.95`, CQ solid on Apple Silicon/macOS 15+) and **visually validate vs the ffmpeg baseline** before cutover.
- Buffer gotcha: don't mutate/reuse a `CMSampleBuffer` after `append()` (writer caches; copy if needed).

### Decision framing (for interview)
- **Option A — AVFoundation-native (zero binary):** no bundled ffmpeg → smaller app, no nested-binary signing/notarization/hardened-runtime surface, pure-Apple sunset story. Cost: more novel code (AVAssetReader/Writer re-tag pass + native sampling), quality must be validated, more risk for a weekend.
- **Option B — Bundle ffmpeg/ffprobe:** reuses the EXACT proven pipeline (the live gate already passed with it) → lowest output-quality risk. Cost: bundle + codesign `--options runtime --timestamp` nested binaries, notarize, verify Gatekeeper-clean on a clean machine, ~larger app + Sparkle payload; ffmpeg licensing (LGPL/GPL build) to confirm for distribution.
- **Option C — Hybrid:** AVFoundation native, ffmpeg as optional fallback if on PATH. Most code; probably over-scoped for the deadline.

Sources (AVFoundation): kCMSampleBufferAttachmentKey_ForceKeyFrame, kVTEncodeFrameOptionKey_ForceKeyFrame, shouldOptimizeForNetworkUse, kVTCompressionPropertyKey_Quality/ProfileLevel, Apple forum threads on VT H.264 quality.

## C. Testing context (for TDD)
- Swift Testing framework (GIF branch added a `Tests` target via xcodegen — precedent to follow; main has none yet).
- Offline gates (no network/ffmpeg-on-CI dependency where possible):
  - **DP-match parity:** feed a fixed `[stills grids] + [frames grids]` fixture, assert Swift `matchStillsToFrames` == TS output (port the TS fixture).
  - **Viewer byte-parity:** assert Swift `VideoViewerGenerator.generate(...)` == Electron `generateVideoViewerHtml(...)` for identical inputs (extract Electron output as a fixture, like the GIF port did).
  - **probe/encode arg/property:** unit-test the constructed ffmpeg args (Option B) or the AVAssetWriter settings dict (Option A).
- Live gate (final acceptance, manual/Edward): real 39-slide ILS Quals video + stills → deploy → reachable viewer URL with 39 baked stops. Asset path known: `…/Keynote Video for Portal/ILS_Quals 2026 V3.m4v` + `…/ILS_Quals 2026 V3/ILS_Quals 2026 V2/` (39 jpegs).
