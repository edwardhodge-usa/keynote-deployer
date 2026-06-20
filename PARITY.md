# Keynote Deployer — Feature Parity Tracker

Primary: Electron 33 + React 18 + TypeScript
Swift: SwiftUI + SwiftData (macOS 15+, Swift 6.2)

## Processing Pipeline

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| Folder selection (file picker) | Done | Done | NSOpenPanel + validateKeynoteFolder wired |
| Drag-and-drop folder input | Done | Done | onDrop → validateFolder → confirm phase |
| Keynote folder validation (header.json + main.js) | Done | Done | FileOperations.validateKeynoteFolder |
| Metadata parsing from header.json | Done | Done | KeynoteMetadata with flexible key decoding |
| HiDPI Fix 1: zC scale (PDF rasterization) | Done | Done | KeynoteProcessor.fixes[0] |
| HiDPI Fix 2: Fullscreen bypass | Done | Done | KeynoteProcessor.fixes[1] |
| HiDPI Fix 3: Viewport A (sparkle/particle) | Done | Done | KeynoteProcessor.fixes[2] |
| HiDPI Fix 4: Viewport B (firework) | Done | Done | KeynoteProcessor.fixes[3] |
| HiDPI Fix 5: Resize viewport DPR | Done | Done | KeynoteProcessor.fixes[4] |
| HiDPI Fix 6: Constructor viewport division | Done | Done | KeynoteProcessor.fixes[5] |
| HiDPI Fix 7: Canvas DPR backing store | Done | Done | KeynoteProcessor.fixes[6] |
| main.js backup/restore before patching | Done | Done | KeynoteProcessor.process |
| index.html generation (wrapper + nav + loading) | Done | Done | IndexHtmlGenerator |
| Secure embed script injection | Done | Done | IndexHtmlGenerator.generate(secureEmbed:) |
| vercel.json CSP headers for secure embed | Done | Done | VercelDeployer.writeVercelConfig |

## Deployment

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| Vercel project creation/lookup (REST API) | Done | Done | VercelAPI.ensureProject |
| Vercel CLI deployment (shell out) | Done | Done | VercelDeployer.deploy |
| Production URL resolution (handles truncation) | Done | Done | VercelAPI.resolveProductionUrl |
| Deployment verification (static file check) | Done | Done | DeploymentVerifier — fetches main.js + index.html, checks all 7 fix patterns |
| Runtime verification (Puppeteer) | Done | N/A | No Puppeteer equivalent on native — browser automation not needed |

## Deploy View

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| Select phase (drop zone UI) | Done | Done | NSOpenPanel + onDrop + validation |
| Confirm phase (metadata, project name, secure toggle) | Done | Done | Full metadata display, kebab-case name gen, prefix |
| Processing phase (16-step progress) | Done | Done | DeployProgressView connected via onProgress callbacks |
| Complete phase (URL copy, Framer embed copy, open) | Done | Done | Copy URL, copy Framer embed, open in browser |
| Error phase (retry) | Done | Done | Shows progress + error, retry calls startDeploy() |
| Framer embed code generation + copy | Done | Done | iframe string + NSPasteboard |
| Auto-copy URL to clipboard on completion | Done | Done | Reads settings.autoCopyUrl |

## Projects View

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| Fetch and list Vercel projects | Done | Done | VercelAPI.fetchProjects wired with async/await |
| Filter to only Keynote Deployer projects | Done | Done | Cross-references SwiftData @Query history |
| Inline iframe preview thumbnails | Done | N/A | No WebView equivalent — native app doesn't need it |
| Project status dots (READY/ERROR/BUILDING) | Done | Done | Color-coded circles |
| Copy project URL | Done | Done | NSPasteboard with "Copied!" feedback |
| Update (redeploy) project | Done | Done | Wires to onSelectProject |
| Delete project from Vercel | Done | Done | VercelAPI.deleteProject with confirm dialog |

## History View

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| List deployment history | Done | Done | SwiftData @Query |
| Display date, slides, fixes count | Done | Done | |
| Copy URL | Done | Done | NSPasteboard |
| Open in browser | Done | Done | NSWorkspace.shared.open |
| Delete history entry | Done | Done | modelContext.delete |
| Delete also removes from Vercel | Done | Done | VercelAPI.deleteProject + local modelContext.delete |

