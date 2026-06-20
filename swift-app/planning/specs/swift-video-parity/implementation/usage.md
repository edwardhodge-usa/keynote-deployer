# Video Deck Deploy — Usage Guide

The Swift Keynote Deployer now has a **Deploy Video** tab that turns an H.264 deck
export + per-slide stills into a hosted, interactive single-`<video>` slide viewer on
Vercel. This is the parity feature delivered by the `swift-video-parity` spec (sections
01–09).

## Quick Start (in the app)

1. Open Keynote Deployer → **Deploy Video** tab (2nd sidebar item).
2. **Drop** an H.264 `.mp4` / `.mov` / `.m4v` (or "Choose Video…"). The fps field
   auto-fills from the probed rate.
3. **Pick Stills Folder** — one image per slide (PNG/JPEG/HEIC/TIFF). Non-images
   (`.DS_Store`, etc.) are ignored; the count is the slide count.
4. Confirm the project name (prefix + kebab of the filename), frame rate, and Secure
   Embed toggle → **Deploy**.
5. Watch the 4 steps (Analyze → Encode → Generate → Deploy). On completion: **Copy URL**,
   **Copy Framer Embed** (responsive, probed aspect ratio), **Open in Browser**,
   **Deploy Another**. The deploy is saved to History; the URL auto-copies if that
   setting is on.

> Stills are a **build-time input only** — never deployed. The deployed artifact is
> `deck.mp4` + a self-contained `index.html`.

## How it works (pipeline)

`probe → derive timestamps → encode → generate viewer HTML → deploy to Vercel`

- **Probe / VFR reject** — `AVFoundationVideoEncoder.probe` (rejects VFR / corrupt / no-track).
- **Slide timestamps** — `GridSampler` + `StillsMatch` DP-match each still to its video
  frame; `VideoTimestampDeriver` converts matched frame indices → per-slide timestamps at
  the authoritative `fps`.
- **Encode** — `AVFoundationVideoEncoder.encodeWithKeyframes(…, fps:)` re-encodes to H.264
  yuv420p with a forced keyframe per slide (output stamped at `fps`; keyframes land on the
  matched frames). ffmpeg fallback (`FFmpegVideoEncoder`) is gated by the hidden
  `useFfmpegEncoder` UserDefaults flag and is **not bundled**.
- **Viewer** — `VideoViewerGenerator` fills `video-viewer-template.html` (byte-parity with
  Electron); single `<video>`, rest = paused keyframe, Next plays the real transition.
- **Deploy** — `VideoDeployer` + `VideoDeployerSeams.live` reuse `VercelAPI` /
  `VercelDeployer`; emits 4 progress steps; returns `VideoDeployResult`.

## Developer: ffmpeg fallback

```bash
brew install ffmpeg                                   # ffmpeg + ffprobe on PATH
defaults write <bundleid> useFfmpegEncoder -bool YES  # default is AVFoundation
```
Keep the fps field at the export rate when using ffmpeg (it forces keyframes at the
second-valued timestamps).

## Test

```bash
cd swift-app && xcodegen generate && \
  xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -quiet; echo $?
```
65 tests, all offline (seam-injected). Settle the verdict on the exit code.

## Key files

| File | Role |
|------|------|
| `Sources/Services/VideoEncoding.swift` | `VideoEncoder` protocol + JSNumber/keyframe helpers |
| `Sources/Services/AVFoundationVideoEncoder.swift` | default encoder |
| `Sources/Services/FFmpegVideoEncoder.swift` | fallback (hidden flag, not bundled) |
| `Sources/Services/GridSampler.swift`, `StillsMatch.swift` | grid sampling + DP match |
| `Sources/Services/VideoTimestampDeriver.swift` | per-slide timestamps |
| `Sources/Services/VideoViewerGenerator.swift` | viewer HTML (+ `Resources/video-viewer-template.html`) |
| `Sources/Services/VideoDeployer.swift` | orchestrator + seams + result |
| `Sources/Views/VideoDeployView.swift` | the Deploy Video tab (+ `VideoDeployLogic`) |
| `Sources/Models/{VideoDeployRequest,VideoAnalysis}.swift` | models |

## Not yet done (handed to Edward — need sign-in / human gate)

- Live A7 quality gate: deploy the real 39-slide ILS Quals deck and human side-by-side vs
  the ffmpeg baseline.
- `/notarize` → DMG + Sparkle appcast.
- `/portal-deck` → confirm render on the published Framer page.
