# GIF Slide Boundaries (Build-Time, Deck-Agnostic) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Determine GIF slide boundaries in the app at build-time (three user-selectable sources — Auto / Stills / Manual), bake them into the deployed viewer, and stop the viewer from detecting slides itself.

**Architecture:** The boundary list (`DetectedSlide[]`) becomes a build-time artifact produced by one of three sources and passed through the `deploy-gif` IPC into `generateGifViewerHtml`, which bakes it as a JSON literal. The deployed viewer consumes the baked array (no client-side detection) and composites frames progressively (GIF is `disposalType=1`, no random access). Animation always plays; only stop points change.

**Tech Stack:** Electron 33, React 18, TypeScript 5.7, Vite 6, gifuct-js. Tests: vitest (pure logic, added in Task 1) + puppeteer (viewer/integration, already a dependency).

## Global Constraints

- Electron-only feature. Swift parity is out of scope — note "GIF boundary sources: Electron-only" in `PARITY.md`.
- Production build MUST output outside iCloud: `npx vite build && npx electron-builder --config.directories.output=/tmp/keynote-deployer-release`. Run `npx vite build` before electron-builder.
- All three sources produce the SAME `DetectedSlide[]` shape (`src/utils/slideDetection.ts`):
  `{ restFrame: number; holdStart: number; holdEnd: number; transitionFrames: {start,end}|null }`.
- The build-merge work on branch `fix/gif-slide-detection-builds` is retained; this plan builds on it. Stay on that branch.
- Animation (builds/transitions) always plays in full — sources only change which frames are slide STOPS.
- The deployed viewer must NOT random-access frames: GIF is do-not-dispose + partial-patch, so frame N requires compositing 0→N. Composite sequentially/progressively, cache baked restFrames.
- Three synced detection copies exist (`src/utils/slideDetection.ts` canonical, `electron/gifViewerGenerator.ts` ES5, `gif-slide-viewer.html` ES5) — but only the canonical runs at build-time now; the ES5 viewer copies STOP detecting (Task 6/7).

---

## Phase 0 — Conservative Auto

### Task 1: Add vitest + revert overfit threshold to precision-first

**Files:**
- Modify: `package.json` (add vitest devDep + `test` script)
- Create: `vitest.config.ts`
- Modify: `src/utils/slideDetection.ts:36` (the `TRANSITION_PEAK` constant)
- Test: `src/utils/slideDetection.test.ts`

**Interfaces:**
- Consumes: existing `detectSlides(diffs: number[]): DetectedSlide[]`, `findQuietRuns`, `mergeBuildRuns`.
- Produces: `TRANSITION_PEAK` lowered to a precision-first value; `npm test` runs vitest.

- [ ] **Step 1: Install vitest**

Run: `npm install -D vitest@^2`
Expected: exit 0, vitest in devDependencies.

- [ ] **Step 2: Add test script + vitest config**

In `package.json` `scripts`, add: `"test": "vitest run"`.
Create `vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config'
export default defineConfig({ test: { include: ['src/**/*.test.ts'] } })
```

- [ ] **Step 3: Write the failing test (precision-first: never merge a real slide)**

Create `src/utils/slideDetection.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { detectSlides, mergeBuildRuns, findQuietRuns } from './slideDetection'

// Build a synthetic diffs array: quiet holds (0) separated by gaps of given peak.
function synth(holds: number, holdLen: number, gapPeaks: number[]): number[] {
  const d: number[] = []
  for (let s = 0; s < holds; s++) {
    for (let i = 0; i < holdLen; i++) d.push(0)        // quiet hold
    if (s < holds - 1) { d.push(gapPeaks[s]); d.push(0.1) } // 1-frame transition spike
  }
  return d
}

describe('conservative Auto threshold', () => {
  it('merges only clearly-tiny micro-build gaps (<=0.5), never a real slide change', () => {
    // 4 holds; gaps: 0.4 (micro-build), 1.2 (real change), 0.45 (micro-build)
    const diffs = synth(4, 10, [0.4, 1.2, 0.45])
    const slides = detectSlides(diffs)
    // 0.4 and 0.45 merge; 1.2 stays → 2 slides
    expect(slides.length).toBe(2)
  })

  it('does NOT merge a 1.0 gap (real text-only slide change on constant bg)', () => {
    const diffs = synth(2, 10, [1.0])
    expect(detectSlides(diffs).length).toBe(2)
  })
})
```

