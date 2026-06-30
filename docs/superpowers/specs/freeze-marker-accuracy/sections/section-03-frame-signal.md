# section-03-frame-signal

## Goal

Create a new pure module **`FrameSignal`** that converts the raw-RGB frame grids into perceptual, multi-channel signals that the threshold (section-04), boundary (section-06), and rest-selector (section-05) layers all consume. This is where the **core dark-fade-visibility fix lives**: a single mean-abs RGB diff goes to ~0 across a cross-fade between two *different* dark images, so dark-on-dark transitions are invisible to the current detector. Decomposing each frame into luma / saturation / chroma channels and taking a normalized weighted diff makes that transition register.

This section has **no dependencies** and **blocks** sections 04, 05, and 06. Everything here is a pure function over `[[Double]]` grids, so it is fully offline-unit-testable (no video decode).

## Background an implementer needs

### What a "grid" is

Upstream, `GridSampler.sample(_:)` (in `swift-app/Sources/Services/GridSampler.swift`) downsamples each decoded image (a video frame or a still) to a fixed **32×18** grid and returns a **flat `[Double]`** of length `32 * 18 * 3 = 1728`. Layout is **row-major, R,G,B per cell** (alpha skipped). Values are **RAW sRGB in the range `0.0...255.0`** — NOT normalized to 0...1. The encoder's `sampleGrids(url:)` returns one such grid per video frame, so a deck is `frameGrids: [[Double]]` with `frameGrids.count == frameCount`.

Critical: do **not** normalize anywhere. The luma/sat/chroma formulas below assume the 0–255 range, and downstream thresholds are tuned against it.

Useful constants (already defined on `GridSampler`): `GridSampler.width = 32`, `GridSampler.height = 18`, `GridSampler.channels = 3`, `GridSampler.valueCount = 1728`. A grid is laid out as, for each cell index `i` in `0..<(32*18)`: `R = grid[i*3]`, `G = grid[i*3 + 1]`, `B = grid[i*3 + 2]`.

### Why multi-channel

A fade between two dark slides (e.g. dark blue → dark red) keeps every RGB component small, so `mean(|ΔR|+|ΔG|+|ΔB|)` stays under any reasonable threshold the whole way through — the transition never registers, and Rest can land mid-fade. But the **saturation** (max−min of R,G,B) and **chroma** (R−G, G−B) signals do change meaningfully across such a fade. Weighting those channels into the diff surfaces the transition that raw RGB hides.

## Tests FIRST

Create `swift-app/Tests/FrameSignalTests.swift`. Framework is **Swift Testing** (`@Test`/`@Suite`/`#expect`), matching the existing suites (see `Tests/HoldDetectorTests.swift` for the import/structure pattern: `import Testing` + `@testable import KeynoteDeployer`, a `@Suite("FrameSignal") struct`, and small helper functions that build flat grids inline).

