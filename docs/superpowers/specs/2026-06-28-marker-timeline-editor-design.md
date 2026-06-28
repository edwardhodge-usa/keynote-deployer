# Marker / Timeline Editor — Design (v1.3.0)

**Date:** 2026-06-28
**App:** Keynote Deployer (swift-app, Swift 6.2 / SwiftUI / macOS 15+)
**Status:** Design approved — pending writing-plans

## Problem

The video deck viewer rests on a "settled" frame between slides. Those rest
frames are auto-derived by DP-matching each clean per-slide still to its best
video frame (`VideoTimestampDeriver` → `VideoAnalysis.timestamps`). On some
slides the auto-match lands on or near a transition, so the viewer pauses on a
half-rendered/animating frame. The v1.2.1 attempt to patch this with a global
`REST_BIAS` constant (0 and 0.08 both tried) **cannot** fix it — different slides
need different offsets. The only fix is a human picking the true settled frame
per slide.

## Goal

A **Review Markers** phase in the Deploy Video tab, between Analyze and Encode:
show the auto-derived per-slide markers on a filmstrip + big live preview; let
the user drag / add / remove each marker with an exact-frame preview before
encoding. The approved marker becomes **BOTH** the viewer rest point **AND** the
forced encoder keyframe — a single source of truth that retires `REST_BIAS` and
the off-keyframe-seek bug class.

## Key decisions (from brainstorm)

1. **Marker ops:** adjust + add + remove. The edited marker list becomes the
   **authoritative** slide set. Stills are only the *seed* (DP-match); once a
   human edits, the marker list IS the truth. `slideCount = markers.count`,
   decoupled from `stillURLs.count`.
2. **Marker semantics:** one marker per slide = that slide's settled/hold frame,
   used as both the forced keyframe and the viewer rest point.
3. **Layout:** filmstrip + big preview (video-editor pattern) — large live
   preview on top, scrubber below, horizontal thumbnail filmstrip at the bottom.
4. **Persistence:** none (per-deploy review step). A fresh Keynote re-export
   changes frame indices, so saved markers wouldn't map to a new file anyway.
5. **REST_BIAS → 0** in the viewer; poster extracts at `markers[0]` exactly.

## Architecture & data flow

Split analysis out of the deploy pipeline so markers can be reviewed before
encode.

**Before:** `VideoDeployer.deploy` ran Step 1 (analyze → timestamps) → Step 2
(encode) → Step 3 (generate) → Step 4 (Vercel) as one call.

**After:**
- `VideoDeployer.analyze(request:seams:onProgress:) async throws -> VideoAnalysis`
  — probe + DP-match only. Returns the seed `VideoAnalysis` (timestamps,
  frames, width, height, fps).
- `VideoDeployer.deploy(request:analysis:timestamps:seams:onProgress:) async
  throws -> VideoDeployResult` — Steps 2–4, takes the **human-edited**
  `[Double]` timestamps instead of re-deriving. `slideCount = timestamps.count`.

The edited marker list is the same `[Double]` that already flows to the encoder
(forced keyframes), the viewer (`{{TS}}`), and the poster. Small blast radius —
markers ride the existing pipe.

**State machine** (`VideoDeployView.Phase`):
`drop → confirm → analyzing → reviewMarkers → deploying → complete` (+ `error`).
- `analyzing`: spinner while `analyze()` runs; on done, seeds the editor.
- `reviewMarkers`: hosts `MarkerEditorView`.

## Editor component — `MarkerEditorView`

SwiftUI view shown in the `reviewMarkers` phase. Three regions:

**Live preview (top)** — `AVPlayerView` via `NSViewRepresentable` (the pattern
already used in the viewer). One `AVPlayer` over the source video. Exact-frame
seek: `player.seek(to:toleranceBefore:.zero, toleranceAfter:.zero)`. Shows the
selected slide's current marker frame.

**Scrubber + buttons (middle)** — a slider bound to the selected marker's time.
Drag = live `player.seek` + update `markers[sel]`. Range **clamped to
`(markers[sel-1]+ε, markers[sel+1]-ε)`** so markers stay strictly increasing and
can't cross. Readout shows `time / frame#`.
- `[+ add]`: insert a marker at the current playhead (splits the gap → new
  slide). Keeps array sorted + monotonic.
