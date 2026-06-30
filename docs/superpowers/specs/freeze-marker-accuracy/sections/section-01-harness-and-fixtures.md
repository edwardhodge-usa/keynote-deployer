# Section 01 — Measurement Harness + Fixtures

## Objective

Build the headless **seed-measurement harness** — a permanent, first-class diagnostic tool that runs the REAL seed pipeline (`GridSampler` → `StillsMatch` → `HoldDetector` → marks) on a deck folder and emits a per-slide numeric + visual report. This is BOTH the Phase-0 culprit-triage instrument and the re-measurement tool used after every later change. Capture the archetype-deck and synthetic grid fixtures the detector unit suites (other sections) consume, with path-traversal-safe output. Finally, run the harness on the real fade deck and write the Phase-0 `harness-triage.md`.

This section is independent (no code dependencies on other sections) and is one half of what the final validation section (08) needs. It must NOT change any existing pipeline behavior — it only observes it.

## Background (everything you need)

**Keynote Deployer** (macOS, Swift 6.2 / SwiftUI, `swift-app/`) turns a rendered presentation video plus a folder of per-slide still images into an interactive web deck viewer. For each slide it computes two **video frame indices**:

- **Rest (`holdStart`)** — the settled frame the viewer pauses on.
- **Go (`holdEnd`)** — the frame where the outgoing transition begins.

These pairs are `SlideMark { holdStart: Int, holdEnd: Int }` and seed a timeline editor.

The seed is produced by a pure-function pipeline over downsampled frame grids:

```
video ──► VideoEncoder.sampleGrids → frameGrids [[Double]]  (one 32×18×3 sRGB grid per frame)
stills ─► VideoEncoder.sampleGrids → stillGrids [[Double]]  (one grid per slide still)
            │
   StillsMatch.matchStillsToFrames(stillGrids, frameGrids) → anchors [Int]  (strictly increasing)
            │
   HoldDetector.detect(frameGrids:anchors:frameCount:) → [SlideMark]
```

**Existing types you will USE (do not change their shape):**

```swift
struct SlideMark: Sendable, Equatable, Codable { var holdStart: Int; var holdEnd: Int }

protocol VideoEncoder: Sendable {
    func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double)
    func sampleGrids(url: URL) async throws -> [[Double]]   // every frame; 1728 raw-RGB doubles 0.0...255.0
    func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double], fps: Double) async throws
}

enum StillsMatch { static func matchStillsToFrames(_ stills: [[Double]], _ frames: [[Double]]) throws -> [Int] }
enum HoldDetector { static func detect(frameGrids: [[Double]], anchors: [Int], frameCount: Int,
                                       motionThreshold: Double = 6.0, defaultTransition: Int = 15) -> [SlideMark] }
```

- Grid values are **RAW RGB in `0.0...255.0`** (NOT normalized). One grid = `32 * 18 * 3 = 1728` doubles.
- `GridSampler.width = 32`, `.height = 18`, `.channels = 3`.
- The **slide-count authority is `stillURLs.count`** — the harness reports `markCount` against it so the count-loss failure mode is visible. The current `HoldDetector` silently dedups colliding anchors (which is the count bug we are diagnosing) — the harness must MEASURE this, not depend on it being fixed.

**The problem this whole feature fixes:** the seed degraded — Rest lands mid-transition/blurry, Go is mistimed, and marker count ≠ slide count — because detection was tuned on a single deck with two fixed constants. The harness exists because **synthetic decks hid the original bug; the real fade-heavy deck is the only honest accuracy oracle.**

