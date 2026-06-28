# Marker / Timeline Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Review Markers" phase to the Deploy Video tab so the user drags/adds/removes per-slide rest markers (with a live frame preview) before encode; the approved marker becomes BOTH the viewer rest point AND the forced keyframe.

**Architecture:** Split `VideoDeployer.deploy` into `analyze()` (probe + DP-match → seed `VideoAnalysis`) and `deploy(...editedTimestamps:)` (encode + generate + deploy with the human-edited markers). A new SwiftUI `MarkerEditorView` (filmstrip + big `AVPlayerView` preview + scrubber) edits the marker list; pure list logic lives in `MarkerEditorLogic` for offline tests. `REST_BIAS` retires to 0 — the marker IS the rest point and the forced keyframe. `slideCount` follows `editedTimestamps.count`, decoupled from the stills count.

**Tech Stack:** Swift 6.2, SwiftUI, AVFoundation/AVKit (`AVPlayerView` via `NSViewRepresentable`, `AVAssetImageGenerator`), Swift Testing.

## Global Constraints

- Swift 6.2 / SwiftUI / SwiftData, macOS 15+. Swift-only repo (`swift-app/`).
- Concurrency: service calls `async`; progress callbacks `@Sendable`; rebuild `ProcessingStep` each tick (capture nothing mutable).
- Use AppKit `AVPlayerView` via `NSViewRepresentable` — **never** SwiftUI `AVKit.VideoPlayer` (SIGABRTs in `_AVKit_SwiftUI` on macOS 26).
- Timestamp rounding stays EXACT: `round((frame/fps)*1000)/1000` (3dp). The viewer `{{TS}}` and encoder `-force_key_frames` re-derive from the same `[Double]` — no drift.
- `JSNumber.format` is the sole formatter for any timestamp emitted to JS/ffmpeg.
- Build outside iCloud; build-verify with `cd swift-app && xcodegen generate && xcodebuild build -scheme KeynoteDeployer -destination "platform=macOS" -quiet`.
- Test-run: `cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -quiet` (delegate to the apple-platform-build-tools:builder agent to absorb logs).
- STOP and report blockers; never silently work around them.
- Version bump to 1.3.0 happens in the final task.

---

### Task 1: MarkerEditorLogic (pure marker-list operations)

**Files:**
- Create: `swift-app/Sources/Services/MarkerEditorLogic.swift`
- Test: `swift-app/Tests/MarkerEditorLogicTests.swift`

**Interfaces:**
- Consumes: nothing (pure, no AVFoundation).
- Produces:
  - `MarkerEditorLogic.clamp(_ proposed: Double, index: Int, markers: [Double], duration: Double, epsilon: Double = 0.001) -> Double`
  - `MarkerEditorLogic.insert(_ time: Double, into markers: [Double]) -> (markers: [Double], index: Int)`
  - `MarkerEditorLogic.remove(at index: Int, from markers: [Double]) -> (markers: [Double], selected: Int)`
  - `MarkerEditorLogic.isMonotonic(_ markers: [Double]) -> Bool`

- [ ] **Step 1: Write the failing tests**

Create `swift-app/Tests/MarkerEditorLogicTests.swift`:

```swift
import Testing
@testable import KeynoteDeployer

@Suite("MarkerEditorLogic")
struct MarkerEditorLogicTests {

    @Test("clamp keeps a marker strictly between its neighbors")
    func clampBetweenNeighbors() {
        let m = [0.0, 2.0, 4.0]
        // proposed above the upper neighbor → clamped just below it
        #expect(MarkerEditorLogic.clamp(5.0, index: 1, markers: m, duration: 10) == 4.0 - 0.001)
        // proposed below the lower neighbor → clamped just above it
        #expect(MarkerEditorLogic.clamp(-1.0, index: 1, markers: m, duration: 10) == 0.0 + 0.001)
        // proposed in range → unchanged
        #expect(MarkerEditorLogic.clamp(3.0, index: 1, markers: m, duration: 10) == 3.0)
    }

    @Test("clamp respects 0 and duration at the ends")
    func clampEnds() {
        let m = [1.0, 5.0]
        #expect(MarkerEditorLogic.clamp(-2.0, index: 0, markers: m, duration: 9) == 0.0)
        #expect(MarkerEditorLogic.clamp(99.0, index: 1, markers: m, duration: 9) == 9.0)
    }

    @Test("insert keeps the array sorted and returns the new index")
    func insertSorted() {
        let (m, idx) = MarkerEditorLogic.insert(3.0, into: [0.0, 2.0, 4.0])
        #expect(m == [0.0, 2.0, 3.0, 4.0])
        #expect(idx == 2)
        #expect(MarkerEditorLogic.isMonotonic(m))
    }

    @Test("remove deletes the marker and reselects in range")
    func removeReselects() {
        let (m, sel) = MarkerEditorLogic.remove(at: 2, from: [0.0, 2.0, 4.0])
        #expect(m == [0.0, 2.0])
        #expect(sel == 1)
    }

    @Test("remove is guarded at N==1 (a deck needs at least one slide)")
    func removeGuardedAtOne() {
        let (m, sel) = MarkerEditorLogic.remove(at: 0, from: [3.0])
        #expect(m == [3.0])
        #expect(sel == 0)
    }

    @Test("isMonotonic is false for equal or decreasing values")
    func monotonicDetectsViolations() {
        #expect(MarkerEditorLogic.isMonotonic([0.0, 1.0, 2.0]))
        #expect(!MarkerEditorLogic.isMonotonic([0.0, 1.0, 1.0]))
        #expect(!MarkerEditorLogic.isMonotonic([0.0, 3.0, 2.0]))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -only-testing:KeynoteDeployerTests/MarkerEditorLogicTests -quiet`
