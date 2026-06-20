I have everything I need. The `.video` case does NOT actually exist in NavigationTab on main (the plan §5.9 says "already has `.video`" but the live source shows it doesn't). I'll note this accurately. Now I'll write the section content.

# section-01-models-project — Models + project.yml (test target + resources + version bump)

## Purpose

This is the foundation section for the Swift video-deploy parity work. It introduces the two new model structs that every later section consumes (`VideoDeployRequest`, `VideoAnalysis`), and it wires the Xcode project so the rest of the work is possible:

1. A **Swift Testing test target** (there is NO test target on `main` today — every later section's tests depend on this existing).
2. A **`Sources/Resources` bundling entry** so section-03 can ship `video-viewer-template.html` inside the app bundle.
3. A **`CURRENT_PROJECT_VERSION` bump** for the eventual release.

There is no runtime behavior to build here beyond the two structs. The deliverable is: the project compiles, the new test target builds, and an empty `@Test` runs green. This de-risks the entire rest of the plan by proving the xcodegen test wiring before any algorithm is written.

This section has **no dependencies** and **blocks all other sections** (02–09).

## Background context (so this section stands alone)

**What the app is:** Keynote Deployer is a macOS app (Swift 6.2 / SwiftUI / SwiftData, macOS 15+) that turns a Keynote presentation into a shareable web viewer hosted on Vercel. It is generated from a `project.yml` via **XcodeGen** (`xcodegen generate`), then built with `xcodebuild`.

**What this larger effort adds:** a VIDEO deploy path. The user drops an H.264 video export of a deck, picks a folder of per-slide still images (one PNG/JPEG per slide — the still count IS the slide count), sets the frame rate, and deploys an interactive single-`<video>` slide viewer. The stills are matched to the video frames they appear on to derive per-slide timestamps; the deployed artifact is `deck.mp4` + `index.html` (stills are a build-time input only, never deployed).

**The two models in this section:**
- `VideoDeployRequest` — the user's deploy inputs (video path, still paths, fps, naming, secure-embed flag).
- `VideoAnalysis` — the result of matching stills to frames (per-slide frame indices, per-slide timestamps, slide count, video dimensions, fps). Produced later by `VideoTimestampDeriver` (section-06), consumed by the viewer generator (section-03) and deployer (section-07).

**Existing project layout** (already on disk, do not disturb):
```
swift-app/
  project.yml                      # XcodeGen spec (you will edit this)
  Sparkle.xcconfig                 # public Sparkle values, committed
  Sources/
    App/        Models/  Services/  Views/  Config/
    Info.plist  KeynoteDeployer.entitlements
```
Models currently present: `AppSettings.swift`, `HistoryEntry.swift`, `KeynoteMetadata.swift`, `PipelineResult.swift`, `ProcessingStep.swift`, `VercelProject.swift`, `NavigationTab.swift`. Add the two new model files alongside these.

## Tests FIRST

Framework is **Swift Testing** (`import Testing`, `@Test`/`#expect`) — NOT XCTest. These tests live in the NEW test target created by this section. Write assertions only where they clarify intent; stubs/signatures are sufficient per the plan.

From `claude-plan-tdd.md` §Section 1:

```swift
import Testing
@testable import KeynoteDeployer   // module name = target name "KeynoteDeployer"

@Suite("Section 1 — Models + project wiring")
struct ModelsAndProjectTests {

    // Proves the xcodegen test-target wiring works end-to-end:
    // this empty test compiling + running green IS the wiring acceptance gate.
    @Test func testTargetRunsAnEmptyTest() {
        #expect(true)
    }

    // VideoDeployRequest is Sendable and constructible with all fields.
    @Test func videoDeployRequestIsConstructible() {
        let req = VideoDeployRequest(
            videoPath: "/tmp/deck.mp4",
            stillPaths: ["/tmp/s001.jpeg", "/tmp/s002.jpeg"],
            fps: 30,
            projectName: "my-deck",
            title: "My Deck",
            secureEmbed: true
        )
        #expect(req.stillPaths.count == 2)
        // ... assert remaining fields ...
    }

    // VideoAnalysis is Sendable and constructible; slideCount mirrors frames/timestamps length.
    @Test func videoAnalysisIsConstructible() {
        let a = VideoAnalysis(
            frames: [0, 45, 90],
            timestamps: [0.0, 1.5, 3.0],
            slideCount: 3,
            width: 1920, height: 1080, fps: 30
        )
        #expect(a.slideCount == a.timestamps.count)
        // ... assert remaining fields ...
    }
}
```

**Sendable conformance test:** Both structs must be `Sendable` (they cross actor boundaries in later async services). Sendability is checked by the Swift 6 compiler at strict-concurrency level — there is no runtime assert needed. To make the requirement explicit and self-documenting, you may add a trivial compile-time witness in the test target, e.g.:

```swift
@Test func modelsAreSendable() {
    func requireSendable<T: Sendable>(_ : T.Type) {}
    requireSendable(VideoDeployRequest.self)
    requireSendable(VideoAnalysis.self)
    #expect(true)
}
```

**Codable note:** The TDD says "encode/round-trip **if** `Codable` is added." `Codable` is NOT required for these models (they are passed in-process, not persisted — `HistoryEntry` is the persisted type and is unrelated). Do not add `Codable` unless a later section needs it. If you do add it, also add a round-trip `#expect` test. Default: `Sendable` only.

## Implementation

### 1. `swift-app/Sources/Models/VideoDeployRequest.swift` (new)

The user's deploy inputs. Exact shape from `claude-plan.md` §5.1:

```swift
import Foundation

struct VideoDeployRequest: Sendable {
    let videoPath: String      // H.264 .mp4/.mov/.m4v
    let stillPaths: [String]   // one image per slide, natural-sorted (boundary/count source)
    let fps: Double            // constant export frame rate (default 30)
    let projectName: String
    let title: String
    let secureEmbed: Bool
}
```

### 2. `swift-app/Sources/Models/VideoAnalysis.swift` (new)

The stills-to-frames match result. Exact shape from `claude-plan.md` §5.1:

```swift
import Foundation

struct VideoAnalysis: Sendable {
    let frames: [Int]          // matched video-frame index per slide
    let timestamps: [Double]   // frame/fps, rounded 3dp
    let slideCount: Int        // == stillPaths.count
    let width: Int
    let height: Int
    let fps: Double
}
```

Field semantics (so later sections rely on the right invariants):
- `frames.count == timestamps.count == slideCount`.
- `timestamps[i] == round((Double(frames[i]) / fps) * 1000) / 1000` (3-decimal rounding — produced in section-06).
- `frames` is strictly increasing (monotonic by DP-match construction in section-02).

### 3. `swift-app/project.yml` — three edits

The current `project.yml` declares a single `KeynoteDeployer` application target. You must:

**(a) Add a `Sources/Resources` resources bundling entry to the app target.** Section-03 will drop `video-viewer-template.html` into `swift-app/Sources/Resources/` and load it via `Bundle.main`. XcodeGen treats files under a `sources` path with known code extensions as compile inputs; non-code files (`.html`) are bundled as resources automatically when the path is included in the target's sources. The cleanest approach that matches the existing layout (the whole `Sources` tree is already a source path) is:

- Create the directory `swift-app/Sources/Resources/` now (add a `.gitkeep` so it is non-empty and committed; section-03 replaces it with the template). Because `Sources` is already listed as a source path, `Sources/Resources/*.html` will be picked up and bundled. Confirm after generating that the `.html` lands in `Copy Bundle Resources`, not `Compile Sources`.
- If XcodeGen mis-buckets the html (it should not for `.html`), add an explicit resources mapping. Verify with `xcodegen generate` then inspecting the generated target's build phases, OR by a section-03 runtime test (`Bundle.main.url(forResource: "video-viewer-template", withExtension: "html") != nil`). For THIS section, with only `.gitkeep` present, the acceptance is simply that generate + build succeed.

**(b) Add a Swift Testing test target.** There is no test target on `main` — this is greenfield. Follow the `feat/gif-deploy-swift` branch precedent (it added a test target via xcodegen). Add a sibling target under `targets:`:

```yaml
  KeynoteDeployerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests
    dependencies:
      - target: KeynoteDeployer
    settings:
      base:
        SWIFT_VERSION: "6.2"
        MACOSX_DEPLOYMENT_TARGET: "15.0"
        GENERATE_INFOPLIST_FILE: "YES"
        PRODUCT_BUNDLE_IDENTIFIER: com.imaginelabstudios.keynote-deployer.tests
        # Test bundles are loaded into the host app for @testable import.
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Keynote Deployer.app/Contents/MacOS/Keynote Deployer"
        BUNDLE_LOADER: "$(TEST_HOST)"
```

Notes and gotchas:
- The host app's executable name is `Keynote Deployer` (with a space — `CFBundleDisplayName` is "Keynote Deployer"). Verify the actual product path after the first `xcodegen generate` (`ls "$BUILT_PRODUCTS_DIR"`); if the `.app` name differs, fix `TEST_HOST`/`BUNDLE_LOADER` to match exactly, since a wrong path silently fails to load the host and `@testable import` breaks.
- `@testable import KeynoteDeployer` requires the app target to build with testability enabled (Debug config does by default: `ENABLE_TESTABILITY = YES`). If `@testable` import fails to find symbols, confirm the app target's Debug config has `ENABLE_TESTABILITY: "YES"` (XcodeGen sets this for app targets in Debug by default; add it explicitly under the app target's `configs.Debug` if needed).
- Test target must also be Swift 6.2 strict-concurrency clean (it imports `Sendable` models).
- Create `swift-app/Tests/` and add at least the empty-`@Test` file shown above so the target is non-empty and the wiring is provable.

**(c) Bump `CURRENT_PROJECT_VERSION`** (and keep it consistent with the marketing/release strategy). The app target currently has `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, and `CFBundleShortVersionString`/`CFBundleVersion` all at `"1.0.4"`. Bump `CURRENT_PROJECT_VERSION` for this release (e.g. `"1.0.5"` build number). The final marketing version is settled in section-09 (sunset/release); for this foundation section, bumping `CURRENT_PROJECT_VERSION` is sufficient and is what the section manifest calls for. Do not regress the existing Sparkle/signing config.

### 4. Create the directories/files this section introduces

- `swift-app/Sources/Models/VideoDeployRequest.swift`
- `swift-app/Sources/Models/VideoAnalysis.swift`
- `swift-app/Sources/Resources/.gitkeep` (placeholder; section-03 replaces with the template)
- `swift-app/Tests/ModelsAndProjectTests.swift` (the Swift Testing file above)

## Verification

Run from the spec's project config (this is the canonical test command):

```bash
cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -quiet
```

Acceptance:
- `xcodegen generate` succeeds and produces a project containing BOTH `KeynoteDeployer` and `KeynoteDeployerTests` targets.
- The app target still builds (HTML path untouched — do NOT regress existing behavior; there are no existing Swift tests on main, so "no regression" means the app still compiles and signs in Debug).
- The new test target builds and the empty `@Test` plus the two model-construction tests run green (exit code 0 — the exit code is the verdict oracle, not stdout).
- Swift 6 strict-concurrency clean (no `Sendable` warnings on the two new models).
- The `KeynoteDeployer` **scheme** must include the new test target in its Test action. XcodeGen auto-generates a scheme per app target; confirm the generated `KeynoteDeployer` scheme's Test action references `KeynoteDeployerTests` (if XcodeGen does not auto-attach the test target to the app scheme, add an explicit `schemes:` block to `project.yml` wiring `KeynoteDeployerTests` into the `KeynoteDeployer` scheme's `test:` targets — otherwise `xcodebuild test -scheme KeynoteDeployer` runs zero tests and falsely reports green with no test execution). Confirm the run actually executes tests (the framework prints `Test run with N tests`), not "Testing started/finished" with zero.

## Out of scope for this section

- No `GridSampler`, `StillsMatch`, encoders, deriver, viewer generator, deployer, or views (those are sections 02–08).
- No `Codable` on the models unless a later section requires it (default: `Sendable` only).
- No navigation wiring (`NavigationTab.video`) — that is section-08. Note for downstream: contrary to `claude-plan.md` §5.9 which states "`NavigationTab` already has `.video`", the live `Sources/Models/NavigationTab.swift` on main has only `deploy / projects / history / settings` — the `.video` case does NOT exist yet and will be added in section-08. Do not add it here.
- No version bump to `MARKETING_VERSION`/`CFBundleShortVersionString` beyond `CURRENT_PROJECT_VERSION` (final release versioning is section-09).

## Dependencies

- **Depends on:** nothing.
- **Blocks:** all sections (02–09). The test target this section creates is the home for every later section's tests; the two models are consumed by sections 03, 06, 07, 08; the `Sources/Resources` entry is consumed by section-03.

---

Files I read to write this section (all absolute paths):
- `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/planning/specs/swift-video-parity/claude-plan.md`
- `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/planning/specs/swift-video-parity/claude-plan-tdd.md`
- `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/planning/specs/swift-video-parity/sections/index.md`
- `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/project.yml`
- `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Models/NavigationTab.swift`
- `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Models/ProcessingStep.swift`

Load-bearing correction I surfaced for downstream sections: the plan (§5.9) claims `NavigationTab` already has a `.video` case, but the live source at `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Models/NavigationTab.swift` only declares `deploy / projects / history / settings`. The `.video` case must be ADDED (in section-08), not assumed present. I noted this in the section so section-01 doesn't add it prematurely and section-08 knows to create it.
---

## ✅ As-built (deep-implement)

- Created `Sources/Models/VideoDeployRequest.swift` + `Sources/Models/VideoAnalysis.swift` (exact §5.1 shapes, `Sendable`, no Codable).
- Created `Sources/Resources/.gitkeep` (section-03 REPLACES with `video-viewer-template.html`).
- Created `Tests/ModelsAndProjectTests.swift` (4 Swift Testing tests, all green).
- `project.yml`: added `KeynoteDeployerTests` (`bundle.unit-test`, dep on app); **dropped manual TEST_HOST/BUNDLE_LOADER** — XcodeGen auto-derives the host from the dependency (cleaner; sidesteps the space-in-app-name footgun) and auto-attaches the test target to the app scheme. Bumped `CURRENT_PROJECT_VERSION` 1.0.4→1.0.5.
- Verified: `xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS"` → build OK, **4 tests passed, exit 0** (real execution, not zero-test green).
- Downstream: VideoAnalysis invariants validated in §06; .gitkeep replaced in §03; version reconciled in §09.
