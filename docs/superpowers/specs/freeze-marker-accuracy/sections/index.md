<!-- PROJECT_CONFIG
runtime: swift-xcodebuild
test_command: cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS"
END_PROJECT_CONFIG -->

<!-- SECTION_MANIFEST
section-01-harness-and-fixtures
section-02-quick-wins
section-03-frame-signal
section-04-adaptive-threshold
section-05-rest-selector
section-06-boundary-detector
section-07-holddetector-rewrite
section-08-remeasure-and-validate
END_MANIFEST -->

# Implementation Sections Index — Freeze/Hold-Marker Seed Accuracy

Build/test via the **apple-platform-build-tools builder agent** (one xcodebuild at a time; the test_command
above is the canonical verifier — `xcodegen generate` first because new files change the project). All detector
modules are PURE over `[[Double]]` grids → fast offline unit tests; the REAL-deck harness is the accuracy oracle.

## Dependency Graph

| Section | Depends On | Blocks | Parallelizable |
|---------|------------|--------|----------------|
| section-01-harness-and-fixtures | - | 08 | Yes |
| section-02-quick-wins | - | 08 | Yes |
| section-03-frame-signal | - | 04, 05, 06 | Yes |
| section-04-adaptive-threshold | 03 | 06 | Yes |
| section-05-rest-selector | 03 | 07 | Yes |
| section-06-boundary-detector | 03, 04 | 07 | No |
| section-07-holddetector-rewrite | 05, 06 | 08 | No |
| section-08-remeasure-and-validate | 01, 02, 07 | - | No |

## Execution Order

1. **section-01, section-02, section-03** (no deps — parallel)
2. **section-04, section-05** (parallel after 03)
3. **section-06** (after 03 AND 04)
4. **section-07** (after 05 AND 06)
5. **section-08** (final — needs harness 01, quick-wins 02, new detector 07)

## Section Summaries

### section-01-harness-and-fixtures
Headless `SeedHarness` + `HarnessReport` (per-slide diagnostics, JSON + self-contained HTML montage with
Rest/Go thumbnails and ASCII diff profiles). New SwiftPM/xcodegen executable target wrapping it. Capture the 3
archetype decks (fade/clean-cut/build) + small synthetic grid fixtures under `Tests/Fixtures/`. Path-traversal-safe
output. This is the diagnostic AND re-measurement tool. Also produce the Phase-0 `harness-triage.md` on the real deck.

### section-02-quick-wins
MarkStore `algorithmVersion` in the fingerprint (auto-reseed on algo change; old edits preserved on disk) +
update the two `VideoDeployView` call sites. Fix `VideoDeployer.deploy` to report `analysis.slideCount` not
`marks.count`, with a divergence assertion. Independent, low-risk, individually shippable.

### section-03-frame-signal
`FrameSignal` (pure): per-frame luma/sat/chroma channels from raw-RGB 0–255 grids; multi-channel normalized
weighted-average `diffSignal`; per-frame `frameVariance`. The signal both the threshold + boundary layers consume.
Core dark-fade-visibility fix lives here.

### section-04-adaptive-threshold
`AdaptiveThreshold` (pure): robust dual thresholds (MAD/percentile, Ts<Tb) + fps-relative local-window ratios
with an absolute floor. Replaces the fixed 6.0 with deck-derived, unitless detection.

### section-05-rest-selector
`RestSelector` (pure): settled+sharp Rest within a hold — argmin local-diff tie-broken by variance-of-Laplacian
on luma. Fixes Rest landing mid-transition / blurred; honors margins; degenerate-hold safe.

### section-06-boundary-detector
`BoundaryDetector` (pure): local-ratio cuts + twin-comparison dual-threshold accumulation (with noise grace) +
variance-dip vote; transient-dip vs sustained-black-slide discrimination; min-hold in seconds×fps. Emits
transition spans.

### section-07-holddetector-rewrite
Rewrite `HoldDetector.detect` (same entry shape) to orchestrate FrameSignal→BoundaryDetector→RestSelector:
ONE mark per slide (no silent dedup-drop; collisions flagged), explicit first/last-slide boundaries,
low-confidence-anchor flag, strictly-increasing valid spans. Update `HoldDetectorTests` to the new contract.

### section-08-remeasure-and-validate
Re-run the harness on all archetypes; regenerate the visual report; lock the global parameter set in
`harness-triage.md`. Regression tests over captured real-deck grid fixtures (Rest never inside a transition span).
Full suite green + Release build. Then the manual gates: Edward eyeballs the seed + the iPhone cross-origin-iframe
gate on the real deck before merge.