Expected: FAIL — `cannot find 'MarkerEditorLogic' in scope`.

- [ ] **Step 3: Write the implementation**

Create `swift-app/Sources/Services/MarkerEditorLogic.swift`:

```swift
import Foundation

/// Pure, AVFoundation-free operations on the per-slide marker list edited in the
/// Review Markers phase. The marker list is the authoritative slide set: it must
/// stay sorted + strictly increasing (the encoder's forced keyframes and the
/// viewer's {{TS}} both depend on it). Extracted from the view so it's unit-testable
/// offline.
enum MarkerEditorLogic {

    /// Clamp a proposed time for `markers[index]` so it stays strictly between its
    /// neighbors (an `epsilon` gap on each side) and within `[0, duration]`. Keeps
    /// markers from crossing while a scrubber drags one.
    static func clamp(_ proposed: Double,
                      index: Int,
                      markers: [Double],
                      duration: Double,
                      epsilon: Double = 0.001) -> Double {
        let lower = index > 0 ? markers[index - 1] + epsilon : 0
        let upper = index < markers.count - 1 ? markers[index + 1] - epsilon : duration
        if upper < lower { return lower }   // degenerate: neighbors closer than 2·epsilon
        return min(max(proposed, lower), upper)
    }

    /// Insert a new marker at `time`, keeping the array sorted. Returns the new
    /// array and the inserted element's index. Caller is responsible for choosing a
    /// `time` that doesn't duplicate a neighbor (use the current playhead, which sits
    /// between existing markers).
    static func insert(_ time: Double, into markers: [Double]) -> (markers: [Double], index: Int) {
        var m = markers
        let idx = m.firstIndex(where: { $0 > time }) ?? m.count
        m.insert(time, at: idx)
        return (m, idx)
    }

    /// Remove `markers[index]`. Guarded: never removes the last marker (a deck needs
    /// ≥1 slide). Returns the new array and the index to select next (clamped).
    static func remove(at index: Int, from markers: [Double]) -> (markers: [Double], selected: Int) {
        guard markers.count > 1, markers.indices.contains(index) else {
            return (markers, min(max(index, 0), max(markers.count - 1, 0)))
        }
        var m = markers
        m.remove(at: index)
        return (m, min(index, m.count - 1))
    }

    /// True iff strictly increasing — the encoder/viewer invariant.
    static func isMonotonic(_ markers: [Double]) -> Bool {
        zip(markers, markers.dropFirst()).allSatisfy { $0 < $1 }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -only-testing:KeynoteDeployerTests/MarkerEditorLogicTests -quiet`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
