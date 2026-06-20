GridSampler is from section 02 (a dependency). I have everything needed. Now I'll write the section content.

# Section 04 — VideoEncoder Protocol + AVFoundationVideoEncoder

## Objective

Define the `VideoEncoder` protocol and implement `AVFoundationVideoEncoder`, the default (shipping) encoder for the Swift video-deploy path. This encoder uses only Apple frameworks (no bundled binary) and provides three operations:

1. **`probe`** — read dimensions + constant frame rate from a video container; reject VFR and corrupt/no-track inputs.
2. **`sampleGrids`** — decode a video (many frames) or a still image (one frame) into ordered 32×18 RGB grids via `GridSampler`.
3. **`encodeWithKeyframes`** — re-encode the source video to web-safe H.264 with a forced keyframe at each slide timestamp (`AVAssetReader` → `AVAssetWriter`).

**Why AVFoundation-native:** This eliminates the bundled-binary problem entirely — no nested-binary codesigning, notarization, or hardened-runtime surface; smaller app; cleaner sunset. Apple supports the one hard requirement — a forced keyframe at each arbitrary slide timestamp — via `kCMSampleBufferAttachmentKey_ForceKeyFrame` on individual sample buffers during an `AVAssetReader → AVAssetWriter` re-encode. The known risk is that VideoToolbox's H.264 encoder is less quality-efficient than `libx264 -crf 18`; mitigate with a high bitrate / High profile, then gate on human review (the ffmpeg fallback in Section 05 is the escape hatch).

## Files to Create / Modify

- **Create** `swift-app/Sources/Services/VideoEncoding.swift` — the `VideoEncoder` protocol + shared error/helper types.
- **Create** `swift-app/Sources/Services/AVFoundationVideoEncoder.swift` — the default implementation.
- **Add tests** to the Swift Testing target created in Section 01 (e.g. `swift-app/Tests/AVFoundationVideoEncoderTests.swift`).

The test target wiring (`xcodegen` test target + `Tests/` group) already exists from **Section 01**. New `.swift` files under `Sources/Services/` are picked up automatically by the existing source-glob in `project.yml` — no `project.yml` change is needed unless you add a fixture resource (see "Test fixtures" below).

## Dependencies (reference only — do not duplicate)

- **Section 01 (models + project.yml):** provides the Swift Testing test target and the `xcodegen` test wiring. Do not re-add the target.
- **Section 02 (StillsMatch + GridSampler):** provides `GridSampler.sample(_ cgImage: CGImage) -> [Double]`, returning exactly 32×18×3 = 1728 `Double` values, sRGB-normalized (per amendment A3, `GridSampler` draws each `CGImage` into an explicit sRGB `CGContext` before sampling). `sampleGrids` in this section MUST reuse `GridSampler.sample` so video frames and stills land on the SAME grid. Do not re-implement grid sampling here.

This section **blocks** Section 05 (ffmpeg fallback shares the protocol), Section 06 (`VideoTimestampDeriver` calls `sampleGrids`), and Section 07 (`VideoDeployer` calls `probe` + `encodeWithKeyframes`).

## Background: the protocol contract

```swift
protocol VideoEncoder: Sendable {
    /// Probe container/stream for dimensions + constant frame rate.
    func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double)

    /// Decode `url` to per-frame 32x18 RGB grids (downscaled), in order.
    /// Used for both the video (many frames) and a still (one frame).
    func sampleGrids(url: URL) async throws -> [[Double]]

    /// Re-encode `input` to web-safe H.264 with a forced keyframe at each timestamp.
    /// Output: yuv420p, High profile, no audio, moov-atom-at-front (faststart).
    func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double]) async throws
}
```

Both this section's `AVFoundationVideoEncoder` and Section 05's `FFmpegVideoEncoder` conform to this single protocol. Place the protocol in `VideoEncoding.swift` along with a descriptive error type, e.g.:

```swift
enum VideoEncoderError: Error, LocalizedError, Sendable {
    case noVideoTrack            // A8: file has no video track
    case corruptFile(String)     // A8: unreadable / undecodable
    case variableFrameRate       // A2: VFR rejected, tell user to re-export CFR
    case readerFailed(String)
    case writerFailed(String)
    case cancelled
    // errorDescription: user-facing, actionable strings (esp. .variableFrameRate
    //   → "re-export at a constant frame rate", and .noVideoTrack)
}
```

## Implementation details

