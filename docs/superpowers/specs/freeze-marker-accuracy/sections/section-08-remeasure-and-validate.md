# Section 08 — Re-measure & Validate (Phase 5)

## Goal

This is the **final** section. After the new adaptive seed pipeline is built (sections 03–07) and the quick wins (section 02) and harness (section 01) are in place, this section:

1. Re-runs the harness on all three archetype decks and regenerates the visual report.
2. Locks the final global parameter set with evidence in `harness-triage.md` (anti-overfit gate).
3. Adds **regression tests** over captured real-deck grid fixtures — chiefly that **Rest is never inside a transition span** (the original bug class) and that **count == slideCount** on every deck.
4. Confirms the full suite is green and the Release build passes.
5. Drives the two **manual gates**: Edward eyeballs the seed, and the iPhone cross-origin-iframe gate on the real deck — both required before merge (project DoD).

This section writes **regression tests** and **validation artifacts**; it does not introduce new detector logic. All algorithm modules already exist from prior sections.

## Background an implementer needs

**What the seed pipeline is.** Keynote Deployer (macOS, Swift 6.2 / SwiftUI, `swift-app/`) turns a deck video + per-slide stills into a "deck viewer." For each slide it computes two **video frame indices**:

- **Rest (`holdStart`)** — the settled frame the viewer pauses on.
- **Go (`holdEnd`)** — the frame where the outgoing transition begins.

These are `SlideMark { holdStart: Int; holdEnd: Int }`. The pipeline (all pure over downsampled `[[Double]]` frame grids — one 32×18×3 **raw sRGB 0–255** grid per frame):

```
video → GridSampler.sample → frameGrids [[Double]]
stills → GridSampler.sample → stillGrids [[Double]]
   → StillsMatch.matchStillsToFrames → anchors [Int]      (COUNT authority = stillURLs.count)
   → HoldDetector.detect(...)  → [SlideMark]              (one mark per slide, never fewer)
   → VideoTimestampDeriver.derive(...) → (VideoAnalysis, [SlideMark] seed)
   → VideoDeployView loads MarkStore by deck fingerprint, user edits,
   → VideoDeployer.deploy(marks:)
```

**The three failure modes this whole spec fixes:** (a) Rest landing on a mid-transition/blurry frame, (b) Go mistimed, (c) marker **count** ≠ slide count. Sections 03–07 made detection deck-adaptive; this section proves the fixes held by **measuring on the real decks** (synthetic decks hid the original bug — the real fade-heavy deck is the oracle).

**The three archetype decks** (anti-overfit requires all three): a **fade-on-dark** deck (already captured), a **clean-cut** deck, and a **build-heavy** deck (Edward provides the latter two). Full videos are NOT committed; for offline tests, store **small captured grid sequences** plus hand-built synthetic ones.

## Dependencies (reference only — do NOT re-implement)

These exist when this section runs. Use them; do not duplicate their content.

- **Section 01 — harness.** `SeedHarness.run(_:encoder:) async throws -> HarnessReport`, `HarnessReport.writeJSON(to:)` / `writeVisualReport(to:)`, `PerSlideDiagnostic` (fields incl. `slideIndex`, `matchedAnchorFrame`, `anchorCollidedWithPrevious`, `lowConfidenceMatch`, `seededRest`, `seededGo`, `diffProfileAroundAnchor`), and the captured-deck fixtures under `swift-app/Tests/Fixtures/decks/`. The `harness-triage.md` Phase-0 baseline note also already exists from section 01.
- **Section 02 — quick wins.** `MarkStore.algorithmVersion`; `VideoDeployer.deploy` already reports `analysis.slideCount` (not `marks.count`) with a divergence assertion.
- **Section 07 — HoldDetector rewrite.** `HoldDetector.detect(...)` now emits exactly **one mark per slide** (no silent dedup-drop; collisions flagged), explicit first/last-slide boundaries, `lowConfidenceMatch` flag, strictly-increasing valid spans. Its `BoundaryDetector` produces `TransitionSpan { start: Int; end: Int; kind: .cut | .gradual }`.