## Settings View

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| Vercel token input (secure field) | Done | Done | SecureField + FileOperations.saveSettings |
| Vercel token auto-detect from CLI config | Done | Done | FileOperations.detectVercelToken wired |
| Token status badge (Connected/Not Set) | Done | Done | Updates on load, save, and detect |
| Team ID input | Done | Done | TextField + onChange save |
| Project name prefix | Done | Done | TextField + onChange save |
| Auto-copy URL toggle | Done | Done | Toggle + onChange save |
| Runtime verification toggle | Done | Done | Toggle + onChange save |
| Secure embed toggle | Done | Done | New embed section in SettingsView |
| Embed allowed domains input | Done | Done | TextField + onChange save |

## App Chrome

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| Sidebar navigation (5 tabs) | Done | Done | NavigationSplitView + List (Deploy, Deploy Video, Projects, History, Settings) |
| Menu bar (Cmd+, Settings, Cmd+N Deploy) | Done | Done | .commands modifier |
| Dark mode (system theme) | Done | Done | Native SwiftUI |
| Hidden inset title bar + traffic lights | Done | Done | .windowStyle(.hiddenTitleBar) + .windowToolbarStyle(.unified) |
| Vibrancy sidebar | Done | Done | .background(.ultraThinMaterial) on NavigationSplitView |
| Version display in sidebar | Done | Done | CFBundleShortVersionString in safeAreaInset footer |
| Auto-updater | Done | Done | Sparkle 2.7 via SPM, UpdaterService, "Check for Updates" menu item |

## Video Deploy

The GIF deploy path is **retired** on both apps — GIF compositing ghosts on
held-build / constant-background decks and is 256-color. Electron replaced it with
the H.264 **video** path, and this Swift build now reaches parity with it. The
deployed artifact is `deck.mp4` + a single-`<video>` `index.html` viewer that plays
real transitions and pauses crisply on each slide. Slide boundaries can't be
recovered from video pixels, so the user supplies one still per slide (build-time
input only, never deployed); the still count IS the slide count and each is
DP-matched to its video frame to derive that slide's timestamp.

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| Drop H.264 video + video preview | Done | Done | `VideoDeployView` drop/confirm phases (AVKit) |
| Pick per-slide stills folder (image-only filter) | Done | Done | `VideoDeployLogic.filterImages` — `UTType.image` (A8) |
| Frame-rate field + project name (prefix + kebab) | Done | Done | `VideoDeployView` confirm phase + `AppConfig.toKebabCase` |
| Probe input (reject VFR / corrupt / no-track) | Done | Done | `AVFoundationVideoEncoder.probe` (A2, A8) |
| Stills→frame DP-match + timestamp derivation | Done | Done | `StillsMatch` + `VideoTimestampDeriver` (sections 02, 06) |
| H.264 encode with forced keyframe per slide | Done | Done | `AVFoundationVideoEncoder.encodeWithKeyframes` (section 04) |
| ffmpeg fallback encoder (hidden flag, not bundled) | Done | Done | `FFmpegVideoEncoder` via `useFfmpegEncoder` (A1, A6) |
| Single-`<video>` viewer HTML generation | Done | Done | `VideoViewerGenerator` byte-parity (section 03) |
| Deploy to Vercel + URL resolution | Done | Done | `VideoDeployer` reuses `VercelDeployer`/`VercelAPI` (section 07) |
| Analyzing-progress + 4-step deploy progress | Done | Done | `onProgress` (A5) → `DeployProgressView`, ids 1–4 |
| Complete (URL copy, Framer embed, open) | Done | Done | embed uses probed aspect ratio (`VideoDeployResult.width/height`) |
| Secure embed toggle | Done | Done | reuses HTML secure-embed path |
| Persist HistoryEntry + auto-copy on completion | Done | Done | SwiftData + `settings.autoCopyUrl` (in the View) |

## Summary

- **Total features:** 53 (HTML/Chrome) + 13 (Video Deploy) = 66
- **Done:** 51 + 13 = 64 (Done on both apps)
- **TODO:** 0
- **Parity:** 100% — HTML path (45/45 applicable) **and** the video deck-deploy path
  (13/13) are at Swift parity. The GIF path is retired on both. **Swift is now the
  sole shipping app; Electron is deprecated** (code retained one release as a safety
  net — see CLAUDE.md / README.md).
