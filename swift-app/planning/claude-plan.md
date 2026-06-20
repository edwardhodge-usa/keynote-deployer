# Implementation Plan — GIF Deploy (Swift Port, Phase 1)

## 1. Context for an unfamiliar reader

**The app.** Keynote Deployer is a macOS utility that takes a Keynote presentation and publishes it to the web on Vercel. It ships as two parallel codebases at feature parity: an Electron/React/TypeScript app (the primary, source-of-truth) and a Swift 6.2 / SwiftUI / SwiftData app (`swift-app/`). The Swift app already handles the main "HTML deploy" path and owns a complete, working backend for Vercel deployment, settings, history, and progress reporting.

**The feature being ported.** "GIF Deploy" is an alternate publish path. Keynote's HTML export rasterizes embedded images to low-resolution thumbnails, so image-heavy decks look broken on the web. The workaround: the user exports the whole deck as a single animated GIF (full-fidelity rendered slides, albeit 256-color), and the app deploys a **self-contained interactive HTML viewer** that loads the GIF and lets the audience step through slides (forward/back, dot navigation, keyboard, touch). This path exists today only in the Electron app. This plan ports it to Swift.

**The hard sub-problem — slide boundaries.** The deployed viewer must know where each *slide* begins and ends within the GIF's frame sequence, because a GIF is just frames — it has no notion of "slides." A held build step or a constant background makes frame-difference detection unreliable, so boundaries are computed **at build (deploy) time** and **baked** into the viewer as a static `DetectedSlide[]` JSON array. The viewer never detects anything; it just navigates the baked list. There are three boundary sources in the full feature — **Auto** (pixel-diff "quiet runs"), **Stills** (per-slide image exports matched to frames), and **Manual** (a grid editor). **This plan covers Phase 1 = the Auto path only**, which is sufficient to prove the entire pipeline end-to-end. Stills and Manual are deferred to later, separately-planned phases.

**Scope boundary of this plan.** Phase 1 delivers: a new tab in the Swift app where the user picks a Keynote-exported GIF; the app decodes frames, runs Auto boundary detection, emits the interactive viewer HTML, deploys it to Vercel via the existing backend, and records the result in history. Auto detection accuracy is explicitly "seed quality" — good enough to prove plumbing, not the final accurate path (that's Phase 2's Stills matcher). Out of scope: Stills matching, the Manual editor, live in-app animated playback, and refactoring the Electron viewer generator.

## 2. Key technical decision — GIF frame compositing (READ FIRST)

This decision drives the whole pipeline and corrects the original scope document.

A GIF stores frames using *disposal methods* and inter-frame compression. For "do-not-dispose" GIFs (which Keynote produces), each stored frame is a **partial patch** layered onto the accumulated previous image — not a standalone full picture. In the browser, the deployed viewer therefore composites frames progressively (0→N) using gifuct-js; it cannot grab an arbitrary full frame directly.

The original scope assumed Swift faces the same problem and must hand-roll a "GifCompositor." **Research indicates this is wrong for Apple's ImageIO framework.** `CGImageSourceCreateImageAtIndex` returns the **fully composited** frame at each index — ImageIO performs the disposal/compositing bookkeeping internally and never exposes a disposal-method key. This is corroborated by the fact that mature libraries (SDWebImage, Kingfisher) wrap that single call with zero manual compositing, by the absence of any disposal key in `kCGImagePropertyGIFDictionary`, and by the documented "ghosting" symptom (a single extracted frame shows accumulated content — i.e. it was composited).

**Because this inverts the scope's #1 risk and contradicts a prior project lesson, the plan does not take it on faith. Phase 1 opens with an empirical spike (see §5, Task 1) that settles it on a real Keynote GIF before any dependent code is written.**

