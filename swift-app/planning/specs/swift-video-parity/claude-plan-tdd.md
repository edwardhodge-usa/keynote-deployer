# TDD Plan — Swift Video-Deploy Parity

Framework: **Swift Testing** (`@Test`/`#expect`). A test target is added in Section 1 (none on `main` today; follow the `feat/gif-deploy-swift` precedent). Offline gates (Sections 2–3, 6–7) require no network/encoder/ffmpeg and run in CI. Encoder integration (Sections 4–5) needs a small real video asset; the live deploy + quality gate are manual (Edward).

Test stubs are prose/signatures only — the implementer (deep-implement) writes the assertions.

## Section 1 — Models + project.yml
- Test: `VideoDeployRequest` / `VideoAnalysis` are `Sendable`, encode/round-trip if `Codable` is added.
- Test: the new test target builds and runs an empty `@Test` (proves xcodegen test wiring).
- (No behavior to test beyond compile + target wiring.)

## Section 2 — StillsMatch + GridSampler  ← highest-value offline gate
**StillsMatch (parity vs TS `stillsMatch.ts`):**
- Test: `meanAbs` of two equal-length grids = known mean of absolute diffs; empty → 0.
- Test: `matchStillsToFrames` on a hand-built fixture (grids for N stills + M frames) returns the SAME per-slide frame indices as the TS `matchStillsToFrames` for that exact input (port the TS output as the oracle).
- Test: result is strictly monotonic (each matched frame > previous).
- Test edges: empty stills → `[]`; single still → globally-cheapest frame; N == M; document/assert behavior when M < N.
- Test: `naturalSort` (via `String.compare(.numeric)`) orders `["…010.jpeg","…002.jpeg","…001.jpeg"]` → `001,002,010` and matches the TS `naturalSort` order on the 39-name set (A10 parity).

**GridSampler:**
- Test: `sample(cgImage)` returns exactly 32×18×3 = 1728 values, all in 0…255.
- Test: a solid-color image yields a (near-)uniform grid of that color (sRGB-normalized).
- Test (A3): two images identical except tagged Display-P3 vs sRGB produce (near-)equal grids after sRGB normalization.

## Section 3 — VideoViewerGenerator + bundled template
- Test (byte-parity): `generate(videoFilename:secureEmbed:timestamps:videoWidth:videoHeight:)` output == an Electron `generateVideoViewerHtml(...)` fixture for identical inputs (extract the Electron output as a golden file).
- Test: `{{TS}}` is emitted as compact JSON (no spaces) matching JS `JSON.stringify` (guards byte-parity).
- Test: secureEmbed=true injects the exact CSS + contextmenu script strings; secureEmbed=false omits both.
- Test: the bundled `video-viewer-template.html` loads from `Bundle.main` at runtime (not nil).
- Test: filename + width/height tokens land in `src="./<file>"` and the aspect-ratio CSS.

## Section 4 — VideoEncoder protocol + AVFoundationVideoEncoder
- Test: `probe` on a known small CFR fixture returns its true width/height/fps.
- Test (A2): `probe` on a synthesized VFR fixture throws the VFR-reject error; on an audio-only/no-video-track file throws a descriptive error; on a corrupt file throws (A8).
- Test: the AVAssetWriter output settings dict = H.264 codec, High profile, `AllowFrameReordering=false`, 4:2:0 8-bit, high bitrate/quality; writer `shouldOptimizeForNetworkUse == true`.
- Test: forced-keyframe selection maps each timestamp to the nearest output-frame index (pure helper testable without encoding).
- Integration (small asset): `encodeWithKeyframes` produces a file whose frames at each timestamp are I-frames (probe keyframe positions), yuv420p, faststart (moov before mdat).
- Test: cancellation mid-encode stops and cleans up.

## Section 5 — FFmpegVideoEncoder (fallback)
- Test (A1 security): the constructed invocation uses `executableURL` + `arguments` array; assert NO `/bin/sh -c` and NO string interpolation of paths; a filename containing `"; rm -rf …` is passed as a single inert argument.
- Test (arg parity): `probe`/`sampleGrids`/`encodeWithKeyframes` argument arrays match the `videoDeckPipeline.ts` flags exactly (codec/crf/preset/pix_fmt/force_key_frames csv/faststart/-an; scale=32:18 rawvideo rgb24; ffprobe show_entries).
- Test: missing ffmpeg on PATH → clear actionable error.

## Section 6 — VideoTimestampDeriver
- Test: on the 39-still grid fixture + a frame-grid fixture, `derive` returns slideCount=39, 39 monotonic timestamps, `timestamps == frames.map{ round(($0/fps)*1000)/1000 }`.
- Test (A5): the progress handler is invoked during sampling (≥1 callback; final ≈ 100%).
- Test: stills are natural-sorted before matching.

## Section 7 — VideoDeployer + seams
- Test (offline, injected seams; no network/encoder): `deploy` calls steps in order probe→derive→encode→generate→deploy; returns `VideoDeployResult` with the resolved URL + slideCount; emits 4 progress steps.
- Test: missing `vercelToken` → guarded error before any deploy.
- Test (A4): the temp dir is removed on success AND on a thrown error (defer).
- Test (A6): when the hidden `useFfmpegEncoder` default is set, the seam injects `FFmpegVideoEncoder`; default injects `AVFoundationVideoEncoder`.

## Section 8 — VideoDeployView + nav wiring
- Test (logic, not pixels): phase transitions drop→confirm on file select; Deploy disabled until video + stills.count>0 + non-empty projectName; project name = prefix + kebab(filename).
- Test: stills picker filters `UTType.image` (ignores `.DS_Store`/`Icon`) and sets slideCount = image count (A8).
- Test: Framer-embed string uses the probed aspect ratio.
- Manual/Peekaboo: dev-launch → Deploy Video tab visible (no GIF tab) → drop → pick stills → deploy → complete URL.

## Section 9 — PARITY.md + CLAUDE.md + sunset
- Not unit-tested. Verification = doc review + the live gate + `/notarize` Gatekeeper check + portal-render check (manual).

## Cross-cutting
- Full suite green via `xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS"` (exit 0), Swift 6 strict-concurrency clean.
- Do not regress existing HTML-path tests.
