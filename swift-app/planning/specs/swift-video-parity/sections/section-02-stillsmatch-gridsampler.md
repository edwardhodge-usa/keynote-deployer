I have everything I need. Now I'll write the section content.

# Section 02 — StillsMatch + GridSampler

## Goal

Port two pure, offline, fully unit-testable algorithms into the Swift app:

1. **`StillsMatch`** — a dynamic-programming matcher that aligns N per-slide still images to M video frames (plus `meanAbs` and `naturalSort` helpers). Faithful port of `src/utils/stillsMatch.ts`.
2. **`GridSampler`** — downscales a `CGImage` (a decoded still, or a decoded video frame) to a fixed 32×18 sRGB-normalized RGB grid and returns a flat `[Double]`. Salvaged from the `feat/gif-deploy-swift` branch and adapted to the Electron *video* sampler's 32×18 grid.

These are the **highest-value parity gate** in the whole project: the DP matcher must produce byte-identical slide→frame indices to the TypeScript oracle, because those indices become per-slide timestamps baked into the deployed viewer. They require no AVFoundation, no ffmpeg, and no network — they run in CI.

## Background / Why

Keynote HTML exports raster images as low-res thumbnails, so the deck-deploy path uses an H.264 **video** of the rendered deck plus one **still** per slide. Slide boundaries cannot be derived from pixels alone (held-build/constant-bg decks defeat frame-diff detection). The per-slide stills are the ground-truth slide count and boundary source: each still is matched to the video frame it corresponds to via `matchStillsToFrames`, and `frame / fps` becomes that slide's timestamp.

For the cross-engine match to agree, **stills and frames must be sampled through the identical grid**. Electron's video sampler uses a **32×18 RGB grid (1728 values)**. This Swift port must use exactly 32×18×3 = 1728 to preserve parity. (Note: the GIF branch used a different grid for GIF work — ignore that; match the *video* sampler here.)

## Dependencies

- **Section 01 (`section-01-models-project`)** must be complete: it adds the Swift Testing **test target** to `project.yml` (none exists on `main` today) and the `Sources/Resources` bundling entry. This section's tests run in that target. Do not re-create the test target.
- No other section dependencies. This section **blocks** Section 04 (encoder reuses `GridSampler.sample`) and Section 06 (`VideoTimestampDeriver` calls `StillsMatch` + `naturalSort`).

## Files to Create

```
swift-app/Sources/Services/GridSampler.swift     # enum, static sample(_:) -> [Double]
swift-app/Sources/Services/StillsMatch.swift     # enum: meanAbs, naturalSort, matchStillsToFrames
swift-app/Tests/StillsMatchTests.swift           # Swift Testing @Test cases (parity gate)
swift-app/Tests/GridSamplerTests.swift           # Swift Testing @Test cases (shape + sRGB)
```

(Test file paths follow the test target's source roots established in Section 01; place them under the test target's directory as configured there.)

## The TypeScript Oracle (source of truth — port this exactly)

`src/utils/stillsMatch.ts`, reproduced verbatim so you do not need to open it:

