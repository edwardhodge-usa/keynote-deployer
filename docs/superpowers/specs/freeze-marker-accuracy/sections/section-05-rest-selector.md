I have all the context needed. Let me write the section content.

# section-05-rest-selector

## Goal

Create a new **pure** module `RestSelector` that picks the **Rest frame** (the settled, sharp frame a viewer pauses on) inside a known hold span `[start, end]`. The Rest frame is the **temporally-calmest** frame (argmin of the consecutive diff signal over the interior of the hold), with ties broken by **maximum sharpness** (variance-of-Laplacian on the luma grid) so a half-faded / motion-blurred frame never wins over a crisp held frame.

This fixes the failure mode where Rest lands on a mid-transition or blurry frame. It honors margins (never returns the exact hold edges when interior frames exist) and is degenerate-hold safe (a 1–2 frame hold returns a valid in-range frame, no crash).

This section is **pure over `[[Double]]` grids** → fully offline unit-testable. No video decode, no UI, no file I/O.

## Background context (self-contained)

**Keynote Deployer** (macOS, Swift 6.2 / SwiftUI, `swift-app/`) computes, for each slide of an exported deck video, a `SlideMark { holdStart: Int, holdEnd: Int }` pair in **video frame indices**:
- **Rest (`holdStart`)** — the settled frame the viewer pauses on for that slide.
- **Go (`holdEnd`)** — the frame where the outgoing transition begins.

The detection pipeline is all pure functions over downsampled frame grids:

```
video ─► GridSampler.sample → frameGrids [[Double]]   (one 32×18×3 sRGB grid per frame)
stills ► GridSampler.sample → stillGrids [[Double]]
            │
   StillsMatch.matchStillsToFrames → anchors [Int]
            │
   HoldDetector.detect(...) → [SlideMark]   ← section-07 orchestrates BoundaryDetector + RestSelector
```

`RestSelector` is the **Rest-picking** stage. Section-07's rewritten `HoldDetector` calls it once per slide with that slide's hold range to choose `holdStart`.

### Grid format (critical — do not normalize)

`GridSampler` emits **raw RGB doubles in `0.0...255.0`** (NOT normalized to 0–1), 32 wide × 18 high × 3 channels = **1728 values per frame**, interleaved or planar per the existing `GridSampler` convention. Constants:

```swift
enum GridSampler {
    static let width = 32       // 32 columns
    static let height = 18      // 18 rows
    static let channels = 3     // R, G, B
    static func sample(_ image: CGImage) -> [Double]   // 1728 raw RGB doubles, 0.0...255.0
}
```

A single grid therefore has `32 * 18 = 576` pixels, each with 3 channels.

## Dependency on section-03 (FrameSignal)

This section depends on **section-03-frame-signal**, which provides the pure `FrameSignal` module. You consume two things from it; do **not** re-implement them:

1. **`FrameSignal.diffSignal(_ frameGrids:)` → `[Double]`** — the per-adjacent-pair multi-channel diff signal. `diffSignal.count == frameGrids.count - 1`. Entry `i` is the diff between frame `i` and frame `i+1`. This is the "temporal calmness" signal the RestSelector minimizes over. **Section-07 computes this once for the whole deck and passes it in** — `RestSelector.restFrame` receives the already-computed `diffSignal` as a parameter (do not recompute it per hold).

2. **`FrameSignal.channels(_ grid:) → FrameChannels`** where:
   ```swift
   struct FrameChannels { let luma: [Double]; let sat: [Double]; let chroma: [Double] }
   ```
   `luma` is the per-cell brightness `Y = 0.299R + 0.587G + 0.114B`, one value per grid cell → a **576-element** array representing the 32×18 luma image (row-major). You use **only** `luma` for the sharpness (variance-of-Laplacian) tie-break.

> If section-03 is not yet merged when you start, you may stub a minimal local luma extractor for your tests, but the production `restFrame` must call `FrameSignal.channels(...).luma`. Confirm the exact `FrameChannels` shape against the merged section-03 before finalizing.

## File to create

- `swift-app/Sources/Services/RestSelector.swift` — the pure module.
- `swift-app/Tests/RestSelectorTests.swift` — the Swift Testing suite (write FIRST).

