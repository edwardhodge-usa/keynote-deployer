# Section 03 — GridSampler — Code Review

Reviewer: deep-implement code-reviewer subagent. Verdict: happy path + memory model solid; two marketed load-bearing guarantees (no-silent-truncation, between-frames cancellation) were unenforced/mis-tested.

## IMPORTANT
1. **frameDiffs can silently truncate.** `diffs` is pre-zeroed length `n`; the `while let frame = nextFrame()` loop never asserts it filled all `n` slots. If `nextFrame()`'s contract ever regresses to return nil early, a truncated deck bakes wrong boundaries invisibly. Fix: terminal `guard index == n else { throw .decodingFailed(...) }`.
2. **No decode-failure propagation test.** All synthetic GIFs decode cleanly; the `nextFrame()`-throws path is unverified at this layer. `GifFrameSource` is a `final class` with no injection seam → hard to test directly.
3. **Cancellation checked after the decode, and the test only exercises the ENTRY guard.** `checkCancellation()` ran after `nextFrame()` already decoded a frame; the test cancels before `frameDiffs` runs, so it proves the entry guard, not the loop guard.

## MINOR
- `sampleSolidColorIsUniform` over-loose (passes for any non-black uniform output; doesn't track input magnitude or channel order).
- RGB-vs-alpha byte order untested (solid gray hides channel transposition).
- `sample()` silently returns all-zeros if `CGContext` creation fails (effectively impossible for fixed 32×32/8bpp/DeviceRGB; low priority).

## NIT
- Buffer size `g * bytesPerRow` reads obliquely; `g*g*4` clearer.
- `samplePoints = 1000` vestigial — `gridSize` hardcoded 32, not derived.

## CONFIRMED CLEAN
Memory discipline correct (one CGImage + one vector live). CoreGraphics setup internally consistent, no UB, `withUnsafeMutableBytes` scope ends before read. `meanAbs` empty→0 correct+tested. Length 3072, diffs[0]==0, length==frameCount correct+tested. `<2` guard correctly documented defensive.
