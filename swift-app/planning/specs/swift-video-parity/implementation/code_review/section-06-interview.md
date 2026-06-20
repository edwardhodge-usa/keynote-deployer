# Section 06 — Review Triage & Decisions

All findings auto-fixable, no user tradeoff.

## Auto-fixes applied
- **I1:** `guard let first = grids.first else { throw .readerFailed(...) }` — a still that yields no grid is now a hard error, so slideCount == frames.count == timestamps.count always (no inconsistent VideoAnalysis).
- **I2:** stills sorted by `sorted { $0.path.compare($1.path, options: .numeric) == .orderedAscending }` — identical algorithm to StillsMatch.naturalSort but applied directly to URLs, eliminating the Dictionary round-trip dup/collision hazard.
- **I3:** `guard fps > 0 else { throw .corruptFile(...) }` at the top of derive — no inf/nan timestamps from a bad caller fps.

## Noted for Section 07 (not fixable here)
- Section 07 (VideoDeployer) must catch `matchStillsToFrames` `tooFewFrames` and surface it as an actionable error (or degrade) per StillsMatch's doc-comment, AND probe before derive/encode. Recorded for the Section 07 review.
