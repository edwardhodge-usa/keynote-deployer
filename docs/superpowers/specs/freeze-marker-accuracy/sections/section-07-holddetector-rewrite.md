I now have everything needed. The dependency section files (05, 06) don't exist yet (generated in parallel), so I'll reference their contracts from the plan. Here is the section content.

---

# Section 07 — HoldDetector Rewrite (orchestrate FrameSignal → BoundaryDetector → RestSelector)

## Goal

Rewrite `HoldDetector.detect` so it orchestrates the new pure detection layers (FrameSignal, BoundaryDetector, RestSelector) instead of the old fixed-threshold forward scan. The rewrite must:

1. Emit **exactly one mark per slide** — never silently drop a slide via anchor dedup (the count-loss bug). Two anchors colliding in one detected hold keep BOTH slides and are **flagged**, not merged away.
2. Set **explicit first-slide and last-slide boundaries** (no preceding / following transition).
3. Set a **low-confidence-anchor flag** when a DP anchor lands far from any detected hold (points the finger at `StillsMatch`, not the boundary layer).
4. Produce **strictly-increasing, valid** marks (`SlideMarkLogic.isValid` holds for realistic inputs).
5. Keep the `detect(...) -> [SlideMark]` entry shape so `VideoTimestampDeriver` and the timeline editor are unchanged in their consumption.

This is the integration section. Sections 03 (FrameSignal), 05 (RestSelector), and 06 (BoundaryDetector) provide the pure building blocks; this section wires them and replaces the old algorithm.

## Background (self-contained)

**Keynote Deployer** (macOS, Swift 6.2, `swift-app/`) turns a rendered presentation video + a folder of per-slide stills into an interactive deck viewer. For each slide it computes two video frame indices:

- **Rest (`holdStart`)** — the settled frame the viewer pauses on.
- **Go (`holdEnd`)** — the frame where the outgoing transition to the next slide begins.

The seed pipeline (all pure over downsampled `[[Double]]` frame grids, so offline-unit-testable):

```
video ─► GridSampler.sample → frameGrids [[Double]]  (one 32×18×3 sRGB grid per frame, every frame)
stills ► GridSampler.sample → stillGrids [[Double]]
            │
   StillsMatch.matchStillsToFrames → anchors [Int]   (DP align stills→frames, strictly increasing,
            │                                          one frame index per slide — the COUNT authority)
            ▼
   HoldDetector.detect(frameGrids, anchors, frameCount, ...) → [SlideMark]   ◄── THIS SECTION rewrites the body
            │
            ▼
   VideoTimestampDeriver.derive(...) wraps it → (VideoAnalysis, [SlideMark] seed)
```

**Grid format:** each grid is `32*18*3 = 1728` **raw RGB doubles in `0.0...255.0`** (NOT normalized). The FrameSignal channel formulas assume this 0–255 range — do not normalize.

**Existing types you depend on (do not change shape):**

```swift
struct SlideMark: Sendable, Equatable, Codable { var holdStart: Int; var holdEnd: Int }

// SlideMarkLogic.isValid: !empty AND for each mark holdStart in [0,frameCount), holdStart<=holdEnd,
// holdEnd<frameCount, AND marks[i-1].holdEnd < marks[i].holdStart (strictly increasing, frame-distinct).
```

### Why the rewrite (the bug being killed)

The old `HoldDetector` (see "Old behavior to delete" below) had two flaws:

- **Motion-diff is blind to fades on a dark background.** A cross-fade between two different dark images keeps per-frame mean-abs RGB diff below any fixed threshold, so the old forward scan never found Go and the old "expand a low-motion run" idea ran Rest backward into the *previous* transition (Rest landed mid-fade). The fix moves to FrameSignal's multi-channel (luma/sat/chroma) diff signal + BoundaryDetector's adaptive, twin-comparison + variance-vote span detection — which *sees* dark fades.
- **Silent dedup-drop loses the slide count.** The old code deduplicated equal anchors and dropped "unfittable" marks, so `marks.count < slideCount`. The new contract: one mark per slide, collisions flagged not dropped. The DP stills-match (`StillsMatch`, `anchors.count == slideCount`) stays the count authority.

## Dependencies (reference contracts — implemented in other sections)

Treat these as available. Do **not** re-implement them here; call them.

**Section 03 — `FrameSignal` (`Sources/Services/FrameSignal.swift`):**

