## section-06-boundary-detector

### Goal

Create a new **pure** Swift module `BoundaryDetector` that finds **transition spans** between slides in a deck's diff signal, so the hold (static region) for slide *i* is the gap `(end of transition i−1, start of transition i)`. This replaces the old fixed-threshold forward scan in `HoldDetector` that used two hard-coded constants (`motionThreshold = 6.0`, `defaultTransition = 15`) tuned to a single deck.

`BoundaryDetector` consumes the per-frame **diff signal** and **per-frame variance** produced upstream, plus the adaptive thresholds, and emits `[TransitionSpan]`. It must handle three transition styles correctly:

1. **Hard cuts** — one big diff spike between two slides.
2. **Gradual cross-fades** — a run of small per-frame diffs that individually stay below the hard threshold but **sum** past it (the dark-fade-on-dark case that the old detector missed entirely).
3. **Variance-dip fades through black** — a transition that passes through a near-monochrome frame where even the multi-channel diff is tiny, detected via a U-shaped variance dip.

The critical correctness requirement (a Gemini-identified edge case) is distinguishing a **transient** variance dip (a transition that briefly passes through black) from a **sustained** low-variance run (a legitimately black/monochrome slide held on screen for dramatic effect). A sustained low-variance run lasting ≥ `minHoldSeconds × fps` is a valid HOLD, not a transition — only short dips split slides.

This is a **pure function over `[Double]` arrays** — no video decode, no main-thread work, fully offline-unit-testable.

### Background context (the pipeline)

Keynote Deployer (macOS, Swift 6.2, `swift-app/`) turns an exported deck video + per-slide stills into an interactive web viewer. For each slide it computes two frame indices: **Rest** (`holdStart`, the settled frame to pause on) and **Go** (`holdEnd`, where the outgoing transition begins). The detection pipeline is all pure functions over downsampled 32×18×3 sRGB frame grids:

```
video → frameGrids [[Double]]  (one grid per frame, raw RGB 0...255)
          │
          ▼
   FrameSignal.diffSignal      → [Double]  (one diff value per adjacent frame pair)
   FrameSignal.frameVariance   → [Double]  (one variance per frame)
          │
          ▼
   AdaptiveThreshold.dualThreshold / localRatios   → deck-derived thresholds
          │
          ▼
   BoundaryDetector.transitions(...)  → [TransitionSpan]    ◀── THIS SECTION
          │
          ▼
   HoldDetector.detect(...)   → [SlideMark]   (section-07 consumes the spans)
```

Grid values are **raw RGB in 0.0...255.0** (NOT normalized). The diff signal and variances arrive already computed by the upstream modules; this section only consumes `[Double]` arrays.

### Dependencies (provided by other sections — DO NOT re-implement)

This section depends on **section-03 (FrameSignal)** and **section-04 (AdaptiveThreshold)**. You consume their outputs; their signatures (for reference only — they are implemented elsewhere):

```swift
// section-03 — FrameSignal.swift
enum FrameSignal {
    /// Consecutive-frame diff as a normalized weighted average of per-channel
    /// (luma/sat/chroma) mean-abs deltas. Returns frameGrids.count - 1 values.
    static func diffSignal(_ frameGrids: [[Double]], weights: ChannelWeights = .default) -> [Double]
    /// Per-frame spatial variance over the grid: mean((cell − mean)²). One value per frame.
    static func frameVariance(_ grid: [Double]) -> Double
}

// section-04 — AdaptiveThreshold.swift
enum AdaptiveThreshold {
    /// Robust (Tb, Ts) from the signal's own distribution (MAD/percentile). Ts ≈ 0.3–0.5·Tb.
    static func dualThreshold(_ signal: [Double]) -> (hard: Double, gradual: Double)
    /// Local-window ratio: score_i / mean(neighbors over ±window). Unitless multiple, no per-deck constant.
    /// `window` is fps-relative: max(2, Int(fps/15)).
    static func localRatios(_ signal: [Double], window: Int) -> [Double]
}
```

