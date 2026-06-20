The Swift source tree is not on this branch but the section-01 author read it (their notes confirm live structure). I have all I need. Let me write the section content.

# Section 08 — VideoDeployView + Navigation Wiring

## Goal

Build the `VideoDeployView` SwiftUI phase-machine view that lets the user drop an H.264 video, pick a per-slide stills folder, set the frame rate, name the project, toggle secure embed, and deploy an interactive video slide viewer to Vercel — at parity with the Electron `VideoViewer.tsx`. Then wire it into the app's navigation (a "Deploy Video" sidebar item / tab) **without** a GIF tab, persist a `HistoryEntry` on success, and auto-copy the URL if the user's setting enables it.

This is the last UI section before sunset (section-09). It depends on section-07 (`VideoDeployer.deploy`, `VideoDeployerSeams`, `VideoDeployResult`) and consumes models from section-01 (`VideoDeployRequest`, `VideoAnalysis`) and section-02 (`StillsMatch.naturalSort`).

## Background / Context (do not assume the reader has seen the plan)

The Swift app already ships an HTML-deploy path. The new video path mirrors the Electron flow (`videoDeckPipeline.ts` + `videoViewerGenerator.ts` + the `deploy-video` IPC + `VideoViewer.tsx`) and reuses the existing Swift deploy infrastructure unchanged. The earlier sections built the whole pipeline behind `VideoDeployer.deploy(...)`. This section is the user-facing front door for it.

### What already exists on `main` (reuse unchanged — do NOT rebuild)

- `swift-app/Sources/Models/AppSettings.swift` — shared settings (Vercel token, team id, project-name prefix, "auto-copy URL" preference, secure-embed default, etc.). Read the actual property names from the live file; the plan refers to `settings.vercelToken`, a project-name prefix, and an auto-copy flag.
- `swift-app/Sources/Models/HistoryEntry.swift` — SwiftData `@Model` for deploy history. The View persists one of these on success.
- `swift-app/Sources/Models/ProcessingStep.swift` — the per-step progress model (`id`, label/title, `status` of `.pending/.active/.completed/...`, and a `detail` string). `VideoDeployer` emits 4 of these via its `onProgress` callback.
- `swift-app/Sources/Models/NavigationTab.swift` — **IMPORTANT (load-bearing correction):** contrary to `claude-plan.md` §5.9 which claims "`NavigationTab` already has `.video`", the live source on `main` declares only `deploy / projects / history / settings`. **The `.video` case does NOT exist and MUST be added in this section.** Verify by reading the file before editing.
- `swift-app/Sources/Views/SidebarView.swift` and `ContentView.swift` — the sidebar list and the tab→view switch. You will add a "Deploy Video" row and a `case .video: VideoDeployView()` branch.
- `swift-app/Sources/Views/DeployProgressView.swift` — the reusable progress UI that renders `[ProcessingStep]`. Reuse it for the `.deploying` phase.
- `swift-app/Sources/Services/VercelDeployer.swift`, `VercelAPI.swift`, `FileOperations.swift` — already wired into `VideoDeployerSeams.live(...)` (section-07). Not touched here.

Look at the existing HTML `DeployView` (and the GIF deploy view, if it still exists in this checkout) for the established Swift conventions: how it shows a drop zone with `.onDrop`, how it presents an `NSOpenPanel`, how it reads `AppSettings`, how it persists `HistoryEntry` via the SwiftData `modelContext`, and how it auto-copies via `NSPasteboard`. **Mirror those conventions exactly** — same pasteboard call, same history-write shape, same settings reads. This section must not introduce a divergent way of doing those things.

### The dependency surface from section-07 (reference only — already built)

```swift
struct VideoDeployRequest: Sendable {          // section-01
    let videoPath: String                       // H.264 .mp4/.mov/.m4v
    let stillPaths: [String]                    // one image per slide, natural-sorted
    let fps: Double                             // constant export frame rate (default 30)
    let projectName: String
    let title: String
    let secureEmbed: Bool
}

struct VideoDeployResult: Sendable {           // section-07
    let url: String; let projectName: String; let title: String
    let slideCount: Int; let folderPath: String  // folderPath == source video path
}

enum VideoDeployer {
    static func deploy(_ request: VideoDeployRequest, settings: AppSettings,
                       seams: VideoDeployerSeams,
                       onProgress: @Sendable (ProcessingStep) -> Void)
        async throws -> VideoDeployResult
}

struct VideoDeployerSeams: Sendable {
    static func live(settings: AppSettings) -> VideoDeployerSeams  // use this in the View
}
```