After adding files, regenerate the project: `cd swift-app && xcodegen generate` (new files change the Xcode project), then build/test via the **apple-platform-build-tools builder agent** with the canonical command:

```
cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS"
```

## Tests FIRST

Framework is **Swift Testing** (`@Test` / `@Suite` / `#expect`), matching the existing `Tests/`. Build small synthetic grid sequences inline (no video decode). Tests are written before the implementation; the implementer writes the concrete assertions. Add to `swift-app/Tests/RestSelectorTests.swift`:

```swift
import Testing
@testable import KeynoteDeployer   // confirm the module name against existing Tests/ files

@Suite("RestSelector")
struct RestSelectorTests {

    // Test: within a hold whose middle frames are calm and edges are moving,
    // `restFrame` returns an INTERIOR (calm) frame, not an edge frame
    // (no trailing-edge seek-back). Build frameGrids/diffSignal so the
    // minimum diff sits at an interior index of [start, end].
    @Test func picksCalmInteriorFrameNotEdge() async throws { }

    // Test: given two equally-calm candidate frames (equal local diff) where one
    // is a blurred / low-contrast variant, the SHARPER frame (higher
    // variance-of-Laplacian on the luma grid) wins the tie.
    @Test func sharperFrameWinsTheTie() async throws { }

    // Test: margin respected — never returns `start` or `end` when interior
    // frames exist (margin default = 1).
    @Test func marginRespectedWhenInteriorExists() async throws { }

    // Test: degenerate 1–2 frame hold returns a valid in-range frame, no crash
    // (margin would collapse the interior to empty → fall back to the calmest
    // available in-range frame, clamped to the hold).
    @Test func degenerateShortHoldReturnsInRangeFrame() async throws { }
}
```

Notes for constructing fixtures:
- A "calm" frame pair → near-identical adjacent grids → near-zero `diffSignal` entry. A "moving"/edge frame → large diff entry.
- For the sharpness tie-break test, make two interior candidate frames have **equal** local diff, but one grid is a smooth/low-contrast blur (low VoL) and the other has sharp high-contrast edges (high VoL). The high-VoL one must be returned.
- Recall `diffSignal` is indexed over **pairs**: the "local diff" attributable to frame `f` should be derived from the diff entries adjacent to `f` (see implementation note below) — keep the test fixtures consistent with whichever convention the implementation uses, and document it.

## Implementation

