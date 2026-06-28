# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

<!--
Project-specific CLAUDE.md. See ~/CLAUDE.md for global preferences.
Update this file after every correction.
-->

## Quick Context
**What**: One-click GUI app that processes Keynote HTML exports (applies 7 HiDPI rendering fixes) and deploys them to Vercel. Replaces a 12-step manual process with drag-and-drop.
**Stack**: Swift 6.2 + SwiftUI + SwiftData macOS 15+ (sole app). *(Electron/React/Vite removed 2026-06-20 — in git history if needed.)*
**Status**: Swift is the **sole shipping app** — Developer ID signed, notarized, Sparkle auto-updater. HTML path at parity (45/45) **plus** the H.264 **video deck-deploy** path (`Deploy Video` tab, sections 01–09 of the swift-video-parity spec). The GIF path is retired on both apps. Electron is deprecated; full removal is a scheduled follow-up.

## Lessons Learned
<!-- Add project-specific mistakes/solutions here -->
<!-- Format: **[Date]** - Issue -> Solution -->
**2026-06-28** - **Video deck viewer played STRAIGHT THROUGH on iPhone (Safari AND Chrome — both iOS WebKit); root cause: iOS WebKit returns `video.currentTime = 0` during inline playback inside a CROSS-ORIGIN IFRAME (the Framer client-page embed).** The boundary watcher polled `vid.currentTime` via `requestAnimationFrame` and paused at the next slide's timestamp — but on iOS-in-cross-origin-iframe that clock reads 0 forever during playback, so it never reached the boundary and free-played the whole deck. Proven ONLY by live on-device instrumentation (an overlay of counters): `raf` ticks fine (~375/playthrough — rAF is NOT throttled, that was the wrong first theory), `t:0.00` the entire time it visibly plays, `tu` (timeupdate) fires ~once, `iv` (setInterval) ticks fine. So **none of `currentTime`, rAF-reading-currentTime, `timeupdate`, nor `requestVideoFrameCallback.mediaTime` is reliable on iOS here** (rVFC mediaTime advanced 0.25s while 1.95s played). The ONE clock that works during iOS inline playback = a **`setInterval` wall-clock**. Fix in `video-viewer-template.html` `go()`: stop off `budgetMs = (target-startPos)*1000 + 350` wall-clock (primary) + rVFC mediaTime as a desktop early-stop; never read currentTime during play; seek to the exact rest frame after stopping so the paused frame is always correct. TWO more iOS quirks, same root family: (1) **iOS won't PAINT a seeked frame on a PAUSED video until it plays** -> Prev/dot-jumps changed state but left the old frame onscreen, and initial load was black -> fix = micro `play()->pause()` (~40ms; restTime sits mid-hold so no visible motion) in `paintFrame()`, AND a `<video poster>` for the gestureless initial load (micro-play is blocked there). (2) **iOS never fires `seeked` for a paused-video seek** -> the busy spinner (gated on `seeked`) spun forever -> drop the seeking/seeked listeners, toggle busy explicitly from next()/finish()/settleOn(). Poster pipeline: `VideoPoster.extract` (AVAssetImageGenerator->JPEG via ImageIO, best-effort — a throw degrades to no-poster, never fails the deploy), written into the deploy folder (the vercel CLI ships the whole folder), `posterFilename` param fills a `{{POSTER_ATTR}}` token (nil -> "" = byte-identical -> existing goldens unchanged). Also added edge tap-zones (tap far-left/right of the slide = prev/next; auto-disabled at ends/during transition). **Validated the only way that works for this bug class: a LIVE cross-origin-iframe test on a real iPhone** — throwaway Vercel deploys (viewer on origin A + a wrapper iframing it on origin B; a top-level link does NOT reproduce the bug), iterated BEFORE/AFTER/instrumented until green, then ran the REAL 39-slide deck through the REAL Swift services headlessly and deployed THAT for a final on-device pass. Desktop can't reproduce ANY of it (currentTime works there). **macOS hosted unit tests do NOT inherit shell env** -> to feed a harness test real paths, inject via a modified `.xctestrun` (`EnvironmentVariables`/`TestingEnvironmentVariables`), not `FOO=bar xcodebuild`. 68/68 tests; merged `b6ef216`. **The template is BUNDLED in the app** (`Bundle.main` -> `VideoViewerGenerator`), so the fix reaches decks only after the APP is rebuilt — a deck re-deployed from the still-installed /Applications app would ship the OLD viewer.
**2026-06-20** - **Video path live-gate caught 3 things stub tests never could** (all fixed, deployed + Edward-approved on the real 39-slide ILS Quals deck): (1) **SwiftUI `AVKit.VideoPlayer` SIGABRTs on macOS 26.6** in `_AVKit_SwiftUI` generic-metadata instantiation (`getSuperclassMetadata` fatalError) the instant the confirm phase renders → use an AppKit `AVPlayerView` via `NSViewRepresentable` instead (sidesteps `_AVKit_SwiftUI`). (2) **fps divergence ship-blocker**: the View probed fps but discarded it (field stuck at 30) while the encoder re-derived its own fps from `track.nominalFrameRate` → forced keyframes on the wrong frames for any non-30fps export. Fix = one authoritative fps end-to-end (`encodeWithKeyframes(fps:)`, View defaults the field to the probed rate) + high-precision 600_000 CMTime timescale (Gemini catch: integer timescale drifts on 29.97/23.976). (3) **rest frame 1-2 frames late**: the matched still lands at the TRAILING edge of each slide's hold, so pausing on `TS[i]` shows the transition-out start → viewer seeks `TS[i] - 0.08s` (REST_BIAS) back into the stable hold. Each is invisible to green stub tests; only the live deploy + human eyeball surfaced them.
**2026-06-20** - Swift reached **video deck-deploy parity** (swift-video-parity spec, 9 sections, TDD via /deep-implement; AVFoundation-default encoder + ffmpeg hidden-flag fallback, stills→frame DP-match for slide timestamps, single-`<video>` viewer byte-parity) and became the **sole shipping app**; Electron deprecated (code kept one release as a safety net). GIF path retired on both — never merge `feat/gif-deploy-swift`. Encoder default = AVFoundation; ffmpeg NOT bundled (hidden `useFfmpegEncoder` flag only). Framer embed for video uses the probed aspect ratio (`aspect-ratio:w/h`, mirroring GifViewer.tsx) — `VideoDeployResult` carries `width`/`height` so the View needn't re-probe.
**General** - Keynote exports images as low-res 266x150 thumbnails -> HiDPI fixes only help text/vectors; workaround is save images as PDF before inserting into Keynote
**2026-04-21** - Vercel CLI token (com.vercel.cli/auth.json) expires silently → Auto-Detect re-reads the same expired token, 403 on team endpoints even if /v2/user returns "Connected". Fix: generate fresh token at vercel.com and paste manually. Also: app writes old in-memory token back to settings.json if you edit while app is running — quit the app first before manually editing settings.json.
**General** - All 7 HiDPI fixes are idempotent -> Re-processing an already-patched file is safe, no need to check
**2026-03-08** - `electron-builder` codesign fails with "resource fork, Finder information, or similar detritus not allowed" when building inside iCloud Drive -> Build with output dir outside iCloud: `npx electron-builder --config.directories.output=/tmp/keynote-deployer-release`
**2026-03-08** - Vercel truncates long project subdomains (e.g. 36-char name → 30-char) → Never construct URL as `${name}.vercel.app`; read actual domain from `targets.production.alias` via Vercel API
**2026-03-08** - Projects view showed all team projects (including imaginelab-portal) → Filter by cross-referencing with local `history.json` deployed project names
**2026-03-21** - iCloud Keynote embeds: strip `#fragment` from share URL, add `?embed=true` → Apple returns `frame-ancestors *` and loads lightweight embed viewer. Without `?embed=true`, `frame-ancestors *.icloud.com:443` blocks all embedding
**2026-03-21** - GIF slide detection: simple per-frame diff threshold fails (misses dissolves, creates false 1-frame "transitions") → Use "quiet runs" algorithm: find 8+ consecutive frames with diff < 0.3, those are the slides. Everything between is transition
**2026-03-21** - `npx electron-builder` without `npx vite build` first → "dist-electron/main.js does not exist". Must run Vite build before electron-builder since `rm -rf dist dist-electron` cleans both
**2026-03-21** - FileManager.copyItem throws if destination exists → removeItem before copyItem when restoring from backup
**2026-03-21** - Process pipe deadlock: waitUntilExit before readDataToEndOfFile hangs if pipe buffer fills → drain pipes on background threads first, then waitUntilExit
**2026-03-24** - `(file as any).path` returns empty string in Electron 33 renderer → use `webUtils.getPathForFile(file)` from preload bridge. Import `webUtils` from `electron` in preload.ts
**2026-03-25** - `decompressFrames(gif, true)` decodes ALL frames into RGBA at once (~2.5GB for 963 frames) → crashes iPhone Safari. Use per-frame `decompressFrame()` with immediate patch release (peak ~5MB)
**2026-03-25** - `getImageData(0, 0, fullWidth, fullHeight)` per frame in a tight loop creates ~2.6MB temporary allocations that overwhelm mobile GC → use scaled-down 32×18 sample canvas for diff detection (~2KB per frame)
**2026-03-25** - `Sparkle.xcconfig` only contains public values (feed URL + EdDSA public key) → safe to commit. Gitignoring it breaks Xcode Cloud archives
**2026-03-31** - GIF quiet-run MIN_QUIET_RUN=8 catches transition dark pauses as false slides → adaptive median filtering (discard runs < 0.5x median) eliminates them. Canonical algorithm in `src/utils/slideDetection.ts`