### `probe(url:)` — dimensions + CFR detection (A2, A8)

- Load via `AVURLAsset`. Get the first video track (`loadTracks(withMediaType: .video)` / `tracks(withMediaType:)`).
- **A8 — no video track / corrupt:** if there is no video track, throw `.noVideoTrack`. If the asset is unreadable / cannot be loaded (corrupt file), throw `.corruptFile(...)` with a clear message. Do not crash; do not return defaults for these cases.
- **Dimensions + fps (happy path):** width/height from `naturalSize` (apply `preferredTransform` if needed so portrait/landscape is correct); fps from `nominalFrameRate`. Fall back to 30 fps / 1920×1080 only when the values are genuinely unavailable on an otherwise-valid track (NOT for the error cases above).
- **A2 — reject VFR:** detect variable frame rate by reading several consecutive frames' presentation timestamps via an `AVAssetReader` + `AVAssetReaderTrackOutput`, collecting `CMSampleBufferGetPresentationTimeStamp` deltas. If the deltas are not (near-)constant within a small tolerance, throw `.variableFrameRate` with a message telling the user to re-export at a constant frame rate. Rationale: `frame/fps` timestamping (used downstream in Section 06) assumes CFR; Keynote exports CFR, but a dropped non-Keynote file could be VFR and would mis-match every slide. (Option A — reject; a full CMTime-grid retime is out of scope.)
  - Sample a bounded number of consecutive frames (e.g. the first ~10–20) rather than the whole file — enough to distinguish CFR from VFR without a full decode.

### `sampleGrids(url:)` — frames/stills → grids (reuses GridSampler)

- **Detect kind:** decide video vs still. A still (single image) has no video track / is an image type → decode via `CGImageSource` (`CGImageSourceCreateImageAtIndex`) to one `CGImage`, then one `GridSampler.sample` → return `[[Double]]` with exactly one element. Otherwise treat as video.
- **Video:** read every frame in order at the video's native frame cadence. Use either:
  - `AVAssetImageGenerator` with `requestedTimeToleranceBefore/After = .zero` and a downscaled `maximumSize`, generating an image per frame time; OR
  - `AVAssetReader` + `AVAssetReaderTrackOutput` (decompressed to a known pixel format), converting each `CVPixelBuffer`/`CMSampleBuffer` to a `CGImage` and downscaling through a `CGContext`.
  - Either way, produce one grid per frame, in presentation order, via `GridSampler.sample`.
- **CRITICAL — same grid for stills and frames:** the returned grids must be directly comparable to still grids produced by the same `GridSampler.sample` (Section 02 already handles sRGB normalization per A3). Do NOT apply any normalization here that `GridSampler` does not also apply to stills.
- This is the operation called by `VideoTimestampDeriver` (Section 06): `sampleGrids(video)` (many) and `sampleGrids(still)` (one each).

### `encodeWithKeyframes(input:output:timestamps:)` — forced-keyframe H.264

The core re-encode: `AVAssetReader` reads source samples → `AVAssetWriter` writes H.264 with a forced keyframe at each slide timestamp.

- **Reader:** `AVAssetReader` on the source video track, `AVAssetReaderTrackOutput` configured to yield decompressed frames (a pixel-buffer format the writer input accepts, e.g. `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` or BGRA — choose one the `AVAssetWriterInput` pixel-buffer adaptor / encoder accepts).
- **Writer + input — REQUIRED output settings** (these are asserted by tests):
  - `AVVideoCodecKey = AVVideoCodecType.h264`
  - `AVVideoProfileLevelKey = AVVideoProfileLevelH264HighAutoLevel` (High profile)
  - In `AVVideoCompressionPropertiesKey`:
    - `AVVideoAllowFrameReorderingKey = false`
    - a high `AVVideoAverageBitRateKey` (or, alternatively, `kVTCompressionPropertyKey_Quality ≈ 0.95` mapped via the compression-properties dict) — bias strongly toward quality, since VideoToolbox H.264 is less efficient than `libx264 -crf 18`.
  - 4:2:0 8-bit output (yuv420p) — ensure the encoder emits `yuv420p` (the default for `.h264` with the above; verify in the integration test via `moov`/track inspection).
  - `writer.shouldOptimizeForNetworkUse = true` (faststart — `moov` atom before `mdat`).