The View calls `VideoDeployer.deploy(request, settings:, seams: .live(settings:), onProgress:)`. The deployer probes, derives timestamps, encodes, generates the viewer HTML, and deploys — emitting 4 `ProcessingStep`s. **The View (not the deployer) persists `HistoryEntry` and auto-copies the URL**, matching how the Swift HTML/GIF views handle history.

## Tests FIRST

Create a new test file in the Swift Testing target (the target was created in section-01; add this file to it).

**File:** `swift-app/Tests/VideoDeployViewTests.swift`

The View's UI is verified live (Peekaboo) — but the **pure logic** it relies on must be unit-tested. Extract this logic into small, free (non-`@MainActor`, non-View) helper functions or a tiny value type (e.g. a `VideoDeployFormState` struct or a `VideoDeployLogic` enum of static funcs) so the tests don't have to instantiate SwiftUI. The View then calls these helpers. This keeps the tests offline and pixel-free.

Required tests (from `claude-plan-tdd.md` §Section 8). Use Swift Testing (`@Test` / `#expect`). Signatures and intent only — fill in bodies:

```swift
import Testing
@testable import KeynoteDeployer

@Suite struct VideoDeployViewTests {

    // Project name = settings prefix + kebab-case(filename without extension).
    // e.g. prefix "ils-" + "ILS Quals Deck.mp4" -> "ils-ils-quals-deck".
    // Verify kebab rules match the established naming used by the HTML/GIF path
    // (lowercase, spaces/underscores -> "-", strip non-url-safe chars, collapse repeats).
    @Test func projectNameIsPrefixPlusKebabOfFilename() {
        #expect(...)
    }

    // Stills picker filters UTType.image: a folder containing image files plus
    // ".DS_Store" / "Icon\r" / a ".txt" yields ONLY the images, natural-sorted,
    // and slideCount == image count (A8).
    @Test func stillsPickerFiltersToImagesAndCountsSlides() {
        #expect(...)
    }

    // Deploy is DISABLED until: video selected AND stills.count > 0 AND projectName non-empty.
    // Toggle each precondition and assert the canDeploy boolean flips correctly.
    @Test func deployDisabledUntilVideoAndStillsAndName() {
        #expect(...)   // no video -> false; video but 0 stills -> false;
                       // video + stills but empty name -> false; all present -> true
    }

    // Framer-embed string uses the PROBED aspect ratio (width/height from the deploy
    // result / analysis), not a hardcoded 16:9. Given e.g. 1920x1080 -> padding-top 56.25%;
    // given 1600x1200 -> 75%. Assert the generated embed string carries the right ratio.
    @Test func framerEmbedUsesProbedAspectRatio() {
        #expect(...)
    }
}
```