- `[− remove]`: delete the selected marker. Guarded so N never drops below 1.

**Filmstrip (bottom)** — horizontal scroll of N thumbnails (one per marker),
generated once on entry via
`AVAssetImageGenerator.generateCGImagesAsynchronously` (batch, off-main). Tap a
thumb → selects that slide; preview + scrubber jump to it. Selected thumb
highlighted. After a marker moves, only that one thumb regenerates.

**Footer:** `[Encode & Deploy]` (uses edited markers) + `[Back]`.

**State:** `@State markers: [Double]`, `@State selected: Int`,
`@State thumbs: [Int: NSImage]`.

**Pure logic** extracted to a `MarkerEditorLogic` enum (no AVFoundation) for unit
tests: insert / remove / clamp / monotonic assertions.

## REST_BIAS retirement, viewer, poster

Why it works: the DP-match maps each clean settled still to its best video frame,
so the seeded `timestamps[i]` is already meant to be the settled frame. The
`REST_BIAS=0.08` backup was a global patch for auto-matches that landed near a
transition. A human marker eliminates the guess → bias unneeded.

**Viewer template** (`Sources/Resources/video-viewer-template.html`):
- `REST_BIAS = 0` — settle exactly on `TS[i]` (may collapse `restTime()` to
  identity). Marker = keyframe = rest point.
- `next()` plays `TS[i] → TS[i+1]`, settles on `TS[i+1]` (a forced keyframe →
  crisp seek). **Keep unchanged from 1.2.1:** iOS wall-clock stop, `navBusy`
  re-entrancy lock, in-memory blob loader, poster, edge-tap.
- Golden fixtures (`Tests/Fixtures/video-viewer-golden-*.html`) regenerate for
  the `REST_BIAS=0` output.

**Poster** (`VideoDeployer` Step 3A): extract at `markers[0]` exactly (was
`markers[0] - 0.08`).

**Encoder:** no change — already forces keyframes at the `[Double]` timestamps
(AVFoundation `CMSetAttachment(ForceKeyFrame)` / ffmpeg `-force_key_frames`).
Edited markers just flow in via `forcedKeyframeFrameIndices`.

## Testing

- `MarkerEditorLogic` unit tests: insert/remove/clamp, monotonic invariant,
  can't-cross-neighbors, add splits gap, remove guarded at N=1.
- `VideoDeployer` split: `analyze` returns the seed; `deploy(timestamps:)`
  honors the edited list; `slideCount == timestamps.count`.
- `VideoViewerGenerator` + ffmpeg arg parity re-asserted at `REST_BIAS=0`.
- **Live gate (mandatory):** real 39-slide deck → edit a few markers → encode →
  deploy → verify on **iPhone in a cross-origin iframe**
  (`wrapper-iota-ten.vercel.app` rig): rest frames land on settled slides,
  transitions smooth. This is the open 1.2.1 problem — only a real-device run
  confirms it.

## Out of scope (YAGNI)

- Persistence / sidecar marker files.
- Per-slide REST_BIAS.
- Audio.
- Slide reordering.

## Files touched

- `Sources/Services/VideoDeployer.swift` — split `analyze` / `deploy(timestamps:)`;
  poster at `markers[0]`; `slideCount = timestamps.count`.
- `Sources/Views/VideoDeployView.swift` — add `analyzing` + `reviewMarkers`
  phases; host editor; wire seed → edit → deploy.
- `Sources/Views/MarkerEditorView.swift` — **new** (filmstrip + preview +
  scrubber).
- `Sources/Services/MarkerEditorLogic.swift` — **new** (pure marker-list logic).
- `Sources/Resources/video-viewer-template.html` — `REST_BIAS = 0`.
- `Tests/Fixtures/video-viewer-golden-*.html` — regenerate.
- `Tests/MarkerEditorLogicTests.swift`, `Tests/VideoDeployerTests.swift`,
  `Tests/VideoViewerGeneratorTests.swift`, `Tests/FFmpegVideoEncoderTests.swift`
  — update/add.
- `swift-app/project.yml` — version bump to 1.3.0.