- **Expected outcome (spike confirms auto-compositing):** there is **no** `GifCompositor`. A thin `GifFrameSource` wraps ImageIO and yields full `CGImage` frames. Pixel-diffing adjacent ImageIO frames is semantically valid (full-frame vs full-frame).
- **Fallback (spike shows partial patches):** implement the disposal-correct compositor — accumulate into a `CGBitmapContext` sized to the GIF canvas; per frame, draw the stored sub-rect, snapshot, then apply disposal (0/1 keep, 2 clear sub-rect to transparent, 3 restore-previous). Disposal method must be parsed from the GIF's binary Graphic Control Extension blocks, since ImageIO does not expose it.

**Performance / memory note (applies either way):** do-not-dispose chains are not independently decodable, so ImageIO may internally re-walk from frame 0 to satisfy a high index. Decode **forward 0→N once** — never random-access jump. **Do NOT cache the full-resolution `CGImage`s** (200 × 1080p frames ≈ 1.5 GB — an OOM risk). The pipeline streams: pull frame i, sample it, keep only the previous *sample vector* (a small `[Double]`), discard the image. Thumbnails for the detected `restFrame`s are produced by a **separate, targeted decode pass after detection** (only the N rest frames), which accepts a second forward re-walk in exchange for bounded memory.

## 3. Architecture overview

Phase 1 introduces a self-contained vertical feature alongside the existing HTML-deploy path. The entire deploy/persistence/settings/progress backend is **reused unchanged**; new code is confined to GIF decoding, pixel sampling, boundary detection, viewer-HTML emission, the deploy orchestrator, and one SwiftUI view plus a file picker.

Data flows in one direction:

```
user picks GIF
   → GifFrameSource (ImageIO → full CGImage frames, cached forward)
   → GridSampler (each frame → 1000-point RGB sample vector; adjacent vectors → diff array)
   → SlideDetector.detectSlides(diffs) → [DetectedSlide]   (Auto quiet-run)
   → GifViewerGenerator (shared template asset + baked slides → index.html string)
   → GifDeployer (temp folder; copy GIF; write index.html; call VercelDeployer.deploy)
   → live Vercel URL + HistoryEntry (fixesApplied=0, folderPath=gifPath)
```

The SwiftUI `GifDeployView` drives this through a phase state machine that mirrors the existing `DeployView`, and renders one static composited thumbnail per detected slide as a confirmation preview.

### Concurrency model (REQUIRED)
The decode → sample → detect pipeline is computationally heavy (hundreds of frames, pixel sampling, analysis) and **must never run on the main thread** — doing so beachballs the app. The entire pipeline is an `async` function executed off the main actor; only UI-state updates hop back to `@MainActor`. `GifDeployView` launches it as a cancellable `Task` on GIF selection (and `GifDeployer.deploy` is already `async`). The pipeline checks `try Task.checkCancellation()` between frames so a user-initiated cancel (or re-selection) stops promptly. This is the plan's single most important runtime requirement after the compositing question.

### Directory structure (new files under `swift-app/Sources/`)

```
swift-app/
  Sources/
    Models/
      GifDeploy.swift              # GifDeployRequest, DetectedSlide, QuietRun
      NavigationTab.swift          # MODIFIED: add `case gifDeploy`
    Services/
      GifFrameSource.swift         # ImageIO decode → full CGImage frames (forward+cached)
      GifCompositor.swift          # FALLBACK ONLY — created iff Task 1 spike fails
      GridSampler.swift            # CGImage → [Double] sample vector; meanAbs; diffs
      SlideDetector.swift          # Auto quiet-run port (verbatim constants)
      GifViewerGenerator.swift     # substitute placeholders into shared asset → HTML
      GifDeployer.swift            # orchestrate temp dir → viewer → VercelDeployer
    Views/
      GifDeployView.swift          # phase state machine + thumbnail preview
      ContentView.swift            # MODIFIED: route `.gifDeploy`
    Resources/
      viewer-template.html         # shared canonical viewer asset (placeholders)
  Tests/                           # NEW test target (Swift Testing)
    SlideDetectorTests.swift
    GridSamplerTests.swift
    GifViewerGeneratorTests.swift
    BoundaryMathTests.swift
```

## 4. Data model