Notes for the test author:
- **`projectNameIsPrefixPlusKebabOfFilename`** — pull the exact kebab/prefix logic the existing Swift deploy views use (do not invent a new normalization). The test pins parity with that logic.
- **`stillsPickerFiltersToImagesAndCountsSlides`** — `UTType.image` filtering (A8): given a directory listing that includes `.DS_Store`, `Icon\r`, and a `.txt`, the helper returns only entries whose `UTType` conforms to `.image`, sorted via `StillsMatch.naturalSort` (section-02), and `slideCount == images.count`. You can drive this with a temp directory of zero-byte files with the right extensions, or with an injected `[URL]` list + a pure `filterImages(_:) -> [String]` helper — the latter is preferred (no filesystem in the unit test).
- **`framerEmbedUsesProbedAspectRatio`** — extract the embed-string builder as a pure function `framerEmbed(url:width:height:) -> String` so it's testable. The Framer/responsive-iframe wrapper computes `padding-top = height/width * 100%`. Mirror the exact string the Electron `VideoViewer.tsx` "Copy Framer Embed" button produces (read it if available in this checkout; otherwise match the responsive-iframe pattern used by the existing Swift HTML deploy view's Framer-embed action).
- Keep all four tests **offline and synchronous**. Do not exercise `VideoDeployer.deploy` here (that is covered by section-07's seam-injected tests).
- Do **not** regress existing HTML-path tests.

## Implementation

### 1. `swift-app/Sources/Views/VideoDeployView.swift` (new)

A SwiftUI `View` (`@MainActor`) implementing a five-state phase machine that mirrors `VideoViewer.tsx`:

```swift
enum Phase { case drop, confirm, deploying, complete, error }
```

State to hold (`@State` / `@Bindable` as appropriate):
- `phase: Phase` (start at `.drop`)
- `videoPath: String?`, `videoSizeBytes: Int64?`, probed `videoWidth/videoHeight: Int?` (probe lazily on confirm, or read from the deploy result — see below)
- `stillPaths: [String]` (natural-sorted), derived `slideCount = stillPaths.count`
- `fps: Double` (default `30`)
- `projectName: String`
- `secureEmbed: Bool` (default `true`, or `settings`'s default if one exists)
- `steps: [ProcessingStep]` (driven by the deployer), `analysisDetail: String` (A5)
- `result: VideoDeployResult?`, `errorMessage: String?`
- `deployTask: Task<Void, Never>?` (so the user can cancel / so it cancels on view disappear)

Environment: `@Environment(\.modelContext)` for SwiftData history; read `AppSettings` the same way the HTML view does.

#### Phase behavior

- **`.drop`** — a drop zone using `.onDrop(of: [.fileURL])` (UTType `.fileURL`) **plus** a "Choose Video…" button that presents an `NSOpenPanel` filtered to `[.mpeg4Movie, .quickTimeMovie, UTType("public.m4v")]` (mp4/mov/m4v). On a valid selection: stash the path + file size, default `projectName = settings.prefix + kebab(filenameWithoutExtension)`, advance to `.confirm`. Reject non-video drops with an inline message (don't crash). Mirror the existing HTML view's drop-zone styling and `ContentUnavailableView`-style empty state.

- **`.confirm`** — the configuration form:
  - **Video preview** — `AVKit.VideoPlayer(player:)` (import `AVKit`), or a thin `NSViewRepresentable` wrapping `AVPlayerView` if `VideoPlayer` sizing is awkward. Construct an `AVPlayer(url:)` from the stashed path.
  - **Metadata** — filename, human-readable size, and dimensions (`width × height`). Dimensions come from probing; you may `await encoder.probe` here for the preview, or display them after deploy — preferred: probe once on entering confirm via a small async task so the user sees dims before deploying. If probe throws (VFR/corrupt/no-track, per section-04 A2/A8), surface that as an inline error on the confirm screen and keep Deploy disabled.
  - **Pick Stills Folder** button — native folder `NSOpenPanel` (`canChooseDirectories = true`, `canChooseFiles = false`). On pick: list the directory, **filter to `UTType.image`** (A8 — ignores `.DS_Store`, `Icon\r`, and any non-image), `StillsMatch.naturalSort` the result (section-02), store the absolute paths, and show the count as the slide count. Warn (non-blocking) if a still's aspect ratio differs markedly from the probed video aspect (A8) — a small caption is sufficient.
  - **fps** numeric field — `TextField`/`Stepper` bound to `fps`, default `30`. Constant-frame-rate hint text is helpful but optional.
  - **Project name** — `TextField` bound to `projectName` (prefilled `prefix + kebab(filename)`; editable).
  - **Secure embed** — `Toggle` bound to `secureEmbed` (default on).
  - **Buttons** — `Back` (→ `.drop`) and `Deploy`. **Deploy is disabled** unless `videoPath != nil && stillPaths.count > 0 && !projectName.isEmpty` (the `canDeploy` helper that the unit test pins). Tapping Deploy builds a `VideoDeployRequest` and advances to `.deploying`.

- **`.deploying`** — render `DeployProgressView(steps: steps)`. Kick off:
  ```swift
  deployTask = Task {
      do {
          let request = VideoDeployRequest(videoPath:, stillPaths:, fps:, projectName:, title:, secureEmbed:)
          let r = try await VideoDeployer.deploy(request, settings: settings,
                                                 seams: .live(settings: settings),
                                                 onProgress: { step in
              Task { @MainActor in
                  // merge/update the step into `steps` by id; surface step.detail
                  // (the "Analyzing video frames…" A5 text) into the visible UI
              }
          })
          await MainActor.run { finish(success: r) }
      } catch is CancellationError {
          await MainActor.run { phase = .drop }   // or stay, per UX
      } catch {
          await MainActor.run { errorMessage = error.localizedDescription; phase = .error }
      }
  }
  ```
  The `onProgress` callback is `@Sendable`; hop to `@MainActor` before mutating `@State` (the `Task { @MainActor in … }` pattern above). Forward the `step.detail` (e.g. "Analyzing video frames…") so the analyze phase doesn't read as hung (A5). Provide a Cancel that calls `deployTask?.cancel()`; cancel the task in `.onDisappear` too. `VideoDeployer`'s `defer` cleanup means a cancel won't strand temp files (A4 — already handled in section-07).

- **`.complete`** — on success (`finish`):
  - **Persist `HistoryEntry`** via `modelContext.insert(...)` exactly like the HTML/GIF view does: `folderPath = result.folderPath` (== source video path), `fixesApplied = 0`, plus url/projectName/title/slideCount/timestamp as that model expects. Read `HistoryEntry`'s actual initializer/fields from the live file — match them, don't invent.
  - **Auto-copy the URL** to `NSPasteboard.general` **iff** the settings auto-copy flag is on (same check the HTML view uses).
  - UI: URL field (read-only/selectable), **Copy URL**, **Copy Framer Embed** (uses the **probed aspect ratio** from `result`/analysis via the `framerEmbed(url:width:height:)` helper — the pinned test), **Open in Browser** (`NSWorkspace.shared.open`), and **Deploy Another** (reset all state → `.drop`).

- **`.error`** — show `errorMessage` + **Retry** (re-run deploy with the same request) and **Start Over** (reset → `.drop`).

#### Extract testable logic (so the unit tests don't touch SwiftUI)

Put these as pure free functions or `static` members (the View calls them; the tests call them directly):
- `projectName(prefix:filename:) -> String` (prefix + kebab) — reuse the existing kebab helper if one exists in the Swift codebase.
- `filterImages(_ urls: [URL]) -> [String]` — `UTType.image` filter + `StillsMatch.naturalSort`.
- `canDeploy(videoPath:stillCount:projectName:) -> Bool`.
- `framerEmbed(url:width:height:) -> String` — responsive iframe with `padding-top = height/width*100%`, byte-matching the Electron `VideoViewer.tsx` embed string (or the existing Swift HTML view's Framer-embed action).

### 2. Navigation wiring

**`swift-app/Sources/Models/NavigationTab.swift`** — **add the `.video` case** (it is NOT present on `main`; the section-01 author confirmed this against the live source). Add it between `.deploy` and `.projects` so sidebar order matches Electron. If the enum has `id`, `title`/`label`, and `systemImage` computed properties (it does — read it), add the `.video` arm to each: label **"Deploy Video"**, an appropriate SF Symbol (e.g. `video` / `play.rectangle`).

```swift
enum NavigationTab: ... {
    case deploy
    case video          // NEW — "Deploy Video"
    case projects
    case history
    case settings
    // ... extend title/systemImage/id switches with the .video arm
}
```

**`swift-app/Sources/Views/ContentView.swift`** — add the detail branch:
```swift
case .video: VideoDeployView()
```

**`swift-app/Sources/Views/SidebarView.swift`** — ensure the sidebar lists `.video` (label "Deploy Video"). Final sidebar order to match Electron: **Deploy HTML, Deploy Video, Projects, History, Settings**. **There is NO GIF tab** — if a GIF/`.gif` row or view-switch case exists in this checkout, remove it from the sidebar and the `ContentView` switch (the GIF path is retired in favor of video; full GIF code removal is section-09's concern, but the tab must not appear).

### 3. Test target

Add `swift-app/Tests/VideoDeployViewTests.swift` to the Swift Testing test target created in section-01 (the `project.yml` test target). After editing, the suite must compile and pass under the project's test command.

## Files to create / modify

- **Create:** `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Views/VideoDeployView.swift`
- **Create:** `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/VideoDeployViewTests.swift`
- **Modify:** `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Models/NavigationTab.swift` (add `.video`)
- **Modify:** `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Views/ContentView.swift` (add `case .video: VideoDeployView()`)
- **Modify:** `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Views/SidebarView.swift` (add "Deploy Video"; remove any GIF row)

## Dependencies (already met — reference only, do not duplicate)

- **section-01** — `VideoDeployRequest`, `VideoAnalysis` models + the Swift Testing test target + `project.yml` wiring.
- **section-02** — `StillsMatch.naturalSort` (used by the stills picker) and `GridSampler` (used downstream, not here).
- **section-07** — `VideoDeployer.deploy(...)`, `VideoDeployerSeams.live(settings:)`, `VideoDeployResult`. The View is purely a front end over `VideoDeployer.deploy`.

## Verification

**Offline (run before live):**

```bash
cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -quiet
```
Exit code 0; Swift 6 strict-concurrency clean; the four `VideoDeployViewTests` pass; **no regression** of existing HTML-path tests. Settle the verdict on the explicit exit code, not stdout.

**Runtime / Peekaboo gate (Claude runs this itself, per the Swift verify loop):**
- Dev-launch the FRESH DerivedData build (never a stale `/Applications` copy).
- Confirm the **Deploy Video** tab is visible in the sidebar and there is **no GIF tab**; sidebar order = Deploy HTML, Deploy Video, Projects, History, Settings.
- Drop (or "Choose Video…") an H.264 file → confirm phase shows the video preview + metadata.
- Pick a stills folder → slide count reflects only the image files (A8).
- Deploy → progress shows the 4 steps incl. an "Analyzing video frames…" state (A5) → complete phase shows a reachable URL, with Copy URL / Copy Framer Embed / Open in Browser / Deploy Another.
- Use Peekaboo `image` (pixel grab) + `see`/`inspect_ui` (AX-tree assert) as two independent reads; macOS `.sheet`/folder pickers are separate windows — find them via `peekaboo window list` if the main-window grab misses them. Then read `log stream` for runtime errors.
- Verify `HistoryEntry` was written (the new deploy appears in the History tab) and, if the auto-copy setting is on, the URL is on the clipboard.

The full live deck deploy + quality gate is exercised in section-09.

---

A few load-bearing notes I surfaced while writing this section, for the implementer and downstream:

- **`NavigationTab.video` does not exist on `main`.** The plan (§5.9) wrongly states it does; section-01's author verified the live `NavigationTab.swift` declares only `deploy / projects / history / settings`. This section must ADD the `.video` case (and its `title`/`systemImage`/`id` arms). Do not assume it is present.
- **The Swift source tree is not on this branch.** The current checkout (`main`) has no `swift-app/Sources/**/*.swift` files visible — the video work lives on a feature branch. Before editing, read the actual `AppSettings`, `HistoryEntry`, `ProcessingStep`, `NavigationTab`, `ContentView`, `SidebarView`, and the existing HTML `DeployView` on that branch and mirror their exact property names, history-write shape, kebab/prefix helper, `NSPasteboard` call, and auto-copy-setting check — this section deliberately defers those exact identifiers to the live source rather than guessing.
- **History persistence + auto-copy live in the View, not the deployer** (per section-07): `folderPath = result.folderPath` (source video path), `fixesApplied = 0`.

---

## As-built (deviations from plan)

Files: `Sources/Views/VideoDeployView.swift` (+ `VideoDeployLogic`), `Tests/VideoDeployViewTests.swift`, `Sources/Models/NavigationTab.swift` (+`.video`), `Sources/Views/ContentView.swift` (+`case .video`). 64/64 tests green, Swift 6 clean. No GIF tab existed on this branch — nothing to remove; `SidebarView` auto-derives rows from `NavigationTab.allCases`, so the `.video` row appears with no SidebarView edit.

**Framer embed model.** The plan suggested `padding-top = height/width*100%`. The live byte-target is `GifViewer.tsx` (the video path supersedes GIF), which uses `aspect-ratio:${w}/${h}`. `framerEmbed` mirrors that exactly (raw probed w/h, not 16/9). DeployView's bare-iframe embed was correctly NOT mirrored here.

**Review-driven fixes (section-08-review/interview):**
- **C2 / cross-section amendment:** `VideoDeployResult` (section-07) gained `width`/`height`, populated from `analysis`. The complete-phase embed sources the ratio from `result.width/height` — not a racy re-probe with a fabricated 1920×1080 fallback. Section-07's happy-path test asserts the new dims. (Additive fields; section-07 tests unaffected.)
- **C1:** AVPlayer is a stored `@State` built once in `acceptVideo` (was rebuilt every body render → playback reset/stutter).
- **I1:** Cancel returns to `.confirm` (coherent state); `acceptVideo` clears `stillPaths`/`result` so a new video can't inherit the old deck's stills.
- **I3:** m4v picker type via `UTType(filenameExtension: "m4v")` (the `UTType("public.m4v")` literal is frequently nil).
- **I4:** Vercel-token pre-check in `startDeploy` (actionable error, mirrors DeployView).
- **I5:** Settings loaded once in `acceptVideo`, passed to `probeDimensions`; `startDeploy` keeps its own fresh deploy-time read (DeployView pattern).
- **M1/M3/M4:** empty-stills warning rendered in `confirmPhase`; history/title use the filename without extension; fps clamped to `max(1, …)`.

**Deferred to the section-09 live gate:** the Peekaboo runtime walk (Deploy Video tab visible, drop→confirm→deploy→complete, HistoryEntry written, clipboard). M2 (does `onDisappear` cancel fire on tab switch) + M5 (instant Cancel feedback) are runtime behaviors to confirm there.

Relevant absolute paths: the section will be written to `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/planning/specs/swift-video-parity/sections/section-08-video-deploy-view.md`; source-of-truth plan files are `claude-plan.md` (§5.8/§5.9/§10 amendments A5/A8) and `claude-plan-tdd.md` (§Section 8) in the same `swift-video-parity/` directory.