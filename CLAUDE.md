# Keynote Deployer

<!--
Project-specific CLAUDE.md. See ~/CLAUDE.md for global preferences.
Update this file after every correction.
-->

## Quick Context
**What**: One-click GUI app that processes Keynote HTML exports (applies 7 HiDPI rendering fixes) and deploys them to Vercel. Replaces a 12-step manual process with drag-and-drop.
**Stack**: Electron 33 + React 18 + TypeScript 5.7 + Vite 6 + Tailwind 3 + Vercel REST API + CLI
**Status**: Active -- core workflow complete, deployment and processing functional

## Lessons Learned
<!-- Add project-specific mistakes/solutions here -->
<!-- Format: **[Date]** - Issue -> Solution -->
**General** - Keynote exports images as low-res 266x150 thumbnails -> HiDPI fixes only help text/vectors; workaround is save images as PDF before inserting into Keynote
**General** - All 7 HiDPI fixes are idempotent -> Re-processing an already-patched file is safe, no need to check
**2026-03-08** - `electron-builder` codesign fails with "resource fork, Finder information, or similar detritus not allowed" when building inside iCloud Drive -> Build with output dir outside iCloud: `npx electron-builder --config.directories.output=/tmp/keynote-deployer-release`
**2026-03-08** - Vercel truncates long project subdomains (e.g. 36-char name → 30-char) → Never construct URL as `${name}.vercel.app`; read actual domain from `targets.production.alias` via Vercel API
**2026-03-08** - Projects view showed all team projects (including imaginelab-portal) → Filter by cross-referencing with local `history.json` deployed project names

## Key Commands
```bash
npm run electron:dev     # Start development (Vite + Electron)
npm run electron:build   # Build for production
```

## Important Files
| File | Purpose |
|------|---------|
| `electron/main.ts` | BrowserWindow + IPC handlers |
| `electron/preload.ts` | Context bridge API |
| `electron/keynoteProcessor.ts` | 7 HiDPI fixes + custom index.html generation |
| `electron/vercelDeployer.ts` | Vercel REST API + CLI deployment |
| `electron/fileOperations.ts` | Settings persistence, history, file validation |
| `electron/runtimeVerifier.ts` | Runtime verification logic |
| `src/components/Deploy.tsx` | 4-phase deployment workflow UI |
| `src/components/DeployProgress.tsx` | 14-step progress indicator |
| `src/components/History.tsx` | Past deployments list |
| `src/components/Settings.tsx` | Vercel token + team ID config |

## The 7 HiDPI Fixes (in keynoteProcessor.ts)
1. zC scale -- PDF rasterization at 3x instead of 1x
2. Fullscreen bypass -- enable rendering without fullscreen mode
3. Viewport A -- DPR scaling for sparkle/particle effects
4. Viewport B -- DPR scaling for firework effects
5. Resize viewport -- DPR scaling in resize handler
6. Constructor viewport -- divide viewportWidth/Height by DPR
7. Canvas DPR -- scale canvas backing store + add CSS size

## Key Architecture Notes
- Settings stored in ~/Library/Application Support/keynote-deployer/
- Vercel token auto-detected from CLI config if available
- Default team: team_E1wAzl9zyAPrlGzyjmcXNuxd
- macOS native feel: hidden inset title bar, SF Pro fonts, dark mode
- Generated index.html includes loading overlay, nav controls, slide counter

## Parallel Build Architecture

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
| `electron-updater` | Sparkle (future) |

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

### Known Issues the Swift Build Must Respect
- Vercel truncates long subdomains → always resolve via `targets.production.alias` API
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

### Swift Build Commands
```bash
cd swift-app && xcodegen generate && xcodebuild build -scheme KeynoteDeployer -destination "platform=macOS" -quiet
```

### Swift Important Files
| File | Purpose |
|---|---|
| `swift-app/project.yml` | XcodeGen project definition |
| `swift-app/Sources/App/KeynoteDeployerApp.swift` | App entry point + menu commands |
| `swift-app/Sources/Services/KeynoteProcessor.swift` | 7 HiDPI fixes (actor) |
| `swift-app/Sources/Services/IndexHtmlGenerator.swift` | index.html generation |
| `swift-app/Sources/Services/VercelAPI.swift` | Vercel REST API client |
| `swift-app/Sources/Services/VercelDeployer.swift` | Vercel CLI deployment |
| `swift-app/Sources/Services/FileOperations.swift` | Settings, validation, token detection |
| `swift-app/Sources/Views/DeployView.swift` | 4-phase deploy workflow |
| `swift-app/Sources/Views/ProjectsView.swift` | Vercel projects list |
| `swift-app/Sources/Views/HistoryView.swift` | SwiftData deployment history |
| `swift-app/Sources/Views/SettingsView.swift` | Vercel config + preferences |

## Update Protocol
When Claude makes a mistake: "Update CLAUDE.md so you don't make that mistake again."
