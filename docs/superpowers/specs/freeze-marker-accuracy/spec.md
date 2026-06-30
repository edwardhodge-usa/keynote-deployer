# Spec: Restore + Improve Freeze/Hold-Marker Seed Accuracy

## Problem

Keynote Deployer (swift-app) automatically analyzes a rendered video deck and
**seeds** freeze/hold markers that the timeline editor then lets the user hand-tune.
Each marker is a `SlideMark { holdStart, holdEnd }`:

- **Rest (holdStart)** = the frame the viewer pauses on (the settled slide).
- **Go (holdEnd)** = the frame the transition to the next slide begins.

Edward reports the **seed markers became LESS ACCURATE** since the recent
timeline-editor work (notably commit `d52b1dc`, which made Rest the DP-match
anchor *verbatim* and dropped the old backward-expansion). All three failure
modes are present at once:

1. **Rest lands on a bad frame** — mid-transition / blurry / not the settled slide.
2. **Go is mistimed** — fires too early (clips the slide) or too late (runs into next).
3. **Wrong marker COUNT** — number of seeded markers ≠ number of slides.

## Current Pipeline (ground-truthed)

```
Video export ─┐                         Per-slide stills ─┐
              ↓                                            ↓
   GridSampler.sample (32×18 RGB, sRGB, .high interp, every frame)
              ↓                                            ↓
        frameGrids [[Double]] (1728×N)        stillGrids [[Double]] (1728×M)
              └──────────────┬───────────────────────────┘
                             ↓
        StillsMatch.matchStillsToFrames  (DP, cost = meanAbs, strictly increasing,
                             ↓            tie-break <= largest-prior-wins) → anchors[Int]
        HoldDetector.detect(frameGrids, anchors, frameCount,
                             ↓            motionThreshold=6.0, defaultTransition=15)
        Rest = anchor verbatim; Go = forward motion onset, else fade fallback band
                             ↓
                     [SlideMark] seed
                             ↓
        VideoDeployer.deploy(marks:) → forcedKeyframeSeconds (∪ holdStart,holdEnd)
                             ↓            + viewerSpans → baked {{TS}} → Vercel
```

### Key files
- `Sources/Services/StillsMatch.swift` — DP match stills→frames → anchors.
- `Sources/Services/GridSampler.swift` — 32×18 sRGB grid sampler (shared by both paths).
- `Sources/Services/HoldDetector.swift` — Rest/Go seed from anchors + motion.
- `Sources/Services/VideoTimestampDeriver.swift` — `derive(...)` orchestrates the pipeline.
- `Sources/Services/VideoDeployer.swift` — `deploy(marks:)` → forced keyframes + viewer spans.
- `Sources/Services/MarkStore.swift` — persists marks by deck fingerprint (can shadow a fresh seed).
- `Tests/HoldDetectorTests.swift`, `Tests/StillsMatchTests.swift` — current unit coverage.

### Tunable parameters (current values)
| Param | File | Default | Role |
|---|---|---|---|
| `motionThreshold` | HoldDetector | 6.0 | per-frame meanAbs grid diff = "moving" |
| `defaultTransition` | HoldDetector | 15 | fallback Go band (frames) when fade undetectable |
| grid W×H | GridSampler | 32×18 | downsample resolution |
| interp | GridSampler | `.high` | downscale averaging |

## Root Suspicions (to confirm by measurement, not assumption)
- Thresholds (`6.0`, `15`) were tuned on **one deck** (ILS Quals) and are **fixed /
  non-deck-adaptive**. Different decks (fade-on-dark, clean cut, build-heavy) have
  different per-frame diff distributions and transition lengths.
- **Verbatim-anchor Rest**: the DP match's anchor may itself land on a transition
  frame (the DP cost just finds the best-matching frame; nothing guarantees it is the
  *settled* frame), so taking it verbatim can put Rest mid-transition.
- **Wrong count**: anchor dedup collapses two slides matched to the same frame; or
  stills count ≠ slide count; or DP mismatches on near-identical consecutive slides.
- A regression may also be a **stale MarkStore** shadowing the seed, or a forced-keyframe
  rounding drift (`round(frame/fps*1000)/1000`) putting the keyframe off the anchor frame.

## Hard Constraint: the real deck is the ONLY oracle
The codebase's own lesson (CLAUDE.md / STATE.md): the HoldDetector motion-diff bug was
invisible on a synthetic deck and only reproduced on the **real fade-heavy deck**.
Synthetic/unit tests prove the cases we already imagined; they cannot characterize the
regression. Therefore:

- **First deliverable must be a headless measurement/diagnostic harness** run on the
  REAL deck that dumps, per slide: matched anchor frame, per-frame grid-diff profile
  around the anchor, seeded Rest/Go, and the gap to ground-truth stills — to localize
  WHERE accuracy is lost (DP match vs Rest choice vs Go threshold vs count).
- Decks available: real 39-slide deck at iCloud `…/Quals Decks/2026 Master Quals
  /Keynote Video for Portal/ILS_Quals 2026 V3.m4v` (+ V3 Images); test deck at
  `~/Desktop/kd-test-deck/` (deck.mp4 + stills/).

## Goal
Restore and improve **seed** accuracy so that, across diverse decks:
- **Rest** lands on a settled (non-transition) frame of the correct slide.
- **Go** brackets the real transition (not too early, not too late).
- **Marker count** equals slide count.

This is about the **automatic seed quality** — the editor hand-tuning stays. Out of
scope: redesigning the timeline editor UI, the encoder, or the viewer. In scope:
StillsMatch, GridSampler (if sampling is implicated), HoldDetector, the derive wiring,
MarkStore shadowing behavior, and a reusable measurement harness + diverse-deck fixtures.

## Definition of done
- A measurement harness exists and runs on the real deck + test deck, emitting a
  per-slide accuracy report.
- Each of the three failure modes is localized to a pipeline stage with evidence.
- Fixes are applied and **re-measured on the real deck** (the oracle), showing Rest on
  settled frames, Go bracketing transitions, count == slides.
- Improvements hold on ≥2 deck archetypes (at minimum fade-on-dark + clean-cut), not
  just the single tuning deck — guarding against re-overfitting.
- Regression-guard tests capture the now-characterized real-deck behavior.
