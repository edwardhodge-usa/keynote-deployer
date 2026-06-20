# Keynote Deployer

One-click GUI app that processes Keynote HTML exports and deploys them to Vercel. Replaces a 12-step manual process with a single drag-and-drop workflow.

## What It Does

1. **Processes** Keynote HTML exports by applying 7 HiDPI rendering fixes to `main.js`
2. **Generates** a custom `index.html` with loading overlay, navigation controls, and slide counter
3. **Deploys** the processed presentation to Vercel with one click
4. **Manages** deployment history with quick-copy URLs

## Tech Stack

- **Swift 6.2 + SwiftUI + SwiftData** (macOS 15+) — the sole app, in `swift-app/`.
- Developer-ID signed, notarized, Sparkle auto-update.
- Vercel REST API (project creation) + CLI (deployment).

> The original Electron 33 + React build was removed 2026-06-20 (Swift reached full
> parity incl. the video deck-deploy path). It remains in git history if needed.

## Getting Started

```bash
cd swift-app && xcodegen generate && xcodebuild build -scheme KeynoteDeployer -destination "platform=macOS"
```

## Configuration

On first launch, go to **Settings** and enter your:
- **Vercel Token** — auto-detected from CLI config if available
- **Team ID** — defaults to `team_E1wAzl9zyAPrlGzyjmcXNuxd`

Settings are stored in `~/Library/Application Support/keynote-deployer/`.

## Usage

1. Drag a Keynote HTML export folder onto the app (or click Browse)
2. Confirm/edit the project name
3. Click Deploy — the app applies fixes, generates index.html, and deploys to Vercel
4. Copy the deployment URL from the completion screen or History tab

## The 7 HiDPI Fixes

| # | Fix | Purpose |
|---|-----|---------|
| 1 | zC scale | PDF rasterization at 3x instead of 1x |
| 2 | Fullscreen bypass | Enable rendering without fullscreen mode |
| 3 | Viewport A | DPR scaling for sparkle/particle effects |
| 4 | Viewport B | DPR scaling for firework effects |
| 5 | Resize viewport | DPR scaling in resize handler |
| 6 | Constructor viewport | Divide viewportWidth/Height by DPR |
| 7 | Canvas DPR | Scale canvas backing store + add CSS size |

All fixes are idempotent — re-processing an already-patched file is safe.

## Project Structure

```
├── electron/
│   ├── main.ts              # BrowserWindow + IPC handlers
│   ├── preload.ts           # Context bridge API
│   ├── keynoteProcessor.ts  # 7 HiDPI fixes + index.html generation
│   ├── vercelDeployer.ts    # Vercel REST API + CLI deployment
│   └── fileOperations.ts    # Settings, history, validation
├── src/
│   ├── components/
│   │   ├── Deploy.tsx       # 4-phase workflow UI
│   │   ├── DeployProgress.tsx # 14-step progress indicator
│   │   ├── History.tsx      # Past deployments
│   │   ├── Settings.tsx     # Configuration
│   │   └── Sidebar.tsx      # Navigation
│   ├── styles/globals.css   # Tailwind + macOS components
│   └── types/index.ts       # TypeScript interfaces
└── package.json
```

## Known Limitation

Keynote exports embedded images at low resolution (266x150 thumbnails). The 7 fixes improve text/vector rendering but can't fix image quality. Workaround: save images as PDF before inserting into Keynote.

## Video Deck Deploy

For image-heavy decks the HTML path can't fix (thumbnailed rasters), export the deck
as an **H.264 video** plus one **still image per slide** and deploy an interactive
single-`<video>` viewer. The still count is the slide count; each still is DP-matched
to its video frame to derive that slide's timestamp. Stills are a build-time input —
never deployed. Deployed artifact: `deck.mp4` + `index.html`.

> Use **H.264, never HEVC** — Chrome/Firefox don't decode HEVC.

### Developing the ffmpeg fallback (A9)

The shipping encode path is **AVFoundation-native** and needs nothing extra. An
optional `ffmpeg` fallback exists but is **not bundled** in the shipping binary. To
develop/test it:

```bash
brew install ffmpeg                                   # ffmpeg + ffprobe on PATH
defaults write <bundleid> useFfmpegEncoder -bool YES  # hidden flag (default: AVFoundation)
```

### Video deploy quality gate (A7 — human sign-off)

Run on the real 39-slide ILS Quals deck, side-by-side against the ffmpeg-baseline deploy:

- (a) No transition blockiness / compression artifacts on the deck transitions.
- (b) Slide text is crisp and readable.
- (c) Colors match the source Keynote.
- (d) Paused keyframes are clean — no shimmer / ghosting from the prior frame.

If AVFoundation passes (a)–(d), it ships. If it fails, switch to the ffmpeg fallback
(then ffmpeg must be bundled + notarized as a nested binary — out of scope for this release).

## Status: Swift is the shipping app — Electron is deprecated

The **Swift/SwiftUI app is the sole shipping app**. The Electron app is **deprecated**:
do not build new features on it. Its code is retained for one release as a safety net;
full removal is a scheduled follow-up.
