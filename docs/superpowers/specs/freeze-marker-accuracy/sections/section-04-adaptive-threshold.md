# Section 04 — Adaptive Threshold

## Goal

Create a new **pure** module `AdaptiveThreshold` that replaces the old fixed `motionThreshold = 6.0` constant with **deck-derived, unitless detection**. It computes two things over a per-frame diff signal:

1. **Robust dual thresholds** `(hard, gradual)` from the signal's own distribution (MAD/percentile based, not mean+kσ), with `gradual < hard` and both above a static-noise floor.
2. **Local-window ratios** — each frame's diff as a multiple of its neighbors' mean, an fps-relative unitless measure (~3× at a real transition) that needs no per-deck constant, plus an absolute floor so a dead-still dark hold can't manufacture a huge ratio from sensor noise.

This module is consumed by the BoundaryDetector (section-06). It is a small, self-contained, fully offline-unit-testable piece.

## Background context (you do not need to read other sections)

**What this pipeline does:** Keynote Deployer turns a rendered presentation video + per-slide stills into an interactive deck viewer. For each slide it computes a **Rest** frame (settled frame to pause on) and a **Go** frame (where the outgoing transition begins). Detection runs over downsampled frame grids so it's pure and unit-testable.

**The diff signal you consume (produced by section-03 `FrameSignal`, a dependency):** A `[Double]` array, one value per *adjacent frame pair*, so for `N` frames it has `N-1` entries. Each value is a multi-channel (luma/saturation/chroma) weighted mean-abs frame-to-frame difference. Values are roughly in the raw-RGB 0–255 magnitude range (grids are RAW sRGB `0.0...255.0`, **not** normalized). Most entries are near-zero (static holds dominate the distribution); transitions appear as spikes (hard cuts) or runs of small-but-sustained values (gradual cross-fades). **You do not call FrameSignal yourself** — your functions take the already-computed `signal: [Double]` as input.

**Why the distribution is skewed:** A typical deck is mostly static holds → the diff signal is a long flat tail of ~0 with a few spikes. A naive `mean + k·σ` threshold gets dragged upward by the spikes and the long tail, producing a bad threshold. Use **robust** statistics (median + MAD, or percentile) which are insensitive to the sparse high outliers.

**The anti-overfit contract (important):** The whole point of this work is to stop tuning to one deck. The constants in this module (the MAD multiplier `k`, the `gradual ≈ 0.3–0.5 · hard` ratio, the noise floor, the local-ratio default window formula) are **global algorithm constants validated once across all archetype decks**, NOT per-deck knobs. Derive thresholds from each deck's own distribution; keep only unitless multiples and time-relative windows as constants. Record final chosen values in `harness-triage.md` (done in section-08, not here — but pick sane, well-motivated defaults).

## Dependencies

- **section-03-frame-signal** (must exist first): provides the diff signal that this module's functions consume as input. You only need the *shape* of that input (`[Double]`, one value per adjacent frame pair) — you do not call into `FrameSignal` from this module. If section-03 isn't merged yet, you can still implement and unit-test `AdaptiveThreshold` entirely against hand-built `[Double]` signals.

This section **blocks** section-06 (BoundaryDetector consumes these thresholds and ratios).

## Files

- **Create:** `swift-app/Sources/Services/AdaptiveThreshold.swift`
- **Create:** `swift-app/Tests/AdaptiveThresholdTests.swift`

After creating new files, run `cd swift-app && xcodegen generate` so the project picks them up, then build/test. Use the **apple-platform-build-tools builder agent**, one `xcodebuild` at a time. Canonical verifier:

```
cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS"
```

## Tests FIRST

Framework: **Swift Testing** (`@Test` / `@Suite` / `#expect`), matching the existing `Tests/`. Write these BEFORE the implementation. Build the input signals inline as small synthetic `[Double]` arrays — no video decode, no fixtures needed for this suite. The implementer writes the concrete assertions; the cases to cover:

```swift
import Testing
@testable import KeynoteDeployer   // confirm the module name matches the existing test files

@Suite struct AdaptiveThresholdTests {

    // dualThreshold robustness over a static-hold-dominated distribution.
    @Test func dualThresholdReturnsGradualBelowHardAndAboveNoiseFloor() {
        // A signal of mostly-zeros (long flat tail) with a few large spikes —
        // the typical deck distribution. Expect:
        //   - gradual < hard
        //   - both strictly above the static-noise floor (not dragged to ~0 by the flat tail,
        //     and not skewed huge by the sparse spikes — i.e. robust, MAD/percentile-based).
    }

    // Local ratio peaks at a real transition, stays low under uniform motion.
    @Test func localRatiosPeakAtSpikeStayFlatOnRamp() {
        // Signal A: zeros with ONE injected single-frame spike → ratio at that index is sharply high (~>=3).
        // Signal B: a uniformly rising ramp (build-style motion that raises the neighbors too) →
        //   ratios stay ~1 everywhere (no false peak), because each frame's neighbors rose with it.
    }

    // Window is fps-relative.
    @Test func localRatioWindowIsFpsRelative() {
        // The window used for the neighbor mean is max(2, Int(fps/15)).
        // Assert a higher fps yields a wider window (e.g. via an exposed `window(forFps:)` helper,
        // or by observing the smoothing behavior differs). Prefer exposing the small helper for a
        // direct, deterministic assertion.
    }

    // Absolute floor guards a dead-still dark hold.
    @Test func localRatiosFloorPreventsNoiseAmplification() {
        // A near-zero signal with only tiny sensor-noise-magnitude wiggles must NOT produce large ratios
        // (dividing tiny-by-tinier would manufacture a huge unitless multiple). With the absolute floor
        // (min content value) applied, ratios on a dead-still region stay ~1.
    }
}
```