```ts
export function naturalSort(names: string[]): string[] {
  const key = (s: string) => s.split(/(\d+)/).map(p => /^\d+$/.test(p) ? p.padStart(10, '0') : p).join('')
  return [...names].sort((a, b) => key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0)
}
function meanAbs(a: number[], b: number[]): number {
  if (a.length === 0) return 0
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
      if (f - 1 >= 0 && dp[i-1][f-1] <= bestPrev) { bestPrev = dp[i-1][f-1]; bestPrevIdx = f - 1 }
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

### Porting notes (parity-critical — read before coding)

- **`matchStillsToFrames` must be a faithful structural port.** Keep the same `dp`/`back`/`cost` matrices, the same running-min `bestPrev`/`bestPrevIdx` sweep, and the same backtrack from the minimal `dp[N-1][f]`. Tie-breaking matters: TS uses `dp[i-1][f-1] <= bestPrev` (`<=`, not `<`) so the **largest** prior frame index wins on ties; preserve that exact comparison so Swift picks the same frame as TS. Likewise the end-state scan uses strict `<` (`dp[N-1][f] < best`), so the **first** (smallest-index) minimal end frame is chosen — preserve strict `<`.
- **`meanAbs`**: empty input → `0`. Otherwise sum of `abs(a[i] - b[i])` over the full length, divided by `a.length`. Assumes equal lengths (as TS does). Use `Double`.
- **Use `Double` throughout** to match JS number semantics. `INF` → `Double.infinity`.
- **Amendment A10 — `naturalSort`**: the plan directs implementing this via `String.compare(options: .numeric)` (Swift's numeric-aware compare) rather than the TS `padStart(10)` key hand-port. This is acceptable **only if** the parity test confirms it orders the still names identically to the TS `naturalSort`. The expected ordering on `…001.jpeg`…`…039.jpeg`-style names is plain ascending numeric (`001, 002, …, 010, …, 039`). If `String.compare(.numeric)` ever diverges from the TS key-based order on the test set, fall back to a direct port of the TS `key` function (split on digit runs, zero-pad numeric runs to width 10, join, compare strings). The TS order is the oracle.
- **N stills require M ≥ N** for a valid strictly-increasing assignment. When `M < N`, the TS DP leaves some `dp[i][f] = Infinity` and backtrack can hit a `back == -1` (the `f` becomes `-1`). **Document and assert the chosen Swift behavior** in this case — either clamp to a safe result or throw a descriptive error. Pick one, make it deterministic, and cover it with the M < N test below. (Real decks always satisfy M ≥ N; this is a robustness guard.)
- **Edge cases to preserve:** empty stills (`N == 0`) → `[]`. Single still (`N == 1`) → the globally-cheapest frame (the `dp[0][f] = cost[0][f]` row, then the end scan picks the min). `N == M` → the only strictly-increasing assignment is identity-ish but still cost-driven; let the DP decide.

## Component Signatures

### `StillsMatch.swift`

```swift
enum StillsMatch {
    /// Mean absolute difference of two equal-length grids. Empty -> 0.
    static func meanAbs(_ a: [Double], _ b: [Double]) -> Double

    /// Natural (numeric-aware) sort of file names/paths. A10: String.compare(.numeric),
    /// verified against the TS naturalSort order in tests.
    static func naturalSort(_ names: [String]) -> [String]

    /// DP-match N stills to M frames with strictly-increasing frame indices.
    /// Returns one matched frame index per still (length N). Monotonic by construction.
    /// Faithful port of stillsMatch.ts matchStillsToFrames (tie-breaks included).
    /// Edge cases: empty stills -> []; single still -> globally-cheapest frame.
    /// M < N: <document chosen behavior — clamp or throw>.
    static func matchStillsToFrames(_ stills: [[Double]], _ frames: [[Double]]) -> [Int]
}
```

### `GridSampler.swift`

```swift
import CoreGraphics

enum GridSampler {
    /// Downscale a CGImage to a 32x18 RGB grid -> 1728 Doubles in 0...255, row-major RGB.
    /// A3: draw the source into an explicit sRGB CGContext before sampling so stills
    /// (often Display P3) and frames (sRGB) are compared in one color space.
    static func sample(_ image: CGImage) -> [Double]
}
```

**`GridSampler.sample` implementation guidance:**
- Create a `CGContext` sized 32×18, backed by an explicit **sRGB** color space (`CGColorSpace(name: CGColorSpace.sRGB)`), 8-bit per channel, RGBA byte layout (e.g. `CGImageAlphaInfo.premultipliedLast` or `.noneSkipLast`). Drawing into an sRGB context performs the color-space conversion for you — this is amendment **A3**, and it is what makes a Display-P3 still and an sRGB video frame produce near-equal grids.
- `context.interpolationQuality = .high` so downscaling averages pixels (a solid-color image must yield a near-uniform grid).
- `context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 18))`.
- Read back the context's pixel buffer and emit, **row-major, R then G then B per pixel** (skip alpha), as `Double` values in `0...255`. Result length must be exactly 32 × 18 × 3 = **1728**.
- Constants: width 32, height 18, channels 3 — define as named constants so Section 04 can reference the same grid dimensions.

## Tests (write these FIRST)

Use **Swift Testing** (`@Test` / `#expect`) in the test target wired by Section 01. Test stubs are prose/signatures — write the assertions yourself.

