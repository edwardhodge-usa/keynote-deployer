# Section 04 — Code Review Triage (CRITICAL findings — reworked before commit)

Reviewer found a ship-blocker: the first cut neutralized detection in the exact 1.5–2.0
dark-fade band the feature targets. All findings addressed (the green tests had dodged the
danger band — the "synthetic deck too clean" trap the project already documented).

## Fixed (Critical)
- **noiseFloor=2.0 erased the dark fade.** The 2.0 floor (also the localRatios denominator)
  sat ABOVE the fade band (1.5–2.0), pinning fade ratios to ~1 (indistinguishable from static).
  → Decoupled the floors: `ratioDenominatorFloor = 0.3` (static-noise level) so a cut edge over
  a dark baseline still ratios large; threshold `hardFloor = 0.5`.
- **gradual (0.8) sat in the noise band.** The old gradual = 0.4·floor = 0.8 couldn't separate a
  1.8 fade from noise. → Explicit `gradualFloor = 0.3`, and the constants are now chosen so the
  design invariant `gradual < fadeStep < hard` holds for a ~1.8 fade (test-proven: gradual≈1.6 <
  1.8 < hard≈4.1). This is THE fix — the gradual/twin path (not localRatios) catches sustained fades.

## Fixed (Important)
- **0.5·max outlier domination** — one giant cut could raise `hard` past smaller real cuts. →
  Replaced raw `max` with `rescueFraction · P95` (percentile, outlier-robust).
- **MAD-collapse** (median-of-deviations = 0 on sparse signals) — now explicitly handled via a
  90th-percentile-gap σ fallback (`max(madSigma, pctSigma)`), so the robust apparatus isn't dead code.
- **No test in the target band** — added the 1.5–2.0 dark-fade-band test (the proof the old code
  failed) + a dark-baseline cut-edge test + a clean-cut test.

## Fixed (Minor)
- Named all constants (rescueFraction, madToSigma 1.4826, p90ToSigma) so §08 can retune.
- `window(forFps:)` now rounds (NTSC-safe: 59.94 → 4), not truncates.

## Documented for §06 (BoundaryDetector)
- **localRatios is a HARD-CUT detector only** — a sustained fade is a plateau (locally a ramp →
  ratio ≈ 1), so §06 must NOT rely on localRatios for fades; the gradual absolute threshold +
  twin-comparison accumulation is the sustained-fade path. End-window clamping biases the first/last
  frames' ratios — §06's edge-slide handling must account for it.

110/110 green.
