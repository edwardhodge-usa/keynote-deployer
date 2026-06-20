# GIF Deploy — Swift Port — Synthesized Specification

Synthesis of: the staged scope (`gif-deploy-spec.md`), research findings (`claude-research.md`), and interview decisions (`claude-interview.md`). This is the authoritative spec the implementation plan is written against. **Scope: Phase 1 only.**

---

## Goal

Bring the Electron-only "GIF Deploy" feature to the Swift app as a **new 5th tab** (`.gifDeploy`), reusing the existing Swift Vercel deploy/persistence/settings backend unchanged. Phase 1 = prove the pipeline end-to-end: pick a Keynote-exported GIF → decode frames → Auto slide-boundary detection → emit a self-contained interactive viewer → deploy to Vercel → live URL + history record.

Phases 2 (Stills DP matcher) and 3 (Manual grid editor) are explicitly **out of scope** for this plan (separate later deep-plans).

## Why it exists

Keynote's HTML export rasters images to low-res 266×150 thumbnails; the 7 HiDPI fixes repair only text/vectors. Image-heavy decks look broken via HTML. GIF Deploy is the fallback: deploy the deck as an animated GIF behind a self-contained viewer (forward/back/dots/keyboard/touch). 256-color GIF bands on photos — "better than broken," not lossless.

---

## Corrected technical foundation (from research)

### Compositing — RESOLVED in plan as a gated spike
The staged scope's TOP RISK (Swift must hand-composite disposal=1 patches) is **likely inverted**. Apple's ImageIO **auto-composites**: `CGImageSourceCreateImageAtIndex(src, i, nil)` returns the full rendered frame, honoring GIF disposal internally (corroborated by SDWebImage/Kingfisher doing zero manual compositing, the absence of any disposal-method key in `kCGImagePropertyGIFDictionary`, and the documented "ghosting" symptom).

