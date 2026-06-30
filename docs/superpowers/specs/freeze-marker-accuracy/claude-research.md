# Research: Freeze/Hold-Marker Seed Accuracy

Two research streams: (A) codebase regression-diff of what changed, (B) CV literature
for de-overfitting the algorithm. Synthesized for planning.

---

## A. Codebase regression-diff (Explore, read-only)

### A1. Rest/Go logic change in `d52b1dc` — UNLIKELY the regression
**Before (`3b06bc5`)** — backward+forward expansion from anchor:
```swift
var start = a, end = a
while start > 0, diff(frameGrids[start-1], frameGrids[start]) < motionThreshold { start -= 1 }
while end < frameGrids.count-1, diff(frameGrids[end], frameGrids[end+1]) < motionThreshold { end += 1 }
return SlideMark(holdStart: start, holdEnd: end)
```
Backward expansion traversed INTO the previous transition on fade decks (Rest landed mid-fade) — that was the bug.

**After (`d52b1dc`)** — anchor verbatim Rest, forward-only Go:
```swift
let hs = max(0, min(deduped[i], bound-1))            // Rest = anchor verbatim
var e = hs
while e < lastBefore, diff(frameGrids[e], frameGrids[e+1]) < motionThreshold { e += 1 }
he = (e >= lastBefore) ? max(hs, lastBefore - defaultTransition) : e
```
Verdict: the forward-only change was a correct fix, not the regression. BUT it introduced a NEW
assumption — that the DP anchor is itself a settled frame. Nothing guarantees that (see B4).

### A2. MarkStore shadowing — 🔴 LIKELY CULPRIT
`MarkStore.fingerprint = "\(frameCount)-\(fpsKey)-\(fileSize)"`. Re-deploying the SAME video file
at the same fps produces an IDENTICAL fingerprint even when the algorithm changed.
`VideoDeployView.swift:555-561`:
```swift
if let saved = MarkStore.load(fp), SlideMarkLogic.isValid(saved, frameCount: ...) {
    marks = saved          // SAVED marks OVERRIDE the fresh seed
} else { marks = a.marks } // fresh seed only if no saved set
```
→ Edward testing the same deck repeatedly loads marks saved under an OLD algorithm version,
shadowing every improvement. **Explains "less accurate SINCE all our changes"** as much as any
algorithm change. **Must rule out first** (clear `~/Library/Application Support/keynote-deployer/timeline-marks.json`, re-seed).

### A3. derive() wiring — UNLIKELY
`frameGrids.count` = total decoded frames (no subsampling). `stillGrids.count == stillURLs.count`
(one grid per still, natural-sorted). Probed `fps` used verbatim for timestamps + passed to detector.
Symmetric and correct.

### A4. Dedup + count divergence — 🔴 LIKELY CULPRIT
- `HoldDetector` dedups anchors: `[10,10,20] → [10,20]` → fewer marks than stills.
- Over-packed drop loop discards any mark with `holdStart ≤ prev.holdEnd`.
- `VideoDeployer.deploy()` returns `slideCount: marks.count`, NOT `analysis.slideCount` → compounds
  under-count in the deployed result.
→ Two stills matching the same frame (near-identical consecutive slides / weak DP discrimination)
silently drops a marker. **This is the "wrong COUNT" symptom.**

### Regression priority for the harness
1. Clear MarkStore, re-seed same deck — does accuracy jump? (rules in/out A2)
2. Log per-slide: matched anchor frame, did two stills collide? (A4)
3. Dump per-frame diff profile around each anchor vs the seeded Rest/Go (B-stage tuning)

---

## B. CV literature for de-overfitting (web research)

Current metric = mean-abs per-component diff over a 32×18 RGB grid, fixed `motion=6.0`,
`defaultTransition=15`. All techniques below port onto that downsampled-grid signal without OpenCV.

### B1. Multi-channel content score (PySceneDetect ContentDetector)
Replace one RGB mean-diff with a normalized weighted average of per-channel deltas:
`score = Σ(delta_c · w_c) / Σ|w_c|`, components luma + saturation + chroma.
- Luma `Y = 0.299R+0.587G+0.114B`; saturation proxy `S = max(R,G,B) − min(R,G,B)`; chroma on R−G, G−B.
- A **cross-fade on a dark background** is near-invisible in raw RGB mean-diff but shows in
  saturation/chroma. This is the core upgrade for the dark-fade failure.
- PySceneDetect defaults: weights hue/sat/lum = 1.0, edges = 0.0; threshold 27, min_scene_len 15.

### B2. AdaptiveDetector local-window ratio — THE de-tuning fix
Don't compare the score to a fixed number. Compare to the local neighbor average:
```
avg_window = Σ(neighbor scores, excl. target) / (2·window_width)
ratio = min(target_score / avg_window, 255)
cut iff ratio ≥ adaptive_threshold AND target_score ≥ min_content_val AND (t − last_cut) ≥ min_scene_len
```
Defaults: `adaptive_threshold=3.0`, `window_width=2`, `min_content_val=15`, `min_scene_len=15`.
- The `3.0` is a **unitless multiple** ("3× the local baseline"), not a brightness constant → portable
  across decks. Build/camera motion raises baseline AND neighbors, so the ratio stays low → fewer
  false positives. Cleanest single replacement for `motion=6.0`.