In tests for **this** section you may either call the real `AdaptiveThreshold` (if it's already built) or construct synthetic signals where the thresholds are obvious. The `transitions(...)` entry point computes the thresholds internally from the passed-in `diffSignal` (via `AdaptiveThreshold.dualThreshold` and `localRatios`), so the unit under test is `BoundaryDetector.transitions`. Keep `BoundaryDetector` self-contained: it takes the raw `diffSignal` + `variances` + `fps` and does its own thresholding internally by calling `AdaptiveThreshold`.

### File to create

`swift-app/Sources/Services/BoundaryDetector.swift`

### Tests FIRST

Write these BEFORE the implementation in a new file `swift-app/Tests/BoundaryDetectorTests.swift`. Framework: **Swift Testing** (`@Test`/`@Suite`, `#expect`), matching the existing `Tests/`. Use small synthetic `[Double]` signal sequences inline — no video decode needed. The implementer writes the assertions; the cases to cover:

```swift
import Testing
@testable import KeynoteDeployer  // or the module name used by other Tests/ files — match existing imports

@Suite struct BoundaryDetectorTests {

    // Clean hard cut: a flat-low diff signal with ONE big spike → exactly one .cut span at the spike frame.
    @Test func hardCut_singleSpike_oneSpan() { /* ... */ }

    // Gradual cross-fade: a RUN of small sub-Tb diffs whose SUM exceeds Tb → exactly ONE .gradual span
    // [Fs, Fe] covering the run. Must NOT emit zero spans, and must NOT split into many (twin-comparison
    // accumulation works). Fs = run start (outgoing Go), Fe = settle (incoming).
    @Test func gradualCrossFade_accumulatesToOneSpan() { /* ... */ }

    // Noise grace: a gradual run with ONE single sub-Ts dropout frame in the middle still yields ONE span
    // (the 1–2 frame grace rule bridges the dropout), not two adjacent spans.
    @Test func gradualRun_withSingleDropout_staysOneSpan() { /* ... */ }

    // Black-SLIDE vs fade-to-black (the Gemini edge case):
    //  - A SUSTAINED low-variance run lasting ≥ minHoldSeconds × fps is a HOLD → NO transition emitted there.
    //  - A SHORT variance dip (well under minHold) between two slides IS a transition.
    @Test func sustainedBlackSlide_isHold_notTransition() { /* ... */ }
    @Test func shortVarianceDip_isTransition() { /* ... */ }

    // minHoldSeconds honored: two candidate cuts closer together than minHoldSeconds × fps don't BOTH register
    // (the second is suppressed until min-hold has elapsed).
    @Test func minHold_suppressesTooCloseSecondCut() { /* ... */ }

    // Build-heavy / intra-slide motion: a uniformly elevated diff region (motion that raises its own neighbors,
    // so localRatio stays ~1 and no single frame crosses the hard threshold) must NOT manufacture extra
    // transitions inside one slide.
    @Test func buildMotion_doesNotManufactureTransitions() { /* ... */ }
}
```

Notes for constructing the synthetic signals:
- A **hard cut** = `[0.1, 0.1, 0.1, 50.0, 0.1, 0.1, ...]` — one large value against a flat-low baseline; `localRatio` peaks sharply, `score ≥ floor`.
- A **gradual cross-fade** = a contiguous run like `[..., 3, 4, 4, 3, 4, ...]` where each value sits in `[Ts, Tb)` and the running sum crosses `Tb`. Pick a baseline near 0 so the threshold derivation (MAD/percentile) puts `Tb` above the individual fade values but below their sum.
- A **noise dropout** = the same gradual run with one frame dipped just below `Ts` (e.g. one `0.5` among the `3–4`s) — the grace rule (1–2 frames) must not break the run.
- The **black-slide vs fade** cases need both `diffSignal` AND `variances`: build a `variances` array with either a sustained low run (length ≥ `minHoldSeconds × fps`) or a short dip (a few frames), and assert the span output accordingly.
- The **build-motion** case = an elevated-but-uniform diff plateau (e.g. a run of `8`s) where no single frame's `localRatio` spikes and no twin-comparison run terminates with a settle — assert zero spans across that plateau.

Keep `fps` small in tests (e.g. `fps = 10`, `minHoldSeconds = 0.5` → min-hold = 5 frames) so the synthetic arrays stay short and the thresholds are easy to reason about.

The deeper regression — that **Rest never lands inside a transition span on the captured REAL fade-deck grid fixture** — is asserted in **section-07** (HoldDetector rewrite) and **section-08** (re-measure), not here. This section's unit tests prove the span-finding logic on synthetic signals.

### Implementation

Create `swift-app/Sources/Services/BoundaryDetector.swift`. It is a pure `enum` namespace (stateless, like the other detector modules). Implement the span type and the single entry point:

```swift
/// A detected transition between two slides, expressed in video frame indices.
/// `start` (Fs) = the frame where the outgoing transition begins (becomes the previous slide's Go).
/// `end`   (Fe) = the frame where the incoming slide has settled (becomes the next slide's hold start region).
struct TransitionSpan: Sendable, Equatable {
    let start: Int
    let end: Int
    let kind: Kind
    enum Kind: Sendable { case cut, gradual }
}

enum BoundaryDetector {
    /// Find transitions over the deck's diff signal. Pure; no I/O.
    ///
    /// `diffSignal`  — one value per ADJACENT frame pair (count == frameCount − 1), from FrameSignal.diffSignal.
    /// `variances`   — one value per FRAME (count == frameCount), from FrameSignal.frameVariance.
    /// `fps`         — used to convert minHoldSeconds → min-scene-length frames and to size the local window.
    /// `minHoldSeconds` — minimum hold duration; transitions closer than this don't both register, and a
    ///                    low-variance run ≥ this is a HOLD (black slide), not a transition.
    static func transitions(diffSignal: [Double],
                            variances: [Double],
                            fps: Double,
                            minHoldSeconds: Double = 0.5) -> [TransitionSpan]
}
```

The body combines three signals (per the plan's Phase 3.2). All thresholds are **derived from the deck's own diff distribution** — never global constants — to avoid re-overfitting:

1. **Local-ratio hard cut.** Compute `ratios = AdaptiveThreshold.localRatios(diffSignal, window: max(2, Int(fps/15)))` and `(hard, gradual) = AdaptiveThreshold.dualThreshold(diffSignal)`. A frame `i` is a **hard cut** when its local ratio is large (≈ ≥3×, a unitless multiple) **AND** `diffSignal[i] ≥ hard` (an absolute floor so a dead-still dark hold can't manufacture a huge ratio out of noise) **AND** the min-hold gap since the last emitted transition has elapsed. Emit a `.cut` span (a one- or two-frame span at `i`).

2. **Twin-comparison gradual accumulation.** A frame whose diff is in `[gradual, hard)` (i.e. `Ts ≤ diff < Tb`) **starts an accumulation run**. While subsequent frames each stay `≥ gradual` (with a **1–2 frame grace** for a single sub-`gradual` noise dropout — do not end the run on the first dip; allow up to ~2 consecutive sub-`gradual` frames before terminating), keep summing the sub-`hard` diffs. If the accumulated sum reaches `hard`, this is a **gradual transition** spanning `[Fs, Fe]` where `Fs` = the frame the run started and `Fe` = the frame it settled (first frame after the run where diff drops back to baseline). Emit one `.gradual` span. The grace rule prevents one dissolve from being split into two; tune the grace count against the real fade deck via the harness in section-08.

3. **Variance-dip vote (fade-through-black).** Even when every consecutive diff is below `gradual` (the darkest fades), a U-shaped dip in `variances` toward near-zero (monochrome) between two slides confirms a gradual transition. **CRUCIAL discrimination:** measure the LENGTH of the low-variance run. A low-variance run lasting **≥ `minHoldSeconds × fps`** is a legitimately held black/monochrome **SLIDE** — emit NO transition there. Only a **SHORT** variance dip (well under the min-hold length) splits two slides into a transition. Use the variance vote to confirm/extend a gradual span when the diff signal alone is too quiet, but gate it on this length check so a dramatic black slide is preserved as a hold.

**Min-hold enforcement (resolution/framerate-independent).** Convert `minHoldSeconds` to frames as `minHoldFrames = max(1, Int((minHoldSeconds * fps).rounded()))`. After emitting any span, suppress further span detection until at least `minHoldFrames` have elapsed since the previous transition's end. Two cuts closer than `minHoldFrames` must not both register (the second is the loser). This expresses min-scene-length in time, not raw frames, so it's consistent across framerates and resolutions.

**Output contract:**
- Return spans **sorted by `start`, strictly non-overlapping** (a later detection inside a still-open min-hold window is dropped).
- `start` and `end` are valid frame indices in `[0, frameCount)`. Note `frameCount = variances.count` and `diffSignal.count = frameCount − 1`; index carefully when mapping a diff-pair index `i` (the diff between frame `i` and `i+1`) to frame indices.
- A `.cut` span may be a single frame (`start == end` or a 1–2 frame band); a `.gradual` span covers `[Fs, Fe]` with `Fe > Fs`.
- This function does **not** know about slides/anchors or slide count — it only finds where the transitions are. Section-07's `HoldDetector` assigns these spans to anchors and guarantees one mark per slide.

**Anti-overfit discipline (carry into the constants you pick):** the only allowed constants are *unitless multiples* (local-ratio ≈ 3×) and *times* (`minHoldSeconds`, the fps-relative window). The hard/gradual thresholds come from `AdaptiveThreshold` (deck-derived MAD/percentile). The local-ratio multiple, twin-comparison grace count, and `minHoldSeconds` are **global algorithm constants validated once across all three archetype decks** (fade / clean-cut / build-heavy) in section-08 — not per-deck knobs. Do not add any deck-specific configuration.

**Concurrency / purity:** keep it a pure synchronous function over arrays. No main-thread work, no shared state, no I/O. The larger pipeline runs off-main and is cancellable (handled by callers); this pure function inherits that for free.

### Verify

Build and test via the apple-platform-build-tools builder agent (one xcodebuild at a time). New files change the project, so regenerate first. Canonical command:

```bash
cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS"
```

All `BoundaryDetectorTests` must pass. The accuracy oracle (real-deck behavior) is exercised later in section-07/section-08 via the harness — this section's gate is the synthetic-signal unit suite plus a clean build.

### Out of scope for this section

- `FrameSignal` (section-03) and `AdaptiveThreshold` (section-04) — consumed, not implemented here.
- Assigning spans to slides / anchors, one-mark-per-slide guarantee, edge slides, low-confidence flags — that is **section-07** (`HoldDetector` rewrite, which consumes `transitions(...)`).
- Rest-frame selection within a hold — **section-05** (`RestSelector`).
- Re-measurement / real-deck regression fixtures / final constant tuning — **section-08**.

---

Relevant file paths:
- Create: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/BoundaryDetector.swift`
- Create: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/BoundaryDetectorTests.swift`
- Consumes (other sections): `swift-app/Sources/Services/FrameSignal.swift` (section-03), `swift-app/Sources/Services/AdaptiveThreshold.swift` (section-04)
- Consumed by: `swift-app/Sources/Services/HoldDetector.swift` (section-07)