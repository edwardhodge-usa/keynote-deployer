# Section 05 — Code Review (code-reviewer subagent)

No Critical. A1 security, arg parity (probe/sample/encode vs videoDeckPipeline.ts), byte→grid mapping, probe regex/fps-fallback, Swift-6 concurrency: all CORRECT-BY-DESIGN. JS-number CSV ("0,2.5,5") confirmed correct parity with the live path.

## Important
- **stderr drain ordering fragile.** stdout drained off-thread, stderr read AFTER on the calling thread. Safe under `-v error` (stderr ~empty) but a future flag / decoder-warning flood >64KB before stdout EOF → child blocks on stderr → stdout never closes → run() hangs. The documented "full stderr pipe deadlock" class. → drain stderr concurrently too.
- **jsNumber duplicated** (FFmpegVideoEncoder vs VideoViewerGenerator) — two copies of the determinism-critical formatter; if one is fixed and not the other, viewer timestamps and keyframe CSV silently diverge. → hoist ONE shared helper, both call it.

## Nits
- cancellation: after waitUntilExit, run() returns normally on cancel → encode throws writerFailed("status 15") / sampleGrids returns []. → `if Task.isCancelled { throw .cancelled }`.
- probe ignores exit status (silently yields 1920×1080/30 defaults on ffprobe failure) — acceptable probe-with-defaults design; add a comment.
- protocol doc says "High profile" but ffmpeg path omits -profile:v (Electron does too → parity holds). Pre-existing from section 04; no change.
