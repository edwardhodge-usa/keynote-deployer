# Swift Video-Deploy Parity → Sunset Electron

## Goal
Bring the Swift/SwiftUI **Keynote Deployer** to full feature parity with the **updated Electron app** (which now uses an H.264 **video** deck-deploy path instead of GIF), so the Electron app can be **retired this weekend**. Once the Swift app ships (notarized, via Sparkle), Electron is no longer used.

**Hard deadline:** ship-ready by this weekend.

## Repo
`~/Code/keynote-deployer` — dual-stack. Electron 33 + React (primary, being sunset) | Swift 6.2 + SwiftUI + SwiftData (macOS 15+, becoming sole app).

## What changed in Electron (the parity target)
The deck-deploy path switched **GIF → H.264 VIDEO** (PR #2, branch `feat/electron-video-deploy-ui`, merged/queued on origin). The GIF deploy UI was **removed**. New/relevant Electron code:
- `electron/videoDeckPipeline.ts` — `probeVideo` (ffprobe: width/height/fps), `deriveTimestamps` (DP-match per-slide stills → video frames → per-slide timestamps; `slideCount = stills.length`), `encodeWithKeyframes` (ffmpeg libx264 crf18, `-force_key_frames` at each slide, `+faststart`, `-an`).
- `electron/videoViewerGenerator.ts` — `generateVideoViewerHtml(videoFilename, secureEmbed, timestamps, w, h)` → self-contained single-`<video>` slide viewer (rest = paused keyframe, Next = play transition then pause, Prev/dots = instant seek; iframe-fill responsive; secure-embed CSS/script).
- `electron/main.ts` — `deploy-video` IPC handler (mkdir temp → probe → deriveTimestamps → encodeWithKeyframes → generate index.html → VercelDeployer → HistoryEntry → auto-copy → cleanup) + `select-stills-folder` (natural-sorted image paths).
- `src/components/VideoViewer.tsx` — drop `.mp4/.mov/.m4v` → confirm (live `<video>` preview, pick per-slide stills folder, fps, project name, secure-embed) → `deployVideo` → 4-step progress → complete (Copy URL / Framer Embed / Open).
- Reference pipeline (proven): `scripts/video-deck/{build.sh, derive-timestamps.py, gen-video-viewer.mjs}` + `docs/VIDEO_DECK_VIEWER.md`. Proven deck-agnostic on the 39-slide ILS Quals deck (39/39) and a 22-slide deck (22/22).

**Key invariant (do not break):** the per-slide **stills are the slide-count + boundary source of truth** — pixel frame-diff cannot segment held-build / constant-background decks. Stills are a **build-time input only**; they are never inserted into the video and never shipped. Deployed artifact = `deck.mp4` + `index.html` only.

## Current Swift state
- Swift `main` has **100% parity on the HTML deploy path** (Processing pipeline, Deployment, Deploy View, Projects, History, Settings — per `PARITY.md`). It has **no** video path and **no** GIF path.
- A prior **Swift GIF port** exists on shelved branch `feat/gif-deploy-swift` (`GifDeployer`, `GifFrameSource`, `GifViewerGenerator`, `GifDeployView`, models). GIF is retired → **do NOT merge it**; salvage patterns only (the deploy-seam injection, history wiring, phase-machine view shell, off-main pipeline pattern, and the stills→frame DP-match if present).
- Reusable Swift services already at parity and to be **reused unchanged**: `VercelDeployer`, `FileOperations`, `HistoryEntry` (SwiftData `@Model`), `DeployProgressView`, `AppSettings`, `NavigationTab`/sidebar pattern, `IndexHtmlGenerator` (the bundled-resource generator pattern to mirror).

## Swift work required
1. **Native video pipeline** — Swift equivalents of `probeVideo` / `deriveTimestamps` / `encodeWithKeyframes`. **Resolve the ffmpeg/ffprobe dependency for a distributable app**: the Swift app ships **Developer-ID-signed, hardened-runtime, notarized, auto-updated via Sparkle** — NOT run from a dev shell, so `/opt/homebrew/bin/ffmpeg` is not guaranteed. Decide and justify: **bundle ffmpeg/ffprobe in the app** (sign + notarize the nested binaries, hardened runtime) vs **require on PATH with a guided install** vs **AVFoundation-native** (probe/encode via `AVAsset`/`AVAssetWriter`, keyframe placement via `AVAssetWriter` settings) vs hybrid. AVFoundation removes the binary-dependency problem but must reproduce `-force_key_frames`-at-each-slide + web-safe H.264 yuv420p + faststart; verify it can.
2. **Native stills → video-frame DP-match** — port the Python `derive-timestamps.py` / JS `matchStillsToFrames` (downscale-to-grid sampling + O(N·M) dynamic-programming sequence alignment, monotonic) into Swift. No shelling to python. Output per-slide timestamps + slideCount. Frame sampling for matching can use `AVAssetImageGenerator` (downscaled) or extracted frames.
3. **Swift `VideoViewerGenerator`** — mirror `videoViewerGenerator.ts` exactly, as a **bundled HTML resource** with placeholder tokens (like `IndexHtmlGenerator`), loaded via `Bundle.main`. Byte-parity gate vs the Electron output for the same inputs.
4. **`VideoDeployView`** — phase machine (drop → confirm → deploying → complete → error) mirroring `VideoViewer.tsx`: drop video, pick stills folder, fps, project name (kebab + prefix), secure-embed toggle, live `<video>`/preview, 4-step progress, complete (Copy URL / Framer Embed / Open). Nav wiring; **remove/replace any GIF tab** so the sidebar matches Electron (Deploy HTML, Deploy Video, Projects, History, Settings).
5. **Reuse** `VercelDeployer` / `FileOperations` / `HistoryEntry` / `DeployProgressView` unchanged; persist a video deploy to History.
6. **Confirm all other parity holds** — re-validate `PARITY.md` rows; flip the deck-deploy rows to the video path; ensure shared `settings.json` compatibility between both apps during the transition.
7. **Cutover / sunset checklist** — notarize + DMG + Sparkle appcast release of the Swift app (use the existing `/notarize` pipeline), verify the portal workflow (`/portal-deck` → Airtable `Deck URL` → Framer embed) still works with a Swift-deployed video URL, then deprecate/retire the Electron app (stop building, archive, update docs/CLAUDE.md, update README/parity).

## Constraints & conventions
- Swift 6.2, strict concurrency; `@Sendable` progress closures; off-main heavy work (`nonisolated async`), cancellable.
- Stateless services as `enum` with static methods; `actor` only if stateful. Bundled resources via `Bundle.main` (NOT `Bundle.module`).
- TDD throughout (Swift Testing). Offline-verifiable gates first (DP-match fixture parity vs the TS/Python output; viewer byte-parity vs Electron). Live deploy gate (real video + stills → Vercel) is the final acceptance, runnable with the proven 39-slide ILS Quals asset.
- Build/verify via XcodeBuildMCP / the apple-platform-build-tools builder; visual gate via Peekaboo on the fresh DerivedData build.
- Do NOT regress the HTML deploy path. Do NOT merge the shelved GIF branch.

## Acceptance
- Swift app builds clean (Swift 6), all tests green.
- DP-match produces the same slideCount + boundaries as the proven pipeline for the 39-slide deck.
- Swift `VideoViewerGenerator` output is byte-parity with Electron for identical inputs.
- End-to-end: drop video → pick stills → deploy → reachable Vercel URL that loads the navigable video viewer with N baked slide stops.
- ffmpeg/ffprobe dependency resolved in a way that survives notarization + a clean machine (no dev shell).
- Sunset checklist complete enough to retire Electron this weekend.
