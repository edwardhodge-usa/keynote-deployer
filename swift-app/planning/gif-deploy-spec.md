# GIF Deploy — Swift Port Scope

**Status:** Scoping (no code written). Source of truth = Electron implementation.
**Date:** 2026-06-19
**Goal:** Bring the Electron-only "GIF Deploy" feature family to the Swift app, reusing the existing Swift Vercel deploy seam.

---

## 1. What GIF Deploy is (and why it exists)

Keynote's HTML export rasterizes images to low-res 266×150 thumbnails; the 7 HiDPI fixes only repair text/vectors, not raster images. For image-heavy decks the HTML path looks bad. GIF Deploy is the fallback: deploy the deck as an animated GIF behind a self-contained interactive slide viewer (forward/back/dots/keyboard/touch). 256-color GIF bands on photos/gradients — "better than broken," not lossless.

**Boundary problem (the hard part):** the deployed viewer needs to know where each *slide* starts/ends within the GIF's frames. Frame-diff detection **cannot** reliably tell a real slide from a build/fade step on held-build or constant-background decks (proven 2026-06-19; six pixel signals rejected). So boundaries are computed **at build time** from one of three sources and **baked** into the viewer as a `DetectedSlide[]` JSON literal. The viewer never detects — it just navigates the baked list.

Three boundary sources (priority order):
- **Stills** (accurate): per-slide JPEG/PNG exports from Keynote, matched to GIF frames via DP alignment. Deck-agnostic, verified 39/39 + 22/22 on real decks.
- **Auto** (seed only, never authoritative): quiet-run on per-frame pixel diffs.
- **Manual**: user grid editor — override when Auto/Stills unavailable or wrong.

---

## 2. ⚠️ TOP RISK — GIF frame compositing (corrects the exploration)

The exploration's "Swift can skip compositing — ImageIO gives random-access full frames, just diff each frame" is **likely wrong for Keynote GIFs** and is the single biggest port risk.

- CLAUDE.md (2026-06-19) records the GIF is **`disposalType=1` (do-not-dispose)** → frames are stored as **partial patches** layered on prior state, which is exactly why the browser viewer composites `0→N` progressively and cannot random-access.
- `CGImageSourceCreateImageAtIndex` returns each frame **as stored** — it does **not** auto-composite GIF disposal. For a disposal=1 GIF, that's a partial patch image, not the full rendered slide.
- **Consequence:** if the Swift detector diffs raw ImageIO frames, the diffs are garbage (patch-vs-full), and quiet-run/Stills both break.
- **Required:** the Swift detector must replicate the progressive composite (accumulate patches honoring disposal) **before** sampling + diffing — same algorithm the browser viewer already runs. ImageIO buys frame *access* and delays, not freedom from compositing.

**Action:** Phase 1 must include a `GifCompositor` (CGContext accumulate + disposal handling) and a verification harness that compares Swift-composited frame N against the browser viewer's composite for the same GIF before trusting any boundary output. Do **not** accept the "just diff raw frames" shortcut.

Second risk: **viewer HTML drift.** `gifViewerGenerator.ts` (~570 lines, embeds gifuct-js + compositing + playback) is the deployed product. Re-implementing it as Swift string-building invites silent divergence from the Electron viewer. **Recommendation:** extract the canonical viewer into a **shared template asset** (one HTML/JS file with `{{GIF_FILENAME}}` / `{{BAKED_SLIDES}}` / `{{SECURE_EMBED}}` placeholders) that **both** Electron and Swift emit. Single source of truth; both platforms produce byte-identical viewers. This also de-risks future viewer fixes (fix once, both ship it).

---

## 3. Component map: Electron → Swift

| Electron (source of truth) | Swift target | Reuse / New | Difficulty |
|---|---|---|---|
| `GifDeployRequest`, `DetectedSlide`, `QuietRun` types (`src/types`, `slideDetection.ts`) | `Models/GifDeploy.swift` — Codable/Sendable structs | New | Trivial |
| GIF parse + **progressive composite** (gifuct, `GifViewer.tsx` + viewer) | `Services/GifCompositor.swift` — ImageIO decode + CGContext composite w/ disposal | New | **High (the risk above)** |
| Grid sampler (~1000 pts, 32×32, RGB) | `Services/GridSampler.swift` — CGContext → raw bytes (or vImage) | New | Medium |
| `slideDetection.ts` Auto quiet-run (`findQuietRuns`/`mergeBuildRuns`/`filterTransitionArtifacts`/`buildSlideMap`; consts 0.3 / 8 / 0.5) | `Services/SlideDetector.swift` — pure array math, copy verbatim atop sampler | New | Low logic / Medium (needs composite+sampler) |
| `stillsMatch.ts` DP matcher + `naturalSort` + `meanAbs` (O(N·M)) | extend `SlideDetector` — DP copies verbatim; load JPEG/PNG via ImageIO | New | Low logic / Medium (image load) |
| `boundaryEdits.ts` remove/insert/recomputeTransitions | pure functions in `SlideDetector` | New | Low |
| `gifViewerGenerator.ts` (HTML + baked slides + gifuct + safe-embed CSS) | **shared template asset** emitted by `Services/GifViewerGenerator.swift` | New (+ refactor Electron to same asset) | Medium |
| `deploy-gif` IPC orchestration (`main.ts`) | `Services/GifDeployer.swift` (temp folder → copy GIF → write index.html → call deployer) | New | Low |
| `select-stills-folder` + GIF picker | NSOpenPanel wrappers in `FileOperations` | New (mirror existing) | Trivial |
| `vercelDeployer.deployToVercel` | **`VercelDeployer.deploy` + `VercelAPI.ensureProject`** | **REUSE as-is** | None |
| CSP / secure-embed headers | already in `VercelDeployer` | **REUSE** | None |
| History record | **`HistoryEntry` SwiftData** (`fixesApplied: 0`, `folderPath: gifPath`) | **REUSE — no migration** | None |
| Settings (token/team/secureEmbed/domains) | **`AppSettings`** shared JSON | **REUSE** | None |
| `ProcessingStep` + `@Sendable onProgress` | existing pattern | **REUSE** | None |

