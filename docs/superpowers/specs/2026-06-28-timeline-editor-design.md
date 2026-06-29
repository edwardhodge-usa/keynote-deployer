# Timeline Editor (frame-accurate hold spans) — Design (v1.3.0)

**Date:** 2026-06-28
**App:** Keynote Deployer (swift-app, Swift 6.2 / SwiftUI / macOS 15+)
**Status:** Design approved — supersedes the single-marker editor (filmstrip) merged earlier today.

## Problem

The first marker editor modeled each slide as ONE rest point. A single point can
land on a transition, so the viewer still pauses on an animating frame — the exact
bug this feature exists to kill. The structure that actually matters is each
slide's **hold span** (the stable settled frames) bounded by the end of its
incoming animation and the start of its outgoing animation. The user needs to see
that structure on a timeline and set it frame-accurately, watching the frame
render as they nudge.

## Goal

An After-Effects-style, frame-accurate timeline for the "Review Markers" phase.
Each slide is a hold span on a continuous frame timeline; transitions are the gaps
between holds. The user selects a marker, steps it ±1 frame (buttons + ←/→ keys),
and the preview re-renders that exact frame so they can confirm it's right. The
hold span drives both the encoder's forced keyframes and the viewer's rest +
transition playback, guaranteeing rest lands inside the hold.

## Key decisions (from brainstorm)

1. **Marker semantics:** forced keyframe + viewer rest at each slide's
   `holdStart` (first settled frame). Pressing **Next** seeks to this slide's
   `holdEnd` (a forced keyframe, the start of the outgoing animation), then plays
   the real transition and stops at the next slide's `holdStart`. Prev / dot-jump
   seek `holdStart`. This skips replaying the static hold and guarantees rest is
   inside the hold.
2. **Boundary source:** auto-detect (best-effort seed), then hand-tune. Stills
   DP-match still owns slide **count** + a per-slide anchor frame; a new
   `HoldDetector` refines each slide's hold span around its anchor via frame-diff.
   The constant-bg detection caveat (CLAUDE.md) does not bite — detection is a
   tunable seed, not authoritative.
3. **Editing unit = the frame.** All marks are Int frame indices; seconds derive
   (`frame/fps`, exact 3dp) only at the deploy boundary.
4. **Interaction:** click a marker → preview shows its frame; ±1-frame buttons and
   ←/→ keys nudge the selected marker → preview re-renders that exact frame
   instantly (zero-tolerance `AVPlayer.seek`).

## Data model

```swift
/// One slide's stable hold span, in VIDEO FRAME INDICES. The transition between
/// slide i and i+1 is the gap (holdEnd_i, holdStart_{i+1}).
struct SlideMark: Sendable, Equatable {
    var holdStart: Int   // first settled frame (rest + forced keyframe)
    var holdEnd: Int     // last settled frame / start of outgoing animation
}
```

Invariant across `[SlideMark]`: `0 <= holdStart_i <= holdEnd_i < holdStart_{i+1}`
and `holdEnd_last < frameCount`. Strictly ordered, non-overlapping, frame-distinct.

## Pipeline & contracts

- **analyze()** (unchanged shape) returns a seed `VideoAnalysis` PLUS a seed
  `[SlideMark]`. It runs the existing stills DP-match (slide count + anchor frame
  per slide) then `HoldDetector` to widen each anchor into a hold span. Concretely
  `analyze` returns the existing `VideoAnalysis` and the seed marks are derived by
  `HoldDetector.detect(frameGrids:anchors:frameCount:)` — keep `analyze`'s return
  as `VideoAnalysis` and add the marks as a second returned value
  `(VideoAnalysis, [SlideMark])`.
