# Section 04 — Code Review (code-reviewer subagent)

No Critical. Findings below; verified-correct items omitted (concurrency, cancellation, explicit-timing rebuild, forcedKeyframeFrameIndices, out-of-scope boundaries, faststart/output settings).

## Important
- **I1** VFR tolerance is relative-to-mean 10% — wrong shape: false-accepts ~9% steady jitter, false-rejects on small N. → compare deltas to expected 1/fps, require ≥2 violations.
- **I2** runEncode sizes the writer to ORIENTED (transform-applied) dims but appends RAW (untransformed) frames → dimension mismatch on any rotated source. (Keynote=identity so masked.) → size writer to RAW naturalSize (we don't rotate pixels).
- **I3** ForceKeyFrame attachment uses ShouldPropagate; a one-shot encoder hint should be ShouldNotPropagate.
- **I4** 5ms readiness poll has no timeout → a wedged encoder hangs forever (only Task-cancel escapes). → bounded stall watchdog throwing .writerFailed.

## Nits
- **N1** integer-timescale rebuild + round(t*fps) is contingent on integer fps; encodeWithKeyframes itself doesn't call assertConstantFrameRate (only probe does). Section 07 must enforce probe-before-encode. → add contract comment.
- **N2** bitrate heuristic hardcodes 30fps. Keynote ≤30 → fine. (left, quality-biased + ffmpeg escape hatch)
- **N3** sampleGrids routes frames through an unpinned default CIContext → color hop stills don't take; risks violating A3 "same grid." → pin CIContext to sRGB + add frame-vs-still grid-equality test.
- **N4** sampleGrids silently drops nil frames (shifts Section-06 DP alignment). → throw .readerFailed on unexpected nil.