**Net:** the entire deploy/persistence/settings/progress backend is already in Swift and reused unchanged. New code is concentrated in: compositor, sampler, detector (3 algorithms), viewer generator, the GIF deploy view, two file pickers.

---

## 4. UI placement (decision needed)

Two options:

- **A — New 5th tab `.gifDeploy`** (recommended): add `case gifDeploy` to `NavigationTab` (SidebarView auto-iterates `allCases`), route in `ContentView`, new `GifDeployView`. Cleanest separation, matches Electron's separate GifViewer surface, no risk to the proven HTML `DeployView`.
- **B — HTML/GIF toggle inside `DeployView`**: less nav surface, but forks the most-load-bearing view and complicates its 5-phase state machine.

`GifDeployView` phases (mirror DeployView): `selectGif → (optional selectStills) → detect → confirm(source picker + project name + secure embed) → processing → complete → error`.

**Local preview scope cut:** Electron shows a live composited canvas preview. For Swift MVP, render a **static thumbnail per `restFrame`** (one composited CGImage per slide) instead of live playback — the *deployed* viewer is the actual product. Live in-app playback can be a later polish item.

---

## 5. Recommended phasing

**Phase 1 — Prove the pipeline end-to-end (highest-risk-first).**
GIF picker → `GifCompositor` (disposal-correct) → `GridSampler` → Auto quiet-run → `GifViewerGenerator` (shared asset) → `GifDeployer` → reuse VercelDeployer → live URL → HistoryEntry. **Gate:** Swift-composited frame N matches browser composite for a real Keynote GIF (verification harness), and a deployed Swift-built viewer is byte-identical to the Electron-built one for the same inputs. Auto is seed-only — acceptable for Phase 1 because the goal is proving the *plumbing*, not boundary accuracy.

**Phase 2 — Stills (the accurate, deck-agnostic path).**
Stills folder picker → ImageIO load + natural sort → reuse sampler → DP `matchStillsToFrames` → snap to quiet runs → monotonicity check + worst-diff report. **Gate:** reproduce 39/39 and 22/22 on the two known decks, matching Electron's matches.

**Phase 3 — Manual editor (most UI work).**
SwiftUI thumbnail grid + frame scrubber, `removeStop`/`insertStop`/`recomputeTransitions`. Override path for when Auto/Stills are wrong.

Phases are independently shippable; Phase 1 alone reaches "GIF Deploy exists in Swift."

---

## 6. Decisions (LOCKED 2026-06-19)

1. **UI:** ✅ **New 5th tab `.gifDeploy`** — own `GifDeployView`, zero risk to the proven HTML `DeployView`.
2. **Viewer source of truth:** ✅ **Shared template asset** — extract the viewer into one placeholder-driven HTML/JS file emitted by **both** Electron and Swift. Single source of truth, byte-identical output. Includes refactoring `gifViewerGenerator.ts` to consume the same asset.
3. **Scope depth:** ✅ **All three sources (full parity)** — Auto + Stills + Manual editor (Phase 3 SwiftUI thumbnail grid included).
4. **Local preview:** open — default to static `restFrame` thumbnails for MVP; live composited playback as later polish (revisit during Phase 1).
5. **Build-output coupling:** ✅ Accepted — Swift computes boundaries at deploy time and bakes them into the viewer; same end result as Electron's build-time bake.

---

## 7. Effort estimate (rough)

- Phase 1: the bulk — compositor + sampler + detector + viewer asset + deploy view. Most risk in the compositor.
- Phase 2: moderate — DP is verbatim, image load + sampler reused.
- Phase 3: moderate — mostly SwiftUI grid UI.

Backend reuse means ~0 risk on deploy/auth/persistence. Risk is entirely in **disposal-correct compositing** and **viewer fidelity** — both gated by verification harnesses in Phase 1.

---

## 8. Next step

Convert this scope → a TDD, section-based implementation plan via `/deep-plan` (research already done; this doc is the input). Phase 1 first, gated on the compositing verification harness before any boundary work.