```swift
enum FrameSignal {
    /// Consecutive-frame multi-channel diff (luma+sat+chroma), normalized weighted average.
    /// Returns ONE value per adjacent frame pair → diffSignal.count == frameGrids.count - 1.
    static func diffSignal(_ frameGrids: [[Double]], weights: ChannelWeights = .default) -> [Double]

    /// Per-frame spatial variance over the grid (monochrome/fade-dip signal). One value per frame.
    static func frameVariance(_ grid: [Double]) -> Double
}
```

**Section 06 — `BoundaryDetector` (`Sources/Services/BoundaryDetector.swift`):**

```swift
struct TransitionSpan { let start: Int; let end: Int; let kind: Kind
    enum Kind { case cut, gradual } }

enum BoundaryDetector {
    /// Transition spans over the diff signal. Spans are sorted, non-overlapping.
    /// span.start = outgoing transition start (the Go frame); span.end = settle frame (incoming slide begins).
    /// minHoldSeconds × fps = min-scene-length (resolution/framerate-independent).
    static func transitions(diffSignal: [Double],
                            variances: [Double],
                            fps: Double,
                            minHoldSeconds: Double = 0.5) -> [TransitionSpan]
}
```

**Section 05 — `RestSelector` (`Sources/Services/RestSelector.swift`):**

```swift
enum RestSelector {
    /// The settled+sharp Rest frame inside a hold: argmin local diff over [start+margin, end−margin],
    /// tie-broken by max variance-of-Laplacian (sharpness) on luma. Degenerate-hold safe (returns an
    /// in-range frame, never crashes; respects margin only when interior frames exist).
    static func restFrame(in hold: Range<Int>,
                          diffSignal: [Double],
                          frameGrids: [[Double]],
                          margin: Int = 1) -> Int
}
```

If a parallel section has not landed a building block yet, stub it minimally to compile; the real implementation arrives from its own section. Do not duplicate its logic.

## Files to modify

- `swift-app/Sources/Services/HoldDetector.swift` — **rewrite** the body of `detect`; add a detailed-result method + diagnostics struct.
- `swift-app/Sources/Services/VideoTimestampDeriver.swift` — **edit one line**: pass `fps` into `detect` (see "fps plumbing").
- `swift-app/Tests/HoldDetectorTests.swift` — **rewrite** to the new contract (remove the bug-encoding tests).

## fps plumbing

The new algorithm needs `fps` (BoundaryDetector's `minHoldSeconds × fps`, AdaptiveThreshold's fps-relative window inside section 06). The old signature had no fps. Add `fps: Double` to `detect` as a **defaulted** parameter (e.g. `= 30`) so source compatibility holds, and update the single call site in `VideoTimestampDeriver.derive` (currently line ~83):

```swift
// VideoTimestampDeriver.derive — fps is already in scope (it's a parameter of derive).
let marks = HoldDetector.detect(frameGrids: frameGrids, anchors: frames,
                                frameCount: frameGrids.count, fps: fps)
```

The old `motionThreshold` / `defaultTransition` parameters are **superseded** by the adaptive layer. Keep them in the signature ONLY if needed for source compatibility (existing tests reference them); mark them deprecated/ignored in a doc comment. Prefer removing them and updating the tests, since this section rewrites the tests anyway.

## New `HoldDetector` design

Keep `enum HoldDetector`. Provide:

```swift
/// One slide's seed plus the diagnostic flags the harness (Section 01) surfaces.
struct HoldDetection: Sendable, Equatable {
    let marks: [SlideMark]
    let collidedWithPrevious: [Bool]   // parallel to marks: two anchors fell in one detected hold
    let lowConfidenceMatch: [Bool]     // parallel to marks: anchor far from any detected hold (StillsMatch suspect)
}

enum HoldDetector {
    /// Primary entry (unchanged shape for VideoTimestampDeriver + the editor).
    static func detect(frameGrids: [[Double]],
                       anchors: [Int],
                       frameCount: Int,
                       fps: Double = 30) -> [SlideMark] {
        detectDetailed(frameGrids: frameGrids, anchors: anchors,
                       frameCount: frameCount, fps: fps).marks
    }

    /// Detailed entry used by SeedHarness for per-slide diagnostics. Returns marks + parallel flags.
    static func detectDetailed(frameGrids: [[Double]],
                               anchors: [Int],
                               frameCount: Int,
                               fps: Double = 30) -> HoldDetection { /* orchestration below */ }
}
```

`detect` delegates to `detectDetailed` and returns `.marks`, so the count/validity contract is identical and the harness (section 01) can read the flags it needs (`anchorCollidedWithPrevious`, `lowConfidenceMatch` in `PerSlideDiagnostic`).

### Orchestration algorithm

