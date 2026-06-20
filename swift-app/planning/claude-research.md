# Research Findings — GIF Deploy Swift Port

Date: 2026-06-19. Two parallel research tracks: (A) codebase ground-truth of the Electron source + Swift reuse seam, (B) web/docs verification of the TOP RISK (ImageIO GIF compositing).

---

## ⚠️ HEADLINE: The spec's TOP RISK is likely INVERTED — verify empirically before committing the plan

The spec (§2) asserts: *"`CGImageSourceCreateImageAtIndex` returns each frame as stored… for a disposal=1 GIF that's a partial patch, not the full slide → Swift MUST replicate progressive compositing (GifCompositor)."*

**Web research strongly contradicts this for the ImageIO path.** ImageIO **auto-composites**: `CGImageSourceCreateImageAtIndex(src, i, nil)` returns the **fully composited, full-canvas frame** as it would appear during playback — ImageIO does the GCE-disposal bookkeeping internally and never exposes a disposal-method or frame-rect key.

Evidence (converging):
- The documented `kCGImagePropertyGIFDictionary` key set has **no disposal-method key and no per-frame rect key** — because ImageIO consumes disposal internally; the caller never composites.
- **SDWebImage** (`SDImageGIFCoder`/`SDImageIOAnimatedCoder`) and **Kingfisher** are thin wrappers around `CGImageSourceCreateImageAtIndex` with **zero** disposal handling, CGContext accumulation, or GCE parsing. A library this battle-tested would have to composite manually if ImageIO didn't.
- The well-known "ghosting" symptom (pulling one frame shows cumulative prior content) is itself proof of auto-compositing.
- Apple's `CGAnimateImageAtURLWithBlock` hands back ready-to-draw frames off the same machinery.

**Reconciliation with our own CLAUDE.md lesson (2026-06-19):** That lesson — "disposalType=1 do-not-dispose → no random-access frame decode, composite 0→N progressively" — describes the **browser/Canvas/gifuct reality** (the deployed viewer gets stored patches and MUST composite). It is correct *there*. It does **not** describe the ImageIO contract. Both facts coexist:
- **Deployed web viewer:** must composite 0→N (gifuct gives patches). Lesson holds.
- **Swift detector via ImageIO:** gets full composited frames already. No hand-rolled `GifCompositor` needed.

**Consequences for the plan:**
- The single highest-risk/highest-effort component (disposal-correct `GifCompositor`) **may be unnecessary** → large scope reduction in Phase 1.
- Naive per-index decode + pixel-diff is **semantically valid** on the ImageIO path (full-frame vs full-frame), not garbage.
- **Performance caveat:** do-not-dispose chains aren't independently decodable — ImageIO may re-walk 0→i internally per index. **Iterate forward 0→N once with caching**, don't random-access jump.
- Read timing from `kCGImagePropertyGIFUnclampedDelayTime` (fallback `kCGImagePropertyGIFDelayTime`).

**DO NOT take this purely on the research's word (Edward's ground-truth rule cuts both ways).** The research itself recommends — and the plan MUST include as a **Phase 1 gate-0 spike** — a cheap empirical check on a real Keynote deck GIF: decode frame 0 and a late frame N via `CGImageSourceCreateImageAtIndex`; eyeball that N shows the full accumulated slide (not a sliver/patch). This 30-minute spike decisively settles compositor-or-not BEFORE any boundary code. Plan branches:
- **Spike confirms auto-composite (expected):** drop `GifCompositor`; sampler reads ImageIO full frames directly.
- **Spike shows patches (unexpected):** fall back to the spec's `GifCompositor` (CGBitmapContext accumulate, disposal 0/1 keep, 2 clear-subrect, 3 restore-prev — but disposal must then be parsed from GCE binary since ImageIO doesn't expose it).

---

## A. Codebase ground-truth (Explore agent)

### Electron source-of-truth (port targets)

**`electron/gifViewerGenerator.ts`** (~570 lines) — `generateGifViewerHtml(gifFilename, secureEmbed, slides[])`:
- Embeds gifuct-js as a minified IIFE (~3KB, global `gifuct`).
- Placeholders: `var BAKED_SLIDES = ${JSON.stringify(slides)}` (line 254); `fetch('./${gifFilename}')` (line 296).
- Progressive compositing + playback JS lives **inside the generated HTML** (lines 318–527); canvas 1080×608, scaled to 100% width via `aspect-ratio`.
- **CSP/secure-embed is NOT in this file** — written into `vercel.json` by the deployer at deploy time (`deployToVercel.ts:114–145`). *(Corrects spec §3 line implying CSP is in the viewer generator.)*

**`src/utils/slideDetection.ts`** — Auto quiet-run. Exact constants:
```
QUIET_THRESHOLD = 0.3
MIN_QUIET_RUN   = 8
TRANSITION_PEAK = 0.5
```
Functions: `findQuietRuns(diffs)`, `mergeBuildRuns(runs, diffs)`, `filterTransitionArtifacts(runs)`, `buildSlideMap(quietRuns)`, `detectSlides(diffs)` (wrapper).
- **Adaptive median filter (line 102):** `adaptiveMin = max(MIN_QUIET_RUN, floor(median * 0.33))` — factor is **0.33, NOT 0.5** (lowered to avoid dropping a briefly-held real slide on the 39-slide calibration deck). *(Spec §3 says "0.5"; real code is 0.33. Use 0.33.)*

**Grid sampler (in `GifViewer.tsx`):** `SAMPLE_POINTS = 1000`; `gridSize = ceil(sqrt(1000)) = 32` → 32×32; samples **RGB only, no alpha**; diff = mean-absolute-difference over sampled channels.

