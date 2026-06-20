# Section-08 Review Interview — VideoDeployView

No user interview needed — every finding is a clear correctness/convention fix with no
genuine tradeoff. All auto-fixed:

## Auto-fixes applied
- **C1** — AVPlayer is now a stored `@State private var player: AVPlayer?`, created once in
  `acceptVideo`, used in `confirmPhase` (no more per-render rebuild).
- **C2** — Added `width`/`height` to `VideoDeployResult` (section-07), populated from
  `analysis`. The complete-phase Framer embed now uses `result.width/height` (the real
  probed ratio), not the racy `videoWidth ?? 1920` fallback. Section-07's happy-path test
  asserts the new dims.
- **I1** — Cancel returns to `.confirm` (coherent state preserved), and `acceptVideo` clears
  `stillPaths`/`result` so a new video never inherits the old deck's stills.
- **I3** — m4v picker type via `UTType(filenameExtension: "m4v")`.
- **I4** — Vercel-token pre-check in `startDeploy` (actionable `.error`, mirrors DeployView).
- **I5** — Settings loaded once in `acceptVideo`, passed to `probeDimensions`; startDeploy
  keeps its own fresh read (matches DeployView's deploy-time read).
- **M1** — `errorMessage` now rendered in `confirmPhase` (empty-stills warning visible).
- **M3** — history/title use the filename WITHOUT extension.
- **M4** — fps clamped to `max(1, …)` when building the request.

## Cross-section amendment
- C2 modifies the already-committed `VideoDeployResult` (section-07). Additive fields only;
  section-07's tests still pass + gained a dims assertion. Documented in both section docs.

## Let go / deferred
- **I2** (extension-only drop validation) — probe is the real validator; acceptable gate.
- **M2/M5** (tab-switch cancel, instant Cancel feedback) — runtime behavior → section-09 live gate.
- **T1/T3** (state-machine extraction + Keynote-format positive tests) — deferred; the
  high-value gap (result dims) is now covered.
