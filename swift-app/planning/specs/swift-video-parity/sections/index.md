<!-- PROJECT_CONFIG
runtime: swift-xcode
test_command: cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -quiet
END_PROJECT_CONFIG -->

<!-- SECTION_MANIFEST
section-01-models-project
section-02-stillsmatch-gridsampler
section-03-viewer-generator
section-04-avfoundation-encoder
section-05-ffmpeg-fallback
section-06-timestamp-deriver
section-07-video-deployer
section-08-video-deploy-view
section-09-parity-sunset
END_MANIFEST -->

# Implementation Sections Index — Swift Video-Deploy Parity

Source: `claude-plan.md` (incl. §10 review amendments) + `claude-plan-tdd.md`. Build the H.264 video deck-deploy path in the Swift app at parity with Electron, then deprecate Electron.

## Dependency Graph

| Section | Depends On | Blocks | Parallelizable |
|---------|------------|--------|----------------|
| section-01-models-project | - | all | Yes |
| section-02-stillsmatch-gridsampler | 01 | 04, 06 | Yes |
| section-03-viewer-generator | 01 | 07 | Yes |
| section-04-avfoundation-encoder | 01, 02 | 05, 06, 07 | No |
| section-05-ffmpeg-fallback | 01, 04 | 07 | Yes |
| section-06-timestamp-deriver | 02, 04 | 07 | Yes |
| section-07-video-deployer | 03, 04, 05, 06 | 08 | No |
| section-08-video-deploy-view | 07 | 09 | No |
| section-09-parity-sunset | 08 | - | No |

## Execution Order

1. section-01-models-project (no dependencies)
2. section-02-stillsmatch-gridsampler, section-03-viewer-generator (parallel after 01)
3. section-04-avfoundation-encoder (after 01 AND 02)
4. section-05-ffmpeg-fallback, section-06-timestamp-deriver (parallel after 04; 06 also needs 02)
5. section-07-video-deployer (after 03 AND 04 AND 05 AND 06)
6. section-08-video-deploy-view (after 07)
7. section-09-parity-sunset (after 08)

## Section Summaries

### section-01-models-project
`VideoDeployRequest`, `VideoAnalysis` models; add a Swift Testing test target + a `Sources/Resources` bundling entry to `project.yml`; bump `CURRENT_PROJECT_VERSION`. Foundation for everything else.

### section-02-stillsmatch-gridsampler
Port `StillsMatch` (DP-match + `meanAbs` + numeric `naturalSort`) from `stillsMatch.ts`, and `GridSampler` (32×18 sRGB-normalized grid, salvaged from the GIF branch). Pure, offline; the highest-value parity gate (DP-match vs TS oracle; sRGB normalization A3; naturalSort A10).

### section-03-viewer-generator
`VideoViewerGenerator` + bundled `video-viewer-template.html` extracted verbatim from `videoViewerGenerator.ts`; single-pass token fill. Byte-parity with Electron output (compact `{{TS}}` JSON, exact secure-embed strings, iframe-fill behavior).

### section-04-avfoundation-encoder
`VideoEncoder` protocol + `AVFoundationVideoEncoder`: `probe` (CFR-only; reject VFR A2 + corrupt/no-track A8), `sampleGrids` (AVAssetImageGenerator → GridSampler), `encodeWithKeyframes` (AVAssetReader→AVAssetWriter, per-frame `kCMSampleBufferAttachmentKey_ForceKeyFrame`, H.264 High/yuv420p/AllowFrameReordering=false/optimizeForNetworkUse, cancellable).

### section-05-ffmpeg-fallback
`FFmpegVideoEncoder` implementing the same protocol via argument-array `Process` (A1 — no shell, no string interpolation); exact `videoDeckPipeline.ts` arg parity; PATH discovery + clear missing-binary error. Selected only via the hidden `useFfmpegEncoder` UserDefaults flag (A6); not bundled.

### section-06-timestamp-deriver
`VideoTimestampDeriver.derive`: natural-sort stills → sample(video)+sample(stills) → `StillsMatch` → `VideoAnalysis` (timestamps frame/fps 3dp, slideCount). Off-main, cancellable, progress handler (A5).

### section-07-video-deployer
`VideoDeployer` + `VideoDeployerSeams` (encoder injection via A6 flag): temp dir (defer-cleanup A4) → probe → derive → encode → generate index.html → `VercelDeployer.deploy` + resolve URL → 4-step progress → `VideoDeployResult`. Token guard. Reuse Vercel/FileOperations unchanged. Seam-injected offline tests.

### section-08-video-deploy-view
`VideoDeployView` phase machine (drop→confirm→deploying→complete→error) mirroring `VideoViewer.tsx`: drop video, video preview, pick stills folder (UTType.image filter A8), fps field, project name (prefix+kebab), secure-embed toggle, analyzing-progress (A5), DeployProgressView, complete actions. Wire `.video` into ContentView/SidebarView (no GIF tab); persist HistoryEntry + auto-copy. Runtime/Peekaboo gate.

### section-09-parity-sunset
Flip PARITY.md deck rows to the video path (retire GIF rows; confirm non-deck rows Done); README ffmpeg dev note (A9) + quality-gate checklist (A7); update CLAUDE.md (Swift video services + Electron-deprecated note); `/notarize` → DMG + Sparkle appcast; verify portal workflow with a Swift-deployed video URL; deprecate Electron (code stays one release).