Create `swift-app/Sources/Services/RestSelector.swift` as a stateless `enum` with static methods (matches the project's convention for stateless services). Signature from the plan:

```swift
enum RestSelector {
    /// Pick the Rest frame inside a hold [start, end]: the temporally-calmest frame
    /// (argmin local diff over [start+margin, end−margin]), tie-broken by max sharpness.
    /// Sharpness = variance-of-Laplacian on the luma grid — higher = sharper, rejects
    /// motion-blurred / mid-fade frames. Comparable only WITHIN one hold (content-dependent),
    /// never across. On the coarse 32×18 grid VoL is approximate; adequate to separate a
    /// held frame from a half-faded one.
    static func restFrame(in hold: Range<Int>,
                          diffSignal: [Double],
                          frameGrids: [[Double]],
                          margin: Int = 1) -> Int
}
```

### Algorithm

1. **Resolve the candidate window.** The hold is `hold: Range<Int>` (`start..<end` or treat `[start, end]` per section-07's convention — **confirm and match** how section-07 passes the hold; the plan's prose says hold `[start, end]`). Apply `margin`:
   - `lo = hold.lowerBound + margin`
   - `hi = hold.upperBound - margin` (exclusive/inclusive per your Range convention)
   - If applying the margin leaves **no interior frames** (degenerate 1–2 frame hold, or `lo >= hi`), fall back to the full hold range clamped to `[0, frameGrids.count)`. **Never crash, never return out of range.**

2. **Compute a per-frame "local diff" (calmness score)** for each candidate frame `f` from `diffSignal`. `diffSignal[i]` is the diff between frames `i` and `i+1`, so frame `f`'s temporal calmness is best captured by combining the diff entering it (`diffSignal[f-1]`) and leaving it (`diffSignal[f]`) — e.g. `localDiff(f) = diffSignal[f-1] + diffSignal[f]` with boundary guards (clamp indices into `0..<diffSignal.count`; for the very first/last frame use the one available adjacent entry). **Pick one convention, document it in a comment, and keep tests consistent with it.** A calm held frame has both adjacent diffs near zero → minimal `localDiff`.

3. **Argmin over candidates.** Choose the candidate frame with the **minimum** `localDiff`. This is the settled frame.

4. **Tie-break by sharpness (variance-of-Laplacian on luma).** When two or more candidates are within a small epsilon of the minimum `localDiff` (use a relative/absolute epsilon — values are diff magnitudes, not normalized), compute sharpness for each tied candidate and pick the **maximum**:
   - Extract the luma grid: `let luma = FrameSignal.channels(frameGrids[f]).luma` — a 576-element row-major 32×18 image.
   - **Variance-of-Laplacian (VoL):** apply the discrete Laplacian kernel to the 32×18 luma image, then return the variance of the Laplacian response:
     ```
     L(x,y) = 4·luma[x,y] − luma[x−1,y] − luma[x+1,y] − luma[x,y−1] − luma[x,y+1]
     VoL    = variance over all interior (x,y) of L
     ```
     Skip border cells (no neighbors) or zero-pad — pick one and keep it; on a 32×18 grid the interior is 30×16. Higher VoL = sharper edges = crisper frame; a half-faded/blurred frame has a near-flat luma image → low VoL.
   - VoL is **only comparable WITHIN one hold** (it is content-dependent) — never compare VoL across different slides/holds.

5. **Return** the chosen absolute frame index (an `Int` in `[0, frameGrids.count)`).

### Edge / safety rules (must hold)

- Always return an index in `[0, frameGrids.count)` and, whenever interior frames exist, **strictly inside** the hold (never `start` or `end`).
- Degenerate holds (1–2 frames, or margin collapses the interior): return the calmest in-range frame clamped to the hold — no crash, no out-of-range.
- Empty / mismatched inputs: guard against `frameGrids.isEmpty` and `diffSignal.count != frameGrids.count - 1` defensively (clamp index access).
- **Pure & cheap:** O(holdLength × 576) for the diff argmin and O(tied × 576) for VoL — same order as the rest of the pipeline. No allocations beyond the small luma slices. Must run off the main thread (the caller, section-07, owns threading; this function is synchronous and pure).

## How section-07 consumes this (reference only — do not implement here)

Section-07's rewritten `HoldDetector.detect(...)` computes the deck-wide `diffSignal` once (via `FrameSignal`), determines each slide's hold span from `BoundaryDetector`, then calls `RestSelector.restFrame(in: hold, diffSignal:, frameGrids:)` to set that slide's `holdStart`. The **first slide** hold is `[0, transitions[0].start]` (handles a fade-in/leader); the **last slide** hold runs to `frameCount − 1`. You only need to make `restFrame` correct for an arbitrary `[start, end]` hold; section-07 supplies the edges.

## Definition of done

- `swift-app/Sources/Services/RestSelector.swift` created (pure `enum`, the signature above).
- `swift-app/Tests/RestSelectorTests.swift` created with the four tests above (calm-interior, sharper-wins-tie, margin-respected, degenerate-hold-safe), all passing.
- `xcodegen generate` run; full suite green via the builder agent.
- No changes to `GridSampler` output shape; no normalization introduced; consumes `FrameSignal` from section-03 for luma.

---

Relevant files for this task:
- Create: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/RestSelector.swift`
- Create: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/RestSelectorTests.swift`
- Depends on (section-03): `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/FrameSignal.swift` (`FrameSignal.diffSignal`, `FrameSignal.channels(...).luma`, `FrameChannels`)
- Consumed by (section-07): `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/HoldDetector.swift`

Key load-bearing facts: grids are raw RGB `0.0...255.0` (32×18×3 = 1728 values; 576 cells); `diffSignal.count == frameGrids.count - 1` indexed over adjacent pairs; sharpness = variance-of-Laplacian on the 576-element row-major luma image, comparable only within a single hold.