- [ ] **Step 4: Run test, verify it FAILS**

Run: `npm test`
Expected: FAIL — current `TRANSITION_PEAK = 0.9` merges the 0.4/0.45 micro-builds (good) but the second test's 1.0 gap is > 0.9 so it stays separate (passes); the FIRST test fails because 0.9 is fine for 0.4/0.45 too... Verify actual failure: with 0.9, `synth(4,...,[0.4,1.2,0.45])` → merges 0.4 and 0.45 → 2 slides (PASS unexpectedly). Adjust expectation OR threshold. **The real intent:** lower threshold so the band 0.5–0.9 (ambiguous, could be a subtle real change) is NOT merged. Rewrite test gap `0.4`→`0.7` to assert 0.7 is NOT merged at the new threshold:

```ts
    const diffs = synth(4, 10, [0.7, 1.2, 0.45])  // 0.7 ambiguous, 0.45 clear micro-build
    const slides = detectSlides(diffs)
    expect(slides.length).toBe(3)  // only 0.45 merges; 0.7 and 1.2 kept
```

Re-run: FAIL (0.9 merges 0.7 → 2 slides, expected 3).

- [ ] **Step 5: Lower the threshold (precision-first)**

In `src/utils/slideDetection.ts`, change the constant and its doc:

```ts
// Precision-first: Auto is now only a SEED (Stills/Manual are the reliable sources).
// Merge ONLY unambiguous micro-builds (tiny localized reveals). A real text-only slide
// change on a constant-background deck can be as small as ~1.0, and ambiguous reveals
// sit at 0.5–0.9 — so we merge only <=0.5 and never risk dropping a real slide.
// Over-counting a build is acceptable here; the human fixes it in Manual, or Stills overrides.
const TRANSITION_PEAK = 0.5
```

- [ ] **Step 6: Run tests, verify PASS**

Run: `npm test`
Expected: PASS (both tests).

- [ ] **Step 7: Commit**

```bash
git add package.json package-lock.json vitest.config.ts src/utils/slideDetection.ts src/utils/slideDetection.test.ts
git commit -m "test+fix(gif): conservative precision-first Auto threshold (0.9->0.5) + vitest"
```

---

## Phase 1 — Build-time boundary architecture

### Task 2: Thread `slides` through the type + IPC + generator signature

**Files:**
- Modify: `src/types/index.ts:53-59` (`GifDeployRequest`)
- Modify: `electron/gifViewerGenerator.ts:4` (`generateGifViewerHtml` signature)
- Modify: `electron/main.ts:454` (pass `request.slides`)
- Test: `electron/gifViewerGenerator.test.ts`

**Interfaces:**
- Consumes: `DetectedSlide` from `src/utils/slideDetection`.
- Produces: `GifDeployRequest.slides: DetectedSlide[]`; `generateGifViewerHtml(gifFilename: string, secureEmbed: boolean, slides: DetectedSlide[]): string`.

- [ ] **Step 1: Add `slides` to `GifDeployRequest`**

`src/types/index.ts`:

```ts
import type { DetectedSlide } from '../utils/slideDetection'

export interface GifDeployRequest {
  gifPath: string
  projectName: string
  slideCount: number
  title: string
  secureEmbed: boolean
  slides: DetectedSlide[]   // build-time boundaries, baked into the viewer
}
```

- [ ] **Step 2: Write the failing test (generator bakes slides JSON)**