cd swift-app && git add Sources/Services/MarkerEditorLogic.swift Tests/MarkerEditorLogicTests.swift
git commit -m "feat(markers): pure MarkerEditorLogic (clamp/insert/remove/monotonic)"
```

---

### Task 2: Split VideoDeployer into analyze() + deploy(editedTimestamps:)

**Files:**
- Modify: `swift-app/Sources/Services/VideoDeployer.swift`
- Test: `swift-app/Tests/VideoDeployerTests.swift`

**Interfaces:**
- Consumes: `VideoAnalysis` (frames/timestamps/slideCount/width/height/fps), `VideoDeployerSeams`, `VideoTimestampDeriver.derive`, `VideoViewerGenerator.generate`, `VideoPoster.extract`.
- Produces:
  - `VideoDeployer.analyze(_ request: VideoDeployRequest, seams: VideoDeployerSeams, onProgress: @Sendable (ProcessingStep) -> Void) async throws -> VideoAnalysis`
  - `VideoDeployer.deploy(_ request: VideoDeployRequest, analysis: VideoAnalysis, editedTimestamps: [Double], settings: AppSettings, seams: VideoDeployerSeams, onProgress: @Sendable (ProcessingStep) -> Void) async throws -> VideoDeployResult`
  - (The old single-call `deploy(_:settings:seams:onProgress:)` is removed; `VideoDeployView` is updated in Task 5.)

**Behavior changes:**
- `analyze` runs only Step 1 (probe + DP-match) and returns the seed `VideoAnalysis`. Emits the id:1 step (active → completed with slide count).
- `deploy` runs Steps 2–4 using `editedTimestamps` (NOT `analysis.timestamps`) for both the encoder keyframes and `{{TS}}`. `width/height/fps` come from `analysis`.
- `slideCount` in the result = `editedTimestamps.count`.
- Poster extracts at `editedTimestamps.first` **exactly** (no `- 0.08`), mirroring the viewer's `REST_BIAS = 0` from Task 3.

- [ ] **Step 1: Write/adjust the failing tests**

In `swift-app/Tests/VideoDeployerTests.swift`, the existing tests call the old `deploy(_:settings:seams:onProgress:)`. Replace the orchestration test(s) with the split flow and add the edited-timestamps + slideCount tests. Add this suite member (keep the existing `StubEncoder`/`DeployFlag`/fixtures):

```swift
    @Test("analyze returns the seed analysis; deploy honors editedTimestamps")
    func analyzeThenDeployUsesEditedTimestamps() async throws {
        // 3-frame video; 2 stills matching frames 0 and 2 → seed timestamps [0, 2/fps].
        let encoder = StubEncoder(
            videoURL: Self.videoURL,
            frameGrids: [[0], [1], [0]],
            stillGridByPath: [Self.stillURL("a.png").path: [0],
                              Self.stillURL("b.png").path: [0]])
        let flag = DeployFlag()
        let seams = VideoDeployerSeams(encoder: encoder) { _, name, _, _ in
            flag.mark(); return "https://\(name).vercel.app"
        }
        let request = VideoDeployRequest(
            videoPath: Self.videoURL.path,
            stillPaths: [Self.stillURL("a.png").path, Self.stillURL("b.png").path],
            fps: 30, projectName: "kd-sec7", title: "deck", secureEmbed: false)

        let analysis = try await VideoDeployer.analyze(request, seams: seams) { _ in }
        #expect(analysis.slideCount == 2)
        #expect(analysis.timestamps.count == 2)

        // The human edits the markers (e.g. adds one → 3 slides).
        let edited = [0.0, 0.05, 0.1]
        var settings = AppSettings.default
        settings.vercelToken = "tok"
        let result = try await VideoDeployer.deploy(
            request, analysis: analysis, editedTimestamps: edited,
            settings: settings, seams: seams) { _ in }

        #expect(flag.called)
        #expect(result.slideCount == 3)            // follows editedTimestamps.count
        #expect(encoder.calls.contains("encode"))
    }
```

Update any other test in the file that called the old single `deploy(_:settings:seams:onProgress:)` to first `analyze` then `deploy(..., editedTimestamps: analysis.timestamps, ...)` (pass the seed unchanged where the test only checks deploy mechanics like the missing-token guard).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -only-testing:KeynoteDeployerTests/VideoDeployerTests -quiet`
Expected: FAIL — `analyze` not found / old `deploy` signature mismatch.

- [ ] **Step 3: Write the implementation**

In `swift-app/Sources/Services/VideoDeployer.swift`, replace the single `deploy(_:settings:seams:onProgress:)` with `analyze` + the new `deploy(...editedTimestamps:)`:

