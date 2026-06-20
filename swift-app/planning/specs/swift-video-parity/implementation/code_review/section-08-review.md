# Section-08 Code Review — VideoDeployView

Reviewer: deep-implement code-reviewer. 64/64 green, Swift 6 clean. Findings are design/correctness/coverage, not compile errors.

## Critical
- **C1 — AVPlayer rebuilt every render.** `VideoPlayer(player: AVPlayer(url:))` is inline in `confirmPhase`; any @State change (fps/name/secureEmbed/probe writes) rebuilds the player → playback resets/stutters + decoder churn. Store the player once.
- **C2 — framerEmbed sources the ratio from racy probe state, falls back to a fabricated 1920/1080.** Root cause: `VideoDeployResult` has no width/height, so the View can't source the ratio from the result and is forced onto `videoWidth ?? 1920`. Add dims to the result (section-07 contract gap); the deployer already has `analysis.width/height`.

## Important
- **I1 — Cancel leaves stale stills.** `catch is CancellationError → phase = .drop` retains prior state; dropping a new video keeps the OLD deck's stills (mismatched deploy hazard).
- **I3 — m4v picker fragile.** `UTType("public.m4v")` is often nil → picker hides .m4v though drop accepts it. Use `UTType(filenameExtension: "m4v")`.
- **I4 — No Vercel-token pre-check.** DeployView guards `!settings.vercelToken.isEmpty` with an actionable error; this view doesn't (relies on a deep deployer failure). Convention divergence.
- **I5 — Settings loaded 3×.** acceptVideo + probeDimensions + startDeploy; mixes stale/fresh. DeployView reads at seed + at deploy. Consolidate.
- **I2 — Drop validates by extension string only** (probe is the real validator). Acceptable first gate; noted.

## Minor
- **M1 — "No images in folder" set on `errorMessage` but confirmPhase never renders it** → invisible.
- **M3 — title carries the file extension** (`Deck.mp4`). DeployView uses a clean title.
- **M4 — fps TextField bypasses the Stepper 1...120 range** → fps=0 reaches the request (derive throws, but clamp at the View).
- **M2/M5 — onDisappear cancel may not fire on tab switch; Cancel has no instant feedback** → live-gate checks (section-09).

## Test gaps
- **T1/T2/T3** — only the 4 pure-logic helpers tested. The embed-fallback, cancel/reset state machine, and empty-token gate are untested. Add a result-dims assertion (after C2); state-machine extraction deferred.

## Convention alignment (good)
Drop zone, NSOpenPanel, FileOperations.loadSettings/.default, HistoryEntry (folderPath=result.folderPath, fixesApplied=0), NSPasteboard auto-copy gated on autoCopyUrl, AppConfig.toKebabCase, Task { @MainActor } hop — all mirror DeployView. framerEmbed byte-matches GifViewer.tsx (the correct model for the video path, not DeployView's bare iframe). NavigationTab/.video + ContentView correct; no GIF tab.
