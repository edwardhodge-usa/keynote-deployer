# GIF Slide Boundaries — Build-Time, Deck-Agnostic — Design Spec

**Date:** 2026-06-19
**Project:** Keynote Deployer
**Status:** Approved (design)
**Branch:** `fix/gif-slide-detection-builds`

## Problem

The GIF deploy path turns a Keynote-exported animated GIF into an interactive slide
viewer (step through slides; builds/transitions animate). Slide boundaries are
detected client-side in the deployed viewer by a frame-diff "quiet run" algorithm.

That detection is **not reliable across decks**. Proven empirically against a known
39-slide deck (headless, canvas-exact diffs): when a deck holds in-slide build/fade
states as long as real slide states — common on constant-background decks — **no
frame-derived signal separates "real slide" from "animation step."** Four signals
tested and rejected:

- **Diff magnitude** — build/fade gaps (1.0–1.9) overlap real transitions (also ~1.3+).
- **Spatial extent** (fraction of pixels changed) — constant background makes distinct
  slides look like builds (both change only a small text region).
- **Hold length** — a phantom "The Work" divider fade-stage is held 32–33 frames, the
  same as real slides, while a *real* slide is held only 12 frames.
- **Frame timing** — Keynote exports a constant 30ms/frame GIF; a hold is just many
  identical frames (no timing signal beyond what diff already sees).

The information "which hold is a real slide" is not recoverable from the rendered GIF
frames alone. Threshold tuning that hits one deck (e.g. `TRANSITION_PEAK = 0.9` → 39)
is overfitting and misaligns other decks.

**Non-negotiable:** animated slide deploy is the product. The GIF (builds, transitions)
must still play in full. Static per-slide images are NOT a deliverable — they were only
ground-truth for verification. The fix must keep the animation and get boundaries right
for ANY deck (variable count, builds, styles).

## Solution overview

Two changes:

1. **Move boundary determination from the deployed viewer (client-side) into the app
   (build-time), and bake the resulting boundary list into the generated viewer HTML.**
   The deployed viewer stops detecting; it plays the GIF and snaps Next/Prev to the
   baked stops. This is the enabling change for everything below, and it also lets the
   viewer lazy-decode only the frames it shows (fixes the slow client-side parse).

2. **Three boundary *sources*, user-selectable per deck**, all producing the same
   boundary list:
   - **Auto** — existing diff detection (build-merge kept) as a *best-effort seed*.
   - **Stills (C)** — match a folder of per-slide exports to GIF frames → exact boundaries.
   - **Manual (D)** — thumbnail grid; remove false stops / insert missing ones.

Animation always plays in full; only the stop points differ between sources.

## Data model

The single shared artifact is the **boundary list**, the existing `DetectedSlide[]`
shape (`src/types` / `slideDetection.ts`):

```ts
interface DetectedSlide {
  restFrame: number                                   // frame to show when stopped on this slide
  holdStart: number
  holdEnd: number
  transitionFrames: { start: number; end: number } | null  // frames to animate when entering
}
```

