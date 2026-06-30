# Implementation Plan: Freeze/Hold-Marker Seed Accuracy

## 1. Context for an unfamiliar reader

**Keynote Deployer** (macOS, Swift 6.2 / SwiftUI, `swift-app/`) turns a rendered presentation into an
interactive web "deck viewer." For the **video** path, the app takes an exported video of the deck plus
a folder of per-slide still images, and automatically computes, for each slide, two frame indices:

- **Rest (`holdStart`)** — the settled frame the viewer pauses on for that slide.
- **Go (`holdEnd`)** — the frame where the outgoing transition to the next slide begins.

These pairs (`SlideMark { holdStart: Int, holdEnd: Int }`, in **video frame indices**) are the *seed*
shown in a timeline editor where the user hand-tunes them, then drive H.264 forced keyframes and the
deployed viewer's pause/play behavior.

The seed is produced by this pipeline (all pure functions over downsampled frame grids, so unit-testable):

```
video ──► GridSampler.sample → frameGrids [[Double]]  (one 32×18×3 sRGB grid per frame, every frame)
stills ─► GridSampler.sample → stillGrids [[Double]]  (one grid per slide still)
            │
            ▼
   StillsMatch.matchStillsToFrames  → anchors [Int]   (DP align stills→frames, strictly increasing)
            │
            ▼
   HoldDetector.detect(frameGrids, anchors, frameCount,
        motionThreshold = 6.0, defaultTransition = 15) → [SlideMark]
            │   Rest = anchor verbatim;  Go = forward-scan to first frame whose
            │   consecutive mean-abs grid diff ≥ motionThreshold, else a 15-frame fallback band
            ▼
   VideoTimestampDeriver.derive(...) wraps the above → (VideoAnalysis, [SlideMark] seed)
            │
            ▼
   VideoDeployView loads MarkStore by deck fingerprint (may OVERRIDE the seed), user edits,
   VideoDeployer.deploy(marks:) → forced keyframe seconds (∪ holdStart,holdEnd) + viewer spans
```

### The problem
The seed degraded after recent timeline-editor work. **All three** failure modes occur: Rest on a
mid-transition/blurry frame, Go mistimed, and marker **count** ≠ slide count. The root issue is that the
detection was **tuned on a single deck** with two fixed constants (`motionThreshold = 6.0`,
`defaultTransition = 15`), and two *non-algorithm* bugs amplify the appearance of regression.

### The goal
Across diverse decks (fade-on-dark, clean-cut, build-heavy), make Rest land on a settled frame, Go
bracket the real transition, and marker count equal slide count — verified by **measuring on the real
deck**, which is the only honest oracle (synthetic decks hid the original bug).

---

## 2. Key type & module contracts (existing — do not change shape)

```swift
struct SlideMark: Sendable, Equatable, Codable { var holdStart: Int; var holdEnd: Int }

struct VideoAnalysis: Sendable {                 // produced by VideoTimestampDeriver
    let frames: [Int]; let timestamps: [Double]; let slideCount: Int
    let width: Int; let height: Int; let fps: Double; let frameCount: Int
}

enum GridSampler {                                // 32×18×3 sRGB, .high interp
    static let width = 32; static let height = 18; static let channels = 3
    static func sample(_ image: CGImage) -> [Double]   // returns 1728 raw RGB doubles, values 0.0...255.0
}
// NOTE: grid values are RAW RGB in 0.0...255.0 — NOT normalized to 0...1. The FrameSignal formulas
// (luma/sat/chroma deltas) assume this 0–255 range. Do not introduce normalization upstream.

protocol VideoEncoder { func sampleGrids(url: URL) async throws -> [[Double]] }  // every frame
```

The new work **consumes** the existing `[[Double]]` raw-RGB grids; it does not change `GridSampler`'s
output shape. All new detection logic stays pure over `[[Double]]` so the existing offline-test pattern holds.

---

## 3. Architecture decisions

