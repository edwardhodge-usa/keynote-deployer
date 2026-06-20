I have everything needed. The grid is 32×18×3 = 1728 Doubles (0..255), row-major RGB — and FFmpeg's `scale=32:18 -pix_fmt rgb24` raw bytes map directly to that (one byte per Double). Now I'll write the section content.

# Section 05 — FFmpegVideoEncoder (fallback)

## Objective

Implement `FFmpegVideoEncoder`, a fallback implementation of the `VideoEncoder` protocol that shells out to `ffmpeg`/`ffprobe` via an argument-array `Process` (never a shell). It must reproduce the **exact** argument flags used by the Electron `videoDeckPipeline.ts` so output is byte-equivalent to the already-live ffmpeg deploy path. This encoder is selected only via a hidden `useFfmpegEncoder` UserDefaults flag (wired in Section 07) — it is **not the default**, and ffmpeg is **not bundled** in the shipping app target.

This is the safety net for the AVFoundation encoder (Section 04): if Edward's quality gate rejects AVFoundation H.264 output, flipping the hidden flag swaps in this encoder without a rebuild.

## Dependencies (already implemented — do not duplicate)

- **Section 01** (`section-01-models-project`): provides the Swift Testing test target, the `Sources/Services/` location, and project scaffolding. Tests in this section register against that target.
- **Section 02** (`section-02-stillsmatch-gridsampler`): provides `GridSampler` and defines the canonical grid shape — **32×18 RGB = 1728 `Double` values, 0..255, row-major RGB**. `FFmpegVideoEncoder.sampleGrids` must produce grids of exactly this shape so cross-engine DP-match parity holds with the AVFoundation encoder.
- **Section 04** (`section-04-avfoundation-encoder`): defines the `VideoEncoder` protocol that this section implements. **You must conform to that exact protocol — do not redefine it here.** For reference, the protocol is:

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

