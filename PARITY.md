# Keynote Deployer — Feature Parity Tracker

Primary: Electron 33 + React 18 + TypeScript
Swift: SwiftUI + SwiftData (macOS 15+, Swift 6.2)

## Processing Pipeline

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| Folder selection (file picker) | Done | Stub | NSOpenPanel wired, validation TODO |
| Drag-and-drop folder input | Done | Stub | onDrop handler wired, validation TODO |
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
| Deployment verification (static file check) | Done | TODO | verifier.ts not yet ported |
| Runtime verification (Puppeteer) | Done | TODO | runtimeVerifier.ts — may skip for Swift |

## Deploy View

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| Select phase (drop zone UI) | Done | Stub | View exists, validation not wired |
| Confirm phase (metadata, project name, secure toggle) | Done | Stub | View exists, pipeline not wired |
| Processing phase (16-step progress) | Done | Stub | DeployProgressView exists, not connected |
| Complete phase (URL copy, Framer embed copy, open) | Done | Stub | View exists, no pipeline result |
| Error phase (retry) | Done | Stub | View exists, no pipeline connection |
| Framer embed code generation + copy | Done | TODO | Not in Swift complete phase yet |
| Auto-copy URL to clipboard on completion | Done | TODO | Need to wire to settings |

## Projects View

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| Fetch and list Vercel projects | Done | Stub | View exists, API call TODO |
| Filter to only Keynote Deployer projects | Done | TODO | Cross-reference with history |
| Inline iframe preview thumbnails | Done | TODO | No WebView equivalent planned |
| Project status dots (READY/ERROR/BUILDING) | Done | Done | Color-coded circles |
| Copy project URL | Done | TODO | |
| Update (redeploy) project | Done | Stub | Wires to onSelectProject |
| Delete project from Vercel | Done | Stub | Button exists, API call TODO |

## History View

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| List deployment history | Done | Done | SwiftData @Query |
| Display date, slides, fixes count | Done | Done | |
| Copy URL | Done | Done | NSPasteboard |
| Open in browser | Done | Done | NSWorkspace.shared.open |
| Delete history entry | Done | Done | modelContext.delete |
| Delete also removes from Vercel | Done | TODO | Need VercelAPI integration |

## Settings View

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| Vercel token input (secure field) | Done | Stub | SecureField exists, save TODO |
| Vercel token auto-detect from CLI config | Done | Stub | FileOperations ready, button not wired |
| Token status badge (Connected/Not Set) | Done | Stub | UI exists, logic TODO |
| Team ID input | Done | Stub | TextField exists, save TODO |
| Project name prefix | Done | Stub | TextField exists, save TODO |
| Auto-copy URL toggle | Done | Stub | Toggle exists, save TODO |
| Runtime verification toggle | Done | Stub | Toggle exists, save TODO |
| Secure embed toggle | Done | TODO | Not in Settings yet (only in Deploy) |
| Embed allowed domains input | Done | TODO | Not in Settings yet |

## App Chrome

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| Sidebar navigation (4 tabs) | Done | Done | NavigationSplitView + List |
| Menu bar (Cmd+, Settings, Cmd+N Deploy) | Done | Done | .commands modifier |
| Dark mode (system theme) | Done | Done | Native SwiftUI |
| Hidden inset title bar + traffic lights | Done | TODO | Need .windowStyle config |
| Vibrancy sidebar | Done | TODO | Need Material/vibrancy |
| Version display in sidebar | Done | TODO | |
| Auto-updater | Done | TODO | Sparkle integration future |

## Summary

- **Total features:** 47
- **Done:** 22 (services + models complete)
- **Stub:** 17 (views exist but not wired to services)
- **TODO:** 8 (not started)
- **Parity:** 47% done, 83% scaffolded
