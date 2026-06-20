# Section 06 — Code Review (code-reviewer subagent)

Correct-by-design: 3dp rounding (matches Electron Math.round → viewer/keyframe consumers), cancellation placement, progress monotonicity/terminal 1.0, Swift-6 concurrency.

## Important
- **I1 slideCount inconsistency on dropped grid.** `if let first = grids.first { append }` silently drops a still with an empty grid, yet `slideCount = stillURLs.count` → VideoAnalysis where slideCount != frames.count != timestamps.count (out-of-bounds for any consumer indexing timestamps[slide]). → `guard let first = grids.first else { throw }` (assert the section-04/05 ≥1-grid contract at the boundary; keeps the three counts equal).
- **I2 naturalSort path round-trip hazard.** Sorting path strings then rebuilding URLs via a `Dictionary` keyed on path collapses duplicate paths (could duplicate a slide); also sorts full absolute paths while parity was validated on filenames. → sort the URLs DIRECTLY with the same `.compare(options:.numeric)` comparator naturalSort uses (no dict, no collapse, faithful).

## Nit
- **I3 fps<=0 unguarded** → inf/nan timestamps → corrupt -force_key_frames / invalid {{TS}} JSON. derive uses caller-supplied fps (discards probed fps). → guard fps>0, throw.

## Cross-section watch (Section 07)
- StillsMatch doc says callers must CATCH `matchStillsToFrames` `tooFewFrames` + degrade. derive propagates raw — Section 07/UI must handle it (for the video path, M<N = genuine bad input; a hard error is acceptable). Note for Section 07 review.
