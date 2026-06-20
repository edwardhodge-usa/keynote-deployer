<!-- PROJECT_CONFIG
runtime: swift-xcode
test_command: cd swift-app && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS"
END_PROJECT_CONFIG -->

<!-- SECTION_MANIFEST
section-01-foundation-and-models
section-02-frame-source
section-03-grid-sampler
section-04-slide-detector
section-05-viewer-generator
section-06-gif-deployer
section-07-view-and-navigation
END_MANIFEST -->

# Implementation Sections Index — GIF Deploy (Swift Port, Phase 1)

Source: `claude-plan.md` (implementation) + `claude-plan-tdd.md` (tests-first). Scope: Phase 1 (Auto path) only. All structs `Codable, Sendable`; tests use Swift Testing.

## Dependency Graph

| Section | Depends On | Blocks | Parallelizable |
|---------|------------|--------|----------------|
| section-01-foundation-and-models | - | all | Yes (first) |
| section-02-frame-source | 01 | 03, 07 | Yes (with 04, 05) |
| section-03-grid-sampler | 02 | 07 | No |
| section-04-slide-detector | 01 | 07 | Yes (with 02, 05) |
| section-05-viewer-generator | 01 | 06 | Yes (with 02, 04) |
| section-06-gif-deployer | 05 | 07 | No |
| section-07-view-and-navigation | 02, 03, 04, 06 | - | No |

## Execution Order

1. **section-01-foundation-and-models** (no deps)
2. **section-02-frame-source**, **section-04-slide-detector**, **section-05-viewer-generator** (parallel after 01)
3. **section-03-grid-sampler** (after 02)
4. **section-06-gif-deployer** (after 05)
5. **section-07-view-and-navigation** (after 02 AND 03 AND 04 AND 06)

## Section Summaries

### section-01-foundation-and-models
Add the Swift Testing target to `project.yml` and regenerate (`xcodegen generate`; never commit a worktree-regenerated `project.pbxproj`). Create `Models/GifDeploy.swift` — `GifDeployRequest`, `DetectedSlide`, `TransitionRange`, `QuietRun` (mirror Electron `src/types` field-for-field) — and the `GifDeployError` enum. Foundation that everything else imports. (Plan §4, Task 8 error enum.)

### section-02-frame-source
The gate-0 ImageIO compositing spike (Task 1, BLOCKS the compositing decision) + `GifFrameSource` (streaming forward decode, `tooFewFrames` guard, targeted `frames(at:)` for thumbnails). Builds `GifCompositor` only if the spike fails. Live tests need `TEST_GIF`. (Plan §2, Tasks 1–2.)

### section-03-grid-sampler
`GridSampler` — 1000-point 32×32 RGB sampling, `meanAbs`, streaming `frameDiffs` (one image held at a time, cancellation-aware). Consumes `GifFrameSource`. (Task 3.)

### section-04-slide-detector
`SlideDetector` — verbatim port of the Auto quiet-run algorithm (constants 0.3 / 8 / 0.5; adaptive-median factor **0.33**) + `recomputeTransitions` boundary math. Pure array math; ports the Electron Vitest cases incl. degenerate-input → `[]`. (Task 4.)

### section-05-viewer-generator
Extract the canonical `Resources/viewer-template.html` (placeholders `{{GIF_FILENAME}}`/`{{BAKED_SLIDES}}`/`{{SECURE_EMBED}}`) from `gifViewerGenerator.ts` (Electron untouched) + `GifViewerGenerator.swift`. GATE-1: output byte-identical to current Electron viewer; baked slides match `JSON.stringify` (NOT `.sortedKeys`); XSS dev-note. (Tasks 5–6.)

### section-06-gif-deployer
`GifDeployer` — secure `FileManager` temp dir → copy GIF → write index.html → `VercelAPI.ensureProject` → `VercelDeployer.deploy` → `HistoryEntry` (`folderPath=gifPath`, `fixesApplied=0`). Reuses the existing backend unchanged. GATE-2 live test. (Task 7.)

### section-07-view-and-navigation
`NavigationTab` (+`case gifDeploy`) + `ContentView` routing + `GifDeployView` phase machine (selectGif→loading→confirm→processing→complete→error), off-main cancellable `Task`, static restFrame thumbnails (separate decode pass), seed-quality note, error-case messages. Runtime/Peekaboo gate. (Task 8.)
