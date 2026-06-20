# Section 04 — Review Triage & Decisions

All findings are robustness/correctness fixes with no user-facing tradeoff → auto-fixing I1–I4, N3, N4; N1 gets a comment; N2 left (correct-by-design for Keynote ≤30fps + ffmpeg escape hatch).

## Auto-fixes applied
- **I1:** `assertConstantFrameRate` now compares each inter-frame delta to the expected `1/fps` and rejects only when ≥2 deltas deviate >25% — better-shaped than mean-relative 10% (catches gross VFR, tolerates encoder jitter). fps passed in from probe.
- **I2:** `runEncode` sizes the writer to the RAW `naturalSize` (matches the untransformed frames the reader emits) — no oriented/raw dimension mismatch on rotated sources. probe keeps oriented dims (viewer aspect ratio). Identical for Keynote (identity transform).
- **I3:** ForceKeyFrame attachment → `kCMAttachmentMode_ShouldNotPropagate` (correct one-shot semantic).
- **I4:** readiness poll bounded by a stall watchdog (~30s of no progress → `.writerFailed`) so a wedged encoder errors instead of hanging.
- **N3:** `sampleGrids` CIContext pinned to sRGB working+output color space (matches GridSampler's sRGB redraw / the stills path); added `frameAndStillGridsMatchForSolidColor` test asserting a solid-color video frame and a solid-color still yield near-identical grids.
- **N4:** `sampleGrids` throws `.readerFailed` on an unexpected nil image buffer / CGImage instead of silently dropping a frame (would shift Section-06 DP alignment).

## Not changed
- **N1:** added a contract comment (encodeWithKeyframes assumes a probed, CFR, integer-fps source; Section 07 enforces probe-first). 
- **N2:** bitrate heuristic left — Keynote exports are ≤30fps and the plan biases to quality + human review, with the ffmpeg fallback as escape hatch.