(If, when this section is built, Section 04's protocol signatures have drifted from the above, conform to the real protocol on disk — that is the source of truth.)

## File to create

`swift-app/Sources/Services/FFmpegVideoEncoder.swift`

## Background — why exact arg parity matters

The Electron app's ffmpeg path is already live and quality-approved. To make this Swift fallback a true drop-in, its ffmpeg/ffprobe invocations must use the **identical** flags. The Electron source (`electron/videoDeckPipeline.ts`) builds these argument arrays:

**probe** (`probeVideo`):
```
['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height,r_frame_rate', '-of', 'default=noprint_wrappers=1', <input>]
```
Output is parsed by regex: `width=(\d+)` (default 1920), `height=(\d+)` (default 1080), `r_frame_rate=(\d+)/(\d+)` → `num/den` (default fps 30 if absent or den is 0/missing).

**sampleGrids** (`sampleGrids` helper, called once for the video and once per still):
```
['-v', 'error', '-i', <input>, '-vf', 'scale=32:18', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-']
```
Output is raw rgb24 bytes on stdout. Frame byte size = `32 * 18 * 3 = 1728`. Split the buffer into `floor(len / 1728)` frames; each frame is 1728 bytes mapped one-to-one to 1728 `Double` values (each byte 0..255, row-major RGB). A still decodes to exactly 1 frame — return its single grid as a one-element `[[Double]]` (matching Electron's `if (g[0]) stillGrids.push(g[0])`). Because `scale=32:18 -pix_fmt rgb24` produces values already in the canonical 1728-RGB shape, **no further GridSampler normalization is applied on this path** — the raw bytes ARE the grid (this matches Electron exactly; the sRGB-normalization in `GridSampler` belongs to the AVFoundation/CGImage path, not the ffmpeg raw path).

**encodeWithKeyframes** (`encodeWithKeyframes`):
```
['-y', '-i', <input>, '-c:v', 'libx264', '-crf', '18', '-preset', 'medium', '-pix_fmt', 'yuv420p', '-force_key_frames', <csv>, '-movflags', '+faststart', '-an', <output>]
```
where `<csv>` = the `timestamps` array joined by `,` (e.g. `"0.0,2.5,5.0"`). `crf` defaults to 18. Note the leading `-y` (overwrite output) and `-an` (drop audio).

Reproduce these arrays verbatim, in order, including the constant string `"scale=32:18"`, `"+faststart"`, `"default=noprint_wrappers=1"`, etc. The arg-parity test asserts these exactly.

## Implementation guidance

### Process invocation (A1 — security: argument array, never a shell)

**Never** construct `/bin/sh -c "<interpolated command>"`. Filenames are untrusted (a still or video path could contain `; rm -rf …` or quotes). Always:

```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: ffmpegBinaryPath)
process.arguments = [ /* exact flags + paths as discrete array elements */ ]
```

A path like `evil"; rm -rf ~`.mp4` must travel as a single inert `arguments` element — never spliced into a command string. The security test passes such a filename and asserts it appears as one untouched argument and that no `/bin/sh -c` is used.

### Binary discovery + missing-binary error

Reuse the `findVercelCli`-style pattern already in `swift-app/Sources/Services/VercelDeployer.swift` (lines 81–109): try `/usr/bin/which <name>` first, then fall back to a candidate list (`/opt/homebrew/bin/<name>`, `/usr/local/bin/<name>`). When running the actual ffmpeg/ffprobe `Process`, also set `env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"` on `process.environment` (mirrors VercelDeployer lines 34–39) — GUI apps launched from Finder have a minimal PATH.

If neither `which` nor any candidate resolves an existing file, throw a **clear, actionable** error, e.g.:

> "ffmpeg not found on PATH. Install via Homebrew: `brew install ffmpeg`"

The missing-binary test asserts this error fires (and is actionable) when the binary cannot be located.

### Pipe draining (avoid deadlock)

`sampleGrids` produces large rawvideo output (the video frames can be hundreds of MB). Drain stdout on a background thread **before** `waitUntilExit()`, exactly as VercelDeployer does (lines 48–60) — otherwise a full pipe buffer deadlocks the child. Read stdout as binary `Data` (not a UTF-8 string) for `sampleGrids`. For `probe`, stdout is small UTF-8 text.

### Encoder design

Make `FFmpegVideoEncoder` a `struct` conforming to `VideoEncoder` (so it is `Sendable`). Allow optional explicit `ffmpegPath`/`ffprobePath` (defaulting to discovery) so tests can inject a known path or a non-existent path to exercise the missing-binary branch. To make arg-parity testable without spawning a process, factor the argument-array construction into small **pure static helpers** that return `[String]` given the input/output/timestamps — e.g. `probeArgs(input:)`, `sampleArgs(input:)`, `encodeArgs(input:output:timestamps:crf:)`. The arg-parity and security tests call these helpers directly; the runtime methods call them then run the `Process`.

### Cancellation

Honor Swift task cancellation: check `Task.checkCancellation()` before/around long `Process` runs, and terminate the running process on cancellation. (This mirrors the cancellability requirement on the AVFoundation encoder; not asserted by a Section-05 test but required for parity behavior.)

## Tests (write FIRST)

Create the test file in the Section-01 test target (e.g. `swift-app/Tests/.../FFmpegVideoEncoderTests.swift`). Use **Swift Testing** (`@Test` / `#expect`). These tests are **offline** — they exercise the pure arg-builder helpers and the missing-binary path; they do NOT need ffmpeg installed or a real video asset.

1. **A1 security — no shell, paths inert.**
   - Build the invocation for an input filename containing a shell-injection payload (e.g. `"a\"; rm -rf ~ #.mp4"`).
   - `#expect` the executable resolves to an `ffmpeg`/`ffprobe` binary path (not `/bin/sh`), and that the injection-laden filename appears as exactly **one** element of the `arguments` array, byte-identical to the input (no escaping, no splitting, no interpolation into a single command string).

2. **Arg parity vs `videoDeckPipeline.ts`.** For each of probe / sampleGrids / encodeWithKeyframes, assert the produced `[String]` argument array equals the expected Electron array element-for-element:
   - **probe:** `["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height,r_frame_rate", "-of", "default=noprint_wrappers=1", <input>]`
   - **sampleGrids:** `["-v", "error", "-i", <input>, "-vf", "scale=32:18", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]`
   - **encodeWithKeyframes** (timestamps `[0.0, 2.5, 5.0]`, default crf 18): `["-y", "-i", <input>, "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p", "-force_key_frames", "0.0,2.5,5.0", "-movflags", "+faststart", "-an", <output>]`
     (Assert the `-force_key_frames` value is the timestamps joined by `,` with the same numeric formatting the encoder uses for the CSV.)

3. **Missing ffmpeg on PATH → clear actionable error.** Construct the encoder pointed at a guaranteed-nonexistent binary path (and/or with discovery stubbed to fail), call a runtime method, and `#expect(throws:)` an error whose message names the missing binary and tells the user how to install it (Homebrew).

(Optional, manual/integration — NOT part of the CI gate, requires `brew install ffmpeg` per the README dev note: run `sampleGrids` on a tiny real video and assert each returned grid has `count == 1728`, and run `encodeWithKeyframes` and probe the output for I-frames at the forced timestamps + `+faststart`. Keep this out of the automated suite.)

## Selection / wiring note (handled in Section 07 — do not implement the seam here)

The active encoder is chosen by `VideoDeployerSeams` reading the hidden `useFfmpegEncoder` UserDefaults flag (`defaults write <bundleid> useFfmpegEncoder -bool YES`). When set, the seam injects `FFmpegVideoEncoder`; default injects `AVFoundationVideoEncoder`. This section only needs to make `FFmpegVideoEncoder` instantiable and protocol-conformant — Section 07 owns the flag read and injection (and its A6 test).

## Out of scope

- Do NOT bundle ffmpeg/ffprobe in the app target.
- Do NOT make this the default encoder.
- Do NOT add a user-facing setting for it (hidden UserDefaults flag only).
- Do NOT redefine the `VideoEncoder` protocol (owned by Section 04).
- Do NOT implement the seam/flag read (owned by Section 07).
- Do NOT touch the AVFoundation encoder or any deploy/Vercel code.

## Definition of done

- `swift-app/Sources/Services/FFmpegVideoEncoder.swift` conforms to the Section-04 `VideoEncoder` protocol.
- Arg-builder helpers produce arrays byte-identical to `videoDeckPipeline.ts`.
- All three Section-05 tests pass: `cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -quiet`.
- No shell invocation anywhere; all `Process` calls use `executableURL` + `arguments`.

---

Key files referenced (all absolute):
- Create: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/FFmpegVideoEncoder.swift`
- Electron arg source of truth: `/Users/EdwardHodge_1/Code/keynote-deployer/electron/videoDeckPipeline.ts` (lines 20–109)
- Binary-discovery + Process/PATH/pipe-drain pattern to reuse: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sources/Services/VercelDeployer.swift` (lines 34–39, 48–60, 81–109)