### `StillsMatchTests.swift`

- **`meanAbs` known value:** two equal-length grids whose absolute diffs are known → assert the exact mean. Empty input → `0`.
- **`matchStillsToFrames` parity vs TS (the core gate):** build a small hand-crafted fixture of grids for N stills + M frames (small dimensions are fine — they need not be 1728-wide for the algorithm test). Run the *exact same input* through the TS `matchStillsToFrames` once (e.g. via `node -e`/`ts-node`, or by reasoning through the algorithm) to capture the per-slide frame indices, then **hard-code that array as the oracle** and `#expect` the Swift output equals it. This must include at least one tie case so the `<=` / `<` tie-break behavior is exercised.
- **Strict monotonicity:** assert each matched frame index is strictly greater than the previous (for any valid M ≥ N fixture).
- **Edges:** empty stills → `[]`; single still → the globally-cheapest frame (construct a fixture where one frame is the obvious min); `N == M`; and **`M < N`** → assert the documented chosen behavior (clamp result shape, or `throws`/precondition — whichever you implemented).
- **`naturalSort` A10 parity:** `["…010.jpeg", "…002.jpeg", "…001.jpeg"]` → `001, 002, 010`; and assert it matches the TS `naturalSort` order on a 39-name set (`…001.jpeg` … `…039.jpeg`, shuffled input → ascending numeric output). Capture the TS order as the oracle. If `String.compare(.numeric)` diverges, switch to the TS-key port (see porting notes).

### `GridSamplerTests.swift`

- **Shape:** `sample(cgImage)` on any test image returns exactly **1728** values, all within `0...255`.
- **Solid color → near-uniform grid:** a solid-color `CGImage` (e.g. pure red) yields a grid whose values are (near-)equal to that color's sRGB channel values (allow a small tolerance for resampling/rounding).
- **A3 color-space normalization:** two images identical except one tagged **Display P3** and one tagged **sRGB** produce **near-equal** grids after sRGB normalization. (Construct the two `CGImage`s with the respective tagged color spaces but the same nominal pixel content; assert per-channel diffs are within a small tolerance.)

## Definition of Done

- `GridSampler.swift` and `StillsMatch.swift` compile under Swift 6 strict concurrency (the `enum`s are stateless; static methods are inherently `Sendable`-safe).
- All tests above pass via:
  `cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -quiet` (exit 0).
- The DP-match output is byte-identical to the TS oracle on the fixture, including a tie case.
- `naturalSort` matches the TS order on the 39-name set.
- `GridSampler.sample` returns exactly 1728 sRGB-normalized values; the P3-vs-sRGB A3 test passes within tolerance.
- The chosen `M < N` behavior is documented in a doc-comment and locked by a test.

---

Relevant files for this task:
- Create: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/GridSampler.swift`, `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/StillsMatch.swift`
- Create tests: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/StillsMatchTests.swift`, `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/GridSamplerTests.swift`
- TypeScript oracle (source of truth, reproduced in the section): `/Users/EdwardHodge_1/Code/keynote-deployer/src/utils/stillsMatch.ts`

Notes on what I found while writing the section:
- The TS `matchStillsToFrames` uses `<=` for the prior-frame tie-break (largest prior index wins on ties) and strict `<` for the end-state scan (first minimal end frame wins). These two comparisons are parity-load-bearing and I called them out explicitly so the implementer does not "clean them up" and break TS parity.
- `GridSampler` does **not** exist on `main` (Glob found no `GridSampler.swift`); it lives only on the `feat/gif-deploy-swift` branch and used a different grid for GIF. The section directs using the Electron *video* sampler's 32×18×3 = 1728 grid, not the GIF grid.
- The `M < N` behavior is genuinely under-specified in the source plan ("clamp/throw") — I flagged it as an implementer decision that must be documented and test-locked rather than left as a silent crash on `back == -1`.