Notes for the test author:
- Keep signals tiny and hand-built so expected values are computable by hand.
- For the fps-relative window test, the cleanest assertion is against a small exposed helper (e.g. `AdaptiveThreshold.window(forFps:)`) rather than trying to infer the window from ratio output. Expose it.
- "Spike" / "ramp" / "noise" magnitudes should be chosen relative to the 0–255 diff range described above.

## Implementation

Create `swift-app/Sources/Services/AdaptiveThreshold.swift` as a pure `enum` namespace (matches the project's stateless-service convention — `enum` with static methods). No state, no I/O, no main-thread concerns.

```swift
enum AdaptiveThreshold {

    /// Robust high/low thresholds (Tb=hard, Ts=gradual) from the diff signal's OWN distribution.
    /// Use MAD-based estimation: median + k·1.4826·MAD (1.4826 makes MAD a consistent σ estimator
    /// for normal data), or a high percentile — chosen because the static-hold-dominated distribution
    /// (a long flat ~0 tail + sparse spikes) makes mean+kσ over-skew. The gradual threshold is a
    /// fraction of the hard one: Ts ≈ 0.3–0.5·Tb. Enforce a static-noise floor so neither collapses
    /// toward 0 on a perfectly clean deck. Guarantee: gradual < hard, both ≥ floor.
    static func dualThreshold(_ signal: [Double]) -> (hard: Double, gradual: Double)

    /// Local-window ratio (AdaptiveDetector): ratio_i = score_i / mean(neighbors over ±window),
    /// a UNITLESS multiple (~3× at a real transition) needing no per-deck constant. The neighbor mean
    /// excludes the frame itself. Apply an absolute floor (min content value) to the denominator/score
    /// so a dead-still dark hold cannot manufacture a huge ratio from sensor noise (tiny ÷ tinier).
    /// `window` is FPS-RELATIVE — pass `window(forFps:)` — so the temporal span is consistent across
    /// framerates instead of being a raw frame count. Returns one ratio per input element.
    static func localRatios(_ signal: [Double], window: Int) -> [Double]

    /// FPS-relative neighbor window: max(2, Int(fps / 15)). Exposed so the window is testable and so
    /// BoundaryDetector (section-06) derives the same value from the deck's fps.
    static func window(forFps fps: Double) -> Int
}
```

### Detail / guidance

- **`dualThreshold`**
  - Compute the **median** and **MAD** (median absolute deviation: `median(|x_i − median|)`) of the signal. Robust estimate of spread = `1.4826 · MAD`.
  - `hard = median + k_hard · (1.4826 · MAD)` (pick a sane `k_hard`, e.g. ~3, validated later in section-08; it does not need to be perfect here, just well-motivated and robust). Alternatively/equivalently a high percentile (e.g. ~90–95th) of the signal — choose one approach and keep it consistent; the MAD route is the documented preference.
  - `gradual = clamp(ratio · hard, …)` with the documented `ratio ≈ 0.3–0.5` (e.g. 0.4). Ensure strictly `gradual < hard`.
  - **Static-noise floor:** define a small absolute floor (a low diff magnitude on the 0–255 scale, e.g. a couple of units — pick a defensible value) and `max(...)` both thresholds against an appropriate floor so a perfectly clean deck (MAD ≈ 0) doesn't yield thresholds at ~0. The floor protects against the degenerate all-zeros / all-equal signal.
  - **Degenerate inputs:** empty or single-element signal, or all-equal values (MAD = 0) → return floor-based thresholds, never NaN/Inf, never `gradual ≥ hard`.

- **`window(forFps:)`** = `max(2, Int(fps / 15))`. (At 30 fps → 2; at 60 fps → 4.) This keeps the neighbor span ~constant in *time*, not frames.

- **`localRatios`**
  - For each index `i`, neighbor mean = mean of `signal` over `[i−window, i+window]` **excluding `i`** (clamp the range to valid bounds at the ends).
  - `ratio_i = score_i / max(neighborMean, floor)` where `floor` is the absolute min-content value (same spirit as the threshold floor — prevents tiny÷tiny blowups). Consider also flooring `score_i` itself if a near-zero numerator over a near-zero denominator is otherwise unstable; the key invariant is: **a dead-still region yields ratios ~1, not huge.**
  - A single-frame spike over a flat-zero background yields a sharply high ratio (≥ ~3). A uniform ramp yields ~1 everywhere because the neighbors rise with the frame. A noise-only region yields ~1 because of the floor.
  - Output length equals input length (define end-of-array behavior via clamped windows; do not crash on small arrays).

### Anti-overfit / constants

The only constants you introduce here should be: the MAD multiplier `k_hard`, the `gradual/hard` ratio, the absolute noise floor, and the `fps/15` window divisor. These are **global, validated-once** values — do not add any per-deck configuration or branching on deck identity. Keep them as clearly-named module constants so section-08 can record and, if needed, retune them in `harness-triage.md`.

## Done criteria

- `AdaptiveThreshold.swift` compiles as a pure `enum` namespace; no app/UI/state dependencies.
- `AdaptiveThresholdTests.swift` covers: dual-threshold robustness/ordering/floor, local-ratio spike vs ramp, fps-relative window, and the noise floor guard.
- `xcodegen generate` then the canonical `xcodebuild test` is green for the new suite (and the rest of the suite stays green).
- No NaN/Inf on degenerate inputs (empty / single / all-equal signals).

## Relevant file paths

- Create: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/AdaptiveThreshold.swift`
- Create: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/AdaptiveThresholdTests.swift`
- Consumed-input shape comes from (dependency) `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/FrameSignal.swift` (section-03).
- Downstream consumer (do not edit here): `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/BoundaryDetector.swift` (section-06).