```swift
    /// Step 1 only: probe + DP-match the stills → seed `VideoAnalysis`. The seed
    /// timestamps become the initial markers the user reviews before encode.
    static func analyze(_ request: VideoDeployRequest,
                        seams: VideoDeployerSeams,
                        onProgress: @Sendable (ProcessingStep) -> Void) async throws -> VideoAnalysis {
        let videoURL = URL(fileURLWithPath: request.videoPath)
        let stillURLs = request.stillPaths.map { URL(fileURLWithPath: $0) }

        onProgress(ProcessingStep(id: 1, label: "Analyze video", detail: "Probing video…", status: .active))
        let analysis = try await VideoTimestampDeriver.derive(
            encoder: seams.encoder,
            videoURL: videoURL,
            stillURLs: stillURLs,
            fps: request.fps,
            onProgress: { p in
                onProgress(ProcessingStep(
                    id: 1, label: "Analyze video",
                    detail: "Analyzing video frames… \(Int((p * 100).rounded()))%",
                    status: .active))
            })
        let slideCount = analysis.slideCount
        onProgress(ProcessingStep(
            id: 1, label: "Analyze video",
            detail: "\(slideCount) slide\(slideCount == 1 ? "" : "s")",
            status: .completed))
        return analysis
    }

    /// Steps 2–4: encode (forced keyframes at the EDITED markers) → generate the
    /// viewer (the same edited markers as {{TS}}) → deploy to Vercel. `width/height/
    /// fps` come from the seed `analysis`; the slide count follows the edited markers.
    static func deploy(_ request: VideoDeployRequest,
                       analysis: VideoAnalysis,
                       editedTimestamps: [Double],
                       settings: AppSettings,
                       seams: VideoDeployerSeams,
                       onProgress: @Sendable (ProcessingStep) -> Void) async throws -> VideoDeployResult {
        let videoURL = URL(fileURLWithPath: request.videoPath)

        let tempDir = "/tmp/keynote-deployer-video-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // ── Step 2 — Encode (forced keyframes at the edited markers) ────────────
        var step2 = ProcessingStep(id: 2, label: "Encode video", detail: "Re-encoding with per-slide keyframes…", status: .active)
        onProgress(step2)
        let outputURL = URL(fileURLWithPath: tempDir).appendingPathComponent("deck.mp4")
        try await seams.encoder.encodeWithKeyframes(input: videoURL, output: outputURL, timestamps: editedTimestamps, fps: analysis.fps)
        step2.status = .completed
        onProgress(step2)

        // ── Step 3 — Generate ───────────────────────────────────────────────────
        var step3 = ProcessingStep(id: 3, label: "Generate viewer", detail: "Building index.html…", status: .active)
        onProgress(step3)
        // Poster = slide 1's marker frame EXACTLY (REST_BIAS retired to 0 — the marker
        // IS the rest frame). Best-effort: a failure degrades to no-poster, never fails.
        var posterFilename: String? = nil
        if let firstTimestamp = editedTimestamps.first {
            let posterURL = URL(fileURLWithPath: tempDir).appendingPathComponent("poster.jpg")
            do {
                try await VideoPoster.extract(from: outputURL, atSeconds: max(0, firstTimestamp), to: posterURL)
                posterFilename = "poster.jpg"
            } catch {
                posterFilename = nil
            }
        }
        let html = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4",
            secureEmbed: request.secureEmbed,
            timestamps: editedTimestamps,
            videoWidth: analysis.width,
            videoHeight: analysis.height,
            posterFilename: posterFilename)
        let indexURL = URL(fileURLWithPath: tempDir).appendingPathComponent("index.html")
        try html.write(to: indexURL, atomically: true, encoding: .utf8)
        step3.status = .completed
        onProgress(step3)

        // ── Step 4 — Deploy ───────────────────────────────────────────────────────
        var step4 = ProcessingStep(id: 4, label: "Deploy to Vercel", detail: "Deploying…", status: .active)
        guard !settings.vercelToken.isEmpty else {
            step4.status = .error
            step4.error = VideoDeployError.missingVercelToken.errorDescription
            onProgress(step4)
            throw VideoDeployError.missingVercelToken
        }
        onProgress(step4)
        let url: String
        do {
            url = try await seams.ensureProjectAndDeploy(tempDir, request.projectName, request.secureEmbed, onProgress)
        } catch {
            onProgress(ProcessingStep(id: 4, label: "Deploy to Vercel", detail: "Deploy failed",
                                      status: .error, error: error.localizedDescription))
            throw error
        }
        step4.detail = url
        step4.status = .completed
        onProgress(step4)

        return VideoDeployResult(
            url: url,
            projectName: request.projectName,
            title: request.title,
            slideCount: editedTimestamps.count,
            width: analysis.width,
            height: analysis.height,
            folderPath: request.videoPath)
    }
```

Keep `VideoDeployerSeams`, `live(settings:)`, `VideoDeployResult`, and `VideoDeployError` exactly as they are.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -only-testing:KeynoteDeployerTests/VideoDeployerTests -quiet`
Expected: PASS (existing + new orchestration tests).

- [ ] **Step 5: Commit**

```bash
cd swift-app && git add Sources/Services/VideoDeployer.swift Tests/VideoDeployerTests.swift
git commit -m "feat(video): split VideoDeployer into analyze() + deploy(editedTimestamps:)"
```

---

### Task 3: Retire REST_BIAS in the viewer template + regenerate goldens

**Files:**
- Modify: `swift-app/Sources/Resources/video-viewer-template.html:75` (`var REST_BIAS = 0.08;` → `var REST_BIAS = 0;`)
- Test: `swift-app/Tests/VideoViewerGeneratorTests.swift`
- Modify (regenerate): `swift-app/Tests/Fixtures/video-viewer-golden-*.html`

**Interfaces:**
- Consumes: `VideoViewerGenerator.generate(...)` (unchanged signature; it passes the template through verbatim, so the `REST_BIAS` literal flows into the output).
- Produces: viewer output where `restTime(i) == TS[i]` (marker = rest point = forced keyframe).

**Why minimal:** the carefully-tuned iOS playback code (wall-clock stop, navBusy lock, blob loader, paintFrame micro-play, poster, edge-tap) stays untouched. Only the bias constant changes; `restTime()` keeps its shape but now returns `TS[i]` unchanged.

- [ ] **Step 1: Add a failing assertion that the generated viewer rests on the keyframe**

In `swift-app/Tests/VideoViewerGeneratorTests.swift`, add:

