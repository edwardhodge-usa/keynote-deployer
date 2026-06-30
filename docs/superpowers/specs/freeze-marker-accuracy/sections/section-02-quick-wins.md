Now I have everything needed. Here is the section content.

---

# Section 02 — Quick Wins (MarkStore algorithm versioning + count-reporting fix)

## What this section delivers

Two small, independent, low-risk, individually-shippable fixes to the video-deck seed pipeline. They are the **two confirmed non-algorithm culprits** behind the perceived freeze/hold-marker regression and should land (and be re-measured) *before* any of the algorithm work in later sections.

1. **MarkStore algorithm versioning** — fold an `algorithmVersion` integer into the deck fingerprint so that whenever the seed algorithm changes, decks auto-reseed (the new seed wins) while a user's old hand-edits remain on disk under their old key (preserved, just not shown).
2. **Count-reporting bug** — `VideoDeployer.deploy(...)` currently reports `marks.count` as the slide count; it must report `analysis.slideCount` (the authority). Add a diagnostic/assertion that fires loudly when `marks.count != analysis.slideCount` so any future divergence surfaces instead of being hidden.

This section has **no dependencies** on other sections and can be implemented in parallel. It is referenced by section-08 (re-measure & validate), which re-runs the harness after these and the algorithm changes land.

> Write tests FIRST (Swift Testing — `@Test`/`@Suite`/`#expect`), then implement. Build/verify via the apple-platform-build-tools builder agent. Canonical verifier:
> ```
> cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS"
> ```
> `xcodegen generate` first because adding a new test file changes the project.

---

## Background context (self-contained)

**Keynote Deployer** (macOS, Swift 6.2 / SwiftUI, `swift-app/`) turns an exported deck video + per-slide stills into an interactive web "deck viewer." For each slide the pipeline computes two video frame indices — **Rest (`holdStart`)** = settled frame to pause on, **Go (`holdEnd`)** = frame where the outgoing transition begins — as `SlideMark { holdStart: Int; holdEnd: Int }`. These seed a timeline editor where the user hand-tunes them, then drive H.264 forced keyframes and the deployed viewer.

Relevant existing types (do **not** change their shape):

```swift
struct SlideMark: Sendable, Equatable, Codable { var holdStart: Int; var holdEnd: Int }

struct VideoAnalysis: Sendable {                 // produced by VideoTimestampDeriver
    let frames: [Int]; let timestamps: [Double]; let slideCount: Int   // slideCount == stills count (the authority)
    let width: Int; let height: Int; let fps: Double; let frameCount: Int
}
```

The **slide count authority is `analysis.slideCount`** (derived from `stillURLs.count` via the DP stills-match), NOT `marks.count`. The whole accuracy effort treats the DP stills-match as the count authority; HoldDetector (rewritten in later sections) will emit exactly one mark per slide so the two agree. Until then, reporting `marks.count` can silently disagree with the real slide count — that's culprit #2.

---

## 5.1 MarkStore algorithm versioning

### File to edit
`swift-app/Sources/Services/MarkStore.swift`

### Current state (for reference)
`MarkStore` is an `enum` persisting `[String: [SlideMark]]` to `timeline-marks.json` in Application Support, keyed by a deck fingerprint. The fingerprint currently combines frame count + fps + byte size:

```swift
static func fingerprint(path: String, frameCount: Int, fps: Double) -> String {
    let attrs = try? FileManager.default.attributesOfItem(atPath: path)
    let size = (attrs?[.size] as? Int) ?? 0
    let fpsKey = Int((fps * 1000).rounded())
    return "\(frameCount)-\(fpsKey)-\(size)"
}
```
`load(_:)` / `save(_:for:)` are best-effort and never throw. The store map is `[fingerprint: [SlideMark]]`.

### Change
Add a module-level `algorithmVersion` constant and fold it into the fingerprint string so a different algorithm version yields a different key. Marks saved under a prior version remain in the JSON map under their own (old) key — they are preserved on disk, just never matched/shown once the current version differs.

Target signature (per the plan):

```swift
enum MarkStore {
    static let algorithmVersion = 2     // bump whenever the seed algorithm changes

    /// Fingerprint now includes algorithmVersion so a new algorithm always re-seeds; marks saved under a
    /// prior version remain on disk under their own key (preserved, not shown).
    static func fingerprint(path: String, frameCount: Int, fps: Double, algorithmVersion: Int) -> String
    // ... existing load/save/storeURL unchanged ...
}
```

Implementation notes:
- Append the version to the returned key (e.g. include `algorithmVersion` as another dash-joined component, such as `"v\(algorithmVersion)-\(frameCount)-\(fpsKey)-\(size)"`). The exact format is the implementer's call; the only contract that matters: **different `algorithmVersion` ⇒ different key; same everything-else+version ⇒ same key.**
- `algorithmVersion = 2` (this is "the new algorithm" — bumping from the implicit v1 forces every existing deck to re-seed).
- Keep `load`/`save`/`storeURL`/`loadAll` as-is — they already operate on whatever fingerprint string is passed.

