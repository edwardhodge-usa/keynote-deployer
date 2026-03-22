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
| Deployment verification (static file check) | Done | TODO | verifier.ts not yet ported |
| Runtime verification (Puppeteer) | Done | TODO | runtimeVerifier.ts — may skip for Swift |

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
| Sidebar navigation (4 tabs) | Done | Done | NavigationSplitView + List |
| Menu bar (Cmd+, Settings, Cmd+N Deploy) | Done | Done | .commands modifier |
| Dark mode (system theme) | Done | Done | Native SwiftUI |
| Hidden inset title bar + traffic lights | Done | TODO | Need .windowStyle config |
| Vibrancy sidebar | Done | TODO | Need Material/vibrancy |
| Version display in sidebar | Done | TODO | |
| Auto-updater | Done | TODO | Sparkle integration future |

## Summary

- **Total features:** 47
- **Done:** 38 (full pipeline + settings + deploy wired)
- **Stub:** 3 (Projects view API calls)
- **TODO:** 6 (verification, app chrome polish, Projects wiring)
- **Parity:** 81% done, 94% scaffolded