```swift
    @Test("viewer rests exactly on the marker (REST_BIAS retired to 0)")
    func restBiasIsZero() {
        let html = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4", secureEmbed: false,
            timestamps: [0, 1.5, 3.0], videoWidth: 1920, videoHeight: 1080)
        #expect(html.contains("var REST_BIAS = 0;"))
        #expect(!html.contains("var REST_BIAS = 0.08;"))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -only-testing:KeynoteDeployerTests/VideoViewerGeneratorTests/restBiasIsZero -quiet`
Expected: FAIL — template still says `0.08`.

- [ ] **Step 3: Edit the template**

In `swift-app/Sources/Resources/video-viewer-template.html` line 75, change:

```javascript
    var REST_BIAS = 0.08;
```

to:

```javascript
    var REST_BIAS = 0;
```

Leave `restTime`, `settleOn`, `next`, `paintFrame`, `finish`, and the wall-clock logic unchanged.

- [ ] **Step 4: Regenerate the golden fixtures**

The byte-parity goldens embed the template verbatim, so they now differ by the `REST_BIAS` literal. Identify the failing goldens and regenerate them from the live generator. Run the full generator suite to see which fixtures mismatch:

Run: `cd swift-app && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -only-testing:KeynoteDeployerTests/VideoViewerGeneratorTests -quiet`
Expected: the new test PASSES; any byte-parity test comparing against `Tests/Fixtures/video-viewer-golden-*.html` FAILS on the `REST_BIAS` line only.

For each failing golden, regenerate it by writing the generator's current output to the fixture. Read the test to confirm the exact `generate(...)` arguments each golden uses, then in a scratch test or via the existing regeneration path used in the repo, overwrite the fixture. The mechanical way that matches this repo's discipline: apply the same one-line edit (`0.08` → `0`) to each `Tests/Fixtures/video-viewer-golden-*.html` (the goldens are the template output; the only changed byte is that literal). Verify with `grep -n "REST_BIAS" Tests/Fixtures/video-viewer-golden-*.html` showing `= 0;` in every file.

- [ ] **Step 5: Run the generator suite to verify parity restored**

Run: `cd swift-app && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -only-testing:KeynoteDeployerTests/VideoViewerGeneratorTests -quiet`
Expected: PASS (byte-parity + the new REST_BIAS test).

- [ ] **Step 6: Commit**

```bash
cd swift-app && git add Sources/Resources/video-viewer-template.html Tests/Fixtures/video-viewer-golden-*.html Tests/VideoViewerGeneratorTests.swift
git commit -m "feat(viewer): REST_BIAS=0 — rest exactly on the marker/keyframe; regen goldens"
```

---

### Task 4: MarkerEditorView (filmstrip + live preview + scrubber)

**Files:**
- Create: `swift-app/Sources/Views/MarkerEditorView.swift`

**Interfaces:**
- Consumes: `MarkerEditorLogic` (Task 1), `VideoPreview` (existing `NSViewRepresentable` in `VideoDeployView.swift`), `AVPlayer`, `AVAssetImageGenerator`.
- Produces:
  - `struct MarkerEditorView: View` with init
    `init(player: AVPlayer, videoURL: URL, duration: Double, initialMarkers: [Double], onConfirm: @escaping ([Double]) -> Void, onBack: @escaping () -> Void)`

**Design notes:**
- One shared `AVPlayer` (the source video, reused from `VideoDeployView`). Exact-frame seek via `player.seek(to:toleranceBefore:.zero, toleranceAfter:.zero)`.
- Scrubber `Binding` clamps through `MarkerEditorLogic.clamp` and seeks live.
- Filmstrip thumbnails generated once on `.task` via `AVAssetImageGenerator.generateCGImagesAsynchronously`; the selected thumb regenerates after its marker moves.
- `[+ add]` inserts a marker at the current playhead (clamped); `[− remove]` deletes the selected (guarded at N==1).

- [ ] **Step 1: Write the view (no separate unit test — logic is covered by Task 1; verified by build + the live gate in Task 5)**

Create `swift-app/Sources/Views/MarkerEditorView.swift`:

