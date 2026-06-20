# Section-07 Code Review — VideoDeployer

Reviewer: deep-implement code-reviewer subagent. 59/59 tests green, Swift 6 clean.

## Critical
(none — temp-dir cleanup correctly installed, token guard correctly ordered, concurrency sound.)

## Important
1. **Progress-step contamination.** The orchestrator's `onProgress` is forwarded straight into `seams.ensureProjectAndDeploy` → `VercelDeployer.deploy`, which emits its OWN `ProcessingStep(id: 13, ...)`. So during Step 4 the View receives interleaved id:13 steps outside the 1–4 model the spec mandates ("emitting 4 progress steps … Number the ids 1–4"). Unit tests miss it because the test seam never calls onProgress. Fix: remap/swallow in the live seam, OR have section-08 View filter.
2. **Redundant double-probe.** `VideoDeployer.swift:37` calls `probe` and discards the result; `VideoTimestampDeriver.derive` probes again internally (the only consumer of the dims). Probe runs twice per deploy — for the ffmpeg fallback that's a redundant `ffprobe` subprocess. Spec line 129 explicitly instructed the standalone probe, so implementer followed the plan, but derive's own probe rejects the same VFR/corrupt inputs before any sampling, making the standalone call redundant.

## Minor
3. Cleanup-on-throw test only covers an encode throw. Token-guard throw + deploy-seam throw (both fire AFTER the temp dir is fully built) are untested.
4. Deploy-seam throw leaves Step 4 stuck `.active` forever (token-guard path correctly sets `.error`; the seam path does not).
5. derive's per-tick id:1 rebuild could in principle be overwritten by a late tick (not possible here given await structure; cosmetic).
6. Temp-dir naming appends `-<uuid8>` vs the spec's literal `<unix-ts>` — an improvement (collision-safe) but an undocumented deviation.

## Nitpick
7. `makeStub(flag:)` — the `flag` parameter is never used.
8. The `.live` success-guard + `https://<name>.vercel.app` fallback have zero coverage (needs network — hard to test offline).

## Verified correct
Token guard before seam; defer cleanup; folderPath = source video path; slideCount = stillPaths.count; .live mirrors HTML DeployView (ensureProject → deploy → resolveProductionUrl + fallback); A6 UserDefaults selection; Sendable/@Sendable soundness.
