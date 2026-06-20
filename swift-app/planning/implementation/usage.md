# GIF Deploy (Swift port) — Usage & Status

Built via `/deep-implement` on branch `feat/gif-deploy-swift` (2026-06-19). Ports the
Electron GIF-deploy path to the Swift app. Phase 1 = **Auto** boundary detection only
(seed quality); Stills/Manual arrive later.

## What it does

On the **GIF Deploy** tab: pick a Keynote-exported animated GIF → the app decodes frames
off-main, detects slide boundaries, generates a self-contained interactive HTML viewer
(byte-identical to the Electron viewer), and deploys it to Vercel. Output: a live URL +
a History entry.

## Pipeline (Swift)

```
GifFrameSource (ImageIO streaming decode)
  → GridSampler.frameDiffs (32×32 RGB, 1000-pt, streaming, cancellable)
  → SlideDetector.detectSlides (quiet-run algorithm → [DetectedSlide])
  → GifViewerGenerator.generate (viewer-template.html + baked slides → index.html)
  → GifDeployer.deploy (temp dir → copy GIF → write index.html → VercelAPI/VercelDeployer)
  → GifDeployResult → view inserts HistoryEntry (folderPath=gifPath, fixesApplied=0)
```

## Sections / commits

| Section | What | Commit |
|---|---|---|
| 01 foundation + models | GifDeploy models, GifDeployError, Swift Testing target | f1f30e3 |
| 02 frame source | GifFrameSource (ImageIO, no compositor) | 839f1a3 |
| 03 grid sampler | GridSampler (streaming diffs) | 072d2a4 |
| 04 slide detector | SlideDetector (quiet-run port) | 37f0347 |
| 05 viewer generator | GifViewerGenerator + viewer-template.html (byte-identical GATE-1) | 26da67f |
| 06 gif deployer | GifDeployer orchestrator (Vercel reuse, injectable seams) | 5bdfd6f |
| 07 view + navigation | GifDeployView phase machine + tab wiring | e2fab55 |

## Verification status

- **Offline: 58/58 Swift Testing green** (build clean under Swift 6) — includes GATE-1
  byte-identical viewer, JSON parity, GifDeployer temp-dir/failure-mapping, navigation/error mapping.
- **GATE-1 (viewer byte-identity):** PROVEN against committed Electron fixtures (secure true/false/empty).
- **PENDING — needs Edward + a real `TEST_GIF`:**
  - **Runtime / Peekaboo visual gate** (Stage 2): tab appears, GIF selection advances
    selectGif→loading→confirm, exactly N thumbnails, UI responsive during loading (off-main),
    Cancel aborts promptly, error messages, seed-quality note.
  - **GATE-2 live deploy:** real GIF → real Vercel deploy → reachable navigable viewer URL.
    Test `gate2LiveDeployProducesReachableUrl` is skip-when-absent; run with
    `TEST_GIF=<path>` env + a configured Vercel token, or exercise via the UI.

## To finish / ship

1. Run the live runtime gate (above) — `xcodebuild` builds a fresh app; launch it, drive the GIF Deploy tab.
2. Regenerate fixtures if the Electron viewer ever changes: `node swift-app/Tests/Fixtures/generate-fixtures.mjs`.
3. `/release` (notarize + DMG + Sparkle appcast) once the live gate passes — this feature is NOT yet released.

## Notes / gotchas baked in

- Viewer template is machine-extracted from `electron/gifViewerGenerator.ts` via sentinel
  reverse-substitution — do not hand-edit; regenerate.
- `BAKED_SLIDES` JSON is hand-assembled to match `JSON.stringify` (NEVER `.sortedKeys`).
- Single-pass placeholder fill (no rescan of injected values) preserves Electron parity.
- Detection pipeline runs off-main (`nonisolated async`); thumbnails are a separate bounded pass.
- `GifDeployer` reuses the existing Vercel backend unchanged; the view (not the deployer) persists history.