```swift
import SwiftUI
import AVFoundation

/// The "Review Markers" phase of the Deploy Video tab. Shows a big live preview of
/// the selected slide's marker frame, a scrubber to move it (exact-frame seek), and
/// a filmstrip of all slide thumbnails. The user drags / adds / removes markers; the
/// approved list becomes BOTH the viewer rest points and the forced encoder keyframes.
///
/// Pure list edits go through `MarkerEditorLogic` (offline-tested). Uses the AppKit
/// `AVPlayerView` wrapper (`VideoPreview`) — never SwiftUI's `AVKit.VideoPlayer`.
struct MarkerEditorView: View {
    let player: AVPlayer
    let videoURL: URL
    let duration: Double
    let onConfirm: ([Double]) -> Void
    let onBack: () -> Void

    @State private var markers: [Double]
    @State private var selected: Int = 0
    @State private var thumbs: [Int: NSImage] = [:]

    init(player: AVPlayer,
         videoURL: URL,
         duration: Double,
         initialMarkers: [Double],
         onConfirm: @escaping ([Double]) -> Void,
         onBack: @escaping () -> Void) {
        self.player = player
        self.videoURL = videoURL
        self.duration = duration
        self.onConfirm = onConfirm
        self.onBack = onBack
        _markers = State(initialValue: initialMarkers)
    }

    /// Scrubber value for the selected marker, clamped between neighbors on write +
    /// seeks the preview to the exact frame.
    private var selectedTime: Binding<Double> {
        Binding(
            get: { markers.indices.contains(selected) ? markers[selected] : 0 },
            set: { proposed in
                guard markers.indices.contains(selected) else { return }
                let t = MarkerEditorLogic.clamp(proposed, index: selected, markers: markers, duration: duration)
                markers[selected] = t
                seek(to: t)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Markers")
                .font(.title2.weight(.semibold))
            Text("Drag each slide's marker to its settled frame. Add or remove markers as needed — this is the final slide set.")
                .foregroundStyle(.secondary)

            VideoPreview(player: player)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text("Slide \(selected + 1) of \(markers.count)")
                    .font(.callout.weight(.medium))
                Spacer()
                Text(String(format: "%.3fs", selectedTime.wrappedValue))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Slider(value: selectedTime, in: 0...max(duration, 0.001))

            HStack(spacing: 12) {
                Button {
                    addAtPlayhead()
                } label: { Label("Add", systemImage: "plus") }
                Button {
                    removeSelected()
                } label: { Label("Remove", systemImage: "minus") }
                    .disabled(markers.count <= 1)
                Spacer()
            }

            filmstrip

            HStack(spacing: 12) {
                Button("Back") { onBack() }
                Spacer()
                Button("Encode & Deploy") { onConfirm(markers) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!MarkerEditorLogic.isMonotonic(markers) || markers.isEmpty)
            }
        }
        .task { await generateThumbnails() }
        .onChange(of: selected) { _, _ in seek(to: selectedTime.wrappedValue) }
    }

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(markers.indices, id: \.self) { i in
                    thumbCell(i)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 64)
    }

    private func thumbCell(_ i: Int) -> some View {
        Group {
            if let img = thumbs[i] {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.secondary.opacity(0.15))
            }
        }
        .frame(width: 96, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(i == selected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .onTapGesture { selected = i }
    }

    // MARK: - Actions

    private func seek(to t: Double) {
        let cm = CMTime(seconds: t, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func addAtPlayhead() {
        let t = MarkerEditorLogic.clamp(selectedTime.wrappedValue, index: selected, markers: markers, duration: duration)
        let (m, idx) = MarkerEditorLogic.insert(t, into: markers)
        markers = m
        selected = idx
        Task { await regenerateThumb(idx) }
    }

    private func removeSelected() {
        let (m, sel) = MarkerEditorLogic.remove(at: selected, from: markers)
        markers = m
        selected = sel
        Task { await regenerateThumbsFrom(sel) }
    }

    // MARK: - Thumbnails

    private func generateThumbnails() async {
        for i in markers.indices { await regenerateThumb(i) }
    }

    private func regenerateThumbsFrom(_ start: Int) async {
        for i in markers.indices where i >= start { await regenerateThumb(i) }
    }

    private func regenerateThumb(_ i: Int) async {
        guard markers.indices.contains(i) else { return }
        let asset = AVURLAsset(url: videoURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.maximumSize = CGSize(width: 192, height: 108)
        let time = CMTime(seconds: markers[i], preferredTimescale: 600)
        do {
            let cg = try await gen.image(at: time).image
            let img = NSImage(cgImage: cg, size: NSSize(width: 96, height: 54))
            await MainActor.run { thumbs[i] = img }
        } catch {
            // Best-effort: a missing thumb just shows the placeholder rectangle.
        }
    }
}
```

- [ ] **Step 2: Build-verify**

Run: `cd swift-app && xcodegen generate && xcodebuild build -scheme KeynoteDeployer -destination "platform=macOS" -quiet`
Expected: BUILD SUCCEEDED. (If `AVAssetImageGenerator.image(at:)` async API is unavailable on the deployment target, fall back to `copyCGImage(at:actualTime:)` wrapped in `withCheckedThrowingContinuation` — STOP and report if the async variant errors.)

- [ ] **Step 3: Commit**

```bash
cd swift-app && git add Sources/Views/MarkerEditorView.swift
git commit -m "feat(markers): MarkerEditorView — filmstrip + live preview + scrubber"
```

---

### Task 5: Wire the analyzing + reviewMarkers phases into VideoDeployView

