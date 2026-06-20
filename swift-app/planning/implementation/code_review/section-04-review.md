# Section 04 — SlideDetector — Code Review

Verdict: **Faithful line-by-line port of `slideDetection.ts`.** Reviewer traced both load-bearing count assertions by hand against TS + Swift; all 7 functions match operator-for-operator (quiet `<=`, merge strict `<`, filter `>=`, factor 0.33, all floors). No critical/important deviations.

## Findings
- **GAP (minor, actionable):** `mergeBuildRunsMergesMicroBuild` checks start/end/lastStart/lastEnd but NOT the recomputed `length` after a merge. A transposition in the length formula (`next.end - cur.start + 1`) would slip through. → add `#expect(merged[0].length == merged[0].end - merged[0].start + 1)`.
- **M1 (cosmetic):** `adaptiveFactor = 0.33` named constant doesn't exist in TS (TS inlines `* 0.33`). Judged an IMPROVEMENT (single source of truth) — keep.
- **M2 (cosmetic, test):** counterfactual uses `.rounded(.down)` vs production `floor` — identical for positives.
- **N1 (nit):** `detectSlidesSingle` passes trivially (1 frame < minQuietRun 8); the empty-`slides[]` deploy-crash class is a DOWNSTREAM (section-07) concern, correctly out of scope here.

## Applied
- Added the merged-`length` assertion to `mergeBuildRunsMergesMicroBuild`.
- Kept `adaptiveFactor` constant.
