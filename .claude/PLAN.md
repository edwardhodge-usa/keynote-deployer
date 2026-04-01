# GIF Deploy Pipeline — Implementation Plan

> **For Claude:** Use `/do` to execute this plan task-by-task via fresh subagents.

**Goal:** Extend the Preview tab so GIF presentations can be deployed to Vercel as interactive slide viewers, producing shareable URLs just like the HTML deploy workflow.

**Architecture:** The GIF viewer already parses slides and plays transitions locally. We add a confirm→deploy→complete flow on top: a new IPC handler (`deploy-gif`) writes a deploy folder to `/tmp/`, generates an `index.html` viewer (adapted from `gif-slide-viewer.html`) that loads the GIF via `fetch`, copies the GIF into the folder, calls the existing `deployToVercel()` function, saves to history, and returns the URL. The renderer-side GifViewer component gains confirm/deploying/complete/error phases.

## Verification Goals
- [x] Dropping a GIF and clicking Deploy produces a Vercel URL
- [ ] The deployed URL loads an interactive slide viewer with forward/back/dots/keyboard
- [ ] The deployed viewer auto-detects slides from the GIF (no server-side processing)
- [ ] History tab shows GIF deployments alongside HTML deployments
- [ ] Copy URL and Copy Framer Embed work on the complete screen
- [ ] `npx vite build` exits cleanly

## Wave 1 (parallel-safe)

### Task 1: Create GIF viewer HTML generator
**Files:** `electron/gifViewerGenerator.ts` (create)
**Do:** Create a function `generateGifViewerHtml(gifFilename: string, secureEmbed: boolean): string` that returns a self-contained HTML string (the deployable viewer page). This is adapted from `gif-slide-viewer.html` but:
- The GIF is loaded via `fetch('./${gifFilename}')` instead of drag-and-drop (auto-loads on page open)
- The drop zone is removed — the GIF URL is hardcoded
- The gifuct-js IIFE bundle is inlined (copy from `gif-slide-viewer.html` lines 280)
- The parsing, slide detection (quiet-run algorithm), canvas viewer, forward/back/dots/keyboard controls are all preserved exactly
- Dark theme CSS preserved
- If `secureEmbed` is true, add `<style>body { user-select: none; } img, canvas { pointer-events: none; }</style>` and disable right-click via `document.addEventListener('contextmenu', e => e.preventDefault())`
- Add a small "Powered by Keynote Deployer" footer text
**Done when:** The function returns valid HTML that, when saved alongside a GIF file and opened in a browser, auto-loads and displays the slide viewer.

### Task 2: Create deploy-gif IPC handler
**Files:** `electron/main.ts` (modify), `electron/preload.ts` (modify), `src/electron.d.ts` (modify), `src/types/index.ts` (modify)
**Do:**
1. Add a `GifDeployRequest` type to `src/types/index.ts`:
   ```typescript
   export interface GifDeployRequest {
     gifPath: string
     projectName: string
     slideCount: number
     title: string
     secureEmbed: boolean
   }
   ```
2. Add a new IPC handler `deploy-gif` in `electron/main.ts` that:
   - Creates a temp deploy folder: `/tmp/keynote-deployer-gif-${Date.now()}/`
   - Copies the GIF file into the folder
   - Calls `generateGifViewerHtml()` to create `index.html` and writes it to the folder
   - Loads settings for Vercel token/team
   - Calls existing `deployToVercel()` from `vercelDeployer.ts` with the temp folder
   - Saves a `HistoryEntry` (reuse existing `addHistoryEntry()`)
   - Auto-copies URL if setting enabled
   - Sends progress events via `processing-progress` channel (reuse existing pattern with steps: "Preparing files", "Creating Vercel project", "Deploying", "Complete")
   - Cleans up the temp folder after deploy
   - Returns `IpcResponse<PipelineResult>` (reuse existing type, `fixesApplied: 0`, `fixesSkipped: 0`)
3. Add `deployGif` to the preload bridge and `ElectronAPI` interface (both `preload.ts` and `electron.d.ts`)
**Done when:** Calling `window.electron.deployGif(request)` from the renderer triggers the full pipeline and returns a URL.

## Wave 2 (depends on Wave 1)

### Task 3: Add deploy flow to GifViewer component
**Files:** `src/components/GifViewer.tsx` (modify)
**Do:** Extend the existing GifViewer component to add phases after the local preview:
1. After slide detection completes and viewing phase shows, add a **"Deploy to Vercel"** button in the controls area (below the keyboard hint). This transitions to a **confirm** phase.
2. **Confirm phase:** Shows GIF metadata (filename, slide count, dimensions, file size), editable project name field (kebab-cased from filename, with prefix from settings), secure embed checkbox. "Back" returns to viewing, "Deploy" starts the pipeline.
3. **Deploying phase:** Progress indicator showing steps (reuse the `processing-progress` push channel — listen for events just like `Deploy.tsx` does).
4. **Complete phase:** Green checkmark, URL input with Copy URL button, Copy Framer Embed button, Open in Browser button, "Deploy Another" resets to drop phase. Mirror the layout from `Deploy.tsx` complete phase.
5. **Error phase:** Error message with Retry and Start Over buttons.
The local preview (canvas + controls) remains visible above the deploy controls in the confirm phase so the user can still step through slides before deploying.
**Done when:** Full flow works: drop GIF → preview slides → click Deploy → confirm → deploying → complete with URL.

### Task 4: Update PARITY.md and CLAUDE.md
**Files:** `PARITY.md` (modify), `CLAUDE.md` (modify)
**Do:**
- Add a "GIF Deploy" section to PARITY.md with the new features (GIF viewer tab, GIF parsing, slide detection, GIF deployment to Vercel). Mark all as Done for Electron, N/A for Swift.
- Add `deploy-gif` to the IPC channels list in CLAUDE.md and note the GIF deploy pipeline in the architecture section.
**Done when:** Docs reflect the new feature.

## Final Verification
Run all verification goals. See /verify skill.

## Execution Route
**Recommended: /do** (subagents)
Reason: 4 tasks across 2 waves, multi-file work, clear separation between backend (Wave 1) and frontend (Wave 2).

Ready to execute?
1. **/do** — Subagent-driven execution
2. **Manual** — I'll work through tasks directly