**Files:**
- Modify: `swift-app/Sources/Views/VideoDeployView.swift`
- Test: `swift-app/Tests/VideoDeployViewTests.swift` (adjust any test referencing the old `Phase` set or single-call deploy, if present)
- Modify: `swift-app/project.yml` (version 1.2.1 → 1.3.0)

**Interfaces:**
- Consumes: `VideoDeployer.analyze`, `VideoDeployer.deploy(...editedTimestamps:)` (Task 2), `MarkerEditorView` (Task 4).
- Produces: phase machine `drop → confirm → analyzing → reviewMarkers → deploying → complete (+ error)`.

- [ ] **Step 1: Add the new phases + state**

In `VideoDeployView`, extend the `Phase` enum and add state for the analysis + markers + the editor's duration:

```swift
    enum Phase { case drop, confirm, analyzing, reviewMarkers, deploying, complete, error }
```

Add near the other `@State` declarations:

```swift
    @State private var analysis: VideoAnalysis?
    @State private var markers: [Double] = []
    @State private var videoDuration: Double = 0
```

- [ ] **Step 2: Route the new phases in `body`**

In the `switch phase` block, add:

```swift
                case .analyzing: analyzingPhase
                case .reviewMarkers: reviewMarkersPhase
```

- [ ] **Step 3: Add the two phase views**

Add these computed views (e.g. after `deployingPhase`):

```swift
    // MARK: - Analyzing Phase

    private var analyzingPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Analyzing…")
                .font(.title2.weight(.semibold))
            Text("Matching stills to the video to seed the slide markers.")
                .foregroundStyle(.secondary)
            DeployProgressView(steps: steps)
            Button("Cancel") { deployTask?.cancel() }
                .controlSize(.small)
        }
    }

    // MARK: - Review Markers Phase

    @ViewBuilder
    private var reviewMarkersPhase: some View {
        if let player, let videoPath {
            MarkerEditorView(
                player: player,
                videoURL: URL(fileURLWithPath: videoPath),
                duration: videoDuration,
                initialMarkers: markers,
                onConfirm: { edited in startDeploy(editedTimestamps: edited) },
                onBack: { phase = .confirm })
        } else {
            ProgressView()
        }
    }
```

- [ ] **Step 4: Replace the confirm "Deploy" action with analyze, and split `startDeploy`**

Change the confirm-phase button label/action from `Button("Deploy") { startDeploy() }` to:

```swift
                Button("Review Markers") { startAnalyze() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canDeploy)
```

Replace the existing `startDeploy()` function with the analyze entry point plus a `startDeploy(editedTimestamps:)` that takes the edited markers. The token pre-check stays in `startAnalyze` so a missing token fails fast before analysis:

```swift
    private func startAnalyze() {
        guard let videoPath else { return }
        let settings = (try? FileOperations.loadSettings()) ?? .default
        guard !settings.vercelToken.isEmpty else {
            errorMessage = "Vercel token not configured. Go to Settings first."
            phase = .error
            return
        }

        phase = .analyzing
        steps = Self.freshSteps()
        errorMessage = ""

        let cleanTitle = ((videoPath as NSString).lastPathComponent as NSString).deletingPathExtension
        let request = VideoDeployRequest(
            videoPath: videoPath,
            stillPaths: stillPaths,
            fps: max(1, fps),
            projectName: projectName.trimmingCharacters(in: .whitespaces),
            title: cleanTitle,
            secureEmbed: secureEmbed)
        currentRequest = request

        deployTask = Task {
            do {
                let a = try await VideoDeployer.analyze(
                    request,
                    seams: .live(settings: settings),
                    onProgress: { step in Task { @MainActor in updateStep(step) } })
                // Editor needs the video's total duration for the scrubber max.
                let dur = (try? await AVURLAsset(url: URL(fileURLWithPath: videoPath)).load(.duration))
                let durSeconds = dur.map { CMTimeGetSeconds($0) } ?? (a.timestamps.last ?? 0)
                await MainActor.run {
                    analysis = a
                    markers = a.timestamps
                    videoDuration = durSeconds.isFinite && durSeconds > 0 ? durSeconds : (a.timestamps.last ?? 0)
                    phase = .reviewMarkers
                }
            } catch is CancellationError {
                await MainActor.run { phase = .confirm }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; phase = .error }
            }
        }
    }

    private func startDeploy(editedTimestamps: [Double]) {
        guard let request = currentRequest, let analysis else { return }
        let settings = (try? FileOperations.loadSettings()) ?? .default

        phase = .deploying
        errorMessage = ""

        deployTask = Task {
            do {
                let r = try await VideoDeployer.deploy(
                    request,
                    analysis: analysis,
                    editedTimestamps: editedTimestamps,
                    settings: settings,
                    seams: .live(settings: settings),
                    onProgress: { step in Task { @MainActor in updateStep(step) } })
                await MainActor.run { finish(r, settings: settings) }
            } catch is CancellationError {
                await MainActor.run { phase = .reviewMarkers }   // keep the edited markers
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; phase = .error }
            }
        }
    }
```