Test conventions (existing): **Swift Testing** (`@Test`/`@Suite`, `#expect`), one suite file per module under `swift-app/Tests/`, small synthetic grid sequences inline, shared fixtures under `swift-app/Tests/Fixtures/`.

## Tests FIRST

Write/confirm these before running the validation pass. Stubs are prose — the implementer writes the assertions.

### Regression suite over captured real-deck grid fixtures

These encode the now-characterized real-deck behavior. Put new fixtures under `swift-app/Tests/Fixtures/decks/` (small captured grid sequences for cut / cross-fade / build archetypes — not full videos). Where a `HoldDetectorTests.swift` / `BoundaryDetectorTests.swift` already exist from sections 06/07, extend them; otherwise add a focused regression suite (e.g. `Tests/SeedRegressionTests.swift`).

- **Test (the original bug class — primary guard):** on the captured REAL **fade-deck** grid fixture, every slide's **Rest frame is NOT inside any detected transition span**. For each produced `SlideMark`, assert `holdStart` does not fall within any `[span.start, span.end]`.
- **Test:** on each captured archetype fixture (cut / cross-fade / build), `marks.count == anchors.count == slideCount` (count authority preserved; no manufactured or dropped marks).
- **Test:** marks strictly increasing across the real fixture — each `holdEnd < next.holdStart`, all indices within `[0, frameCount)` (keeps `SlideMarkLogic.isValid`).
- **Test (cross-fade):** the captured cross-fade fixture yields ONE `.gradual` span per real transition — not zero, not split into many (twin-comparison accumulation works on real fade data).
- **Test (build-heavy):** the build-heavy fixture's intra-slide motion does NOT manufacture extra transitions (count stays == slideCount).
- **Existing `StillsMatchTests` stay green** — the DP-match contract is unchanged (it remains the slide-count authority). Do not modify them.
- **Existing `HoldDetectorTests` reflect the new contract** (from section 07: one-mark-per-slide, no silent dedup-drop). Confirm they pass after the full pipeline is wired; do not re-encode the old `duplicateAnchors → count 1` bug.

### Manual / integration (NOT unit — gate items)

- Run the harness on the **REAL fade deck** (and the clean-cut + build decks once provided) → regenerates the triage report; compare seed Rest/Go/count to the Phase-0 baseline.
- iPhone cross-origin-iframe gate on the real deck (manual; see below).

## Implementation / validation steps

### 1. Re-measure on all three archetypes

Run the harness (from section 01) on each archetype deck and emit JSON + the self-contained HTML montage:

```swift
let report = try await SeedHarness.run(
    SeedHarnessInput(videoURL: deckVideo, stillURLs: deckStills, outputDir: outDir),
    encoder: AVFoundationVideoEncoder()   // the default shipping encoder
)
try report.writeJSON(to: outDir)
try report.writeVisualReport(to: outDir)   // dark, self-contained HTML montage; ASCII diff-profile bars
```

For each deck, compare against the Phase-0 baseline recorded in `harness-triage.md`. The acceptance bar:

- Each of the three failure modes shows **measurable improvement** vs baseline (Rest no longer mid-transition; Go brackets the real transition; no count divergence).
- **`markCount == slideCount` on ALL decks.**
- Improvement holds on **≥2 archetypes** (fade + clean-cut minimum) — the anti-overfit gate. If a single parameter set cannot satisfy fade + clean-cut + build simultaneously, that is a finding to escalate, NOT a reason to add per-deck knobs.

The fade-on-dark deck is captured already; the clean-cut and build-heavy decks come from Edward. If those two are not yet available, run on the fade deck, record results, and flag the missing decks as a blocker on the anti-overfit gate (STOP and report — do not declare the gate passed on one deck).