### Update the call site(s) in `VideoDeployView`
`swift-app/Sources/Views/VideoDeployView.swift`

There is a `MarkStore.fingerprint(...)` call at roughly **line 555** inside the analyze flow:

```swift
let fp = MarkStore.fingerprint(path: request.videoPath, frameCount: a.analysis.frameCount, fps: a.analysis.fps)
```

Add the new argument: `algorithmVersion: MarkStore.algorithmVersion`.

The plan refers to "the two `VideoDeployView` call sites." Grep the whole file for **every** `MarkStore.fingerprint(` invocation and update each to pass `algorithmVersion: MarkStore.algorithmVersion` — do not assume there is only one:
```
rg "MarkStore\.fingerprint" swift-app/Sources/Views/VideoDeployView.swift
```
(The `MarkStore.load(fp)` / `MarkStore.save(edited, for: markFingerprint)` calls take the already-built fingerprint string and need no change.)

### Behavior after change
A deck previously hand-tuned under v1 now shows the fresh v2 seed; the v1 edits are still present in `timeline-marks.json` under the v1 key (recoverable). This is the intended auto-reseed-on-algo-change behavior chosen in the interview.

### Deferred / out of scope (do NOT build)
A one-time non-blocking "Timing detection improved — markers re-seeded; your prior edits are still on disk" notice (UserDefaults-tracked) touches editor UI and is explicitly **not required** here. Note it exists as a possible follow-up; do not implement.

---

## 5.2 Count-reporting bug

### File to edit
`swift-app/Sources/Services/VideoDeployer.swift`

### Current state (the bug)
At the end of `VideoDeployer.deploy(...)` the result is built with `slideCount: marks.count`:

```swift
return VideoDeployResult(url: url, projectName: request.projectName, title: request.title,
                         slideCount: marks.count, width: analysis.width, height: analysis.height,
                         folderPath: request.videoPath)
```

`VideoAnalysis` already carries the authoritative `analysis.slideCount`.

### Change
1. Report **`analysis.slideCount`** instead of `marks.count` in the returned `VideoDeployResult`.
2. Add a **diagnostic/assertion** that fires (or is recorded) when `marks.count != analysis.slideCount`, so a future divergence surfaces loudly rather than silently. Use a mechanism that is observable by a test without crashing a release deploy — e.g. an `assertionFailure(...)` plus a record on the result (a `Bool` flag or a logged message) is acceptable; prefer something a unit test can assert on. Do NOT use a hard `precondition`/`fatalError` that would abort a real deploy on divergence — the deploy must still succeed; the divergence is a signal, not a fatal error.

> Note: `analyze(...)` (around line 34) already computes `let slideCount = analysis.slideCount` for its progress detail string — that path is fine; the fix is specifically the `deploy(...)` return.

### Self-contained-test mechanism note
The deploy seam is injectable: `VideoDeployer.deploy(_:analysis:marks:settings:seams:onProgress:)` takes `seams: VideoDeployerSeams` (a struct with an `encoder: VideoEncoder` and a `ensureProjectAndDeploy` closure). Tests inject a fake encoder + a closure returning a canned URL so `deploy` runs fully offline (no Vercel, no real encode). Use this to drive the count-reporting tests. The existing `Tests/VideoDeployerTests.swift` already constructs such fakes — mirror its setup rather than reinventing it.

---

## Tests (write FIRST)

### MarkStore versioning → `Tests/MarkStoreTests.swift` (create if absent)

Stub intent (implementer writes the `#expect` assertions):

```swift
@Suite struct MarkStoreTests {
    // fingerprint(... algorithmVersion: 1) != fingerprint(... algorithmVersion: 2) for same video/frames/fps.
    @Test func differentAlgorithmVersionsProduceDifferentFingerprints() { /* ... */ }

    // Marks saved under v1 are NOT loaded when the current algorithmVersion is 2 (fresh seed wins);
    // the v1 entry still exists on disk — loading with the explicit v1 fingerprint returns it.
    @Test func versionBumpReseedsButPreservesOldEditsOnDisk() { /* ... */ }

    // Same-version round-trip: save under v2 fingerprint → load v2 fingerprint returns the saved marks
    // (hand-edits persist within a version).
    @Test func sameVersionRoundTripReturnsSavedMarks() { /* ... */ }
}
```

Notes for these tests:
- `fingerprint(path:...)` reads file size off disk; for a deterministic test either point at a real temp file you create, or accept that two calls with the *same* path+frames+fps+version return equal strings (size is stable for a fixed file). The version-difference assertions don't need a real video — just differing `algorithmVersion` args with identical other params must yield non-equal strings.
- The "preserved on disk" test should `save` under a v1-style fingerprint, then assert `load(v2Fingerprint) == nil` (or returns something different) while `load(v1Fingerprint)` still returns the saved marks. Because `MarkStore` persists to the real Application Support `timeline-marks.json`, use fingerprints unique to the test (e.g. embed a UUID in the synthetic path/frameCount) so the test doesn't collide with real app data or other test runs.