Create `electron/gifViewerGenerator.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { generateGifViewerHtml } from './gifViewerGenerator'

const slides = [
  { restFrame: 10, holdStart: 5, holdEnd: 15, transitionFrames: null },
  { restFrame: 40, holdStart: 35, holdEnd: 45, transitionFrames: { start: 16, end: 34 } },
]

describe('generateGifViewerHtml', () => {
  it('bakes the slides array as a JSON literal', () => {
    const html = generateGifViewerHtml('deck.gif', false, slides)
    expect(html).toContain('"restFrame":10')
    expect(html).toContain('"restFrame":40')
  })
  it('does NOT run client-side quiet-run detection', () => {
    const html = generateGifViewerHtml('deck.gif', false, slides)
    expect(html).not.toContain('findQuietRuns')
    expect(html).not.toContain('mergeBuildRuns')
  })
})
```

- [ ] **Step 3: Run test, verify it FAILS**

Run: `npm test src/../electron/gifViewerGenerator.test.ts` (or `npm test`)
Expected: FAIL — signature has 2 params; baked JSON + no-detection assertions fail.

- [ ] **Step 4: Add `slides` param + bake JSON (detection removal is Task 6)**

`electron/gifViewerGenerator.ts` — change the signature and inject the literal near the top of the emitted `<script>`:

```ts
export function generateGifViewerHtml(gifFilename: string, secureEmbed: boolean, slides: import('../src/types/index').DetectedSlide[] | { restFrame: number; holdStart: number; holdEnd: number; transitionFrames: {start:number;end:number}|null }[]): string {
```

Inside the emitted script string, add (before any parse logic):

```js
var BAKED_SLIDES = ${JSON.stringify(slides)};
```

(Type import: add `export type { DetectedSlide } from '../src/utils/slideDetection'` is NOT needed; reference the structural type inline as above to avoid a circular import.)

- [ ] **Step 5: Pass slides from the handler**

`electron/main.ts:454`:

```ts
const indexHtml = generateGifViewerHtml(gifFilename, request.secureEmbed, request.slides)
```

- [ ] **Step 6: Run tests, verify PASS**

Run: `npm test`
Expected: PASS (baked JSON present; detection-string assertions pass once Task 6 removes them — for now mark the `not.toContain` test `.skip` and unskip in Task 6). Add `.skip` to the "does NOT run detection" test with a comment `// unskip in Task 6`.

- [ ] **Step 7: Commit**

```bash
git add src/types/index.ts electron/gifViewerGenerator.ts electron/main.ts electron/gifViewerGenerator.test.ts
git commit -m "feat(gif): thread build-time slides[] through GifDeployRequest -> generator (bake JSON)"
```

### Task 3: Update preload + electron.d.ts (type-only plumbing)

**Files:**
- Modify: `electron/preload.ts:2,8,36` (import already covers `GifDeployRequest`)
- Modify: `src/electron.d.ts:4,19`

**Interfaces:**
- Consumes: updated `GifDeployRequest` (now includes `slides`).
- Produces: no signature change — `deployGif(request: GifDeployRequest)` already references the type; verify it compiles with the new field.

- [ ] **Step 1: Verify type-check passes with the new field**