Mirror the Electron `src/types/index.ts` field-for-field so the baked JSON is identical and the shared viewer asset consumes it unchanged. All structs `Codable, Sendable`.

```swift
struct GifDeployRequest: Codable, Sendable {
    let gifPath: String
    let projectName: String
    let slideCount: Int
    let title: String
    let secureEmbed: Bool
    let slides: [DetectedSlide]   // build-time boundaries, baked into the viewer
}

struct DetectedSlide: Codable, Sendable {
    let restFrame: Int
    let holdStart: Int
    let holdEnd: Int
    let transitionFrames: TransitionRange?   // null ⇒ hard cut
}

struct TransitionRange: Codable, Sendable { let start: Int; let end: Int }

struct QuietRun: Codable, Sendable {
    let start: Int
    let end: Int
    let length: Int
    let lastStart: Int   // start of last sub-run after build-merging
    let lastEnd: Int     // end of last sub-run after build-merging
}
```

**JSON-encoding requirement (parity-critical — read carefully):** the baked slides string must equal Electron's `JSON.stringify(slides)` **byte-for-byte**: compact (no spaces), keys in **insertion order** `restFrame, holdStart, holdEnd, transitionFrames`, and `null` for an absent transition. The byte-identical-viewer gate (Task 6) is defined against the **current Electron output**, so the Swift side must match `JSON.stringify`, not impose its own formatting.

- **Do NOT use `JSONEncoder.OutputFormatting.sortedKeys`.** (An external review suggested it; it is rejected.) Sorted keys produce alphabetical order (`holdEnd, holdStart, restFrame, transitionFrames`), which does **not** match Electron and would silently break parity and the deferred shared-asset goal. See `claude-integration-notes.md` item 8.
- **Chosen approach:** `DetectedSlide` has **zero string fields** (all `Int` / nested `Int` / `null`), so there is no string-escaping hazard today. Build the slides JSON deterministically to mirror `JSON.stringify` exactly.
- **Forward-guard (code comment required):** *if a string field is ever added to `DetectedSlide`, switch to a parity-preserving encoder that escapes strings while preserving `JSON.stringify` key order — never `.sortedKeys`.*

## 5. Build sequence (Phase 1 tasks, highest-risk-first)

Each task is independently verifiable. Tasks 1–2 are gated spikes/foundations; the rest layer the pipeline.

### Task 1 — Gate-0 compositing spike (BLOCKS everything else)
Confirm empirically whether ImageIO returns full composited frames for a real Keynote GIF. Write a minimal harness (a test plus a tiny throwaway command if helpful) that loads `TEST_GIF` (path supplied by Edward at implement time), decodes frame 0 and a late frame N via `CGImageSourceCreateImageAtIndex`, and asserts frame N is a full slide image (not a small sub-rect patch) — checked by image dimensions equal to the GIF canvas size and by visual/structural difference from frame 0.

- **If full frames (expected):** record the result; `GifFrameSource` will use ImageIO directly. Do **not** build `GifCompositor`.
- **If partial patches:** pivot — `GifFrameSource` delegates to a `GifCompositor` (see §2 fallback). This expands Task 2.

**Verification goal:** a recorded, reproducible determination ("ImageIO returns full frames: yes/no") on a real deck GIF, with the dimension/diff evidence.

### Task 2 — `GifFrameSource`
Wrap ImageIO. Decode all frames **forward 0→N once**, caching `CGImage`s (memory-bounded; for very long GIFs, cache lazily but never random-access jump backward without the cache). Expose frame count and indexed access.

```swift
final class GifFrameSource {
    init(gifURL: URL) throws            // throws .tooFewFrames if frameCount < 2
    var frameCount: Int { get }
    /// Streaming forward access for the detection pass: returns the next full
    /// composited frame and advances; nil at end. Caller samples then discards.
    func nextFrame() -> CGImage?
    /// Targeted decode of specific indices (the restFrames) for thumbnails,
    /// AFTER detection. Forward re-walk accepted; bounded count.
    func frames(at indices: [Int]) -> [Int: CGImage]
}
```
- **Streaming, not caching:** the detection pass consumes frames via `nextFrame()` and never holds more than the current image + the previous sample vector (see Task 3). Full-resolution images are not retained.
- **Edge cases:** `init` throws `tooFewFrames` for 0- or 1-frame GIFs (corrupted/static), so downstream never sees a degenerate diff array.
- (If Task 1 hit the fallback, `GifFrameSource` owns a `GifCompositor` internally; the public surface is unchanged.)