- **Forced keyframes:** as each source sample is read, compute whether its presentation time is at/just past an unconsumed slide timestamp; if so, attach `kCMSampleBufferAttachmentKey_ForceKeyFrame = true` (as a `CMSetAttachment` boolean) to that `CMSampleBuffer` before/at append, and advance to the next timestamp. Match each forced timestamp to the **nearest output frame** using the SAME rounding semantics as ffmpeg `-force_key_frames` (so AVFoundation and ffmpeg outputs place keyframes on the same frames). Extract this mapping into a **pure helper** (see below) so it is unit-testable without encoding.
- **Append loop:** drive `AVAssetWriterInput.requestMediaDataWhenReady` (or a manual `while input.isReadyForMoreMediaData` pull loop), reading from the reader output and appending. Do NOT mutate or reuse a `CMSampleBuffer` after `append`.
- **Cancellation:** honor `Task.cancellation` (check `Task.isCancelled` / `try Task.checkCancellation()` in the append loop); on cancel, call `reader.cancelReading()` + `writer.cancelWriting()`, remove the partial output file, and throw `.cancelled`.
- **Finalize:** mark input finished, `await writer.finishWriting()`, verify `writer.status == .completed` (else throw `.writerFailed`).

### Pure helper: forced-keyframe → output-frame-index mapping (unit-testable)

Extract the timestamp→frame-index decision into a free function or `static` method with no I/O, so a test can assert mapping without encoding. Suggested shape:

```swift
/// Maps each slide timestamp (seconds) to the nearest output frame index at `fps`.
/// Same rounding as ffmpeg `-force_key_frames` so AV + ffmpeg agree on keyframe placement.
func forcedKeyframeFrameIndices(timestamps: [Double], fps: Double) -> [Int]
```

(Test: "forced-keyframe selection maps each timestamp to the nearest output-frame index.")

## Tests (write FIRST)

Add to the Swift Testing target (`@Test`/`#expect`). Tests are prose/signatures only — write the assertions during implementation. Pure/settings tests run in CI offline; integration tests need a small real video asset (see "Test fixtures").

**Pure / settings (offline, CI):**
- `probe` on a known small CFR fixture returns its true width / height / fps.
- **(A2)** `probe` on a synthesized VFR fixture throws the VFR-reject error (`.variableFrameRate`).
- **(A8)** `probe` on an audio-only / no-video-track file throws a descriptive error (`.noVideoTrack`); `probe` on a corrupt file throws (`.corruptFile`).
- The `AVAssetWriter` output-settings dict equals: H.264 codec, High profile, `AVVideoAllowFrameReorderingKey = false`, 4:2:0 8-bit, high bitrate/quality; and the writer's `shouldOptimizeForNetworkUse == true`. (Assert by constructing the encoder's settings dict via the same code path the encoder uses — factor settings into a `static` function so the test reads the exact dict without running an encode.)
- Forced-keyframe selection (`forcedKeyframeFrameIndices`) maps each timestamp to the nearest output-frame index (pure helper, no encoding).

**Integration (small real asset):**
- `encodeWithKeyframes` produces a file whose frames at each requested timestamp are I-frames (probe keyframe positions), the stream is `yuv420p`, and the file is faststart (`moov` before `mdat`).
- Cancellation mid-encode stops and cleans up (no partial output file left; throws `.cancelled`).

**`sampleGrids` (can run offline against fixtures):**
- `sampleGrids` on a still image returns exactly one grid of 1728 values, all in 0…255 (delegates to `GridSampler`).
- `sampleGrids` on the small video fixture returns one grid per frame, in order, each 1728 values.

### Test fixtures

- A **small CFR video** (a few frames, e.g. ≤1s, known fps/dimensions) for `probe` + integration + `sampleGrids`.
- A **VFR fixture** — synthesize one (e.g. assemble samples with uneven PTS via `AVAssetWriter`, or include a tiny prebuilt asset) to exercise the A2 reject path.
- An **audio-only / no-video-track** file and a **corrupt** file (e.g. a truncated/garbage `.mp4`) for the A8 paths.
- A **still image** (any `UTType.image`) for `sampleGrids`-on-still and for reuse by Section 06's fixtures.

Bundle fixtures with the test target (add a resources entry for the test target in `project.yml` if not already present from Section 01, or generate the VFR/corrupt fixtures programmatically in the test to avoid binary assets). Prefer generating synthetic fixtures in-test where practical (keeps the repo lean and the test self-contained).

## Concurrency & cleanliness notes

