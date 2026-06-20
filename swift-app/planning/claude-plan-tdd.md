# TDD Companion — GIF Deploy (Swift Port, Phase 1)

Tests-first stubs mirroring `claude-plan.md`'s task structure. **Framework: Swift Testing** (`@Test`/`#expect`/`#require`), new test target added to `project.yml` (regenerate with `xcodegen generate`; never commit a worktree-regenerated `project.pbxproj`). Stubs are prose/signatures — the implementer writes the bodies. Pure-unit tests run offline; live tests need `TEST_GIF` (Edward-supplied) and run at /deep-implement time.

Conventions: one test file per service under `swift-app/Tests/`; suite name mirrors the type; use `#expect` for soft asserts, `#require` to unwrap. Fixtures (committed): the Electron-generated `index.html` for known inputs; small synthetic diff arrays inline.

---

## Task 1 — Gate-0 compositing spike (LIVE, needs TEST_GIF)
- Test: decoding frame 0 and a late frame N of `TEST_GIF` via ImageIO yields images whose pixel dimensions equal the GIF canvas size (not a sub-rect patch).
- Test: late frame N differs structurally from frame 0 (sampled diff > 0) AND looks like a full slide, not a sliver — record the determination (full-frame: yes/no).
- (If spike fails) Test: the fallback `GifCompositor` reproduces a full frame for index N matching the browser composite reference.

## Task 2 — `GifFrameSource` (mixed: unit + LIVE)
- Test (LIVE): `init(gifURL:)` on `TEST_GIF` reports the known frame count.
- Test (LIVE): `nextFrame()` returns non-nil full-canvas `CGImage`s and advances; returns nil past the end.
- Test: `init` throws `GifDeployError.tooFewFrames` for a 1-frame GIF and a 0-frame/corrupted GIF (tiny committed fixtures).
- Test: `frames(at:)` returns exactly the requested indices and no others.
- Test (perf/behavioral): a full detection pass never retains more than one decoded image at a time (assert via a decode-count/peak hook or by design review — no full-array retention API exists).

## Task 3 — `GridSampler`
- Test: `meanAbs([], [])` == 0; `meanAbs` matches hand-computed value on known equal-length vectors.
- Test: `sample(image)` returns a vector of length `gridSize*gridSize*3` (RGB only, no alpha).
- Test: `frameDiffs` returns an array of length `frameCount`, with `diffs[0] == 0`.
- Test: `frameDiffs` returns `[]` for a 0/1-frame source (defensive path).
- Test: `frameDiffs` throws/propagates `CancellationError` when its `Task` is cancelled mid-stream.

## Task 4 — `SlideDetector` (ported Vitest cases)
- Test: `findQuietRuns` flags runs of ≥ `minQuietRun` consecutive frames with diff < `quietThreshold`.
- Test: `mergeBuildRuns` merges micro-build gaps between quiet runs (port the TS "merges only clearly-tiny micro-build gaps" case).
- Test: `filterTransitionArtifacts` uses `adaptiveMin = max(minQuietRun, floor(median(lengths) * 0.33))` — include the case that 0.5 would wrongly drop but 0.33 keeps (the briefly-held real slide).
- Test: `buildSlideMap` produces `restFrame/holdStart/holdEnd` consistent with the runs.
- Test: `detectSlides` on the ported synthetic diff arrays yields the expected slide counts (mirror each Electron Vitest expectation).
- Test: `detectSlides([])` and single-element input return `[]`.
- Test: `recomputeTransitions` sets `transition.start = prev.holdEnd+1`, `.end = next.holdStart-1`; inverted/overlapping ⇒ `transitionFrames == nil`.

## Task 5 — Shared viewer template asset
- Test: the extracted `viewer-template.html` contains exactly the three placeholders `{{GIF_FILENAME}}`, `{{BAKED_SLIDES}}`, `{{SECURE_EMBED}}` and no stray un-substituted braces.
- Test: filling the template with a fixture input reproduces the captured Electron viewer (shared half of the Task-6 gate).

## Task 6 — `GifViewerGenerator` (byte-identical gate)
- Test (GATE-1): `generate(gifFilename:secureEmbed:slides:)` output is **byte-identical** to the committed Electron `generateGifViewerHtml(...)` output for ≥2 fixture inputs (secureEmbed true and false).
- Test: baked-slides substring equals `JSON.stringify(slides)` exactly — compact, key order `restFrame,holdStart,holdEnd,transitionFrames`, `null` for absent transition. Explicitly assert it is NOT alphabetical (guards against an accidental `.sortedKeys` regression).
- Test: empty `slides` ([]) produces valid HTML with `BAKED_SLIDES = []` (guards the zero-slide deploy-crash class).
- Test: `secureEmbed=true` includes the secure-embed block; `false` omits it — matching Electron.

## Task 7 — `GifDeployer` (LIVE integration, needs TEST_GIF + Vercel)
- Test: creates a unique temp directory via `FileManager` (not a predictable `/tmp` path); the dir contains the GIF + `index.html`; dir is removed after deploy.
- Test (GATE-2, LIVE): full `deploy(_:settings:onProgress:)` on `TEST_GIF` returns a `DeployResult` with a reachable URL; progress steps are emitted in order.
- Test: on success a `HistoryEntry` is persisted with `folderPath == gifPath`, `fixesApplied == 0`, `slideCount == slides.count`.
- Test: a `VercelDeployer` failure surfaces as `GifDeployError.vercelDeployFailed` (inject a failing deployer or use sandbox/stub).

## Task 8 — `GifDeployView` + navigation (UI/runtime gate)
- Test: `NavigationTab.allCases` now includes `.gifDeploy`; `ContentView` routes it to `GifDeployView`.
- Test (runtime, Peekaboo): selecting `TEST_GIF` advances selectGif→loading→confirm and renders exactly `slides.count` thumbnails.
- Test (runtime): UI remains responsive during loading/processing (work is off-main) — e.g. a control stays interactive while processing.
- Test (runtime): Cancel during loading aborts promptly and returns to selectGif (no thumbnails, no crash).
- Test (runtime): each `GifDeployError` case maps to its intended user-facing message in the error phase.
- Test (runtime): confirm phase shows the seed-quality "best-effort preview" note.

## Cross-cutting
- Establish the Swift Testing target in `project.yml`; verify `xcodebuild test -scheme KeynoteDeployer` discovers and runs the new suite (Stage 1 of the repo's verify loop) before any runtime/Peekaboo gate.