**House report style:** dark, self-contained single-file HTML, ASCII bars for numeric profiles (matches the project's live-dashboard/report convention). Edward eyeballs the visual report; numbers back it up.

## Files to create / modify

```
swift-app/
  Sources/Diagnostics/
    SeedHarness.swift        # NEW: headless run-on-deck → HarnessReport (pure orchestration)
    HarnessReport.swift      # NEW: report model + JSON + self-contained HTML/montage emitter + path guard
  HarnessCLI/
    main.swift               # NEW: thin CLI entry — parse args, build live encoder, call SeedHarness.run, write reports
  project.yml                # EDIT: add the `kd-seed-harness` executable (tool) target
  Tests/
    SeedHarnessTests.swift   # NEW: offline unit suite (stub encoder)
    Fixtures/decks/          # NEW: small synthetic + captured-grid fixtures per archetype
docs/superpowers/specs/freeze-marker-accuracy/
    harness-triage.md        # NEW: Phase-0 written triage (real-deck evidence)
```

The `Sources/Diagnostics/` folder is automatically compiled into the `KeynoteDeployer` app target (project.yml already has `sources: - path: Sources`), so `SeedHarness`/`HarnessReport` are available to tests via `@testable import KeynoteDeployer`. No project.yml change is needed for the *types*; the project.yml edit is only to add the standalone CLI executable.

## Tests FIRST — `Tests/SeedHarnessTests.swift`

Framework: **Swift Testing** (`@Test`/`@Suite`, `#expect`), matching the existing `Tests/`. Write these before implementing. Use a stub `VideoEncoder` modeled on the existing `VideoDeployerTests.StubEncoder` (a `final class … @unchecked Sendable` that returns canned `frameGrids` for the video URL and a per-path grid for each still). Keep grids tiny — the harness logic is shape/path/count, not pixel fidelity.

Write these cases (assertions are yours to fill in):

- **One diagnostic per still.** `SeedHarness.run` on a tiny synthetic deck (stub encoder returning known grids + matching stills) produces `report.perSlide.count == stillURLs.count`, each with a populated `PerSlideDiagnostic`.
- **`markCount == slideCount` for a clean synthetic deck** (stills that match distinct, well-separated frames).
- **Collision flag.** When two stills are crafted to match the SAME frame, the affected slide's `anchorCollidedWithPrevious == true` (this is the count-loss signal — assert it is surfaced, not silently dropped).
- **JSON emit.** `report.writeJSON(to:)` writes a file that is valid JSON and decodes back to a structure with one entry per slide (round-trip or `JSONSerialization` validity check).
- **Visual report emit.** `report.writeVisualReport(to:)` writes a single self-contained `.html` file that exists, is non-empty, and references each slide (e.g. contains `slideCount` slide blocks / `slideCount` inlined thumbnails). Self-contained = no external network/file dependency required to view.
- **Path-traversal guard.** A `deckName` containing `../`, `/`, or other separators does NOT cause any written file to escape `outputDir`. Assert the resolved output paths are all inside `outputDir.standardizedFileURL` (and that no file appears in a parent dir). This is the security-critical test.

(Manual / integration, NOT a unit test: run the CLI on the REAL fade deck to produce `harness-triage.md` — see the Phase-0 deliverable below.)

## Implementation — `HarnessReport.swift`

Define the report model exactly as below (these shapes are referenced by section 08). Bodies are yours; keep methods small.

```swift
struct PerSlideDiagnostic: Codable, Sendable {
    let slideIndex: Int
    let matchedAnchorFrame: Int
    let anchorCollidedWithPrevious: Bool    // two stills → same frame (count-loss signal)
    let lowConfidenceMatch: Bool            // anchor far from its detected hold → StillsMatch suspect
    let seededRest: Int                     // produced holdStart
    let seededGo: Int                       // produced holdEnd
    let diffProfileAroundAnchor: [Double]   // ±N frames consecutive grid diff, to eyeball Go/Rest fit
    let restFrameThumbnailPath: String      // file path of the rendered Rest thumbnail (for JSON)
    let goFrameThumbnailPath: String        // file path of the rendered Go thumbnail
}

struct HarnessReport: Sendable {
    let deckName: String
    let slideCount: Int                     // == stillURLs.count (the COUNT authority)
    let markCount: Int                      // == produced marks.count (should equal slideCount)
    let perSlide: [PerSlideDiagnostic]

    func writeJSON(to dir: URL) throws          // pretty JSON dump (e.g. <deckName>-seed.json)
    func writeVisualReport(to dir: URL) throws   // single self-contained <deckName>-seed.html montage
}
```

Implementation notes:

- **Path-traversal safety (critical).** All output paths MUST be built via `URL.appendingPathComponent` from `outputDir`, never by string concatenation. Because `deckName` flows into filenames, add a private sanitizer that reduces `deckName` to a safe slug (strip/replace path separators and `..`; restrict to an allow-list like alphanumerics + `-` + `_`; collapse empties to a constant like `"deck"`). After building each output URL, defensively verify `url.standardizedFileURL.path` has `outputDir.standardizedFileURL.path` as a prefix before writing; throw otherwise. Apply the SAME guard to thumbnail filenames.
- **Thumbnails.** The encoder seam only exposes 32×18 grids, not native frames. Render each Rest/Go thumbnail by upscaling the relevant 32×18×3 grid to a small viewable PNG (this honestly shows what the detector "sees"; native-res extraction is explicitly out of scope here — deferred unless later measurement demands it). Write the PNG files under a guarded subdir (so `restFrameThumbnailPath`/`goFrameThumbnailPath` are real for the JSON), AND inline the same images as base64 `data:` URIs in the HTML so the montage is truly self-contained.
- **HTML montage.** House style: dark background, one block per slide showing the Rest + Go thumbnails, the slide's `matchedAnchorFrame`/`seededRest`/`seededGo`, collision/low-confidence flags, and an **ASCII bar** rendering of `diffProfileAroundAnchor` so Edward can eyeball "Rest settled? Go bracketing the transition?" at a glance. A header line shows `deckName`, `slideCount`, and `markCount` (with a loud visual flag when they differ).
- Keep `Codable` on `PerSlideDiagnostic` so JSON emit is trivial.

## Implementation — `SeedHarness.swift`

```swift
struct SeedHarnessInput { let videoURL: URL; let stillURLs: [URL]; let outputDir: URL }

enum SeedHarness {
    /// Run the full seed pipeline on one deck and produce a diagnostic report.
    /// Pure orchestration over the existing encoder/matcher/detector — NO app UI,
    /// NO MarkStore (it bypasses MarkStore so it reports the FRESH seed, which is
    /// how MarkStore shadowing is detected in triage). Off-main, cancellable.
    static func run(_ input: SeedHarnessInput, encoder: VideoEncoder) async throws -> HarnessReport
}
```

`run` must mirror what `VideoTimestampDeriver.derive` does, but for diagnosis rather than deploy:

1. Natural-sort the stills the same way the real pipeline does: `stillURLs.sorted { $0.path.compare($1.path, options: .numeric) == .orderedAscending }` (numeric-aware so `slide-10` follows `slide-2`).
2. `sampleGrids` the video → `frameGrids`; `sampleGrids` each still → one grid each (throw if a still yields no grid, matching `VideoTimestampDeriver`).
3. `anchors = try StillsMatch.matchStillsToFrames(stillGrids, frameGrids)`.
4. `marks = HoldDetector.detect(frameGrids:anchors:frameCount: frameGrids.count)`.
5. Build `PerSlideDiagnostic` per still:
   - `matchedAnchorFrame` = the anchor for that slide.
   - `anchorCollidedWithPrevious` = `slideIndex > 0 && anchors[i] == anchors[i-1]` (the count-loss signal — note `HoldDetector` currently dedups these, so derive collision from `anchors`, not from `marks`).
   - `seededRest`/`seededGo` from the produced marks (map slide→mark carefully; because the current detector can emit FEWER marks than slides on collision, when a slide has no own mark, reuse the surviving mark for the collided group and flag it — the goal is to SHOW the divergence).
   - `diffProfileAroundAnchor` = consecutive `HoldDetector.diff(frameGrids[k], frameGrids[k+1])` for a ±N window around the anchor (e.g. N≈10, clamped to bounds).
   - `lowConfidenceMatch` = anchor sits far (e.g. > ~1–2 s worth of frames) from any low-diff settled region around it (best-effort heuristic — this flags a wildly-wrong `StillsMatch` anchor so triage doesn't blame the detector).
   - thumbnail paths from rendering the Rest/Go grids.
6. `markCount = marks.count`, `slideCount = stillURLs.count`.
7. `deckName` = `videoURL.deletingPathExtension().lastPathComponent` (sanitized at write time).
- Sprinkle `try Task.checkCancellation()` between stages (NFR: off-main + cancellable). Do all heavy work off the main thread.

## Implementation — CLI executable (`HarnessCLI/main.swift` + `project.yml`)

A thin command-line tool that wraps `SeedHarness.run` with a LIVE encoder so the harness can be run on a real deck folder from the terminal:

- Parse args: a deck video path, a stills folder (or glob), and an output dir.
- Build the live encoder (`AVFoundationVideoEncoder()` — the default Apple-native encoder; no external deps).
- `await SeedHarness.run(...)`, then `report.writeJSON` + `report.writeVisualReport`, and print the report dir + the `slideCount`/`markCount` headline.

Add the target to `project.yml` (the canonical build is `xcodegen generate` then xcodebuild). Recommended shape — a `tool` target that compiles `main.swift` plus the Diagnostics sources and the PURE services it transitively needs, deliberately EXCLUDING the SwiftUI/Sparkle app code so the CLI stays lightweight:

```yaml
  kd-seed-harness:
    type: tool
    platform: macOS
    sources:
      - path: HarnessCLI                                   # main.swift
      - path: Sources/Diagnostics                          # SeedHarness, HarnessReport
      - path: Sources/Services/VideoEncoding.swift
      - path: Sources/Services/AVFoundationVideoEncoder.swift
      - path: Sources/Services/GridSampler.swift
      - path: Sources/Services/StillsMatch.swift
      - path: Sources/Services/HoldDetector.swift
      - path: Sources/Services/VideoTimestampDeriver.swift
      # + the small Model files the above need (SlideMark, VideoAnalysis) — add whatever the compiler demands
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.imaginelabstudios.kd-seed-harness
        SWIFT_VERSION: "6.2"
        MACOSX_DEPLOYMENT_TARGET: "15.0"
```

This double-compiles a few pure source files (once into the app, once into the tool) — an acceptable tradeoff for a diagnostic tool that avoids a full shared-library refactor. Include exactly the files the compiler requires (the pure services are Foundation/AVFoundation/CoreGraphics only — no SwiftUI). If a pulled-in file transitively imports SwiftUI/Sparkle, prefer adding the minimal model file it needs rather than the whole app. Do NOT add this target as a test dependency; the unit tests exercise `SeedHarness` through the app target with a stub encoder.

## Fixtures — `Tests/Fixtures/decks/`

Capture each archetype as an offline-usable fixture (small captured GRID sequences, NOT full videos, so detector unit tests in later sections run without video decode):

- **fade-on-dark** (have — the real ILS deck): capture a small representative grid sequence around a couple of cross-fade transitions.
- **clean-cut** and **build-heavy** (Edward provides the source decks): capture representative grid slices.
- Plus a couple of hand-built **synthetic** grid sequences (clean cut, linear cross-fade, build) for deterministic unit tests.

Store these in a stable, decodable form (e.g. JSON arrays of `[[Double]]`, or a small Swift fixture-factory) under `Tests/Fixtures/decks/` so sections 03–07 and the section-08 regression tests can load them. Keep them SMALL. This section only needs to land the fixture format + the captured fade-deck grids that section 08's regression guard ("Rest never inside a transition span") will reuse; the synthetic sequences are shared with the detector suites.

## Phase-0 deliverable — `harness-triage.md`

After the harness builds, run the CLI on the REAL fade deck and write `docs/superpowers/specs/freeze-marker-accuracy/harness-triage.md` localizing each failure mode to a stage, with harness evidence:

- **MarkStore shadowing:** read the live `~/Library/Application Support/keynote-deployer/timeline-marks.json`; compare the harness's FRESH seed (it bypasses MarkStore) to what the app shows for a previously-deployed deck. If they differ, shadowing is confirmed — document with the actual saved JSON. (This is the culprit section-02 fixes via `algorithmVersion`.)
- **Count loss:** report `anchorCollidedWithPrevious` across the real deck — if any slide collides, the count bug is real and reproduced.
- **Threshold fit:** characterize from `diffProfileAroundAnchor` where the fixed `6.0` fires too early/late and where dark fades never cross it — the evidence base that justifies (or drops) the later threshold work.

State, per failure mode, which stage is implicated, so later sections are evidence-justified rather than speculative.

## Constraints / gotchas

- **Pure & offline tests.** All harness *logic* tests inject a stub encoder — no video decode, no network, no MarkStore.
- **Do not change existing pipeline behavior.** The harness only observes `GridSampler`/`StillsMatch`/`HoldDetector`. Don't "fix" the count dedup here — that's section 07; the harness's job is to MEASURE it.
- **NFR:** run off the main thread, sprinkle `Task.checkCancellation()`.
- **Memory ceiling (document, don't solve):** `sampleGrids → [[Double]]` holds all grids in RAM (~42 MB/min at 30 fps). Real decks are minutes long so it's fine, but note the limit; a streaming refactor is out of scope.
- **Path traversal is a hard requirement** — the `deckName`-in-filename guard is the one security-critical test; build all paths with `URL` APIs and verify containment before writing.

## Verification

Build/test via the apple-platform-build-tools builder agent (one xcodebuild at a time). Canonical command:

```
cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS"
```

`xcodegen generate` first because new files (and the new CLI target) change the project. Confirm: the new `SeedHarnessTests` suite is green; the `kd-seed-harness` tool target builds; and the harness produces a valid JSON + a non-empty self-contained HTML montage on the synthetic fixture. Then run the CLI on the real fade deck and commit `harness-triage.md`.

---

Relevant absolute paths for the implementer:
- Create: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Diagnostics/SeedHarness.swift`, `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Diagnostics/HarnessReport.swift`, `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/HarnessCLI/main.swift`, `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/SeedHarnessTests.swift`, `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/Fixtures/decks/`, `/Users/EdwardHodge_1/Code/keynote-deployer/docs/superpowers/specs/freeze-marker-accuracy/harness-triage.md`
- Edit: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/project.yml`
- Reference (existing patterns — do not modify): `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/VideoEncoding.swift`, `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/VideoTimestampDeriver.swift`, `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/HoldDetector.swift`, `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/VideoDeployerTests.swift` (StubEncoder pattern), `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/HoldDetectorTests.swift`
---

## As-built notes (2026-06-29)

**Files created:** `Sources/Diagnostics/SeedHarness.swift`, `Sources/Diagnostics/HarnessReport.swift`,
`HarnessCLI/main.swift`, `Tests/SeedHarnessTests.swift` (6 tests), `Tests/Fixtures/SeedFixtures.swift`
(synthetic clean-cut / cross-fade-on-dark / build archetypes for sections 03–08). `project.yml`: added
the `kd-seed-harness` tool target (builds clean). 93/93 suite green.

**Major ground-truth correction (carried to sections 07/08):** `StillsMatch` produces
strictly-increasing anchors AND the current `HoldDetector` clamps `holdEnd < next holdStart`, so
**`markCount == slideCount` is structurally guaranteed** — the "two stills → same frame → dedup"
count-loss is UNREACHABLE, and the overlap-drop never fires on valid input either. So Edward's "wrong
COUNT" symptom is almost certainly **MarkStore shadowing** (stale saved marks), fixed in section 02 —
not an algorithmic count-loss. `anchorCollidedWithPrevious` is relabeled as an invariant guard (always
false); an honest `markReused` flag was added (a slide that borrowed a neighbor's mark).

**Deviations from the plan:**
- Added `markReused` to `PerSlideDiagnostic` (review finding: the original "collision = count-loss signal"
  was dead). Low-confidence heuristic rescaled to the deck's GLOBAL diff distribution (an absolute 1.0
  floor disabled it on the dark-fade decks this feature targets).
- ASCII diff bars now print the absolute max (uncalibrated bars misread a flat profile as max motion).
- **Deferred to the live pass (not in this section):** the CAPTURED real-fade-deck grid fixtures and
  `harness-triage.md` — both require running `kd-seed-harness` on the real iCloud deck (the binary is
  built and ready). The synthetic `SeedFixtures` cover the offline detector suites; the real deck is the
  accuracy oracle per section 08.