Run: `npx vite build`
Expected: exit 0 (the `deployGif` bridge already takes `GifDeployRequest`; adding a field is source-compatible at the boundary, but callers in GifViewer must now supply `slides` — that's Task 5). Confirm no NEW type errors beyond the pre-existing TS6305 composite-config wart.

- [ ] **Step 2: Commit (if any doc/comment touched)**

```bash
git add electron/preload.ts src/electron.d.ts
git commit -m "chore(gif): preload/electron.d.ts carry slides via GifDeployRequest" --allow-empty
```

### Task 4: GifViewer computes Auto `slides` and sends them on deploy

**Files:**
- Modify: `src/components/GifViewer.tsx` (the `deployGif` call ~line 363; `parsedRef` already holds `slides`)

**Interfaces:**
- Consumes: `parsedRef.current.slides` (already `DetectedSlide[]` from `detectSlides`).
- Produces: `deploy-gif` IPC now carries `slides`.

- [ ] **Step 1: Pass `slides` in the deployGif request**

In the `deployGif` call object (around line 363), add `slides`:

```tsx
const res = await window.electron.deployGif({
  gifPath: gifFilePath,
  projectName,
  slideCount: parsedRef.current?.slides.length ?? 0,
  title: projectName,
  secureEmbed,
  slides: parsedRef.current?.slides ?? [],
})
```

- [ ] **Step 2: Build to verify it compiles**

Run: `npx vite build`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add src/components/GifViewer.tsx
git commit -m "feat(gif): GifViewer sends build-time slides[] on deploy (Auto source)"
```

### Task 5: Deployed viewer consumes BAKED_SLIDES (remove client detection, progressive composite)

**Files:**
- Modify: `electron/gifViewerGenerator.ts` (the emitted viewer script: remove the diff/quiet-run/merge/snapshot detection block; build `slideMap`/`slideSnapshots` from `BAKED_SLIDES`; composite progressively)
- Test: `electron/gifViewerGenerator.test.ts` (unskip the no-detection test)

**Interfaces:**
- Consumes: `BAKED_SLIDES` (injected Task 2).
- Produces: a viewer that renders/navigates from baked boundaries, no detection.

- [ ] **Step 1: Unskip the no-detection test**

Remove `.skip` from the "does NOT run client-side detection" test in `electron/gifViewerGenerator.test.ts`.

- [ ] **Step 2: Run, verify FAIL**

Run: `npm test`
Expected: FAIL — `findQuietRuns`/`mergeBuildRuns` strings still present in the emitted script.

- [ ] **Step 3: Replace detection with baked-boundary consumption**

In the emitted script: delete the single-pass diff loop, the `QUIET_THRESHOLD`/`SNAPSHOT_SETTLE`/`findQuietRuns`/`mergeBuildRuns`/`adaptiveMin`/`buildSlideMap` blocks. Replace with:

```js
// Boundaries are baked at build time (BAKED_SLIDES). The viewer never detects.
var slides = BAKED_SLIDES;
var slideSnapshots = {}; // restFrame -> ImageData, filled lazily during the composite pass

// Progressive sequential composite (GIF is do-not-dispose + partial-patch: no random access).
// Composite frame-by-frame; cache the snapshot when we reach each slide's restFrame.
var restFrameSet = {}; slides.forEach(function(s){ restFrameSet[s.restFrame] = true; });
var compositedUpTo = -1;
function ensureCompositedTo(targetFrame) {
  for (var i = compositedUpTo + 1; i <= targetFrame; i++) {
    var decoded = gifuct.decompressFrame(imageFrames[i], gct, true);
    if (decoded) compositeDecoded(decoded);
    if (restFrameSet[i]) slideSnapshots[i] = compCtx.getImageData(0, 0, gifWidth, gifHeight);
    compositedUpTo = i;
  }
}
// First paint: composite up to slide 1's restFrame, then background-fill the rest.
ensureCompositedTo(slides[0].restFrame);
console.log('Loaded ' + slides.length + ' baked slides from ' + totalFrames + ' frames');
(function backgroundFill(){
  if (compositedUpTo >= totalFrames - 1) return;
  ensureCompositedTo(Math.min(totalFrames - 1, compositedUpTo + 60));
  setTimeout(backgroundFill, 0);
})();
```

In `renderSlide(index)`, before drawing: `ensureCompositedTo(slides[index].restFrame);` then draw `slideSnapshots[slides[index].restFrame]`.

- [ ] **Step 4: Run tests, verify PASS**

Run: `npm test`
Expected: PASS (no detection strings; baked JSON present).

- [ ] **Step 5: Headless render verification (real deck)**

Reuse the session's puppeteer harness. Create `scripts/verify-viewer.mjs` that serves a temp dir (index.html generated with a known `slides[]` + the source GIF) and asserts: `document.querySelectorAll('#dotStrip .dot').length === slides.length`, Next/dot navigation lands on the right counter, no console errors.

Run: `node scripts/verify-viewer.mjs`
Expected: dot count == baked slide count; nav works; no errors.

- [ ] **Step 6: Commit**

```bash
git add electron/gifViewerGenerator.ts electron/gifViewerGenerator.test.ts scripts/verify-viewer.mjs
git commit -m "feat(gif): deployed viewer consumes baked boundaries, progressive composite (no client detection)"
```

### Task 6: Sync standalone `gif-slide-viewer.html` to baked-boundary mode

**Files:**
- Modify: `gif-slide-viewer.html` (mirror Task 5: it's the standalone copy; for the standalone, accept boundaries via a small textarea/JSON paste OR keep its own detection but clearly labeled "standalone preview only")

**Interfaces:**
- Consumes: same `DetectedSlide[]` shape.

- [ ] **Step 1: Decide standalone scope**

The standalone html is a dev tool, not the deploy path. Keep its in-file detection BUT add a header comment: `// STANDALONE DEV PREVIEW — uses local detection; the SHIPPED viewer uses build-time baked boundaries (see gifViewerGenerator.ts).` No behavior change required.

- [ ] **Step 2: Commit**

```bash
git add gif-slide-viewer.html
git commit -m "docs(gif): mark standalone viewer as dev-preview (shipped path uses baked boundaries)"
```

---

## Phase 2 — Manual editor (D)

### Task 7: Boundary-source selector in the confirm phase

**Files:**
- Modify: `src/components/GifViewer.tsx` (add `boundarySource` state + selector UI in the `confirm` phase)

**Interfaces:**
- Produces: `const [boundarySource, setBoundarySource] = useState<'auto'|'stills'|'manual'>('auto')`; the deploy uses the `slides[]` produced by the active source (Auto = `parsedRef.slides`; Manual = edited array in Task 8; Stills = Task 11).

- [ ] **Step 1: Add source state + radio selector**

Add state and, in the `confirm` phase JSX, a 3-way selector: Auto (default) / Manual (opens grid) / Stills (opens folder picker). Auto path is unchanged. Show the active slide count.

- [ ] **Step 2: Build to verify**

Run: `npx vite build`
Expected: exit 0; selector renders (verify in Step 3).

- [ ] **Step 3: Headless render check**

Run app dev or generate a screenshot via the established Peekaboo/puppeteer-on-renderer flow; confirm the selector shows 3 options and Auto is default.

- [ ] **Step 4: Commit**

```bash
git add src/components/GifViewer.tsx
git commit -m "feat(gif): boundary-source selector (Auto/Manual/Stills) in confirm phase"
```

### Task 8: Manual thumbnail-grid editor

**Files:**
- Create: `src/components/SlideBoundaryEditor.tsx`
- Modify: `src/components/GifViewer.tsx` (render editor when source==='manual'; receive edited `slides[]`)

**Interfaces:**
- Consumes: `frames: ImageBitmap[]` (from `parsedRef`), Auto `slides` as seed, `onChange(slides: DetectedSlide[])`.
- Produces: `SlideBoundaryEditor` component; edited `DetectedSlide[]`.

- [ ] **Step 1: Write the helper test (insert/remove keep array valid + sorted)**

Create `src/utils/boundaryEdits.ts` + `src/utils/boundaryEdits.test.ts`:

```ts
// boundaryEdits.ts
import { findQuietRuns, type DetectedSlide } from './slideDetection'
export function removeStop(slides: DetectedSlide[], restFrame: number): DetectedSlide[] {
  return recomputeTransitions(slides.filter(s => s.restFrame !== restFrame))
}
export function insertStop(slides: DetectedSlide[], frame: number, diffs: number[]): DetectedSlide[] {
  const runs = findQuietRuns(diffs)
  const run = runs.find(r => frame >= r.start && frame <= r.end)
    ?? runs.reduce((best, r) => Math.abs((r.start+r.end)/2 - frame) < Math.abs((best.start+best.end)/2 - frame) ? r : best, runs[0])
  const slide: DetectedSlide = { restFrame: frame, holdStart: run?.start ?? frame, holdEnd: run?.end ?? frame, transitionFrames: null }
  const next = [...slides, slide].sort((a,b) => a.restFrame - b.restFrame)
  return recomputeTransitions(next)
}
function recomputeTransitions(slides: DetectedSlide[]): DetectedSlide[] {
  return slides.map((s, i) => ({ ...s, transitionFrames: i > 0 ? { start: slides[i-1].holdEnd + 1, end: s.holdStart - 1 } : null }))
}
```

```ts
// boundaryEdits.test.ts
import { describe, it, expect } from 'vitest'
import { removeStop, insertStop } from './boundaryEdits'
const base = [
  { restFrame: 10, holdStart: 5, holdEnd: 15, transitionFrames: null },
  { restFrame: 40, holdStart: 35, holdEnd: 45, transitionFrames: { start: 16, end: 34 } },
]
describe('boundaryEdits', () => {
  it('removes a stop and recomputes transitions', () => {
    expect(removeStop(base, 10).length).toBe(1)
  })
  it('inserts a stop in sorted order with a recomputed transition', () => {
    const diffs = new Array(50).fill(0); diffs[25] = 2  // quiet around frame 25
    const out = insertStop(base, 25, diffs)
    expect(out.map(s => s.restFrame)).toEqual([10, 25, 40])
    expect(out[1].transitionFrames).not.toBeNull()
  })
})
```

- [ ] **Step 2: Run, verify FAIL**

Run: `npm test`
Expected: FAIL — `boundaryEdits.ts` not yet created/exports missing.

- [ ] **Step 3: Implement `boundaryEdits.ts`** (code above). Run `npm test` → PASS.

- [ ] **Step 4: Build the grid component**

`SlideBoundaryEditor.tsx`: render one thumbnail per `slides[i].restFrame` (draw `frames[restFrame]` to a small `<canvas>`), each with a ✕ (calls `onChange(removeStop(...))`). Below the grid: a frame scrubber (`<input type=range min=0 max=frames.length-1>`) + ←/→ nudge buttons + "Insert stop here" (calls `onChange(insertStop(...))`). Live count display.

- [ ] **Step 5: Wire into GifViewer** when `boundarySource==='manual'`; deploy uses the edited array.

- [ ] **Step 6: Build + headless check**

Run: `npx vite build` (exit 0). Visual check: grid shows N thumbnails; remove drops one; insert adds one; count updates.

- [ ] **Step 7: Commit**

```bash
git add src/utils/boundaryEdits.ts src/utils/boundaryEdits.test.ts src/components/SlideBoundaryEditor.tsx src/components/GifViewer.tsx
git commit -m "feat(gif): Manual thumbnail-grid boundary editor (remove/insert + frame-step)"
```

---

## Phase 3 — Stills (C)

### Task 9: Stills→frame DP matcher (pure logic)

**Files:**
- Create: `src/utils/stillsMatch.ts`
- Test: `src/utils/stillsMatch.test.ts`

**Interfaces:**
- Produces:
  - `naturalSort(names: string[]): string[]`
  - `matchStillsToFrames(stillGrids: number[][], frameGrids: number[][]): number[]` — returns, for each still, its matched frame index, monotonic increasing, via O(N·M) DP minimizing total mean-abs cost. `stillGrids[i]` / `frameGrids[f]` are equal-length flattened grayscale sample arrays.

- [ ] **Step 1: Write failing tests**

```ts
import { describe, it, expect } from 'vitest'
import { naturalSort, matchStillsToFrames } from './stillsMatch'

describe('naturalSort', () => {
  it('orders numerically, not lexically', () => {
    expect(naturalSort(['s.10.jpg','s.2.jpg','s.1.jpg'])).toEqual(['s.1.jpg','s.2.jpg','s.10.jpg'])
  })
})
describe('matchStillsToFrames', () => {
  it('returns monotonic matches and resists greedy poisoning', () => {
    // 3 stills = grids [0],[5],[9]; frames 0..9 are their own value; a decoy: frame 2 also ~5
    const frames = [[0],[1],[5],[3],[4],[5],[6],[7],[8],[9]] // frame2 decoy near still1
    const stills = [[0],[5],[9]]
    const m = matchStillsToFrames(stills, frames)
    expect(m.length).toBe(3)
    expect(m[0] < m[1] && m[1] < m[2]).toBe(true)   // monotonic
    expect(m[2]).toBe(9)                            // last still maps to the true frame 9
    // greedy would grab frame2 for still1 and poison; DP must pick frame5
    expect(m[1]).toBe(5)
  })
})
```

- [ ] **Step 2: Run, verify FAIL.** Run: `npm test` → FAIL (module missing).

- [ ] **Step 3: Implement**

```ts
// stillsMatch.ts
export function naturalSort(names: string[]): string[] {
  const key = (s: string) => s.split(/(\d+)/).map(p => /^\d+$/.test(p) ? p.padStart(10, '0') : p).join('')
  return [...names].sort((a, b) => key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0)
}
function meanAbs(a: number[], b: number[]): number {
  let s = 0; for (let i = 0; i < a.length; i++) s += Math.abs(a[i] - b[i]); return s / a.length
}
// DP: dp[i][f] = min total cost matching stills 0..i with still i -> frame f (f strictly increasing).
export function matchStillsToFrames(stills: number[][], frames: number[][]): number[] {
  const N = stills.length, M = frames.length
  const INF = Infinity
  const cost: number[][] = stills.map(s => frames.map(f => meanAbs(s, f)))
  const dp: number[][] = Array.from({ length: N }, () => new Array(M).fill(INF))
  const back: number[][] = Array.from({ length: N }, () => new Array(M).fill(-1))
  for (let f = 0; f < M; f++) dp[0][f] = cost[0][f]
  for (let i = 1; i < N; i++) {
    let bestPrev = INF, bestPrevIdx = -1
    for (let f = 0; f < M; f++) {
      if (f - 1 >= 0 && dp[i-1][f-1] < bestPrev) { bestPrev = dp[i-1][f-1]; bestPrevIdx = f - 1 }
      if (bestPrev !== INF) { dp[i][f] = bestPrev + cost[i][f]; back[i][f] = bestPrevIdx }
    }
  }
  let endF = -1, best = INF
  for (let f = 0; f < M; f++) if (dp[N-1][f] < best) { best = dp[N-1][f]; endF = f }
  const out = new Array(N).fill(0); let f = endF
  for (let i = N - 1; i >= 0; i--) { out[i] = f; f = back[i][f] }
  return out
}
```

- [ ] **Step 4: Run tests, verify PASS.** Run: `npm test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/utils/stillsMatch.ts src/utils/stillsMatch.test.ts
git commit -m "feat(gif): stills->frame DP sequence matcher + natural sort"
```

### Task 10: Stills folder picker IPC

**Files:**
- Modify: `electron/main.ts` (new `select-stills-folder` handler returning sorted image paths)
- Modify: `electron/preload.ts` + `src/electron.d.ts` (expose `selectStillsFolder`)

**Interfaces:**
- Produces: `selectStillsFolder(): Promise<IpcResponse<string[]>>` — opens `dialog.showOpenDialog({ properties: ['openDirectory'] })`, enumerates `jpg/jpeg/png/webp`, returns natural-sorted absolute paths.

- [ ] **Step 1: Add the handler**

```ts
import { naturalSort } from '../src/utils/stillsMatch'
ipcMain.handle('select-stills-folder', async () => {
  const r = await dialog.showOpenDialog({ properties: ['openDirectory'] })
  if (r.canceled || !r.filePaths[0]) return { success: false, error: 'cancelled' }
  const dir = r.filePaths[0]
  const all = await fs.readdir(dir)
  const imgs = naturalSort(all.filter(f => /\.(jpe?g|png|webp)$/i.test(f))).map(f => path.join(dir, f))
  if (imgs.length === 0) return { success: false, error: 'No images (jpg/png/webp) found in folder' }
  return { success: true, data: imgs }
})
```

- [ ] **Step 2: Expose in preload + electron.d.ts**

`preload.ts`: `selectStillsFolder: () => ipcRenderer.invoke('select-stills-folder')`. `electron.d.ts`: `selectStillsFolder: () => Promise<IpcResponse<string[]>>`.

- [ ] **Step 3: Build to verify.** Run: `npx vite build` → exit 0.

- [ ] **Step 4: Commit**

```bash
git add electron/main.ts electron/preload.ts src/electron.d.ts
git commit -m "feat(gif): select-stills-folder IPC (natural-sorted image paths)"
```

### Task 11: Wire Stills source in GifViewer (load stills, sample, match, build slides)

**Files:**
- Modify: `src/components/GifViewer.tsx`

**Interfaces:**
- Consumes: `selectStillsFolder()`, `matchStillsToFrames`, `findQuietRuns`, the in-memory `frames`/`diffs` (already sampled to a grid during `parseGifBuffer`).
- Produces: a `DetectedSlide[]` from the still→frame matches, used on deploy when `boundarySource==='stills'`.

- [ ] **Step 1: Implement the stills flow**

On "Pick stills folder": call `selectStillsFolder()`; for each image, load into an offscreen canvas, downsample to the SAME grid as the GIF diff sampling (reuse the existing 32-wide sample logic from `parseGifBuffer`), produce `number[]` grayscale grids; build `frameGrids` from the already-parsed frames at the same grid; call `matchStillsToFrames(stillGrids, frameGrids)`; map each matched frame → a `DetectedSlide` snapping to the containing/nearest quiet run (reuse `insertStop`-style snap from `boundaryEdits` or `findQuietRuns`). Show "matched N stills → N stops"; if `N !== autoCount`, show both numbers. On any non-monotonic/failed match, surface a notice and offer to switch to Manual.

- [ ] **Step 2: Build + headless end-to-end on the real 39-slide deck**

Extend `scripts/verify-viewer.mjs` (or a new `scripts/verify-stills.mjs`) to: run the stills match against the 39 supplied stills + the source GIF frames, assert 39 monotonic boundaries, generate the viewer with those `slides`, render each stop, and **compare each rendered stop to its still** (the contact-sheet method from this session) — expect every stop to match its still (no off-by-one).

Run: `node scripts/verify-stills.mjs`
Expected: 39 boundaries; each rendered stop matches its still.

- [ ] **Step 3: Commit**

```bash
git add src/components/GifViewer.tsx scripts/verify-stills.mjs
git commit -m "feat(gif): Stills source — match per-slide exports to frames, build boundaries"
```

---

## Final Verification

### Task 12: Deck-agnostic check + docs

**Files:**
- Modify: `PARITY.md`, `CLAUDE.md`

- [ ] **Step 1: Second-deck check**

Run the Stills + Auto path on at least one ADDITIONAL real deck (different slide count/style — ask Edward for a second GIF + its slide count). Record: Auto count (best-effort), Stills count (must equal the deck's true count), and a spot-check that rendered stops match. Document results in the commit message. This guards against overfitting to the calibration deck.

- [ ] **Step 2: Full build + test gate**

Run: `npm test` (all green) and `npx vite build` (exit 0).
Expected: all tests pass; build clean (only the pre-existing TS6305 from `tsc --noEmit`, which `vite build` does not hit).

- [ ] **Step 3: Update docs**

`PARITY.md`: add "GIF boundary sources (Auto/Stills/Manual) — Electron only, N/A Swift". `CLAUDE.md` Architecture: note boundaries are build-time + baked; viewer no longer detects.

- [ ] **Step 4: Commit**

```bash
git add PARITY.md CLAUDE.md
git commit -m "docs(gif): build-time boundary sources — PARITY + architecture notes; deck-agnostic check recorded"
```

---

## Notes for the implementer

- Stay on branch `fix/gif-slide-detection-builds`.
- The GIF sample-grid used for `diffs` in `parseGifBuffer` (GifViewer) and the stills downsample MUST be the same grid for `matchStillsToFrames` to be comparable — reuse the exact sampling code, don't reinvent it.
- The deployed viewer must never random-access frames — always composite sequentially via `ensureCompositedTo`.
- Auto is a SEED only; never present its count as authoritative. Stills (when present) and Manual are the reliable sources.