- **Auto** produces it from diffs (today's `detectSlides`).
- **Stills** produces it from still→frame matches.
- **Manual** produces it by editing an Auto seed.

The deployed viewer receives this array baked into the HTML (JSON literal) instead of
computing it.

## Components

### 1. In-app GIF decode (renderer) — exists, reused
`GifViewer.tsx` already decodes the GIF to frames for the in-app preview. All three
boundary sources run in the renderer where frames + a canvas are available. No second
decoder.

### 2. Boundary sources

**Auto (conservative).** `detectSlides(diffs)` stays, but `TRANSITION_PEAK` reverts from
the overfit `0.9` to a **precision-first** default that only merges unambiguous
micro-builds (clearly-tiny gaps) and never risks merging a real slide. Auto's job is now
a *seed*, not a correct answer. The confirm screen shows the detected count with an
explicit "verify this — Auto is best-effort" note. (The build-merge work from this branch
is retained; it improves the seed for decks without held fades.)

**Stills (C).** User picks a folder of per-slide images (the exports Keynote already
produces). Algorithm:
- Enumerate images, **natural-sort** by filename (`.001, .002, …` / `1,2,10`), accept
  `jpg/jpeg/png/webp`. The image count `N` is authoritative (it is the slide count).
- For each still `i` (downsampled to the diff sample grid), find the GIF frame with the
  minimum mean-abs pixel difference, **constrained monotonic**: frame(i) > frame(i−1).
  Search frame(i) only in `(frame(i−1), lastFrame]`.
- The matched frame is `restFrame`; `holdStart/holdEnd` derive from the quiet run
  containing it (reuse `findQuietRuns` to snap to the surrounding hold);
  `transitionFrames` = the gap from the previous slide's `holdEnd`.
- Produces exactly `N` slides, in order, for any deck.

**Manual (D).** Thumbnail grid editor:
- Seed the grid from Auto's `DetectedSlide[]`; render each stop's `restFrame` as a thumbnail.
- **Remove** a false stop (✕ on a thumbnail).
- **Insert** a missing stop: scrub the GIF to a frame, "insert stop here" → a new
  `DetectedSlide` at that frame (hold range snapped via `findQuietRuns`; transition recomputed).
- Live slide count. "Deploy" uses the edited array.

### 3. Generator — bake boundaries, drop client detection
`generateGifViewerHtml(gifFilename, secureEmbed, slides)` gains the `slides` argument.
The emitted viewer:
- No longer runs the diff/quiet-run/merge detection client-side.
- Embeds `slides` as a JSON literal.
- Still decodes the GIF for rendering, but **lazy-decodes** the `restFrame`s on demand
  (and transition ranges during playback) instead of a full upfront scan.
- Nav (Next/Prev/dots/keyboard) and transition playback consume the baked `slides`.

`gif-slide-viewer.html` (standalone) and `GifViewer.tsx` (in-app preview) consume the
same `DetectedSlide[]`; the in-app preview already does.

### 4. Deploy flow — boundary-source selector
The GifViewer confirm phase gains a boundary-source choice: **Auto / Stills (pick
folder) / Manual (grid)**. The selected source produces `slides[]`, passed through the
existing `deploy-gif` IPC to `generateGifViewerHtml`.

## Data flow

```
GIF dropped → decode (renderer) → frames + diffs
   ├─ Auto:   detectSlides(diffs)                 → slides[]
   ├─ Stills: matchStillsToFrames(folder, frames) → slides[]
   └─ Manual: edit(Auto seed) in thumbnail grid   → slides[]
                                                       │
Deploy → deploy-gif IPC (slides[]) → generateGifViewerHtml(gif, secure, slides)
       → bake slides JSON into viewer HTML → deploy to Vercel
Deployed viewer: play GIF, snap Next/Prev to baked slides (no detection)
```

## Error handling

- **Stills folder empty / no images** → error, fall back to Auto/Manual; do not deploy 0 slides.
- **Still match non-monotonic / ambiguous** (a still matches a frame ≤ previous) → flag the
  affected still index; let the user drop into Manual to fix, rather than deploy a bad order.
- **Stills count differs from Auto count** → stills win silently (authoritative); surface
  both numbers so the user notices a gross mismatch.
- **Manual: zero stops** → block deploy ("add at least one slide stop").
- **Auto seed empty** (`slides.length < 2`) → keep today's warning; Manual still lets the
  user build stops by hand.
- **Baked `slides` missing/empty in viewer** → viewer shows the whole GIF as one slide
  (existing fallback) rather than crash.

## Testing

- **Unit (`slideDetection.ts` + new matcher):** `detectSlides` conservative threshold
  (real slides never merged on the calibration deck); `matchStillsToFrames` returns N
  monotonic boundaries for a synthetic frames/stills fixture; natural-sort ordering.
- **Headless browser (puppeteer, established this session):** generated viewer with a
  baked `slides[]` renders each stop, Next/Prev/dots/keyboard land on the right frames,
  transitions play, last slide clean, no console errors.
- **Stills end-to-end on the real 39-slide deck:** match the 39 supplied stills → expect
  39 boundaries; render each stop; **compare against the stills** (the contact-sheet
  method from this session) → every rendered stop matches its still (no off-by-one).
- **Deck-agnostic check:** run Stills + Auto on at least one *additional* real deck
  (different count/style) to confirm no overfitting; record results.
- **Build:** `npx vite build` exit 0; Swift unaffected (Electron-only feature).

## Out of scope (YAGNI)

- Swift parity for the new sources (Electron-only for now; note in PARITY.md).
- Auto-detecting *which* source to use — the user chooses.
- Editing transition styles/durations — playback uses the GIF's own frames as-is.
- A second still-matching metric — start with mean-abs on the diff grid; revisit only if
  a real deck defeats it.

## Notes

- Keep the build-merge commit on this branch; this spec builds on it.
- The deployed viewer's removal of client-side detection also resolves the slow-parse
  UX issue observed on raw (unoptimized) Keynote exports.