1. **Guards.** `guard !anchors.isEmpty, frameCount > 0 else { return HoldDetection(marks: [], ...) }`. Use `bound = min(frameCount, frameGrids.count)` as the shared upper limit (so `frameCount != frameGrids.count` can't desync clamps); guard `bound > 0`.

2. **Sort anchors but DO NOT dedup** (dedup was the bug). Clamp each into `[0, bound-1]`. Preserve duplicates so count is preserved.

3. **Build the signal layer (Section 03):**
   - `diffSignal = FrameSignal.diffSignal(frameGrids)` (count `bound-1`).
   - `variances = (0..<bound).map { FrameSignal.frameVariance(frameGrids[$0]) }`.

4. **Detect transition spans (Section 06):**
   - `spans = BoundaryDetector.transitions(diffSignal: diffSignal, variances: variances, fps: fps)`.
   - Spans are sorted & non-overlapping. They partition `[0, bound)` into **hold regions**:
     - `region[0]   = 0 ..< spans[0].start`
     - `region[k]   = spans[k-1].end ..< spans[k].start`  (1 ≤ k < spans.count)
     - `region[last]= spans[last].end ..< bound`
     - If `spans` is empty: a single region `0 ..< bound`.
   - Region count = `spans.count + 1`.

5. **Assign exactly one mark per anchor (slide).** For each slide `i` (in anchor order):
   - Find the hold region containing `anchors[i]`. If `anchors[i]` falls *inside* a transition span (not in any hold region), that is itself a low-confidence signal — snap it to the nearest hold region and set `lowConfidenceMatch[i] = true`.
   - **`holdEnd` (Go):**
     - Interior slide → the start of the transition that **follows** this slide's hold region = `spans[regionIndex].start`.
     - **Last slide (n−1)** → `holdEnd = bound - 1` (extends to video end; no following transition).
   - **`holdStart` (Rest):** `RestSelector.restFrame(in: subHold, diffSignal: diffSignal, frameGrids: frameGrids, margin: 1)` where `subHold` is this slide's hold range (see collisions). Rest is the settled+sharp frame — **never** the verbatim anchor, and never inside a transition span.
   - **First slide (0):** no preceding transition. `holdStart_0` = `RestSelector.restFrame(in: 0 ..< spans[0].start, ...)` (handles a leader / fade-in); `holdEnd_0 = spans[0].start`. If `spans` is empty, the single region spans the whole clip.

6. **Collisions (two anchors → one detected hold).** When two (or more) anchors map to the same hold region, keep **all** of them (count preserved). Split the shared region **deterministically** — e.g. at the midpoint between the consecutive colliding anchors — assign the earlier anchor the lower sub-hold and the later the upper. Set `collidedWithPrevious[i] = true` on the later slide(s). The synthetic split boundary is a flagged best-effort (no real transition there); the harness shows the collision so triage sees the count was preserved, not silently dropped.

7. **Low-confidence anchor.** When an anchor's distance to its assigned hold region exceeds a time threshold (≈ `1.0 * fps` to `2.0 * fps` frames), set `lowConfidenceMatch[i] = true`. This fingers `StillsMatch` (a wildly-wrong anchor), not BoundaryDetector. The count is still preserved (one mark per slide); the flag is a signal, not a drop.

8. **Final validity normalization.** Guarantee a strictly-increasing, frame-distinct result (`SlideMarkLogic.isValid`). Clamp each `holdStart` to `> previous holdEnd` and each `holdEnd` to `< next holdStart` and `< bound`. **Precedence:** strict validity is the hard invariant the editor relies on; count-preservation is required whenever frames allow (`anchors.count ≤ bound`, i.e. ≥1 frame per slide). For the pathological **over-packed** case (`anchors.count > bound` — impossible from real `StillsMatch`, only synthetic test inputs) you may drop the unfittable trailing marks to keep the result valid; document this as the single allowed exception.

### Old behavior to delete

Remove from `HoldDetector.detect`:
- The anchor **dedup** loop (`if deduped.last != v { deduped.append(v) }`) — caused count loss.
- The `motionThreshold` forward-scan (`while ... diff(...) < motionThreshold`) and `defaultTransition` fallback band.
- The final "drop any mark that can't fit" filter (replaced by the validity-normalization pass that drops ONLY in the impossible over-packed case).

Keep (or remove) the static `diff(_:_:)` helper only if still used; FrameSignal now owns the diff semantics.

## Tests FIRST — rewrite `swift-app/Tests/HoldDetectorTests.swift`

Framework: **Swift Testing** (`@Test` / `@Suite` / `#expect`), `@testable import KeynoteDeployer`. Synthetic grids are flat "color" grids; a transition is a value ramp (`private func grid(_ v: Double) -> [Double] { [Double](repeating: v, count: 32 * 18 * 3) }`). Write these BEFORE the implementation.

**Remove the bug-encoding test** `"duplicate anchors collapse to a single slide and stay valid"` — it asserted `marks.count == 1` for two anchors, which encodes the count-loss bug. Replace per below. Rewrite the other old tests (`restIsAnchorGoIsMotionOnset`, `fadeUsesDefaultTransition`, `degenerate`, `overPackedAnchorsStayValid`) to the new contract — the old exact magic frame numbers (e.g. `holdEnd == 3`, `holdEnd == 14`) came from the deleted fixed-threshold algorithm and no longer apply; assert the new invariants instead of those literals.

New / rewritten tests (assertions are the implementer's to fill; intent is fixed):

- **One mark per slide, always.** Even when two anchors collide in one detected hold, `marks.count == anchors.count` (no silent dedup-drop). The collision is **flagged** (`detectDetailed(...).collidedWithPrevious` has a `true` for the later colliding slide), not dropped. (This replaces the deleted `duplicateAnchors → count 1` test.)
- **Valid & strictly increasing.** For a normal synthetic deck, `SlideMarkLogic.isValid(marks, frameCount:)` is true: each `holdEnd < next.holdStart`, all within `[0, frameCount)`.
- **Edge boundaries.** First slide `holdStart` lands in `[0, transitions[0].start]`; last slide `holdEnd == frameCount - 1`.
- **Go == transition start.** For an interior slide, `holdEnd` equals the detected outgoing transition's `start`. Build a synthetic deck with a clear cut and assert Go sits at the cut.
- **Low-confidence flag.** Craft an anchor far from any detected hold (e.g. mid-transition or off in a long flat run with no matching slide) → `detectDetailed(...).lowConfidenceMatch` is `true` for that slide; count still preserved.
- **Rest never inside a transition span** (the original bug class) — over the captured **real fade-deck grid fixture** under `Tests/Fixtures/decks/` (produced by the harness, section 01), assert every mark's `holdStart` falls inside a hold region, never inside a `BoundaryDetector` transition span. If the captured fixture is not yet available when this section is implemented, write the test against a synthetic cross-fade-on-dark grid sequence and leave a clearly-named follow-up so section 08 (remeasure-and-validate) wires it to the real fixture.
- **Degenerate / empty inputs.** Empty anchors → empty marks (no crash). `frameCount == 0` → empty. A 1–2 frame hold yields a valid in-range mark (RestSelector is degenerate-safe).

## Verification

Build/test via the **apple-platform-build-tools builder agent** (one xcodebuild at a time). Canonical command:

```bash
cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS"
```

(`xcodegen generate` first because new files change the project.) The settled verdict is the **exit code**, not stdout. The unit tests prove the cases we imagined; the REAL-deck harness (section 08) is the accuracy oracle — both required. This section is blocked by 05 and 06, and blocks section 08.

---

Relevant file paths:
- Rewrite: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/HoldDetector.swift`
- One-line edit (fps plumbing, call site ~line 83): `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/VideoTimestampDeriver.swift`
- Test rewrite: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/HoldDetectorTests.swift`
- Consumed contracts (other sections): `FrameSignal.swift` (03), `RestSelector.swift` (05), `BoundaryDetector.swift` (06)
- Validity oracle (existing): `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/SlideMarkLogic.swift` (`isValid`)

One load-bearing constraint I verified in source: `VideoTimestampDeriver.derive` already has `fps` in scope and currently calls `HoldDetector.detect(frameGrids:anchors:frameCount:)` with no fps — adding a defaulted `fps:` param and passing the real `fps` at that one call site is the entire plumbing change. The current `SlideMarkLogic.isValid` requires `marks[i-1].holdEnd < marks[i].holdStart` (strictly increasing, frame-distinct) and `holdEnd < frameCount`, which the final normalization pass must guarantee.
---
## As-built notes (2026-06-29)
Rewrote HoldDetector as the orchestrator (FrameSignal→BoundaryDetector→RestSelector). `detectDetailed`
returns marks + collided/lowConfidence flags; `detect()` keeps the entry shape (+fps default).
Go = last span starting in [anchor, nextAnchor); Rest = RestSelector over the hold; first slide gets a
fade-in-aware Rest, last slide holdEnd = frameCount-1. Review-driven fixes: ROOM-RESERVING normalization
(one mark per anchor for all n≤bound — fixes the tail-cluster count-loss the old code had), distance-based
low-confidence, bound-horizon signal computation. 8 tests incl. count-preservation + Rest-not-in-transition.
126/126 green. VideoTimestampDeriver passes the real fps.
