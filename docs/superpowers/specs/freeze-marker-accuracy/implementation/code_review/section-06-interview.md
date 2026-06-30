# Section 06 — Code Review Triage (2 Important findings fixed; index math verified)

Reviewer verified the index/contract math by hand (cut span (i,i+1), gradual (i,lastStrong+1) =
correct Go/Rest frame boundaries) and the grace logic (Fe from lastStrong, never past it). Two real
findings fixed before commit:

## Fixed (Important)
- **resolve() dropped instead of merged (reintroduced the core bug).** A variance-dip span that
  sorted BEFORE the real fade could truncate it → next slide's Rest mid-transition (the exact defect
  the spec kills). → resolve() now MERGES overlapping/adjacent spans (within `mergeGap=2`) into the
  full transition, keeping the longer contributor's kind; min-hold drop applies only to genuinely
  distinct-but-too-close spans. New test `dipBeforeFadeMerges` (covers the full fade, not the dip).
- **`0.5·P95` mixed-magnitude blind spot.** A 30-cut beside 85-cuts → deck-wide `hard≈42.5` → the
  30-cut failed both branches and was dropped. → the hard-cut gate now uses the LOCAL ratio
  (`ratio≥cutRatio`) + `hardFloor` (noise floor), not the deck-wide `hard` — the local spike IS the
  discriminator. New test `mixedMagnitudeCuts` (all 3 cuts detected, incl. the small one). This is
  the §04 P90-term removal's companion fix.

## Fixed (Minor)
- Zero-width variance dip → `end = min(n-1, j)` so Fe > Fs (contract).
- Diff/variance length mismatch → `m = min(diffSignal.count, frameCount-1)` (no out-of-range index).
- >50%-black deck → variance center is the median of NON-ZERO variances (the vote stays alive).

## Documented for §07
- Leading/trailing fade (no flank) isn't a variance-dip transition by design → §07 must handle the
  slide-0 / slide-N edges (first Rest must not land in an opening fade-in). Already in the §07 plan.
- BoundaryDetector is a CANDIDATE detector (can't tell build from fade by pixels) → §07 enforces the
  final per-slide count via the anchor authority.

123/123 green.