### Count-reporting → extend `Tests/VideoDeployerTests.swift`

Stub intent:

```swift
// deploy(...) result.slideCount == analysis.slideCount (NOT marks.count), including a case where they
// would have diverged pre-fix (e.g. analysis.slideCount = 5 but marks has 4 entries) — assert the result
// reports 5, the authority.
@Test func deployReportsAnalysisSlideCountNotMarksCount() async throws { /* inject fake seams */ }

// A diagnostic/assertion is fired (or recorded on the result) when marks.count != analysis.slideCount.
@Test func deployRecordsDivergenceWhenCountsDisagree() async throws { /* ... */ }
```

Notes:
- Build a `VideoAnalysis` with a `slideCount` that intentionally differs from the supplied `marks.count` to exercise the divergence path. `marks` must still satisfy `SlideMarkLogic.isValid(marks, frameCount:)` and be non-empty (deploy guards both up front), and be small enough to keep the fake encode trivial.
- Inject `VideoDeployerSeams` with a fake `encoder` and an `ensureProjectAndDeploy` closure returning a canned URL so the full `deploy` path runs offline. Mirror the existing tests in this file for seam construction and `AppSettings` (it needs a non-empty `vercelToken` to pass the Step-4 token guard).
- If you implement the divergence signal as `assertionFailure`, recall `assertionFailure` is active in test builds — the second test may need the signal exposed as a recordable flag/value on `VideoDeployResult` (or via the `onProgress` callback / a returned diagnostic) so the test can assert it *without* tripping the assertion-trap. Choose the recordable-flag approach if `assertionFailure` would abort the test run.

---

## Implementation order / TODO

1. Write `Tests/MarkStoreTests.swift` (3 tests above) — they fail to compile until the signature changes.
2. Edit `MarkStore.swift`: add `static let algorithmVersion = 2`; add `algorithmVersion:` param to `fingerprint(...)` and fold it into the key string.
3. Update every `MarkStore.fingerprint(...)` call site in `VideoDeployView.swift` to pass `algorithmVersion: MarkStore.algorithmVersion`.
4. Add the count-reporting tests to `Tests/VideoDeployerTests.swift`.
5. Edit `VideoDeployer.deploy(...)`: return `slideCount: analysis.slideCount`; add the non-fatal divergence diagnostic for `marks.count != analysis.slideCount`.
6. `cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS"` via the builder agent; iterate to green.

## Acceptance
- New + existing tests green; Release build passes.
- `fingerprint` keys differ across algorithm versions; old marks remain in `timeline-marks.json` under their old key after a version bump.
- `VideoDeployResult.slideCount` equals `analysis.slideCount`; a `marks.count != analysis.slideCount` divergence is surfaced (assert-able), and a real deploy still succeeds when they diverge.

---

Relevant absolute file paths:
- `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/MarkStore.swift` (edit — add `algorithmVersion`, extend `fingerprint`)
- `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Views/VideoDeployView.swift` (edit — update `MarkStore.fingerprint(...)` call site(s), currently ~line 555)
- `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/VideoDeployer.swift` (edit — `deploy(...)` return `slideCount: analysis.slideCount` + divergence diagnostic, currently ~line 98)
- `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/MarkStoreTests.swift` (create)
- `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/VideoDeployerTests.swift` (extend)

Load-bearing signature facts the implementer needs (verified against current source):
- `MarkStore.fingerprint(path: String, frameCount: Int, fps: Double) -> String` → becomes `(path:frameCount:fps:algorithmVersion:)`.
- `VideoDeployer.deploy(_ request:analysis:marks:settings:seams:onProgress:)` returns `VideoDeployResult`; the buggy field is `slideCount: marks.count` at ~line 98. `VideoDeployResult.slideCount` is a `let Int` (struct at ~line 176).
- `deploy` guards `!marks.isEmpty` and `SlideMarkLogic.isValid(marks, frameCount:)` before any work, and requires `!settings.vercelToken.isEmpty` before Step 4 — fake-seam tests must satisfy all three.
---

## As-built notes (2026-06-29)
Implemented as planned. `MarkStore.algorithmVersion = 2` folded into the fingerprint key
(`v2-<frames>-<fps>-<size>`); `VideoDeployView` call site updated; `VideoDeployer.deploy` now
reports `analysis.slideCount` + a `countDiverged` flag on `VideoDeployResult` + an os.Logger
warning. New `Tests/MarkStoreTests.swift` (3) + a VideoDeployer divergence test; one pre-existing
test updated to the new authority contract. 97/97 green. The divergence flag is a future-regression
guard — per the section-01 finding, count == slideCount is structurally guaranteed today, so the
algorithmVersion re-seed (not a count fix) is what actually resolves Edward's "wrong count" report.