**Verification goal:** loads `TEST_GIF`, reports the expected frame count, `nextFrame()` returns non-nil full-canvas `CGImage`s; a late frame differs structurally from frame 0; a 1-frame GIF makes `init` throw `tooFewFrames`.

### Task 3 — `GridSampler`
Convert each `CGImage` to a fixed sample vector and compute the adjacent-frame diff array that detection consumes. Port the Electron sampler exactly: 1000 sample points on a `ceil(sqrt(1000)) = 32`×32 grid, **RGB only (no alpha)**; diff = mean absolute difference across sampled channels.

```swift
enum GridSampler {
    static let samplePoints = 1000
    static let gridSize = 32     // ceil(sqrt(1000))
    /// Sample RGB at the grid points → flat [Double] (length = gridSize*gridSize*3).
    static func sample(_ image: CGImage) -> [Double]
    /// Mean absolute difference between two equal-length vectors (0 if empty).
    static func meanAbs(_ a: [Double], _ b: [Double]) -> Double
    /// Streams frames forward from `source`, keeping only the previous sample
    /// vector. diffs[i] = meanAbs(sample(frame[i]), sample(frame[i-1])); diffs[0] = 0.
    /// Returns [] for 0/1-frame input (defensive; init already guards <2).
    /// Calls `try Task.checkCancellation()` between frames.
    static func frameDiffs(_ source: GifFrameSource) throws -> [Double]
}
```

**Verification goal:** `meanAbs` matches the TS reference on known vectors (incl. empty→0); `frameDiffs` returns an array of length `frameCount`; never holds more than one decoded image at a time; returns `[]` on degenerate input.

### Task 4 — `SlideDetector` (Auto quiet-run, verbatim port)
Pure array math over the diff array. Port `src/utils/slideDetection.ts` exactly, including the **adaptive median factor 0.33** (not 0.5 — the scope doc was stale here) and the boundary-edit helpers used to recompute transitions.

```swift
enum SlideDetector {
    static let quietThreshold = 0.3
    static let minQuietRun    = 8
    static let transitionPeak = 0.5

    static func findQuietRuns(_ diffs: [Double]) -> [QuietRun]
    static func mergeBuildRuns(_ runs: [QuietRun], _ diffs: [Double]) -> [QuietRun]
    static func filterTransitionArtifacts(_ runs: [QuietRun]) -> [QuietRun]   // adaptiveMin = max(minQuietRun, floor(median(lengths) * 0.33))
    static func buildSlideMap(_ runs: [QuietRun]) -> [DetectedSlide]
    static func detectSlides(_ diffs: [Double]) -> [DetectedSlide]            // orchestration; returns [] for empty/degenerate diffs

    // Boundary math (also reused by later Manual phase)
    static func recomputeTransitions(_ slides: [DetectedSlide]) -> [DetectedSlide]
}
```
`recomputeTransitions`: for each slide i>0, `transition.start = slides[i-1].holdEnd + 1`, `transition.end = slides[i].holdStart - 1`; if inverted (overlap), `transitionFrames = nil` (hard cut).

**Verification goal:** the ported Electron Vitest cases (synthetic diff arrays → expected slide counts, including the micro-build-merge and adaptive-median cases) pass under Swift Testing.

### Task 5 — Extract the shared viewer template asset
Create `Resources/viewer-template.html`: the canonical viewer extracted from `electron/gifViewerGenerator.ts` (~570 lines: embedded gifuct-js IIFE, progressive compositing, playback, navigation, secure-embed CSS), with the three injection points turned into placeholders: `{{GIF_FILENAME}}`, `{{BAKED_SLIDES}}`, `{{SECURE_EMBED}}`. The extraction must reproduce the current Electron output verbatim when the placeholders are filled with the same values the TS generator uses (`var BAKED_SLIDES = <json>`, `fetch('./<filename>')`, conditional secure-embed block). The Electron generator is **not** modified in this plan; the asset must simply match its current output.

