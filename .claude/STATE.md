# Session State

**Last updated:** 2026-06-29 11:00
**Goal:** Build the AE-style marker/timeline editor (v1.3.0) into the app, iterated live with Edward via an HTML mockup.
**Plan:** docs/superpowers/plans/2026-06-28-timeline-editor.md (built); the live-iteration changes are committed on top.

## Current Task
**What:** Interactive timeline editor (layout A) — built from an approved HTML mockup, refined through ~10 live test cycles on the real 39-slide ILS deck.
**Status:** COMPLETE on branch `feat/timeline-editor` (merged-to-main + iPhone gate still pending). 87 tests green, Release build PASS. Commit `d52b1dc` (this session) atop the deep-implement timeline branch.

**Key files (swift-app/):**
- `Sources/Views/TimelineEditorView.swift` — editor: zoom timeline, draggable playhead (scrub), Play-to-next sweep, First, drag Rest/Go ticks, ±frame, Split-at-playhead, Shift-click holds→Merge, right-click sections→Set length…(single/multi), Undo (⌘Z), ScrollView+pinned footer.
- `Sources/Services/HoldDetector.swift` — anchor-anchored seed (Rest=DP anchor, Go=forward motion onset + default transition for fades).
- `Sources/Services/MarkStore.swift` — persist marks by deck fingerprint (frames+fps+size); save on deploy, auto-load on re-drop.
- `Sources/Views/VideoDeployView.swift` — full-width reviewMarkers phase + persistence wiring.
- `Sources/App/KeynoteDeployerApp.swift` — defaultSize 1100×600.

## Context (for next session)
- **HoldDetector motion-diff FAILS on fade-on-dark-bg decks** (real ILS deck): per-frame diff stays below threshold so transitions read as "still" → holds abutted (gap=1f), one purple bar, Rest could land mid-fade. FIX = Rest is the DP anchor verbatim (settled), Go = forward motion onset, default ~15f transition band when no motion detectable. Proven via a headless harness on the REAL deck (synthetic deck was too clean to expose it).
- **macOS dev-launch double-window:** `osascript ... activate "Keynote Deployer"` launches the INSTALLED /Applications v1.0.0 copy via LaunchServices alongside the /tmp dev build. Launch by PATH only (`open -n <path>`), never activate-by-name. Stale `/Applications/KeynoteDeployer.app` v1.0.0 should be replaced once v1.3.0 ships.
- **SwiftUI window grew past screen** when the editor content was tall → wrap editor in ScrollView + pinned footer so window min-height stays small + defaultSize 600.
- Test deck for the editor: `~/Desktop/kd-test-deck/` (deck.mp4 + stills/); real deck at iCloud `…/Quals Decks/2026 Master Quals /Keynote Video for Portal/ILS_Quals 2026 V3.m4v` (+ V3 Images).
- Dev build runs from `/tmp/kd-build/Build/Products/Debug/KeynoteDeployer.app`.

## Next Step
Run the **live iPhone cross-origin-iframe gate** (the only oracle): real deck → edit markers → Encode & Deploy → verify on iPhone that Rest lands on settled slides + transitions play smooth. If good, merge `feat/timeline-editor` → main, push, then `/notarize` for v1.3.0 (also replaces the stale /Applications v1.0.0).

## Verification Goals
- [x] Editor usable on the real 39-slide deck (playhead/scrub/Split/Merge/Set length/Undo/persistence) — Edward live-approved.
- [x] HoldDetector seeds Rest on settled anchors + visible transitions on the real deck.
- [ ] iPhone cross-origin-iframe: every Rest on a settled slide, transitions smooth (the original 1.2.x bug class) — NOT yet run.