- `AVFoundationVideoEncoder` is a `struct`/`final class` conforming to `Sendable` (the protocol requires `Sendable`). Keep it stateless; pass everything via parameters.
- All three methods are `async throws`. The encode loop is the only long-running one — keep it off the main actor (it will be called off-main by Section 06/07).
- Swift 6 strict-concurrency clean: be careful with `CMSampleBuffer` / `CVPixelBuffer` (not `Sendable`) — confine them to the encode/sample task; do not capture them across actor hops.
- Do not regress existing HTML-path tests. Full suite must stay green via `cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -quiet` (exit 0).

## Out of scope for this section

- The ffmpeg fallback implementation (`FFmpegVideoEncoder`) — Section 05 (shares this protocol).
- Encoder selection / the `useFfmpegEncoder` UserDefaults flag — Section 07 (`VideoDeployerSeams`).
- `VideoTimestampDeriver` (calls `sampleGrids`) — Section 06.
- `GridSampler` itself — Section 02 (reuse only).

---

Relevant file paths (all absolute):
- Section spec written to `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/planning/specs/swift-video-parity/sections/section-04-avfoundation-encoder.md`
- Files to create: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/VideoEncoding.swift` and `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/AVFoundationVideoEncoder.swift`
- Tests under `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Tests/`

Note: `GridSampler.swift` (the section-02 dependency) does not yet exist on disk — confirmed via glob, no `**/GridSampler.swift` found. This section depends on it being created in Section 02 first; the encoder's `sampleGrids` must call `GridSampler.sample` rather than re-implement grid logic.
---

## Actual Implementation (2026-06-20)

Built as planned. 40/40 suite green (10 new in "Section 4 — AVFoundationVideoEncoder"), Swift 6 clean, EXIT=0.

**Files:** `Sources/Services/VideoEncoding.swift` (protocol + `VideoEncoderError` (Equatable) + pure `forcedKeyframeFrameIndices`), `Sources/Services/AVFoundationVideoEncoder.swift`, `Tests/AVFoundationVideoEncoderTests.swift` (fixtures synthesized in-test: solid CFR/VFR video via AVAssetWriter, gray/color PNG via ImageIO, audio-only .caf via AVAudioFile, garbage mp4).

**Hard-won implementation facts (cost several debug cycles, captured for sections 05–07):**
- **Forced keyframes REQUIRE rebuilding each frame with explicit timing.** Appending the reader's decompressed `CMSampleBuffer`s verbatim to the writer let VideoToolbox re-time the stream (observed **12 frames in → 16 out**) which broke the 1:1 frame↔index mapping, so `ForceKeyFrame` landed off-by-one and frame count drifted. Fix: `CMSampleBufferCreateForImageBuffer` per frame with `PTS = i/fps`, `duration = 1/fps` (integer timescale). Now decoded output count == source and forced keyframes land exactly. `kCMSampleBufferAttachmentKey_ForceKeyFrame` IS honored — with correct timing.
- **Keyframe DETECTION must be by PTS, not buffer index.** Reading the output compressed (`outputSettings: nil`) returns buffers that do NOT map 1:1 to frames (saw 16 buffers for a 12-frame file); locate keyframes via `round(pts * fps)` + `kCMSampleAttachmentKey_NotSync`.
- **`.noVideoTrack` vs `.corruptFile`:** a PNG/garbage file can't be *opened* as an AVAsset (`loadTracks` throws, err -12848) → `.corruptFile`; only a real container with zero video tracks (audio-only .caf) reaches `.noVideoTrack`.
- **`-only-testing` does NOT filter Swift Testing** structs by name via xcodebuild — run the whole suite.

**Review fixes applied (no Critical):** VFR detect compares deltas to expected `1/fps`, rejects on ≥2 deviations >25% (was mean-relative 10%); writer sized to **raw** naturalSize (not transform-oriented) to match the un-rotated frames it appends (probe keeps oriented dims for the viewer aspect ratio); ForceKeyFrame mode → `ShouldNotPropagate`; readiness poll bounded by a 30s stall watchdog → `.writerFailed`; `sampleGrids` CIContext pinned to sRGB (A3) + throws on a nil frame instead of silently dropping (would shift Section-06 DP alignment); `frameAndStillGridsMatchForSolidColor` test added.

**Contract for Section 07:** `encodeWithKeyframes` assumes a probed, CFR, integer-fps source (integer-timescale rebuild + `round(t*fps)`); it does NOT re-run the VFR check — Section 07 must `probe()` before `encodeWithKeyframes()`.
