# Section 07 — Review Triage + Interview

No items required user decision. Resolved as auto-fix / let-go / deferred-to-Edward (runtime gate).

## AUTO-FIX (applied)
- **IMPORTANT-1**: Added `guard !Task.isCancelled else { return }` INSIDE the `await MainActor.run` hop in `startPipeline`, so a rapid re-selection that cancels the old task after its await resumed cannot clobber the newer run's state.
- **IMPORTANT-2**: Added a non-throwing `if Task.isCancelled { return out }` check at the top of `GifFrameSource.frames(at:)`'s loop — Cancel now aborts the thumbnail pass promptly without changing the method's (section-02) signature; runPipeline's subsequent `try Task.checkCancellation()` discards the partial result.

## LET GO (with rationale)
- **NIT-3**: accept() validates the .gif extension and shows the correct rejection message; matches DeployView's `.fileURL` drop pattern. Tightening to `.onDrop(of: [.gif])` risks a behavior change for marginal benefit.
- **NIT-9**: plan made the processing-phase Cancel optional ("if feasible"); the Vercel deploy is a short async op. Out of scope.
- **NIT-10**: self-heals (accept() re-reads secureEmbed from settings before the next confirm). Harmless.

## DEFERRED TO EDWARD (cannot run autonomously)
- **Runtime / Peekaboo visual gate + GATE-2 live Vercel deploy**: need a real `TEST_GIF` + an outward-facing Vercel deploy + an interactive eyeball. Per the repo's macOS visual-gate rule, the interactive gate is Edward's. Section is code-complete + offline-verified (58/58); the live run is the remaining sign-off before release.
