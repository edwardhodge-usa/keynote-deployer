I have everything needed. Now I'll write the section content.

# Section 06 — VideoTimestampDeriver

## Objective

Create `VideoTimestampDeriver`, a pure-orchestration enum that derives per-slide timestamps for a video deck by DP-matching the user's per-slide still images to the video's frames. Its single `derive(...)` function:

1. natural-sorts the still URLs,
2. samples the video frames into 32×18 RGB grids and each still into one grid (via the injected `VideoEncoder`),
3. runs `StillsMatch.matchStillsToFrames` to get one matched frame index per slide,
4. converts those frame indices to 3-decimal-rounded timestamps and packages everything into a `VideoAnalysis`.

It must run off the main thread, honor task cancellation, and report progress via a handler (amendment **A5**) so the UI can show an "Analyzing video frames…" state instead of appearing hung.

**Why this exists (background):** slide boundaries cannot be recovered from video pixels alone — a build/fade step looks pixel-identical to a real slide on a constant background. So the user exports one still image per slide; the *count* of stills IS the slide count, and each still is matched to the video frame it appears on to derive that slide's timestamp. The stills are a **build-time input only** — never inserted into the video, never deployed. The deployed artifact is `deck.mp4` + `index.html`.

**File to create:** `swift-app/Sources/Services/VideoTimestampDeriver.swift`

## Dependencies (already implemented by prior sections — do NOT re-create)

These types exist and are available to you. Reference only.

- **Section 01 — `VideoAnalysis`** (`Sources/Models/VideoAnalysis.swift`), a `Sendable` struct:
  ```swift
  struct VideoAnalysis: Sendable {
      let frames: [Int]          // matched video-frame index per slide
      let timestamps: [Double]   // frame/fps, rounded 3dp
      let slideCount: Int        // == stillPaths.count
      let width: Int
      let height: Int
      let fps: Double
  }
  ```

- **Section 02 — `StillsMatch`** (`Sources/Services/StillsMatch.swift`), an `enum` with static methods:
  ```swift
  enum StillsMatch {
      static func meanAbs(_ a: [Double], _ b: [Double]) -> Double
      static func naturalSort(_ names: [String]) -> [String]      // numeric-aware (String.compare(.numeric))
      static func matchStillsToFrames(_ stills: [[Double]], _ frames: [[Double]]) -> [Int]  // length == stills.count, strictly monotonic
  }
  ```
  Edge cases handled inside `StillsMatch`: empty stills → `[]`; single still → globally-cheapest frame; N stills require M ≥ N frames.

- **Section 02 — `GridSampler`** (`Sources/Services/GridSampler.swift`): used indirectly through the encoder; you do not call it directly here.

- **Section 04 — `VideoEncoder` protocol** (`Sources/Services/VideoEncoding.swift`):
  ```swift
  protocol VideoEncoder: Sendable {
      func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double)
      /// Decode `url` to per-frame 32x18 RGB grids (downscaled), in order.
      /// Used for both the video (many frames) and a still (one frame -> [[Double]] of length 1).
      func sampleGrids(url: URL) async throws -> [[Double]]
      func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double]) async throws
  }
  ```
  In tests you inject a fake conforming to `VideoEncoder` (see Tests section). In production, Section 07 (`VideoDeployer`) injects the concrete `AVFoundationVideoEncoder`.

This section is parallelizable with Section 05 and depends only on Sections 02 and 04 being merged.

## Source behavior to mirror (from `claude-plan.md` §5.5)

```swift
enum VideoTimestampDeriver {
    /// Derive per-slide timestamps by DP-matching stills to video frames.
    static func derive(encoder: VideoEncoder, videoURL: URL, stillURLs: [URL], fps: Double)
        async throws -> VideoAnalysis
}
```

Behavior, in order:

1. **Natural-sort the stills.** Sort `stillURLs` by their path/filename using `StillsMatch.naturalSort` so e.g. `slide-010.jpeg` sorts after `slide-002.jpeg` (numeric-aware, not lexicographic). The matcher requires stills in true slide order. Sort the URLs by deriving a sortable key (the filename/path string) and reorder the URLs to match `naturalSort`'s ordering. Do not re-sort the frames.