- **deploy(...marks: [SlideMark], fps: Double, ...)** replaces the
  `editedTimestamps: [Double]` parameter. It derives:
  - **forced keyframes** = sorted unique union of every `holdStart` and `holdEnd`,
    each `frame/fps` rounded 3dp → the `[Double]` `encodeWithKeyframes` already
    takes.
  - **viewer pairs** = `[[holdStartSec, holdEndSec], ...]` (3dp) → the new
    `{{TS}}` token.
  - `slideCount = marks.count`; poster extracts at `marks[0].holdStart / fps`.
  - Guards (defense-in-depth): throw `VideoDeployError.invalidMarkers` if `marks`
    is empty or violates the invariant.
- **frame ↔ second** conversion only at this boundary; `JSNumber.format` remains
  the sole JS/ffmpeg number formatter.

## HoldDetector (new service)

`enum HoldDetector` with
`detect(frameGrids: [[Double]], anchors: [Int], frameCount: Int) -> [SlideMark]`.

For each slide anchor (the DP-matched frame, already a settled frame): walk
outward while the frame-to-frame grid diff stays below a motion threshold → that
low-motion run is the hold; the first/last frames of the run are
`holdStart`/`holdEnd`. Clamp so spans don't overlap neighbors (split the gap at
the midpoint of adjacent anchors if runs collide). Pure over the injected grids
(the same 32×18 grids `GridSampler`/the encoder already produce) → unit-testable
offline. Best-effort: if a run can't be found, fall back to
`holdStart = holdEnd = anchor`.

## SlideMarkLogic (new pure logic)

`enum SlideMarkLogic`:
- `clamp(_ frame: Int, marker: MarkerRef, marks: [SlideMark], frameCount: Int) -> Int`
  — keep a moved boundary within its neighbors (`holdStart_i` in
  `[holdEnd_{i-1}+1, holdEnd_i]`; `holdEnd_i` in `[holdStart_i, holdStart_{i+1}-1]`;
  ends clamp to `[0, frameCount-1]`). `MarkerRef = (slide: Int, edge: .start | .end)`.
- `split(at frame: Int, marks: [SlideMark]) -> [SlideMark]` — split the hold span
  containing `frame` into two slides at that frame.
- `merge(slide i: Int, marks: [SlideMark]) -> [SlideMark]` — merge slide i with
  i+1 into one hold span (`holdStart_i … holdEnd_{i+1}`). Guarded at count 1.
- `isValid(_ marks: [SlideMark], frameCount: Int) -> Bool` — the full invariant.

## TimelineEditorView (new SwiftUI view)

Replaces `MarkerEditorView`. Init:
`init(player: AVPlayer, videoURL: URL, frameCount: Int, fps: Double, initialMarks: [SlideMark], onConfirm: @escaping ([SlideMark]) -> Void, onBack: @escaping () -> Void)`.

