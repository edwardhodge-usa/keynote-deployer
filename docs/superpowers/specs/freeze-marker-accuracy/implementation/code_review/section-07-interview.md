# Section 07 — Code Review Triage (validity sound; 2 contract gaps fixed)

Reviewer hand-verified that every KEPT mark satisfies SlideMarkLogic.isValid (the editor's hard
dependency) and that flag arrays stay aligned — both confirmed correct. Two real gaps fixed:

## Fixed (Important)
- **Count-loss on tail-clustered / duplicate anchors** (`[8,8,9]` dropped a slide though n≤bound) —
  resurrected goal-#1's bug for the collision case (not a field bug: real StillsMatch is strictly
  increasing). → ROOM-RESERVING normalization: holdStart_i capped at `bound-(n-i)` so the remaining
  slides always have distinct frames; holdStart may legally sit below the anchor. Now ONE mark per
  anchor for every n≤bound. New test `clusteredAnchorsPreserveCount` ([21,21,22] → 3 valid marks).
- **lowConfidence half-built** — only flagged anchors INSIDE a span. → added the distance check
  (anchor > 1.5·fps frames from its assigned hold → flagged), completing the StillsMatch-suspect signal.

## Fixed (Minor)
- Signal/variances now computed over the truncated `bound` horizon (was full `frameGrids`) so a
  `frameCount < frameGrids.count` caller can't desync lengths or let a span reference a frame ≥ bound;
  RestSelector range clamped in-bounds (prevents an out-of-range index).
- Removed the dead `hs = min(hs, he)` line; corrected the doc comment's count guarantee.

126/126 green.