1. **Keep the DP stills-match (`StillsMatch`) as the COUNT authority, not HoldDetector.** The number of
   slides is `stillURLs.count`. HoldDetector must emit exactly one mark per slide and must NOT silently
   reduce the count via anchor dedup. Colliding/over-packed anchors become a *flagged* condition the
   harness reports, not a silent drop. (Fixes the count failure at its source.)

2. **Introduce a signal layer between grids and detection.** A new pure module computes a per-frame
   **multi-channel content score** and a per-frame **diff signal** from the raw-RGB grids, replacing the
   single mean-abs RGB diff. Detection consumes the signal, not the grids directly.

3. **Replace the two fixed constants with deck-adaptive, ratio-based detection.** Local-window ratio
   (AdaptiveDetector) + twin-comparison dual-threshold (gradual fades) + a variance/monochrome vote.
   Thresholds derive from each deck's own diff distribution (MAD/percentile). Min-hold expressed in
   **seconds × fps**, not raw frames.

4. **Rest = settled+sharp frame near the anchor**, not the verbatim anchor. The DP anchor seeds the
   neighborhood; the chosen Rest is the calm, sharp frame inside the hold.

5. **MarkStore keyed by algorithm version.** Add an `algorithmVersion` component to the fingerprint so a
   new algorithm always re-seeds; old hand-edits remain under the old key.

6. **Measurement harness is a first-class, permanent artifact**, not throwaway — a headless executable
   that runs the real pipeline on a deck folder and emits a visual + numeric per-slide report. It is the
   diagnostic AND the re-measurement tool after every change.

### New files (proposed)
```
swift-app/
  Sources/Services/
    FrameSignal.swift        # NEW: per-frame multi-channel content score + diff signal (pure)
    AdaptiveThreshold.swift  # NEW: MAD/percentile/local-ratio estimators over a diff signal (pure)
    BoundaryDetector.swift   # NEW: ratio + twin-comparison + variance-vote → transition spans (pure)
    RestSelector.swift       # NEW: settled+sharp frame pick within a hold (pure)
    HoldDetector.swift       # REWRITTEN to orchestrate the above; same detect(...) entry shape
    MarkStore.swift          # EDIT: algorithmVersion in fingerprint
    VideoDeployer.swift      # EDIT: report analysis.slideCount, not marks.count
  Sources/Diagnostics/
    SeedHarness.swift        # NEW: headless run-on-deck → report model
    HarnessReport.swift      # NEW: per-slide report types + JSON + HTML/montage emitter
  Sources/                   # NEW executable target "kd-seed-harness" (SwiftPM) wrapping SeedHarness
  Tests/
    FrameSignalTests.swift, AdaptiveThresholdTests.swift, BoundaryDetectorTests.swift,
    RestSelectorTests.swift  # NEW unit suites
    Fixtures/decks/          # NEW: small synthetic + captured-grid fixtures per archetype
```

---

## 4. Phase 0 — Measurement harness + culprit triage (DIAGNOSE FIRST)

**Why first:** the interview chose "harness first." We must localize each failure to a stage and rule the
two non-algorithm culprits in/out *before* touching the algorithm, so we don't "fix" the wrong thing.

### 4.1 Harness
A headless executable target that takes a deck folder (video + stills) and runs the REAL pipeline
(`GridSampler` → `StillsMatch` → current `HoldDetector` → marks), then emits a report.

```swift
struct SeedHarnessInput { let videoURL: URL; let stillURLs: [URL]; let outputDir: URL }

enum SeedHarness {
    /// Run the full seed pipeline on one deck and produce a diagnostic report.
    /// Pure orchestration over the existing encoder/matcher/detector — no app UI.
    static func run(_ input: SeedHarnessInput, encoder: VideoEncoder) async throws -> HarnessReport
}

struct PerSlideDiagnostic {
    let slideIndex: Int
    let matchedAnchorFrame: Int
    let anchorCollidedWithPrevious: Bool       // two stills → same frame (count-loss signal)
    let lowConfidenceMatch: Bool               // anchor far from its detected hold → StillsMatch suspect
    let seededRest: Int
    let seededGo: Int
    let diffProfileAroundAnchor: [Double]       // ±N frames consecutive diff, to eyeball Go/Rest fit
    let restFrameThumbnailPath: String          // for visual eyeballing
    let goFrameThumbnailPath: String
}

struct HarnessReport {
    let deckName: String
    let slideCount: Int                          // == stillURLs.count (the COUNT authority)
    let markCount: Int                           // == produced marks.count (should equal slideCount)
    let perSlide: [PerSlideDiagnostic]
    /// Emit a self-contained HTML montage (rest+go thumbnail per slide, with the diff profile) so
    /// Edward can eyeball "Rest settled? Go bracketing the transition?" at a glance, plus a JSON dump.
    func writeVisualReport(to dir: URL) throws
    func writeJSON(to dir: URL) throws
}
```