## Commands

> **Electron removed 2026-06-20.** This is now a Swift-only repo (`swift-app/`). The
> Electron/React/Vite source and its build commands were deleted at the video-deploy
> sunset; recover from git history (`git log -- src electron`) if ever needed.

### Swift
```bash
cd swift-app && xcodegen generate && xcodebuild build -scheme KeynoteDeployer -destination "platform=macOS" -quiet

# Release archive (universal binary, Developer ID signed):
cd swift-app && xcodebuild archive -scheme KeynoteDeployer -archivePath /tmp/KeynoteDeployer.xcarchive -destination "generic/platform=macOS"

# Notarize (requires keychain profile "notarytool" configured):
xcrun notarytool submit /path/to/KeynoteDeployer.dmg --keychain-profile "notarytool" --wait
xcrun stapler staple /path/to/KeynoteDeployer.dmg
```

## Architecture

### Deploy Pipeline (16 steps)
The core workflow runs as a single `process-and-deploy` IPC call that pushes progress events:
1. **Steps 1-11**: `keynoteProcessor.ts` — backup main.js, apply 7 HiDPI regex fixes, generate index.html wrapper
2. **Steps 12-13**: `vercelDeployer.ts` — REST API project creation/lookup, CLI deployment (`vercel --prod`)
3. **Step 14**: `verifier.ts` — fetch deployed main.js + index.html, verify all 7 fix patterns present
4. **Step 15**: `runtimeVerifier.ts` — Puppeteer browser check (optional, controlled by settings)
5. **Step 16**: Complete — save to history, auto-copy URL if enabled