### 2. Lock the global parameter set in `harness-triage.md`

The new algorithm trades two bad constants (`motionThreshold = 6.0`, `defaultTransition = 15`) for several better-motivated parameters: channel weights, local-ratio threshold + window + floor, twin-comparison `Ts/Tb` ratio + grace frames, `minHoldSeconds`. These are **global constants validated ONCE across all three decks together**, then hard-coded in source — **no deck-specific configuration may exist.**

Append to `swift-app/docs/superpowers/specs/freeze-marker-accuracy/harness-triage.md` (or wherever the section-01 triage note lives — same file): the **final chosen values** for every parameter, and the **harness evidence** (per-deck Rest/Go/count before vs after) that justified them. Channel weights default `(1,1,1)`; only deviate if evidence shows a channel dominates wrongly, and record why.

### 3. Regression-guard the captured behavior

Land the regression tests above. Their purpose is to freeze the now-correct real-deck behavior so future timeline-editor work cannot silently regress the seed again (the way it degraded before this spec). The captured grid-sequence fixtures (cut / cross-fade / build) are the durable encoding of "what the real decks do."

### 4. Full suite green + Release build

Build/test via the **apple-platform-build-tools builder agent** (one xcodebuild at a time). Canonical verifier:

```bash
cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS"
```

(`xcodegen generate` first because new test/fixture files change the project.) Then confirm the **Release archive** builds:

```bash
cd swift-app && xcodebuild archive -scheme KeynoteDeployer -archivePath /tmp/KeynoteDeployer.xcarchive -destination "generic/platform=macOS"
```

Settle every verdict on the **exit code**, not stdout. A stale `.xcresult` or a "missing" new test is a false green — force a fresh `-resultBundlePath` and enumerate new tests by name if anything looks off.

### 5. Manual gates (required before merge — project DoD)

These are **not** unit tests and cannot be self-certified by the agent. Drive them, then hand the eyeball to Edward.

- **Edward eyeballs the visual report + the live timeline editor on the real deck** — the chosen oracle. Confirm Rest lands on settled slides and Go brackets each transition.
- **iPhone cross-origin-iframe gate on the real deck** — the standing 1.2.x bug-class oracle. Rest must land on settled slides and transitions must play smooth in a real iPhone, inside a cross-origin iframe (the Framer client-page embed). Desktop cannot reproduce this bug class. The established method: deploy the real deck through the real Swift services, embed it cross-origin, and verify on-device. **This gate must pass before merge.**

If either manual gate fails, STOP and report — do not merge.

## Definition of done for this section

- Regression tests landed and green (Rest-not-in-transition on the real fade fixture; count == slideCount on all archetype fixtures; strictly-increasing valid marks).
- `harness-triage.md` updated with the final locked parameter set + per-deck before/after evidence; improvement confirmed on ≥2 archetypes.
- Existing `StillsMatchTests` still green; `HoldDetectorTests` reflect the one-mark-per-slide contract.
- Full `xcodebuild test` suite green (verified by exit code) + Release archive builds.
- Manual gates driven and handed to Edward: visual-report/editor eyeball + iPhone cross-origin-iframe gate — both must pass before merge.

## Files

- `swift-app/Tests/SeedRegressionTests.swift` — NEW (or extend `HoldDetectorTests.swift` / `BoundaryDetectorTests.swift`): the regression suite above.
- `swift-app/Tests/Fixtures/decks/` — NEW captured real-deck grid-sequence fixtures (cut / cross-fade / build), small (grids, not videos).
- `swift-app/docs/superpowers/specs/freeze-marker-accuracy/harness-triage.md` — EDIT: append the final locked parameter set + harness evidence.
- No production-source changes are expected here. If re-measurement reveals a parameter must change, make the change in the owning module (FrameSignal / AdaptiveThreshold / BoundaryDetector / RestSelector / HoldDetector) from its section, re-run the full validation pass, and record the revised value in `harness-triage.md`.