**Verification goal:** filling the template with a fixture input reproduces a captured Electron-generated `index.html` exactly (this is half of Task 6's gate).

### Task 6 — `GifViewerGenerator`
Read the shared asset and substitute placeholders to produce the final `index.html` string.

```swift
enum GifViewerGenerator {
    /// Emit the self-contained viewer HTML for the given GIF + baked slides.
    /// WARNING (required code comment): never inject raw, unescaped user-provided
    /// strings into the template. Inputs here are JSON (baked slides), a filename,
    /// and a bool only. `title`/`projectName` are deliberately NOT injected, to
    /// avoid an HTML/JS injection (XSS) vector in the deployed viewer.
    static func generate(gifFilename: String, secureEmbed: Bool, slides: [DetectedSlide]) -> String
}
```
The baked-slides substitution must equal the TS `JSON.stringify(slides)` byte-for-byte (see §4 encoding requirement — and note the explicit rejection of `.sortedKeys`). Secure-embed toggles the same conditional block the TS uses.

**Verification goal (Gate-1):** for one or more fixture inputs, `generate(...)` output is **byte-identical** to the current Electron `generateGifViewerHtml(...)` output. Capture the Electron output as a committed test fixture.

### Task 7 — `GifDeployer` (orchestration, reuses the backend)
Mirror the Electron `deploy-gif` IPC order, calling the existing Swift backend.

```swift
enum GifDeployer {
    static func deploy(_ request: GifDeployRequest,
                       settings: AppSettings,
                       onProgress: @Sendable (ProcessingStep) -> Void) async throws -> DeployResult
}
```
Steps: create a **securely-named unique temp directory** via `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: gifURL, create: true)` (not a hand-built predictable `/tmp/...-<timestamp>` path — avoids TOCTOU and is the idiomatic Apple approach; the temp dir is not part of the deployed output, so this does not affect the byte-identical gate); copy the GIF into it; write `index.html` from `GifViewerGenerator`; resolve/create the project via `VercelAPI.ensureProject`; call `VercelDeployer.deploy(folderPath:projectId:token:teamId:secureEmbed:embedAllowedDomains:onProgress:)`; on success write a `HistoryEntry` (`folderPath = gifPath`, `fixesApplied = 0`, `slideCount = slides.count`); clean up the temp directory. Secure-embed CSP is handled inside `VercelDeployer` (writes `vercel.json`) — do not duplicate it in the viewer HTML.

**Verification goal (Gate-2, live):** with `TEST_GIF` and real Vercel settings, a deploy produces a live URL whose viewer renders and navigates, and a `HistoryEntry` is persisted with the expected fields. Run at /deep-implement time.

### Task 8 — `GifDeployView` + navigation wiring + file picker
Add `case gifDeploy` to `NavigationTab` (auto-appears in `SidebarView` via `allCases`); route it in `ContentView`. Build `GifDeployView` with a phase state machine mirroring `DeployView.Phase`:

`selectGif → loading → confirm → processing → complete → error`

The view holds the running pipeline `Task` handle so it can be cancelled (user Cancel button or re-selection). A dedicated error type drives user-facing messages:

```swift
enum GifDeployError: Error {
    case invalidGifFile(path: String)
    case tooFewFrames(count: Int)
    case decodingFailed(reason: String)
    case fileNotFound(path: String)
    case vercelDeployFailed(underlying: Error)
}
```

- **selectGif:** drop zone + NSOpenPanel GIF picker (mirror `DeployView.selectFolder()`; `canChooseFiles = true`, `.gif` UTType).
- **loading:** runs the pipeline in a cancellable background `Task` — `frameDiffs` (streaming) → `detectSlides` → then a **separate targeted decode pass** producing one composited thumbnail per `restFrame` (via `GifFrameSource.frames(at:)`). UI updates marshalled to `@MainActor`. Shows a Cancel button.
- **confirm:** show thumbnails, slide count, project-name field, secure-embed toggle (from `AppSettings`), plus a small non-intrusive note: *"Automatic detection is a best-effort preview; precise Still-image matching is coming in a later update."* — manages expectations since Auto is seed-quality.
- **processing:** drive `GifDeployer.deploy`, surfacing `ProcessingStep` progress; Cancel available.
- **complete:** URL copy, Framer-embed copy, open-in-browser (mirror `DeployView`).
- **error:** message derived from the specific `GifDeployError` case (e.g. "The selected file does not appear to be a valid GIF.") + retry.

**Verification goal:** the tab appears; picking `TEST_GIF` advances through phases and shows the right number of thumbnails; the UI stays responsive during processing (work is off-main); Cancel aborts promptly; deploy reaches `complete` with a working URL (visual/runtime gate per the repo's Swift verify loop — XcodeBuildMCP build/test, then Peekaboo macOS eyeball).

## 6. Testing strategy

New **Swift Testing** target (`@Test`/`#expect`); `swift-app` currently has none, so the plan establishes it (add the test target to `project.yml`, regenerate with `xcodegen generate`). Two tiers:

- **Pure-unit (offline, deterministic):** `SlideDetector` (ported Vitest cases — synthetic diff arrays → expected slide counts/transitions, adaptive-median edge case, micro-build merge, **empty/single-element diffs → []**), `GridSampler.meanAbs` (incl. empty→0), `recomputeTransitions` (incl. inverted→nil), and `GifViewerGenerator` byte-identical-against-fixture (incl. an empty-`slides` deck — guard the zero-slide deploy crash class seen previously in this feature family).
- **Live/integration (need `TEST_GIF`, run at implement time):** Gate-0 compositing spike (Task 1), `GifFrameSource` frame-count/full-frame check, and the end-to-end Gate-2 deploy.

Follow the repo's existing Swift verify loop: Stage 1 headless build+test via XcodeBuildMCP; Stage 2 visual/runtime gate via Peekaboo on the fresh DerivedData build.

## 7. Risks & mitigations

- **Compositing assumption (highest):** mitigated by the Task 1 gate-0 spike before any dependent code; documented fallback path if it fails.
- **Viewer drift (high):** mitigated by the shared template asset + byte-identical gate (Tasks 5–6). The Electron generator is untouched, so the gate compares against a stable, shipping reference.
- **JSON key-order/null mismatch breaking the byte-identical gate:** mitigated by building the baked-slides string deterministically to match `JSON.stringify` rather than trusting `JSONEncoder` field order.
- **Auto accuracy is only seed-quality:** accepted for Phase 1 (the goal is plumbing); accurate boundaries arrive in Phase 2 (Stills). The UI should not imply Auto is authoritative.
- **No existing Swift test target:** plan adds one (project.yml + xcodegen) as part of Task 4's setup; never commit a worktree-regenerated `project.pbxproj` (known repo hazard).
- **UI freeze / OOM (from review):** mitigated by the required off-main concurrency model (§3) and the streaming, no-full-frame-cache memory model (§2) — both are explicit requirements, not optional.
- **Degenerate GIFs (0/1 frame, corrupted):** mitigated by `GifFrameSource` throwing `tooFewFrames`, graceful empty-array returns downstream, and dedicated unit tests.

## 8. Definition of done (Phase 1)
1. Gate-0 recorded (compositing determination on a real GIF).
2. Gate-1 passing (Swift viewer byte-identical to Electron's for fixture inputs).
3. Gate-2 passing (real GIF → Swift detect → Vercel deploy → live navigable viewer → HistoryEntry).
4. New `.gifDeploy` tab functional end-to-end; pure-unit tests green; build clean via the repo's verify loop.
5. Stills, Manual editor, live playback, and the Electron shared-asset refactor remain deferred and are noted as such in code/docs.