Add the stored request to state (near the other `@State`):

```swift
    @State private var currentRequest: VideoDeployRequest?
```

Add `import AVFoundation` at the top if not already present (the file imports `AVKit`, which re-exports AVFoundation, but add it explicitly for `AVURLAsset.load(.duration)`).

- [ ] **Step 5: Fix the error/retry path**

The error phase's "Retry" button calls `startDeploy()` (old signature). Point it back to `startAnalyze` so a retry re-runs the full flow:

```swift
                Button("Retry") { startAnalyze() }
                    .buttonStyle(.borderedProminent)
```

In `reset()`, also clear the new state:

```swift
        analysis = nil
        markers = []
        videoDuration = 0
        currentRequest = nil
```

- [ ] **Step 6: Adjust any affected view tests**

Run the view suite; if `VideoDeployViewTests` asserts the old `Phase` cases or called the removed single `deploy`, update it to the new flow (analyze → reviewMarkers → deploy). Most `VideoDeployLogic` pure tests are unaffected.

Run: `cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -only-testing:KeynoteDeployerTests/VideoDeployViewTests -quiet`
Expected: PASS.

- [ ] **Step 7: Bump version + full build/test**

In `swift-app/project.yml`, change `MARKETING_VERSION` from `1.2.1` to `1.3.0` (and bump `CURRENT_PROJECT_VERSION` if the repo increments it per release).

Run (delegate to apple-platform-build-tools:builder): `cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -quiet`
Expected: BUILD SUCCEEDED, all tests PASS.

- [ ] **Step 8: Commit**

```bash
cd swift-app && git add Sources/Views/VideoDeployView.swift Tests/VideoDeployViewTests.swift project.yml
git commit -m "feat(video): Review Markers phase (analyze → edit markers → deploy); v1.3.0"
```

---

### Task 6: Live gate on a real iPhone (mandatory — the open 1.2.1 problem)

**Files:** none (validation only).

This is NOT optional — green unit tests proved nothing about the rest-frame placement on a real device, which is the entire reason this feature exists.

- [ ] **Step 1: Run the real deck through the app**

Launch the freshly built app (from DerivedData, not the installed `/Applications` copy — the template is bundled, so a stale app ships the old viewer). Drop the real 39-slide deck + its stills. Proceed to Review Markers.

- [ ] **Step 2: Edit a few markers**

Find 2–3 slides whose auto-seeded marker sits on/near a transition (the known-bad ones from 1.2.1). Drag each to the settled hold frame using the live preview. Add/remove one marker to exercise those paths.

- [ ] **Step 3: Encode & deploy, then verify on iPhone in a cross-origin iframe**

Deploy. Open the result on a real iPhone INSIDE a cross-origin iframe (the `wrapper-iota-ten.vercel.app` rig — a top-level link does NOT reproduce the iOS bug class). Confirm:
- Every slide rests on a clean settled frame (no mid-transition pause), including the edited ones.
- Next/Prev/dots transitions are smooth (blob loader + wall-clock stop intact).
- First paint shows slide 1 (poster at `markers[0]`).

- [ ] **Step 4: Report**

Report the on-device result with specifics (which edited slides, before/after). If any rest frame is still wrong, STOP and report — do not claim success.

---

## Self-Review

**Spec coverage:**
- Split analyze/deploy → Task 2. ✓
- `slideCount = markers.count` → Task 2 (result) ✓.
- REST_BIAS → 0, poster at `markers[0]` → Task 3 + Task 2 ✓.
- Filmstrip + big preview + scrubber, drag/add/remove → Task 4 ✓.
- Monotonic clamp / can't-cross / guard N≥1 → Task 1 ✓.
- New phases (analyzing, reviewMarkers) → Task 5 ✓.
- No persistence → nothing built (correct, YAGNI) ✓.
- Encoder unchanged (markers flow in) → Task 2 passes `editedTimestamps` to `encodeWithKeyframes` ✓.
- Tests: MarkerEditorLogic, VideoDeployer split, generator parity, live gate → Tasks 1,2,3,6 ✓.
- Version bump → Task 5 ✓.

**Placeholder scan:** none — every code step has full code; the golden-regen step (Task 3 Step 4) gives the exact mechanical edit + verification grep.

**Type consistency:** `analyze(_:seams:onProgress:) -> VideoAnalysis` and `deploy(_:analysis:editedTimestamps:settings:seams:onProgress:) -> VideoDeployResult` used identically across Tasks 2 and 5. `MarkerEditorView.init(player:videoURL:duration:initialMarkers:onConfirm:onBack:)` matches Task 4 definition and Task 5 call site. `MarkerEditorLogic.clamp/insert/remove/isMonotonic` signatures consistent across Tasks 1, 4. `VideoDeployResult.slideCount` now sourced from `editedTimestamps.count`.

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-06-28-marker-timeline-editor.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
