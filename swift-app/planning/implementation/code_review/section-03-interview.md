# Section 03 — GridSampler — Review Triage & Decisions

No live user interview needed — internal tooling, no security/money/UX tradeoff. Decisions made by the implementing agent; recorded here as the checkpoint.

## Applied (auto-fix)

| # | Finding | Decision | Fix |
|---|---------|----------|-----|
| IMP-1 | Silent truncation | **FIX** — this is the section's load-bearing contract | Terminal `guard index == n else { throw GifDeployError.decodingFailed(...) }` after the loop in `frameDiffs`. |
| IMP-3 (code) | checkCancellation after decode | **FIX** | Restructured loop to `while true { try Task.checkCancellation(); guard let frame = try source.nextFrame() else { break }; ... }` — cancel check now precedes each decode. Entry check retained. |
| MIN | Loose solid-color test | **FIX** | Added `sampleTracksInputMagnitude` — gray=0 vs gray=255, assert 255-mean ≫ 0-mean. Kept uniformity test. |
| MIN | Channel order untested | **FIX** | Added `samplePreservesRGBChannelOrder` — pure-red image, assert R-channel mean ≫ G/B means (catches transposition / alpha-as-color). |
| NIT | Buffer size readability | **FIX** | `count: g * g * 4`. |
| NIT | `samplePoints` vestigial | **FIX** | `gridSize = Int(Double(samplePoints).squareRoot().rounded(.up))` (= ceil(sqrt(1000)) = 32). Now derived, not hardcoded. |

## Deliberately NOT changed (engineering call)

| # | Finding | Decision | Rationale |
|---|---------|----------|-----------|
| IMP-2 | No decode-failure propagation test | **DEFER** | `GifFrameSource` is a `final class` with no injection seam; a real test needs a corrupt-mid-stream GIF binary fixture. The terminal `index == n` guard (IMP-1) is now the enforcement. Adding a committed corrupt-GIF asset for one defensive branch is over-engineering for internal tooling. Logged for section-07 integration if a real corrupt deck surfaces. |
| IMP-3 (test) | Cancellation test exercises entry guard, not loop guard | **ACCEPT with honest comment** | A deterministic *mid-stream* cancellation test is racy without an injection seam (cancel() from the test thread races the decode loop). The entry-guard test DOES prove `CancellationError` propagates out of `frameDiffs`, which is the contract that matters to callers. Renamed/commented to state exactly what it verifies. Not chasing a flaky mid-stream variant. |
| MIN | `sample()` silent all-zeros on context-creation failure | **LET GO** | For fixed 32×32 / 8bpp / DeviceRGB / premultipliedLast params, `CGContext` init cannot realistically fail. Making `sample` throwing would ripple a `try` through `frameDiffs` for an unreachable branch. |
