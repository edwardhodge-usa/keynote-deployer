# TDD Plan: Freeze/Hold-Marker Seed Accuracy

Framework: **Swift Testing** (`@Test`/`@Suite`, `#expect`), matching existing `Tests/`. All detector logic is
pure over `[[Double]]` grids → offline-unit-testable. Tests are written BEFORE each section's implementation.
Stubs below are prose/signatures only — the implementer writes the assertions.

Conventions (existing): one suite file per module under `Tests/`; small synthetic grid sequences inline; shared
fixtures under `Tests/Fixtures/`. Run via apple-platform-build-tools builder agent. **The unit tests prove the
cases we imagined; the harness on the REAL deck is the oracle for accuracy — both required.**

---

## Phase 0 — Harness + triage  → `Tests/SeedHarnessTests.swift`
- Test: `SeedHarness.run` on a tiny synthetic deck (stub encoder returning known grids + matching stills)
  produces one `PerSlideDiagnostic` per still.
- Test: `markCount == slideCount` for a clean synthetic deck.
- Test: `anchorCollidedWithPrevious == true` when two stills are crafted to match the same frame.
- Test: `HarnessReport.writeJSON` emits valid JSON with per-slide entries; `writeVisualReport` writes a
  self-contained HTML file (exists, non-empty, references each slide thumbnail).
- Test: output path built from a `deckName` containing `../` / slashes does NOT escape `outputDir`
  (path-traversal guard).
- (Manual/integration, not unit) run the harness on the REAL fade deck → produces the triage report.

## Phase 1 — Quick wins

### 1.1 MarkStore versioning → extend `Tests/` (new `MarkStoreTests.swift` if absent)
- Test: `fingerprint(... algorithmVersion: 1)` ≠ `fingerprint(... algorithmVersion: 2)` for same video/frames/fps.
- Test: marks saved under v1 are NOT loaded when the current `algorithmVersion` is 2 (fresh seed wins); the v1
  entry still exists on disk (load with explicit v1 returns it).
- Test: same-version round-trip (save v2 → load v2) returns the saved marks (hand-edits persist within a version).

### 1.2 Count-reporting → extend `Tests/VideoDeployerTests.swift`
- Test: `VideoDeployer.deploy` result `slideCount == analysis.slideCount` (not `marks.count`) including a case
  where they would have diverged pre-fix.
- Test: a diagnostic/assertion fires (or is recorded) when `marks.count != analysis.slideCount`.

## Phase 2 — Signal layer → `Tests/FrameSignalTests.swift`
- Test: `channels` on a known solid-color grid returns expected luma/sat/chroma (hand-computed).
- Test: `diffSignal` is ~0 between two identical grids; large between black↔white grids.
- Test: **dark-fade discrimination** — a synthetic cross-fade between two DIFFERENT dark images yields a
  non-trivial sat/chroma-weighted `diffSignal` even though the raw-RGB mean-abs diff is near zero (the core
  fix; assert the multi-channel score separates them where mean-abs does not).
- Test: `frameVariance` ≈ 0 for a monochrome grid, high for a high-contrast grid.
- Test: `diffSignal.count == frameGrids.count - 1`.

## Phase 3 — Boundary detection

### 3.1 AdaptiveThreshold → `Tests/AdaptiveThresholdTests.swift`
- Test: `dualThreshold` on a signal of mostly-zeros with a few spikes returns `gradual < hard` and both above
  the static-noise floor (robust to the long flat tail — MAD/percentile, not skewed by spikes).
- Test: `localRatios` peaks sharply at an injected single-frame spike; stays ~1 across a uniformly rising ramp
  (build motion raises neighbors too → ratio stays low).
- Test: window is fps-relative (`max(2, Int(fps/15))`) — a higher fps yields a wider window.

### 3.2 BoundaryDetector → `Tests/BoundaryDetectorTests.swift`
- Test: clean hard cut (one big diff spike) → one `.cut` span at the right frame.
- Test: **gradual cross-fade** (a run of small sub-`Tb` diffs that SUM past `Tb`) → one `.gradual` span
  `[Fs, Fe]`, NOT zero spans and NOT split into many (twin-comparison accumulation works).
- Test: **noise grace** — a gradual run with one single sub-`Ts` dropout frame still yields ONE span (grace
  rule), not two.
- Test: **black-SLIDE vs fade-to-black** — a SUSTAINED low-variance run ≥ minHoldSeconds is treated as a hold
  (no transition emitted); a SHORT variance dip is a transition. (The Gemini edge case.)
- Test: `minHoldSeconds` honored — two cuts closer than minHold×fps don't both register.
- Test: build-heavy sequence (intra-slide motion below cut ratio) does NOT manufacture extra transitions.

### 3.3 HoldDetector rewrite → update `Tests/HoldDetectorTests.swift`
- Test: **one mark per slide, always** — `marks.count == anchors.count` even when two anchors collide in one
  detected hold (no silent dedup-drop); the collision is flagged, not dropped. (Replaces the old
  `duplicateAnchors → count 1` test, which encoded the bug.)
- Test: marks strictly increasing, each `holdEnd < next holdStart`, all within `[0, frameCount)` (keeps
  `SlideMarkLogic.isValid`).
- Test: first slide `holdStart` lands in `[0, transitions[0].start]`; last slide `holdEnd == frameCount-1`.
- Test: Go (`holdEnd`) == detected outgoing transition start for an interior slide.
- Test: `lowConfidenceMatch` set when an anchor is crafted far from any detected hold.
- Test: on the captured REAL fade-deck grid fixture, Rest frames are NOT inside a transition span (the original
  bug class) — regression guard.

## Phase 4 — Rest selection → `Tests/RestSelectorTests.swift`
- Test: within a hold whose middle frames are calm and edges are moving, `restFrame` returns an interior
  (calm) frame, not an edge frame (no trailing-edge seek-back).
- Test: given two equally-calm candidate frames where one is a blurred/low-contrast variant, the sharper
  (higher variance-of-Laplacian on luma) frame wins the tie.
- Test: margin respected — never returns `start` or `end` when interior frames exist.
- Test: degenerate 1–2 frame hold returns a valid in-range frame (no crash).

## Phase 5 — Re-measure + regression
- Existing `StillsMatchTests` stay green (DP-match contract unchanged).
- New captured-grid fixtures (cut / cross-fade / build) drive the BoundaryDetector + HoldDetector regression
  tests above — these encode the now-characterized real-deck behavior.
- Full suite green + Release build (builder agent) + the iPhone cross-origin-iframe gate on the real deck are
  the release gates (manual, not unit).