**Plan resolution:**
- **Gate-0 spike (first Phase-1 task):** empirically confirm on a real deck GIF (`TEST_GIF`, path supplied by Edward) that ImageIO returns full composited frames (decode frame 0 + late frame N, assert N is a full slide, not a sliver).
- **If confirmed (expected):** no `GifCompositor`. `GifFrameSource` wraps ImageIO and yields full `CGImage` frames.
- **If refuted (fallback):** build the disposal-correct compositor (CGBitmapContext accumulate; disposal 0/1 keep, 2 clear sub-rect, 3 restore-previous; disposal parsed from GCE binary since ImageIO doesn't expose it).
- **Performance:** iterate frames forward 0→N once with caching (do-not-dispose ⇒ not O(1) random access). Timing via `kCGImagePropertyGIFUnclampedDelayTime` → fallback `kCGImagePropertyGIFDelayTime` (timing not needed for Phase-1 detection, but read for completeness).

### Viewer fidelity — shared asset, Swift-emit only this phase
The deployed viewer (`gifViewerGenerator.ts`, ~570 lines, embeds gifuct-js + progressive compositing + playback) is the actual product. To avoid Swift/Electron drift:
- **Extract** the canonical viewer into one placeholder-driven asset: `{{GIF_FILENAME}}`, `{{BAKED_SLIDES}}` (a `DetectedSlide[]` JSON literal), `{{SECURE_EMBED}}`.
- **Swift emits** that asset (`GifViewerGenerator.swift` string-substitutes placeholders).
- **Phase-1 gate:** Swift's emitted `index.html` is **byte-identical** to the CURRENT Electron-generated viewer for the same `(gifFilename, secureEmbed, slides)` inputs.
- The Electron refactor (make `gifViewerGenerator.ts` consume the shared asset) is a **deferred** separate task — the shipping Electron app is untouched in this plan.

---

## Component plan (Phase 1)

### New Swift code
| Component | Responsibility | Notes |
|---|---|---|
| `Models/GifDeploy.swift` | `GifDeployRequest`, `DetectedSlide`, `QuietRun` Codable/Sendable structs | Mirror Electron `src/types/index.ts` field-for-field (see below) |
| `Services/GifFrameSource.swift` | ImageIO decode → full composited `CGImage` per frame, forward-iterate + cache | Gate-0 proves this is sufficient; fallback `GifCompositor` only if spike fails |
| `Services/GridSampler.swift` | Sample 1000 pts (32×32 grid), RGB only, → `[Double]` per frame; `meanAbs` between adjacent frames → `diffs: [Double]` | CGContext → raw bytes |
| `Services/SlideDetector.swift` | Auto quiet-run: `findQuietRuns`, `mergeBuildRuns`, `filterTransitionArtifacts`, `buildSlideMap`, `detectSlides` | Port verbatim; constants 0.3 / 8 / 0.5; **adaptive median factor 0.33** |
| `Services/GifViewerGenerator.swift` | Substitute placeholders into the shared viewer asset → `index.html` string | Byte-identical-to-Electron gate |
| `Services/GifDeployer.swift` | Orchestrate: temp folder → copy GIF → write index.html → call `VercelDeployer.deploy` → `HistoryEntry` | Mirrors `deploy-gif` IPC order |
| `Views/GifDeployView.swift` | Phase state machine + static restFrame thumbnails + project name / secure-embed confirm | Mirrors `DeployView.Phase` |
| GIF file picker + (Phase-2) stills folder picker | NSOpenPanel wrappers | Mirror `DeployView.selectFolder()`; GIF: `canChooseFiles`, `.gif` UTType |
| Shared asset `viewer-template.html` | Canonical placeholder viewer (extracted from `gifViewerGenerator.ts`) | Committed; Swift reads + substitutes |

### Reused unchanged (verified present)
- `VercelDeployer.deploy(folderPath, projectId, token, teamId, secureEmbed, embedAllowedDomains, onProgress) async throws -> DeployResult` — already writes CSP `vercel.json`.
- `VercelAPI.ensureProject(name) async throws -> VercelProject`.
- `HistoryEntry` `@Model` — set `folderPath=gifPath`, `fixesApplied=0`. **No migration.**
- `AppSettings` (token/team/secureEmbed/domains), `NavigationTab` (+`case gifDeploy`, auto-appears in `SidebarView`; route in `ContentView`), `ProcessingStep` + `@Sendable onProgress`.

### Exact types to mirror
```
GifDeployRequest { gifPath, projectName, slideCount, title, secureEmbed, slides: [DetectedSlide] }
DetectedSlide   { restFrame, holdStart, holdEnd, transitionFrames: {start,end}? }
QuietRun        { start, end, length, lastStart, lastEnd }
```

### Auto detection constants (from real code)
```
QUIET_THRESHOLD = 0.3
MIN_QUIET_RUN   = 8
TRANSITION_PEAK = 0.5
adaptiveMin = max(MIN_QUIET_RUN, floor(median(runLengths) * 0.33))   // 0.33, NOT 0.5
SAMPLE_POINTS = 1000 → gridSize = ceil(sqrt(1000)) = 32   // 32×32, RGB only
```

---

## UI

New 5th tab `.gifDeploy` → `GifDeployView`. Phases mirror `DeployView` with a GIF-parse step:
`selectGif → loading(decode+detect) → confirm(project name + secure embed) → processing(deploy) → complete(URL/embed copy) → error`.

Preview = **static `restFrame` thumbnails** (one composited CGImage per detected slide), not live playback.

---

## Phase 1 acceptance gates
1. **Gate-0 (compositing):** ImageIO returns full composited frames for `TEST_GIF` (or fallback compositor lands and produces them).
2. **Gate-1 (viewer fidelity):** Swift-emitted `index.html` byte-identical to current Electron viewer for identical inputs.
3. **Gate-2 (end-to-end):** real Keynote GIF → Swift detects slides → deploys → live Vercel URL renders the interactive viewer → `HistoryEntry` written (`fixesApplied=0`, `folderPath=gifPath`).
4. Auto detection is seed-quality only (acceptable for Phase 1 — goal is plumbing, not boundary accuracy; accuracy is Phase 2 Stills).

## Testing
- **Swift Testing** (`@Test`/`#expect`), new test target (swift-app has none today).
- Unit tests port the Electron Vitest cases for `SlideDetector` (synthetic diff arrays → expected slide counts), `GridSampler.meanAbs`, boundary math.
- `GifViewerGenerator` byte-identical test against a committed Electron-output fixture.
- Gate-0 + Gate-2 are live/integration checks (need `TEST_GIF`), run at /deep-implement time.

## Out of scope (this plan)
Phase 2 Stills DP matcher; Phase 3 Manual grid editor; live in-app playback; Electron refactor to consume the shared asset.