- `min_content_val` = the one absolute floor kept, stops a dead-still dark hold manufacturing a giant
  ratio from noise.

### B3. Twin-comparison dual-threshold (Zhang et al.) — gradual transitions
Two thresholds on the diff signal: `Tb` (hard cut) and `Ts` (gradual-start, ≈0.3–0.5·Tb).
- `D_i ≥ Tb` → hard cut.
- `Ts ≤ D_i < Tb` → start accumulating `D_acc = Σ D_k` while each `D_k ≥ Ts`; transition ends when
  `D_k` drops below `Ts` (with a 1–2 frame grace for noise). If `D_acc ≥ Tb` over the run → gradual
  transition spanning `[Fs, Fe]`: `Fs`→GO of outgoing slide, `Fe`→REST boundary of incoming.
- Catches the cross-fade where **no single frame crosses `Tb` but the SUM of the dribble does** —
  the exact under-count case.
- Caveat: needs the accumulation threshold + an end-of-run/grace rule, else a noisy sub-`Ts` frame
  splits one dissolve into two.

### B3b. Variance-dip / monochrome-frame (model-based fade signature, 2nd vote)
- Fade-out: frame mean intensity ramps to black, spatial variance ramps to ~0 (monochrome).
- Dissolve `F = (1−α)A + αB`: frame variance dips to a U-shaped minimum mid-transition.
- `variance = mean((cell − frame_mean)²)` over the 768 grid cells — cheap. Fires on ABSOLUTE frame
  stats even when every consecutive diff is tiny → backstops B3 on the darkest fades. Static decks
  (no camera motion) make this far more reliable than the general-video case.

### B4. Settled-frame / representative-keyframe selection — REST fix
Within a hold span, REST should be the calm, sharp center, not the verbatim DP frame (which can sit
on the trailing transition edge):
- **Temporal stability**: `rest = argmin localDiff(i)` over `[start+m, end−m]` (dead-calm middle).
- **Sharpness**: variance-of-Laplacian on grayscale (`Y`) — sharp slides high, motion-blur/mid-fade low.
  Comparable only WITHIN one slide's hold, never across slides; coarse on a 32×18 grid (compute on a
  higher-res crop of candidate frames if precision needed).
- Combined: `argmax [w_s·normVoL − w_d·normLocalDiff]`, or simply argmin-localdiff tie-broken by max-VoL.

### B5. Adaptive thresholding estimators (for Tb/Ts and motion floor)
Slide decks are dominated by near-zero static-hold diffs → mean+k·σ skews low (σ inflated by few spikes).
Prefer:
- **MAD**: `thr = median(D) + k·1.4826·MAD`, robust to the long flat tail.
- **Percentile**: 95th–98th percentile of the diff signal. Simple, shape-agnostic.
- Otsu only as a cross-check (assumes bimodal; the all-static histogram is wildly unbalanced → over-segments).
- Express `min_scene_len`/`defaultTransition` as **seconds × fps**, not raw frames, so they survive
  different exports/framerates.

### Recommended synthesis (priority order)
1. **Multi-channel content score (B1) + AdaptiveDetector ratio (B2)** — kills per-deck tuning, makes
   dark-bg fades visible, improves GO timing + count. Highest leverage.
2. **Twin-comparison (B3) + variance-dip vote (B3b)** — targeted fix for gradual cross-fades / under-count.
3. **Settled+sharp REST (B4)** — fixes Rest landing mid-transition / motion-blurred.
4. Robust adaptive thresholds (B5: MAD/percentile) feed Tb/Ts; min-hold in seconds.

---

## Sources
PySceneDetect ContentDetector/AdaptiveDetector source + docs (scenedetect.com, github.com/Breakthrough);
IJCA "Analysis of Popular Video Shot Boundary Detection Algorithms"; Zhang et al. twin-comparison;
fade/dissolve variance-curve papers (IJCRT, ResearchGate); Otsu (Baeldung); variance-of-Laplacian blur
detection (TheAILearner, OpenCV.org).

## Test setup (existing)
Swift Testing framework. `Tests/HoldDetectorTests.swift` (5 cases: anchor-verbatim Rest, fade default
band, degenerate, dup anchors, over-packed) + `Tests/StillsMatchTests.swift` (DP parity, tie-break,
monotonicity, throw-on-too-few, natural-sort). Pure functions over `[[Double]]` grids → offline-unit-testable.
Build/test via apple-platform-build-tools builder agent. The real-deck harness will be a NEW headless
target/executable that the unit tests cannot replace (synthetic decks hid the original fade bug).