Regions:
- **Live preview (top):** `VideoPreview` (existing AppKit `AVPlayerView`
  NSViewRepresentable). Shows the selected marker's exact frame. Readout: `frame N
  · t.ttts · slide i/N · (holdStart|holdEnd)`.
- **Frame stepper:** `[◀ −1]` / `[+1 ▶]` buttons + ←/→ key handling. Each nudges
  the selected marker one frame, clamps via `SlideMarkLogic.clamp`, and seeks the
  player zero-tolerance to that frame so the preview re-renders instantly.
- **Timeline (scroll/zoom):** the whole video, frames left→right. Holds = solid
  blocks, transitions = gaps. Each hold shows two draggable handles (holdStart,
  holdEnd). Click a handle → selects it + preview jumps to its frame. Selected
  handle highlighted. Drag = continuous clamp + live preview.
- **Slide ops:** `[⊕ Split]` (split the hold at the playhead),
  `[⊖ Merge]` (merge selected slide with next), `[⟲ Re-detect]` (re-run
  HoldDetector seed).
- **Footer:** `[Back]` → `.confirm`; `[Encode & Deploy]` → `onConfirm(marks)`,
  disabled unless `SlideMarkLogic.isValid`.

State: `@State marks: [SlideMark]`, `@State selected: MarkerRef`. Pure edits go
through `SlideMarkLogic`.

## Viewer template playback rewrite

`video-viewer-template.html` becomes hold-span aware. `{{TS}}` token → a pairs
array `var SPANS = [[hs,he],...]` (seconds). Behavior:
- `settleOn(i)` / `prev` / `jump(i)` → seek `SPANS[i][0]` (holdStart), paused.
- `next()` → seek `SPANS[current][1]` (holdEnd, a forced keyframe), play, stop at
  `SPANS[current+1][0]` (next holdStart), settle.
- The boundary watcher's stop target = `SPANS[current+1][0]`.
- **Preserve verbatim:** in-memory blob loader, `navBusy` lock, the `setInterval`
  wall-clock stop (iOS `currentTime=0`-in-cross-origin-iframe), `paintFrame`
  micro-play, `<video poster>`, edge-tap. Only seek targets change.
- Poster at `SPANS[0][0]`. `REST_BIAS` removed (rest is exactly holdStart).
- Goldens regenerate for the pairs `{{TS}}`.

## Keep / replace

**Replace:** `MarkerEditorView` → `TimelineEditorView`; `MarkerEditorLogic`
(+tests) → `SlideMarkLogic` (+tests). Remove the `editedTimestamps` deploy path.
**Keep:** `analyze()`/`deploy()` split shape, `VideoDeployer`/`VideoDeployerSeams`
/`VideoDeployResult`, the ffmpeg `terminationHandler` fix (de1d8d3),
`VideoPreview`, `VideoTimestampDeriver` (stills→anchors), `GridSampler`,
`AVFoundation`/`FFmpeg` encoders.
**New:** `SlideMark` model, `SlideMarkLogic`, `HoldDetector`, `TimelineEditorView`.

## Testing

- `SlideMarkLogic` unit tests: clamp within neighbors (both edges, ends),
  split-at-frame, merge (+guard at count 1), isValid invariant.
- `HoldDetector` on a synthetic grid sequence with known hold/transition runs:
  correct spans; degenerate fallback to anchor.
- `VideoDeployer`: keyframe union (holdStart ∪ holdEnd, sorted/unique/3dp), viewer
  pairs derivation, `slideCount == marks.count`, invalidMarkers guard.
- `VideoViewerGenerator`: pairs `{{TS}}` fill + REST model goldens.
- **Visual/interaction gate (controller-driven on the Mac):** load a real deck →
  open timeline → click a marker (preview shows its frame) → step ±frames (preview
  changes) → confirm holds look right → Encode & Deploy → desktop viewer rests on
  settled frames and Next plays only the transition. (iPhone cross-origin pass
  remains the ultimate oracle but is deferred to the user.)

## Out of scope (YAGNI)

- Persistence / sidecar marks.
- Per-frame thumbnail strip rendering (the live preview is the frame oracle; the
  timeline blocks are schematic, not thumbnails).
- Audio, slide reordering beyond split/merge.

## Files

- New: `Sources/Models/SlideMark.swift`, `Sources/Services/SlideMarkLogic.swift`,
  `Sources/Services/HoldDetector.swift`, `Sources/Views/TimelineEditorView.swift`,
  `Tests/SlideMarkLogicTests.swift`, `Tests/HoldDetectorTests.swift`.
- Modify: `Sources/Services/VideoDeployer.swift` (analyze returns marks;
  deploy(marks:fps:)), `Sources/Services/VideoViewerGenerator.swift` (pairs
  {{TS}}), `Sources/Resources/video-viewer-template.html` (playback rewrite),
  `Sources/Views/VideoDeployView.swift` (host TimelineEditorView, pass marks),
  `Tests/VideoDeployerTests.swift`, `Tests/VideoViewerGeneratorTests.swift`.
- Remove: `Sources/Views/MarkerEditorView.swift`,
  `Sources/Services/MarkerEditorLogic.swift`, `Tests/MarkerEditorLogicTests.swift`.
</content>