2. **Probe dimensions.** Obtain `width`/`height` for the `VideoAnalysis`. Use `encoder.probe(url: videoURL)` to get `(width, height, _)`. (Use the caller-supplied `fps` for timestamp math, per §5.5 — `derive` is given `fps` explicitly; the probe is for width/height. Carry the supplied `fps` into the returned `VideoAnalysis.fps`.)

3. **Sample the video frames:** `let frameGrids = try await encoder.sampleGrids(url: videoURL)` — many 1728-value grids, one per frame, in frame order.

4. **Sample each still:** for each natural-sorted still URL, `encoder.sampleGrids(url: stillURL)` returns a single-element array; take its first (and only) grid. Build `stillGrids: [[Double]]` of length `stillURLs.count`.

5. **Match:** `let frames = StillsMatch.matchStillsToFrames(stillGrids, frameGrids)` — one matched frame index per slide; strictly monotonic by construction; `frames.count == stillGrids.count`.

6. **Compute timestamps** (exact rounding — load-bearing for byte-parity with the viewer and the encoder's forced keyframes):
   ```swift
   let timestamps = frames.map { round((Double($0) / fps) * 1000) / 1000 }
   ```
   This rounds to 3 decimal places (milliseconds). Use `round`, NOT truncation or string formatting. Each downstream consumer (the bundled viewer's `{{TS}}` JSON in Section 03, and `encodeWithKeyframes`'s `-force_key_frames` in Sections 04/05) re-derives from these same values, so the rounding must be identical.

7. **Return:**
   ```swift
   VideoAnalysis(
       frames: frames,
       timestamps: timestamps,
       slideCount: stillURLs.count,
       width: width,
       height: height,
       fps: fps
   )
   ```
   `slideCount == stillURLs.count` (the stills ARE the slide-count truth, not the matched frame count — though by construction they're equal).

## Cross-cutting requirements

- **Off-main / cancellable.** `derive` is `async` and must not block the main actor. Throughout the sample/match work, periodically call `try Task.checkCancellation()` (at minimum: before sampling the video, between sampling each still, and before the match) so a user who cancels mid-analysis stops promptly. The function `throws`, so cancellation propagates as `CancellationError`.

- **A5 — progress handler.** Add a progress callback parameter so `VideoDeployView` can show "Analyzing video frames…". Signature should be extended to:
  ```swift
  static func derive(encoder: VideoEncoder, videoURL: URL, stillURLs: [URL], fps: Double,
                     onProgress: @Sendable (Double) -> Void = { _ in })
      async throws -> VideoAnalysis
  ```
  - `onProgress` reports fractional progress in `0.0...1.0`.
  - Invoke it at least once during the sampling pass and once at completion (`≈1.0` / `100%`). A simple acceptable scheme: report after the video sample completes and after each still is sampled, scaling toward `1.0`; emit a final `onProgress(1.0)` before returning. The exact granularity is up to you, but the test below requires ≥1 callback and a final value ≈ 1.0.
  - Mark the closure `@Sendable` (Swift 6 strict concurrency) and give it a default no-op value so non-UI callers (and tests that don't care) can omit it.

- **Swift 6 strict-concurrency clean.** No data races; `VideoEncoder` is `Sendable`; the closure is `@Sendable`. Build must be warning-clean under the project's strict-concurrency setting.

## Tests

Add to the Swift Testing target created in Section 01. Framework: **Swift Testing** (`@Test` / `#expect`). These run fully offline — no network, no real encoder, no ffmpeg — by injecting a fake `VideoEncoder`. Write the assertions yourself; the stubs below define intent only.

**Test fixture / fake encoder.** Create an in-test type conforming to `VideoEncoder` that returns canned grids:
- `sampleGrids(url:)` returns the pre-built video frame grids for the video URL, and a single-element array (one grid) for a still URL. Distinguish video vs still by URL (e.g. a known video filename vs still filenames you pass in).
- `probe(url:)` returns fixed `(width, height, fps)`.
- `encodeWithKeyframes` can be a no-op / `fatalError("not used")` — `derive` never calls it.

Build a small but realistic fixture: a set of frame grids (M frames) and N still grids where each still grid is (near-)identical to a specific frame grid at a known, strictly-increasing index, so the expected matched frames are known. The plan's headline gate uses the **39-still** fixture, but a smaller hand-built fixture with known monotonic answers is acceptable for the unit test as long as it exercises the full path; if the Section 02 39-still grid fixture is available as shared test data, reuse it to assert `slideCount == 39`.

```swift
// Section 6 — VideoTimestampDeriver tests

@Test("derive returns slideCount, monotonic frames, and 3dp timestamps")
func derive_basic() async throws {
    // GIVEN a fake VideoEncoder returning known frame grids + one grid per still,
    //       arranged so the expected matched frame indices are strictly increasing.
    // WHEN  derive(encoder:videoURL:stillURLs:fps:) runs.
    // THEN  result.slideCount == stillURLs.count
    //       result.frames is strictly monotonic
    //       result.timestamps == result.frames.map { round((Double($0)/fps)*1000)/1000 }
    //       result.width/height/fps == the values supplied/probed.
}

@Test("A5: progress handler fires during sampling and finishes ~1.0")
func derive_reportsProgress() async throws {
    // GIVEN the fake encoder + a sink that records every onProgress value.
    // WHEN  derive runs with an onProgress closure.
    // THEN  the sink received >= 1 callback and the final value is ≈ 1.0 (within epsilon).
    //       (Use a thread-safe collector — e.g. an actor or a lock — since onProgress is @Sendable.)
}

@Test("stills are natural-sorted before matching")
func derive_naturalSortsStills() async throws {
    // GIVEN still URLs supplied OUT OF natural order (e.g. ...010, ...001, ...002)
    //       and a fake encoder whose per-still grid is keyed to the still's true slide number.
    // WHEN  derive runs.
    // THEN  result.frames is strictly increasing — proving the deriver sorted the stills
    //       (numeric-aware) before matching, not relying on input order.
}
```

Additional edge assertion (optional but recommended, cheap):
- Empty `stillURLs` → `derive` returns `slideCount == 0`, `frames == []`, `timestamps == []` (delegating to `StillsMatch.matchStillsToFrames([], …) == []`).

## Definition of done

- `swift-app/Sources/Services/VideoTimestampDeriver.swift` created with the `derive(...)` static func (including the `onProgress` parameter).
- The three `@Test` cases above pass.
- Full suite green and Swift 6 strict-concurrency clean via:
  ```
  cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -quiet
  ```
- No regression to existing HTML-path tests.

---

Section content written. The implementer's file target is `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/VideoTimestampDeriver.swift`, with tests in the Swift Testing target added by Section 01.

Key load-bearing details captured: the exact 3dp rounding `round((Double(frame)/fps)*1000)/1000` (shared with the viewer's `{{TS}}` JSON and the encoder's forced keyframes), natural-sorting stills before matching, `slideCount == stillURLs.count`, the A5 `@Sendable` progress handler with a default no-op, and off-main cancellable execution via `Task.checkCancellation()`. Dependencies on `VideoAnalysis` (Section 01), `StillsMatch`/`GridSampler` (Section 02), and the `VideoEncoder` protocol (Section 04) are referenced with their signatures so the section is implementable in isolation.
---

## Actual Implementation (2026-06-20)

Built as planned. 54/54 suite green (4 new in "Section 6 — VideoTimestampDeriver"), offline (fake VideoEncoder), Swift 6 clean, EXIT=0.

**File:** `Sources/Services/VideoTimestampDeriver.swift` — `enum` + one `static derive(encoder:videoURL:stillURLs:fps:onProgress:)`. 3dp rounding `round((Double(frame)/fps)*1000)/1000` (shared with viewer {{TS}} + encoder keyframes). A5 @Sendable progress (0.5 after video, →0.95 across stills, 1.0 final). Cancellable.

**Review fixes (no Critical):**
- **slideCount invariant:** a still that yields no grid now THROWS (`guard let first = grids.first`) instead of being silently dropped — guarantees slideCount == frames.count == timestamps.count (was: dropped grid → inconsistent VideoAnalysis, out-of-bounds for any timestamps[slide] consumer).
- **natural-sort:** sort URLs DIRECTLY via `.compare(options:.numeric)` (identical algorithm to StillsMatch.naturalSort) instead of a path→URL Dictionary round-trip that would collapse duplicate paths.
- **fps guard:** `guard fps > 0` (caller supplies fps; bad value → inf/nan timestamps → corrupt keyframe CSV / {{TS}}).

**⚠ Section 07 must:** (1) probe() before derive/encode (encoder contract), and (2) catch `StillsMatch.matchStillsToFrames` `tooFewFrames` (M<N stills>frames) and surface it as an actionable error — derive propagates it raw.
