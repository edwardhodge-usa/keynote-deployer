# Section 04 — SlideDetector — Review Triage & Decisions

No live user interview — faithful port, no security/money/UX tradeoff. Decisions by the implementing agent.

| Finding | Decision | Action |
|---------|----------|--------|
| GAP — merged `length` unasserted | **FIX** | Added `#expect(merged[0].length == merged[0].end - merged[0].start + 1)` to `mergeBuildRunsMergesMicroBuild`. |
| M1 — `adaptiveFactor` constant not in TS | **KEEP** | An improvement (self-documenting, single source of truth); behavior identical (0.33). |
| M2 — `.rounded(.down)` vs `floor` in test counterfactual | **LET GO** | Identical for the positive values used; cosmetic. |
| N1 — `detectSlidesSingle` oversells | **LET GO** | Empty-`slides[]` crash guard is a section-07 (consumer) concern; this section correctly returns []. |
