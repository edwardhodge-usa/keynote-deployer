# External Review Integration Notes

Reviewer: Gemini 2.5 Pro (`reviews/iteration-1-gemini.md`). I am the authority on what to integrate. Summary: 8 of 9 findings integrated; 1 suggested *fix* rejected with cause (its finding accepted in spirit).

## INTEGRATED

1. **Concurrency model (Critical) — INTEGRATED.** The plan didn't state where the heavy pipeline runs. Added an explicit rule: the whole `GifFrameSource → GridSampler → SlideDetector` pipeline + thumbnail build runs **off the main thread** in an `async` function; UI updates hop back to `@MainActor`. `GifDeployView` launches it as a `Task` on GIF selection. (Plan §3, Task 8.)

2. **Unbounded CGImage caching → streaming (Critical) — INTEGRATED.** My "cache all frames" wording is a memory bomb (200×1080p frames ≈ 1.5 GB). Replaced with a **forward-streaming** model: `GridSampler.frameDiffs` pulls frame i, samples it, keeps only the previous *sample vector* (not the image), discards the image. Thumbnails for `restFrame`s are decoded in a **separate targeted pass after detection** (only the N rest frames), accepting ImageIO's forward re-walk cost. `GifFrameSource` exposes streaming `next()`-style access, not full-array caching. (Plan §2, §3, Tasks 2/3/8.)

3. **Cancellation — INTEGRATED.** Long GIFs = multi-minute jobs with no escape. The processing `Task` is cancellable; `GifDeployView` holds the handle; Cancel button in `loading`/`processing`; pipeline calls `try Task.checkCancellation()` between frames. (Task 8.)

4. **Granular error enum — INTEGRATED.** Added a `GifDeployError` enum (`invalidGifFile`, `tooFewFrames`, `decodingFailed`, `fileNotFound`, `vercelDeployFailed`) with user-facing messages in the `error` phase. (Task 8.)

5. **Seed-quality UX message — INTEGRATED.** `confirm` phase shows a non-intrusive note that Auto is best-effort and accurate Stills matching is coming. Preempts confusion/support. (Task 8.)

6. **Secure temp directory — INTEGRATED (with parity note).** Switch from a hand-built `/tmp/...-<timestamp>` path to `FileManager.url(for: .itemReplacementDirectory, …)`. The temp dir is NOT part of the deployed output, so this does not affect the byte-identical gate. (Task 7.)

7. **HTML-injection developer note — INTEGRATED.** Added a warning comment requirement in `GifViewerGenerator.swift`: never inject raw unescaped user strings; current inputs are JSON/filename/bool only. Future-proofing. (Task 6.)

9. **Zero/single-frame GIF edge cases — INTEGRATED.** `GifFrameSource` throws `tooFewFrames` if `frameCount < 2`; `GridSampler.frameDiffs` and `SlideDetector.detectSlides` return empty `[DetectedSlide]` gracefully on empty/single input. Added to the unit-test list. (Tasks 2/3/4, §6.)

## REJECTED FIX (finding accepted, remedy rejected)

8. **JSON serialization — finding VALID, suggested fix (`JSONEncoder.sortedKeys`) REJECTED.**
   - *Finding (accepted):* manual string concatenation is brittle if a field ever contains special characters needing escaping.
   - *Suggested fix (rejected):* "use `JSONEncoder` with `.sortedKeys` and update the fixture to match Swift's output."
   - *Why rejected:* the locked Phase-1 gate (decision #2 / Task 6) is **byte-identical to the CURRENT Electron viewer output**, which bakes slides via `JSON.stringify(slides)` — **compact, insertion-order keys** (`restFrame, holdStart, holdEnd, transitionFrames`). `.sortedKeys` would emit `holdEnd, holdStart, restFrame, transitionFrames` — alphabetical — which is **NOT** what Electron produces. Adopting it and "matching the fixture to Swift's output" would silently break parity with the shipping Electron viewer and defeat the deferred-Electron-refactor goal (both platforms must emit the same bytes). This is the classic "reviewer's fix can be wrong even when the finding is right" trap.
   - *Chosen resolution:* `DetectedSlide` contains **zero string fields** (all Int / nested Int / null), so the escaping risk the finding worries about **cannot occur today**. Build the baked-slides string deterministically to match `JSON.stringify` exactly (compact, insertion order, `null` for absent transition). Add an explicit code note: *if a string field is ever added to `DetectedSlide`, this must move to a parity-preserving encoder that escapes strings while keeping `JSON.stringify` key order — NOT `.sortedKeys`.* The Task-6 fixture remains the real Electron output, not Swift's. (Plan §4, Task 6.)