### GIF Deploy Pipeline (4 steps)
**Why it exists:** Keynote's HTML export rasters images as low-res 266×150 thumbnails, and the 7 HiDPI fixes only repair text/vectors — NOT raster images. So image-heavy decks look bad through the HTML deploy path. The GIF path is the fallback: export the deck as an animated GIF (full rendered slides) and deploy an interactive viewer. Caveat: GIF is 256-color, so it beats the thumbnail problem but isn't lossless — photos/gradients band. "Better than broken," not full fidelity.

Alternative deployment path for Keynote-exported GIFs instead of HTML exports:
1. **Step 1**: `gifViewerGenerator.ts` — generates self-contained HTML viewer page, copies GIF to temp deploy folder
2. **Steps 2-3**: Reuses `vercelDeployer.ts` — same REST API project creation + CLI deployment
3. **Step 4**: Complete — save to history, auto-copy URL
The deployed viewer auto-loads the GIF, parses slides client-side, and provides forward/back/dots/keyboard navigation.

**GIF slide boundary sources (Electron only):** Slide boundaries are determined at BUILD TIME and baked into the deployed viewer HTML as a `DetectedSlide[]` array. Three sources in priority order:
- **Stills** (most accurate): JPEG/PNG exports from Keynote matched to GIF frames via dynamic-programming alignment (`matchStillsToFrames`). Verified deck-agnostic on two real decks (39-slide ILS Quals: 39/39 matched, worst diff 8.87/20; 22-slide DUB FDY Proposal: 22/22 matched, worst diff 15.60/20).
- **Auto**: quiet-run algorithm on per-frame pixel diffs — a seed/fallback only, never authoritative.
- **Manual**: user-specified grid — override when Auto and Stills are unavailable or wrong.
The deployed viewer does NOT detect slides itself; it receives the baked boundary list and navigates accordingly.

### IPC Architecture (Electron)
All IPC uses `ipcMain.handle`/`ipcRenderer.invoke` with a typed `IpcResponse<T>` wrapper (`{ success, data?, error? }`).

