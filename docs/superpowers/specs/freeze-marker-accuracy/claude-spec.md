# Synthesized Spec: Freeze/Hold-Marker Seed Accuracy

## What we're building
Restore and improve the **automatic seed** that places Rest (hold-start) and Go (hold-end)
markers on a rendered video deck in Keynote Deployer (swift-app). The timeline editor's hand-tuning
stays; this is about the seed quality the user starts from. Two workstreams:

1. **Diagnose** — a headless measurement harness, run on the REAL decks (the only honest oracle), that
   localizes each failure mode to a pipeline stage with evidence, and rules in/out the two non-algorithm
   culprits before any algorithm change.
2. **Fix** — quick wins (MarkStore shadowing + count bug), then a research-backed algorithm upgrade that
   replaces fixed thresholds with deck-adaptive, multi-channel, gradual-transition-aware detection and a
   settled-frame Rest.

## Failure modes (all present)
- **Rest** on a bad/mid-transition/blurry frame.
- **Go** mistimed (clips the slide or runs into the next).
- **Marker COUNT** ≠ slide count.

## Confirmed culprits (from regression-diff)
- 🔴 **MarkStore shadowing** — fingerprint `frameCount-fps-fileSize` is identical across algorithm
  versions, so re-deploying the same deck loads OLD saved marks over the fresh seed. Prime explanation
  for "less accurate since our changes." **Rule out first.**
- 🔴 **Dedup/count** — `HoldDetector` dedups colliding anchors; `VideoDeployer` reports `marks.count`
  not `analysis.slideCount`. Drops markers when two stills match the same frame.
- ⚪ The `d52b1dc` verbatim-anchor Rest change was a correct fade fix, but assumes the DP anchor is a
  settled frame — which nothing guarantees (drives the Rest failure).

## Algorithm direction (research-backed, replaces fixed thresholds)
1. **Multi-channel content score** (luma + saturation/chroma deltas, normalized weighted average) so
   dark-background cross-fades register at all — over the existing 32×18 grid.
2. **AdaptiveDetector local-window ratio** (unitless `~3×` neighbor baseline + absolute floor + min-hold)
   replacing the fixed `motion=6.0` → kills per-deck tuning, improves Go timing + count.
3. **Twin-comparison dual-threshold** (Tb hard / Ts gradual, accumulate sub-Tb diffs with a grace rule)
   + **variance-dip/monochrome vote** for gradual fades → fixes under-count on dark dissolves.
4. **Settled+sharp Rest** — within each hold, `argmin local-diff` tie-broken by `max variance-of-Laplacian`
   (grayscale) → Rest lands on the calm, fully-rendered frame, not the verbatim anchor.
5. Robust adaptive thresholds (MAD/percentile, not mean+kσ) feed Tb/Ts; min-hold expressed in seconds×fps.

## Decisions (from interview)
- **Harness first, then full upgrade.**
- **Auto re-seed on algorithm change**: add an algorithm-version component to the MarkStore key; old
  hand-edits preserved under the old key but a new algo always shows the fresh seed.
- **Three deck archetypes**: fade-on-dark (have), clean-cut (Edward provides), build-heavy (Edward provides).
- **Oracle = Edward eyeballs the seed in the editor + iPhone gate** → harness output must be VISUAL
  (per-slide montage of seeded Rest/Go frames), not just numbers.
- New algorithm **replaces** the verbatim-anchor path (no toggle).
- Build via deep-implement (TDD). /workflow optional for parallel 3-deck measurement + adversarial review.

## Out of scope
Timeline editor UI redesign, the H.264 encoder, the deployed viewer behavior, the DP stills-match core
(unless measurement implicates it). In scope: GridSampler signal, HoldDetector algorithm, the score/
threshold layer, MarkStore keying, the count-reporting bug, the harness + fixtures + regression tests.

## Definition of done
- Harness runs on all available decks, emits a per-slide visual + numeric accuracy report.
- Each failure mode localized to a stage with evidence; MarkStore + count culprits resolved.
- Algorithm upgrade applied, **re-measured on the real deck**, Rest on settled frames / Go bracketing
  transitions / count == slides.
- Holds on ≥2 archetypes (fade + clean-cut minimum), guarding re-overfit.
- Regression tests capture the characterized real-deck behavior; full suite green; Release build passes;
  iPhone cross-origin-iframe gate passes on the real deck before merge.