The HTML montage follows the house live-dashboard/report style (dark, self-contained, ASCII bars for the
diff profile). It is the artifact Edward looks at; numbers back it up. **Impl note:** construct all report
output paths via `URL` APIs (`appendingPathComponent`); `deckName` may appear in filenames, so guard against
path traversal / unsafe characters.

### 4.2 Culprit triage (run the harness + targeted checks)
- **MarkStore shadowing:** confirm the live `~/Library/Application Support/keynote-deployer/timeline-marks.json`
  contents; run the harness (which bypasses MarkStore) on the real deck and compare its FRESH seed to what
  the app shows. If the app's markers differ from the fresh seed for a previously-deployed deck, shadowing
  is confirmed. Document with the actual saved JSON.
- **Count loss:** read `anchorCollidedWithPrevious` across the real deck; if any slide collides, the count
  bug is real and reproduced.
- **Threshold fit:** read `diffProfileAroundAnchor` per slide; characterize where the fixed `6.0` fires too
  early/late and where dark fades never cross it. This is the evidence base for Phase 2–3 thresholds.

**Output of Phase 0:** a written triage note (`harness-triage.md`) stating, with harness evidence, which
failure mode is which stage. Phases 1–4 are then justified by that evidence (and a phase may be dropped if
the evidence says it's not implicated).

### Fixtures
Capture each archetype as a fixture usable offline: the fade-on-dark deck (have), a clean-cut deck and a
build-heavy deck (Edward provides). For unit tests, store *small captured grid sequences* (not full videos)
plus a couple of hand-built synthetic grid sequences (clean cut, linear cross-fade, build) so detector unit
tests run without video decode.

---

## 5. Phase 1 — Quick wins (the two confirmed culprits)

### 5.1 MarkStore algorithm versioning
Add a module-level `algorithmVersion` constant (e.g. the seed-algorithm semver/int). Fold it into the key.

```swift
enum MarkStore {
    static let algorithmVersion = 2     // bump whenever the seed algorithm changes
    /// Fingerprint now includes algorithmVersion so a new algorithm always re-seeds; marks saved under a
    /// prior version remain on disk under their own key (preserved, not shown).
    static func fingerprint(path: String, frameCount: Int, fps: Double, algorithmVersion: Int) -> String
}
```
Update the two call sites in `VideoDeployView` to pass `MarkStore.algorithmVersion`. Behavior: a deck
previously hand-tuned under v1 now shows the fresh v2 seed; the v1 edits are not lost on disk.

**Optional follow-up (deferred, not required):** a one-time non-blocking notice when a deck is re-seeded
because the algorithm version changed ("Timing detection improved — markers re-seeded; your prior edits are
still on disk"), tracked in UserDefaults. Touches editor UI (scoped out by the interview) and is non-essential
to accuracy, so it's noted here but NOT part of the required work.

### 5.2 Count-reporting bug
`VideoDeployer.deploy(...)` must report `analysis.slideCount` (the authority), not `marks.count`. And
`HoldDetector` must emit one mark per slide (Phase 3), so the two agree. Add an assertion/diagnostic when
`marks.count != analysis.slideCount` to surface any future divergence loudly rather than silently.

These two are low-risk, independently shippable, and may by themselves resolve a large fraction of the
perceived regression (especially shadowing). Land + re-measure before the algorithm work.

---

## 6. Phase 2 — Signal layer: multi-channel content score

Replace the single mean-abs RGB diff with a per-frame **content score** decomposed into perceptual
channels, so dark-background cross-fades (invisible in raw RGB diff) register.

```swift
enum FrameSignal {
    /// Per-frame scalar "content score" components from a raw-RGB 32×18 grid.
    /// luma  Y   = 0.299R+0.587G+0.114B   (brightness)
    /// sat   S   = max(R,G,B) − min(R,G,B) (saturation proxy — where dark-fade signal lives)
    /// chroma    = R−G and G−B channels    (hue-ish proxy; true hue unreliable at 32×18)
    static func channels(_ grid: [Double]) -> FrameChannels

    /// Consecutive-frame diff as a normalized weighted average of per-channel mean-abs deltas:
    ///   score = Σ(delta_c · w_c) / Σ|w_c|     (default weights luma=1, sat=1, chroma=1)
    /// Returns one diff value per adjacent frame pair → the deck's diff signal.
    static func diffSignal(_ frameGrids: [[Double]],
                           weights: ChannelWeights = .default) -> [Double]

    /// Per-frame spatial variance over the grid (monochrome/fade-dip signal): mean((cell − mean)²).
    static func frameVariance(_ grid: [Double]) -> Double
}

struct FrameChannels { let luma: [Double]; let sat: [Double]; let chroma: [Double] }
struct ChannelWeights { let luma: Double; let sat: Double; let chroma: Double; static let `default`: ChannelWeights }
```

The diff signal is the single input both the threshold layer and boundary detector consume.

---

## 7. Phase 3 — Boundary detection (adaptive, gradual-aware)

Replace `HoldDetector`'s fixed-threshold forward scan with deck-adaptive boundary detection that finds
**transition spans** `[Fs, Fe]` between slides; the hold for slide i is `(Fe_{i-1}, Fs_i)`.

### 7.1 Adaptive thresholds
```swift
enum AdaptiveThreshold {
    /// Robust high/low thresholds (Tb, Ts) from the diff signal's own distribution.
    /// MAD-based (median + k·1.4826·MAD) or percentile — chosen for the static-hold-dominated
    /// distribution typical of decks (mean+kσ over-skews). Ts ≈ 0.3–0.5·Tb.
    static func dualThreshold(_ signal: [Double]) -> (hard: Double, gradual: Double)

    /// Local-window ratio (AdaptiveDetector): ratio_i = score_i / mean(neighbors over ±window),
    /// a unitless multiple (~3×) that needs no per-deck constant. Plus an absolute floor
    /// (min_content_val) so a dead-still dark hold can't manufacture a huge ratio from noise.
    /// `window` is FPS-RELATIVE — default `max(2, Int(fps/15))` — so the temporal span is consistent
    /// across framerates rather than a raw frame count. Its sensitivity is checked in Phase 0 triage /
    /// early Phase 3 (a too-small window is noise-sensitive).
    static func localRatios(_ signal: [Double], window: Int) -> [Double]
}
```

### 7.2 Detector
```swift
struct TransitionSpan { let start: Int; let end: Int; let kind: Kind  // .cut | .gradual
    enum Kind { case cut, gradual } }

enum BoundaryDetector {
    /// Find transitions over the diff signal using:
    ///  1. Local-window ratio ≥ threshold AND score ≥ floor AND min-hold elapsed  → hard cut.
    ///  2. Twin-comparison: a frame with Ts ≤ diff < Tb starts an accumulation run; sum sub-Tb diffs
    ///     while each ≥ Ts (with a 1–2 frame grace for noise); if the accumulated sum ≥ Tb → gradual
    ///     transition spanning [Fs, Fe].  Fs = transition start (outgoing Go), Fe = settle (incoming).
    ///  3. Variance vote: a U-shaped frameVariance dip / near-zero monochrome frame between two slides
    ///     confirms a gradual transition even when every consecutive diff is below Ts (darkest fades).
    ///     CRUCIAL: distinguish a TRANSIENT variance dip (a transition through black) from a SUSTAINED
    ///     low-variance run (a legitimately black/monochrome SLIDE held for dramatic effect). A low-variance
    ///     run lasting ≥ minHoldSeconds is a valid HOLD, not a transition — only short dips split slides.
    /// minHoldSeconds × fps gives the min-scene-len (resolution/framerate-independent).
    static func transitions(diffSignal: [Double],
                            variances: [Double],
                            fps: Double,
                            minHoldSeconds: Double = 0.5) -> [TransitionSpan]
}
```

### 7.3 HoldDetector rewrite (same entry shape, anchor-guided)
`HoldDetector.detect(...)` keeps its signature so `VideoTimestampDeriver` is unchanged, but its body now:
- computes the diff signal + variances (Phase 2),
- finds transition spans (7.2),
- **assigns exactly one hold to each anchor/slide** by snapping the DP anchors onto the detected hold
  regions (anchor tells WHICH slide; the detected span tells WHERE the boundary is). One mark per slide —
  never fewer. If two anchors fall in the same detected hold (DP collision), keep both slides but split the
  hold deterministically and FLAG it in a diagnostic (count is preserved; the harness shows the collision).
- Go (`holdEnd`) = the outgoing transition start `Fs` for that slide.
- Rest (`holdStart`) = Phase 4 settled-frame pick within the hold (not the verbatim anchor).

**Edge slides (must be explicit):**
- **First slide (0):** no preceding transition. `holdStart_0` = the settled frame `RestSelector` finds in
  `[0, transitions[0].start]` (handles a leader / fade-in); `holdEnd_0` = `transitions[0].start`.
- **Last slide (n−1):** no following transition. `holdEnd_{n−1}` = `frameCount − 1` (extends to video end);
  `holdStart_{n−1}` = settled frame after the last transition's end.

**Low-confidence anchor flag (DP-failure backstop):** when snapping a DP anchor onto a detected hold, if the
anchor-to-hold distance exceeds a threshold (e.g. > ~1–2 s), record `lowConfidenceMatch = true` in that
slide's `PerSlideDiagnostic`. This points the finger at `StillsMatch` (a wildly-wrong anchor), not the
BoundaryDetector, so triage doesn't chase the wrong stage. The count is still preserved (one mark per slide);
the flag is a signal, not a drop.

The old fixed `motionThreshold`/`defaultTransition` params become deprecated/ignored (kept in the signature
only if needed for source compatibility; the adaptive layer supersedes them).

---

## 8. Phase 4 — Settled+sharp Rest selection

```swift
enum RestSelector {
    /// Pick the Rest frame inside a hold [start, end]: the temporally-calmest frame
    /// (argmin local diff over [start+margin, end−margin]), tie-broken by max sharpness.
    /// Sharpness = variance-of-Laplacian on the grayscale (luma) grid — higher = sharper, rejects
    /// motion-blurred / mid-fade frames. Comparable only WITHIN one hold (content-dependent), never across.
    /// On the coarse 32×18 grid VoL is approximate; adequate to separate a held frame from a half-faded one.
    static func restFrame(in hold: Range<Int>,
                          diffSignal: [Double],
                          frameGrids: [[Double]],
                          margin: Int = 1) -> Int
}
```

Note on precision: if Phase 0 evidence shows 32×18 VoL is too coarse to pick a sharp Rest reliably, an
optional encoder extension could fetch the few Rest-candidate frames at native resolution for a sharper VoL.
This is deferred unless measurement demands it (keeps scope bounded).

---

## 8.5 Parameter tuning strategy (anti-overfit contract)
The plan trades two bad constants (`6.0`, `15`) for several better-motivated parameters: channel weights,
local-ratio threshold + window + floor, twin-comparison `Ts/Tb` ratio + grace frames, `minHoldSeconds`. To
avoid simply re-overfitting, these are **global algorithm constants validated ONCE**, not per-deck knobs:
- They are tuned using the harness across **all three archetype decks together** (fade, clean-cut, build-heavy),
  picking values that work on all, then **hard-coded** in source. No deck-specific configuration exists.
- Channel weights default `(1,1,1)`; only revisit if Phase 0 evidence shows a channel dominates wrongly.
- Acceptance (Phase 5) re-confirms the single constant set holds on ≥2 archetypes — the same anti-overfit gate.
Record the final chosen values + the harness evidence that justified them in `harness-triage.md`.

## 9. Phase 5 — Re-measure, regression-guard, validate

1. **Re-run the harness** on all three archetypes; regenerate the visual report. Compare seed Rest/Go/count
   to Phase 0 baseline. Each failure mode must show measurable improvement, and **count == slideCount** on all.
2. **Edward eyeballs** the visual report + the live timeline editor on the real deck (the chosen oracle).
3. **Regression tests:** capture the now-characterized real-deck behavior as fixtures — unit tests over the
   captured grid sequences asserting the new detector produces the expected spans/marks on cut, cross-fade,
   and build sequences. Keep the existing `HoldDetectorTests`/`StillsMatchTests` green or update them to the
   new contract (one-mark-per-slide; no silent dedup-drop).
4. **iPhone cross-origin-iframe gate** on the real deck (the standing 1.2.x bug-class oracle): Rest lands on
   settled slides, transitions play smooth. This gate must pass before merge — it is in the project's DoD.
5. Full suite green + Release build passes (apple-platform-build-tools builder agent).

---

## 10. Anti-overfit discipline
The original sin was tuning to one deck. Guardrails baked into the plan:
- Every threshold is **derived from the deck's own distribution** (MAD/percentile/local-ratio), not a global
  constant. The only constants are unitless multiples (ratio ≈3×) and a time (min-hold seconds).
- Acceptance requires improvement on **≥2 archetypes** (fade + clean-cut minimum), not just the fade deck.
- The harness makes re-measurement on any new deck a one-command operation, so future drift is caught early.

## 11. Risks & mitigations
- **Twin-comparison splits one dissolve into two** if the grace/end-of-run rule is wrong → unit-test with a
  synthetic noisy dissolve; tune grace on the real fade deck via the harness.
- **VoL too coarse at 32×18** → measure first (Phase 0); escalate to native-res candidate frames only if needed.
- **Changing the detector breaks the editor's expectations** (it consumes `[SlideMark]`) → contract unchanged
  (one mark per slide, strictly increasing); `SlideMarkLogic.isValid` still holds.
- **MarkStore version bump hides a user's good edits** → edits are preserved on disk under the old key; only
  not shown. Acceptable per interview (auto-reseed chosen). Document in release notes.
- **Performance**: multi-channel score + variance per frame is O(frames × 1728) — same order as today; the
  encoder already samples every frame. No new decode passes except optional native-res Rest candidates.
- **Memory on long videos**: `sampleGrids → [[Double]]` holds all grids in RAM (~42MB/min of 30fps → ~2.5GB/hr).
  Real decks are minutes long so this is fine TODAY, but it is a real ceiling. Mitigation in scope: document
  the limitation + add a guard that warns / fails gracefully beyond a duration cap (~20 min). A streaming
  `AsyncSequence<[Double]>` refactor of the encoder is the proper long-term fix but stays OUT of scope here.

### Non-functional requirements
- The entire seed pipeline (`sampleGrids` → `FrameSignal` → `BoundaryDetector` → `RestSelector` → marks) runs
  **off the main thread** and is **cancellable** (document close / new import aborts it). No main-thread block
  at any stage. Harness reuses the same pipeline so it inherits this.

## 12. Out of scope
Timeline editor UI, encoder/forced-keyframe mechanics, deployed viewer behavior, the DP stills-match core
(unless Phase 0 implicates it). The DP match stays the slide-count authority.

## 13. Build & orchestration
Implement via `deep-implement` (TDD, section-by-section, per-section adversarial diff review — the project's
proven practice that has repeatedly caught bugs green tests miss). A `/workflow` may fan out the 3-deck
harness measurement in parallel and run an adversarial review of the new detector against the research, but
the core implementation is sequential TDD sections. Each algorithm section verifies on the REAL deck via the
harness, not synthetic tests alone.