**Invoke channels (renderer → main):** `select-folder`, `validate-keynote-folder`, `process-and-deploy`, `deploy-gif`, `load-settings`, `save-settings`, `detect-vercel-token`, `load-history`, `remove-history-entry`, `fetch-vercel-projects`, `delete-vercel-project`, `get-app-version`, `open-url`, `copy-to-clipboard`, `get-system-theme`

**Push channels (main → renderer):** `processing-progress` (step-by-step pipeline updates), `theme-changed` (system theme), `navigate` (menu bar Cmd+N / Cmd+,)

The preload bridge (`electron/preload.ts`) and type declarations (`src/electron.d.ts`) must stay in sync — both define the `ElectronAPI` interface.

### Vite Configuration
- Path aliases: `@` → `src/`, `@components` → `src/components/`, `@types` → `src/types/`
- Externalized modules: `puppeteer`, `bufferutil`, `utf-8-validate` (native, can't bundle)
- Dev server port: 5173, dev mode detected via `process.env.VITE_DEV_SERVER_URL`

### Deploy View Phases (renderer)
`Deploy.tsx` manages 4 UI phases: **Select** (drop zone + file picker) → **Confirm** (metadata preview, project name, secure embed toggle) → **Processing** (16-step progress via push events) → **Complete** (URL copy, Framer embed copy, open in browser). Error state shows progress + retry.

### Shared Data
- Settings: `~/Library/Application Support/keynote-deployer/settings.json` (shared by both apps)
- History: Electron uses `history.json` in same dir, Swift uses SwiftData
- `schema/` directory contains JSON schemas for all shared types (AppSettings, HistoryEntry, KeynoteMetadata, etc.)
- Vercel token auto-detected from `~/.local/share/com.vercel.cli/auth.json` or `~/Library/Application Support/com.vercel.cli/auth.json`
- Default Vercel team: `team_E1wAzl9zyAPrlGzyjmcXNuxd`

### The 7 HiDPI Fixes
Applied via regex to Keynote's exported `main.js`. All fixes are idempotent — re-processing is safe.
1. zC scale — PDF rasterization at 3x instead of 1x
2. Fullscreen bypass — enable rendering without fullscreen mode
3. Viewport A — DPR scaling for sparkle/particle effects
4. Viewport B — DPR scaling for firework effects
5. Resize viewport — DPR scaling in resize handler
6. Constructor viewport — divide viewportWidth/Height by DPR
7. Canvas DPR — scale canvas backing store + add CSS size

## Parallel Build Architecture

> **⚠️ Electron is deprecated — stop building features on it.** The Swift app is the
> sole shipping app. The dual-track docs below are retained for reference and to keep
> the Electron code maintainable for the one-release safety-net window; full Electron
> removal is a scheduled follow-up. Build all new work in Swift.

### Dual-Track Strategy
| Primary (Electron) | Swift Equivalent |
|---|---|
| React component (`.tsx`) | SwiftUI View (`.swift`) |
| IPC handler (`ipcMain.handle`) | Service method (async func) |
| `fs.readFile` / `fs.writeFile` | `FileManager` / `String(contentsOfFile:)` |
| Vercel CLI (`execFile`) | `Process()` shell-out |
| Vercel REST API (`fetch`) | `URLSession.shared.data(for:)` |
| `~/Library/Application Support/keynote-deployer/` | Same path (shared settings) |
| Electron `dialog.showOpenDialog` | `NSOpenPanel` |
| `clipboard.writeText` | `NSPasteboard.general.setString` |
| Tailwind CSS classes | SwiftUI native modifiers + system colors |
| `electron-updater` | Sparkle 2.7 (SPM, EdDSA signing) |

### Translation Rules
- **Views:** One SwiftUI view per React component. Use `NavigationSplitView` for sidebar layout.
- **Models:** Codable structs for API types, SwiftData `@Model` only for persistent data (HistoryEntry).
- **Services:** Use `actor` for stateful services (KeynoteProcessor), `enum` with static methods for stateless (FileOperations, IndexHtmlGenerator).
- **Concurrency:** All service calls are `async`. Use `@Sendable` closures for progress callbacks.
- **HIG:** Use native SwiftUI controls (Toggle, SecureField, ContentUnavailableView). SF Symbols instead of custom SVGs.

### Sync Rules
- Both apps share `~/Library/Application Support/keynote-deployer/settings.json` for settings.
- History is separate: Electron uses `history.json`, Swift uses SwiftData.
- Both apps use the same Vercel team, token, and project naming convention.
- Both generate identical `index.html` output (IndexHtmlGenerator mirrors keynoteProcessor.ts exactly).

### Swift Signing & Distribution
- **Debug:** `CODE_SIGN_STYLE: Automatic`, `Apple Development` identity
- **Release:** `CODE_SIGN_STYLE: Manual`, `Developer ID Application: Imaginelab Studios (8RHA62T6FQ)`, hardened runtime enabled
- **Entitlements:** `com.apple.security.network.client` (required for Vercel API/CLI)
- **Sparkle config:** EdDSA key + feed URL via gitignored `Sparkle.xcconfig` (referenced in `project.yml` configFiles)
- **Notarization:** Keychain profile `notarytool` configured, must re-sign Sparkle nested binaries with `--options runtime --timestamp`. **Re-sign each EXPLICITLY, inside-out, errors VISIBLE** (XPCServices/{Downloader,Installer}.xpc → Updater.app/Contents/MacOS/Updater + Updater.app → Autoupdate → Versions/B/Sparkle → .framework → app) — a `find -perm +111 … 2>/dev/null` loop silently misses `Versions/B/Autoupdate` → notarize "Invalid: not signed with valid Developer ID / no secure timestamp". Verify `codesign -dvv …/Autoupdate` shows `TeamIdentifier=8RHA62T6FQ` + a Timestamp before zipping. Never `2>/dev/null` a codesign here. (2026-06-20)
- **App icon:** no asset catalog — `AppIcon.icns` (sips→iconutil from the 1024 source) lives in `Sources/Resources/`, set via `info.properties: CFBundleIconFile: AppIcon`.

### Known Issues the Swift Build Must Respect
- Filter projects list by cross-referencing with local deployment history
- All 7 HiDPI fixes are idempotent → safe to re-process
- Build output must be outside iCloud Drive (use `/tmp/`)

### Decision Protocol
STOP and report blockers, never silently work around them.

### Advancement Protocol
1. Check PARITY.md for next batch of TODO/Stub features
2. Read the Electron source for those features
3. Implement SwiftUI equivalents
4. Build-verify with xcodebuild
5. Update PARITY.md
6. Commit with `/ship`

### Swift Code Organization
- `swift-app/Sources/App/` — entry point, `@main` app struct with menu commands
- `swift-app/Sources/Models/` — Codable structs for API types, SwiftData `@Model` for HistoryEntry, NavigationTab enum
- `swift-app/Sources/Services/` — `actor` for stateful (KeynoteProcessor), `enum` with static methods for stateless (FileOperations, IndexHtmlGenerator)
- `swift-app/Sources/Views/` — one SwiftUI view per React component, `NavigationSplitView` sidebar layout
- `swift-app/Sources/Config/` — AppConfig constants
- Menu navigation uses `NotificationCenter` with `.navigateToTab` notification name (no IPC equivalent needed)

**Video deck-deploy services** (`swift-app/Sources/Services/`, swift-video-parity spec sections 01–09):
- `VideoEncoding.swift` — `VideoEncoder` protocol (probe / sampleGrids / encodeWithKeyframes) + `JSNumber`/keyframe helpers
- `AVFoundationVideoEncoder` — **default** encoder (Apple-native, no external deps)
- `FFmpegVideoEncoder` — **fallback** only, gated by the hidden `useFfmpegEncoder` UserDefaults flag; **NOT bundled** in the shipping binary
- `GridSampler` + `StillsMatch` — 32×18 RGB grid sampling + DP match of stills→video frames
- `VideoTimestampDeriver` — derives per-slide timestamps from the matched frames
- `VideoViewerGenerator` — byte-parity single-`<video>` `index.html` from `Sources/Resources/video-viewer-template.html`
- `VideoDeployer` (+ `VideoDeployerSeams`, `VideoDeployResult`) — orchestrator: probe→derive→encode→generate→deploy (reuses `VercelDeployer`/`VercelAPI`); seams injected for offline tests
- View: `swift-app/Sources/Views/VideoDeployView.swift` (`Deploy Video` tab, 5-phase machine; `VideoDeployLogic` holds the testable pure helpers)
- **GIF path is retired** — do NOT merge `feat/gif-deploy-swift` or add a GIF UI to Swift.

## Update Protocol
When Claude makes a mistake: "Update CLAUDE.md so you don't make that mistake again."