Write these tests (assertions are the implementer's to fill; the intent is fully specified):

- **`channels` on a known solid-color grid** returns the expected `luma`/`sat`/`chroma` per cell, hand-computed from the formulas below. Use a uniform grid (every cell the same R,G,B) so every cell's channel value is identical and easy to assert. Each channel array has length `32*18 = 576`.
- **`diffSignal` ≈ 0 between two identical grids**; large between an all-black grid and an all-white grid. Assert the identical-pair value is ~0 (within a small epsilon) and the black↔white value is clearly large.
- **Dark-fade discrimination (the core fix).** Build a synthetic cross-fade between two *different dark* images (e.g. a dark-blue-ish grid and a dark-red-ish grid, all components small, say ≤ ~40). Show that the raw-RGB mean-abs diff across the fade is near zero, but `FrameSignal.diffSignal` (default weights) produces a **non-trivial** value because the sat/chroma deltas survive. Assert the multi-channel score separates the two frames where a plain mean-abs RGB diff does not. (You may compute the mean-abs RGB diff inline in the test for the comparison baseline.)
- **`frameVariance` ≈ 0 for a monochrome grid**, high for a high-contrast grid (half the cells black, half white). Assert near-zero vs clearly-large.
- **`diffSignal.count == frameGrids.count - 1`** (one diff value per adjacent pair). Also assert behavior for an empty / single-frame input is sane (an empty array — no pairs — rather than a crash).

Keep helper grids small and inline. A helper like `func solid(_ r: Double, _ g: Double, _ b: Double) -> [Double]` that fills all 576 cells, and a `func mixed(...)` for the contrast case, keeps tests readable.

## Implementation

Create `swift-app/Sources/Services/FrameSignal.swift`. All functions are `static` on an `enum` (stateless), pure, and `Sendable`-safe (no shared state).

### Public surface (signatures + intent only)

```swift
/// Per-frame multi-channel content score + diff signal over raw-RGB 32×18 grids
/// (flat [Double], length 1728, values 0.0...255.0, row-major R,G,B per cell).
/// Pure; consumed by AdaptiveThreshold (04), RestSelector (05) and BoundaryDetector (06).
enum FrameSignal {

    /// Decompose one raw-RGB grid into per-cell perceptual channels.
    ///   luma   Y = 0.299R + 0.587G + 0.114B          (brightness)
    ///   sat    S = max(R,G,B) − min(R,G,B)            (saturation proxy — where dark-fade signal lives)
    ///   chroma = the R−G and G−B opponent channels    (hue-ish proxy; true hue is unreliable at 32×18)
    /// Each returned array has length width*height (576), one value per cell.
    static func channels(_ grid: [Double]) -> FrameChannels

    /// Consecutive-frame diff as a normalized weighted average of per-channel mean-abs deltas:
    ///   score = Σ_c (meanAbsDelta_c · w_c) / Σ_c |w_c|       (default weights luma=1, sat=1, chroma=1)
    /// Returns one value per adjacent frame pair → the deck's diff signal.
    /// Length == frameGrids.count - 1 (empty if fewer than 2 frames).
    static func diffSignal(_ frameGrids: [[Double]],
                           weights: ChannelWeights = .default) -> [Double]

    /// Per-frame spatial variance of luma over the grid (monochrome/fade-dip signal):
    ///   mean( (lumaCell − meanLuma)^2 ).  ~0 for a flat/monochrome frame, high for high-contrast.
    static func frameVariance(_ grid: [Double]) -> Double
}

struct FrameChannels {
    let luma: [Double]    // length 576
    let sat: [Double]     // length 576
    let chroma: [Double]  // length 576 — single combined opponent magnitude per cell (see note)
}

struct ChannelWeights {
    let luma: Double
    let sat: Double
    let chroma: Double
    static let `default` = ChannelWeights(luma: 1, sat: 1, chroma: 1)
}
```

### Detail / decisions

- **Channel formulas** (per cell, R/G/B each 0...255):
  - `luma = 0.299*R + 0.587*G + 0.114*B`
  - `sat = max(R,G,B) - min(R,G,B)`
  - `chroma`: the plan names two opponent channels (R−G and G−B). For the `FrameChannels.chroma` array, store a **single per-cell magnitude** that summarizes both opponents — use `(|R−G| + |G−B|) / 2` (or `0.5*(|R−G|+|G−B|)`). This keeps `chroma` a length-576 array parallel to `luma`/`sat` and gives `diffSignal` one well-defined chroma delta to weight. (Document this choice in a code comment so section-06 readers understand the chroma term is a combined opponent magnitude, not raw hue.)

- **`diffSignal`**: for each adjacent frame pair `(a, b)`, compute `channels(a)` and `channels(b)`, then for each channel `c` take the **mean over all 576 cells of `|c_a − c_b|`** (mean-abs delta). Combine: `score = (lumaDelta*w.luma + satDelta*w.sat + chromaDelta*w.chroma) / (|w.luma| + |w.sat| + |w.chroma|)`. Guard the denominator: if the weight sum is 0, return 0 for that pair (avoid divide-by-zero). Output array length is `frameGrids.count - 1`; return `[]` when there are fewer than 2 frames.

- **`frameVariance`**: compute the per-cell luma first (reuse the luma formula), then `meanLuma = mean(luma)`, then `variance = mean((luma[i] - meanLuma)^2)`. This is the U-shaped-dip / monochrome signal section-06's variance-vote consumes.

- **Robustness / shape**: validate (or at least tolerate) a grid whose length isn't exactly 1728 by deriving cell count from `grid.count / 3`; but since all real input comes from `GridSampler` you can rely on length 1728. Do not allocate per-cell intermediate structs in hot loops if avoidable — iterate the flat array by stride of 3. Performance target is O(frames × 1728), same order as today.

- **Purity / threading**: no global state, no main-thread assumptions. The whole pipeline runs off the main thread and must be cancellable upstream; `FrameSignal` itself just needs to be a pure, fast function — keep it allocation-light so it doesn't dominate the per-frame budget.

## Project / build notes

- New source file `swift-app/Sources/Services/FrameSignal.swift` and new test file `swift-app/Tests/FrameSignalTests.swift` are picked up automatically by `xcodegen generate` (the project globs `Sources/` and `Tests/`). No manual `project.yml` edit needed, but you **must** run `xcodegen generate` before building because new files change the project.
- Verify via the canonical command (run through the apple-platform-build-tools builder agent, one xcodebuild at a time):
  ```
  cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS"
  ```
- Settle the verdict on the **exit code**, not stdout. Force a fresh result bundle if a prior run cached a stale `.xcresult`, and confirm the new `FrameSignalTests` actually ran by name (a "missing" new test is a false green).

## What this section does NOT do

- It does not touch `HoldDetector`, `MarkStore`, `VideoDeployer`, or any view — those are other sections.
- It does not compute thresholds, transition spans, or Rest frames — it only produces the **signals** (`channels`, `diffSignal`, `frameVariance`) that sections 04 (AdaptiveThreshold), 05 (RestSelector), and 06 (BoundaryDetector) consume. Do not embed any detection thresholds or constants here; the only "tuning" surface in this section is the default channel weights `(1,1,1)`, which stay `(1,1,1)` unless later harness evidence shows a channel dominates wrongly.

---

Relevant absolute paths for this section:
- Create: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/FrameSignal.swift`
- Create: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/FrameSignalTests.swift`
- Reference (grid shape, do not modify): `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/GridSampler.swift`
- Reference (test/suite conventions): `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/HoldDetectorTests.swift`
---
## As-built notes (2026-06-29)
Implemented as planned (channels/diffSignal/frameVariance, chroma = 0.5·(|R−G|+|G−B|), weights 1,1,1).
5 tests, 102/102 green. **Finding:** multi-channel diff does not strictly dominate raw RGB mean-abs
(a hue swap can leave sat/chroma invariant) → the real dark-fade win is the adaptive threshold (§04)
+ twin-comparison (§06), which key on the small ABSOLUTE per-step diff relative to the deck's own
distribution. FrameSignal still provides the perceptually-weighted signal + the variance fade-dip vote.