**`src/utils/stillsMatch.ts`:** `naturalSort(names)`, `meanAbs(a,b)` (Σ|a−b|/n, returns 0 if empty), `matchStillsToFrames(stills, frames)` — O(N·M) DP with strictly-increasing frame indices; `dp[i][f] = min over f'<f (dp[i-1][f']) + meanAbs(stills[i], frames[f])`; backtrack. Snap-to-quiet-run done in `GifViewer.tsx:449–463` (find containing run, else nearest run midpoint).

**`src/utils/boundaryEdits.ts`:** `removeStop(slides, restFrame)`, `insertStop(slides, frame, diffs)`, `recomputeTransitions` — transition[i].start = slides[i-1].holdEnd+1; .end = slides[i].holdStart−1; inverted ⇒ `transitionFrames = null` (hard cut).

**Types (`src/types/index.ts`):**
```ts
GifDeployRequest { gifPath, projectName, slideCount, title, secureEmbed, slides: DetectedSlide[] }
DetectedSlide   { restFrame, holdStart, holdEnd, transitionFrames: {start,end} | null }
QuietRun        { start, end, length, lastStart, lastEnd }
```

**`deploy-gif` IPC (`electron/main.ts:434–542`):** tmp `/tmp/keynote-deployer-gif-${Date.now()}` → `fs.copyFile(gifPath, tmp/gifFilename)` → `generateGifViewerHtml(...)` → `deployToVercel(tmp, projectName, …)` → history `fixesApplied:0`, `folderPath=gifPath` → auto-copy URL → cleanup.

**Disposal handling (`GifViewer.tsx:174–187`):** `if (frame.disposalType === 2) compCtx.clearRect(...)` else progressive draw of patch at `dims.left/top`; per-frame `decompressFrame(...)`, patch released after. Confirms the **web-viewer** composites manually (gifuct gives patches) — consistent with the ImageIO reconciliation above.

### Swift reuse seam (spec "reuse as-is" claims — all VERIFIED ✓)

- **`VercelDeployer.deploy(folderPath, projectId, token, teamId, secureEmbed, embedAllowedDomains, onProgress) async throws -> DeployResult`** — already writes `vercel.json` frame-ancestors CSP when `secureEmbed && !domains.isEmpty`. GIF deploy reuses directly. ✓
- **`VercelAPI.ensureProject(name) async throws -> VercelProject`** — GET /v9, else POST /v10. ✓
- **`HistoryEntry` @Model:** `id(unique), projectName, title, slideCount, url, folderPath, date, fixesApplied`. GIF uses `folderPath=gifPath, fixesApplied=0`. **No migration.** ✓
- **`NavigationTab`** enum: `deploy, projects, history, settings` (CaseIterable). Adding `case gifDeploy` auto-appears in `SidebarView` (`List(NavigationTab.allCases)`); route in `ContentView` switch. ✓
- **`AppSettings`:** `vercelToken, vercelTeamId, theme, autoCopyUrl, enableRuntimeVerification, projectNamePrefix, lastFolderPath, secureEmbed, embedAllowedDomains`. ✓
- **`DeployView.Phase`:** `select, confirm, processing, complete, error` — GifDeployView mirrors, adding an intermediate GIF-parse/loading phase.
- **NSOpenPanel pattern** in `DeployView.selectFolder()` — mirror for GIF file picker (`canChooseFiles=true`, `.gif` UTType) + stills folder picker (`canChooseDirectories=true`).

### Test setup
- Electron tests: **Vitest** (`describe/it/expect`), e.g. `src/utils/slideDetection.test.ts`.
- **Swift app currently has NO tests** in `swift-app/`. Plan must establish the test target. Recommend **Swift Testing** (`@Test`/`#expect`, native macOS 15+) — decision to confirm in interview.

### Spec-compliance flags
| Spec claim | Verdict |
|---|---|
| gifuct embedded inline (~3KB) | ✓ |
| disposalType=1 progressive composite (web viewer) | ✓ (web only) |
| ImageIO returns stored patches → need GifCompositor | ✗ **likely wrong — see headline; gate empirically** |
| secure-embed CSP baked by viewer generator | ✗ CSP is in deployer/vercel.json, not the HTML gen |
| ~1000 pts / 32×32 grid | ✓ |
| Auto constants 0.3 / 8 / 0.5 | ✓ for the three thresholds; adaptive-median factor is **0.33 not 0.5** |
| HistoryEntry no-migration reuse | ✓ |
| NavigationTab auto-append | ✓ |
| Vercel/AppSettings reuse | ✓ |

---

## B. Web/docs — ImageIO GIF compositing (full detail)

See headline. Net recommendations baked into the plan:
1. **Lead with ImageIO full-frame decode**; gate with a Phase-1 gate-0 empirical spike on a real deck GIF.
2. Drop `GifCompositor` if the spike confirms (expected). Keep it as a documented fallback branch only.
3. Forward-iterate 0→N once with caching (do-not-dispose ⇒ not O(1) random access).
4. Timing via `kCGImagePropertyGIFUnclampedDelayTime` → fallback `kCGImagePropertyGIFDelayTime`.
5. Don't read a disposal-method key (none exists); only parse GCE binary if the fallback branch is hit.

Sources: Apple ImageIO docs (`CGImageSourceCreateImageAtIndex`, `CGAnimateImageAtURLWithBlock`), SDWebImage `SDImageGIFCoder.m`/`SDImageIOAnimatedCoder.m`, Kingfisher `AnimatedImageView.swift`, mayoff/uiimage-from-animated-gif, Cloudinary ghosting thread, GIF disposal-method reference.
