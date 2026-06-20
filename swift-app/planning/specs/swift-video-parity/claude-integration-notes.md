# Integration Notes — Gemini iteration-1

Grade: B+/A−, "no significant architectural problems." Decisions below; amendments folded into `claude-plan.md` (§5 component edits + new §10 "Review amendments — amendment wins on conflict").

## Integrating
- **[HIGH][security] ffmpeg via argument-array `Process` (no shell string).** Confirms/locks the intended approach: `process.executableURL` + `process.arguments=[...]`, NEVER `/bin/sh -c "<interpolated>"`. Prevents command injection from malicious filenames. → §5.4 FFmpegVideoEncoder hardened.
- **[HIGH][correctness] VFR detection.** Keynote movie exports are CFR, but a user could drop a VFR file → `frame/fps` timestamps drift. `probe` checks for VFR (sample a handful of `CMSampleBufferGetPresentationTimeStamp` deltas); if non-constant, **reject** with guidance to re-export CFR (Option A — simplest, fits the deadline + parity goal). → §5.4.
- **[HIGH][correctness] sRGB color-space normalization in GridSampler.** Stills (often Display P3) vs video frames (sRGB) compared in raw RGB corrupts the DP match. Draw every source `CGImage` into an explicit sRGB `CGContext` before sampling — applies to BOTH stills and frames so they share one space. (Note: this does NOT make the Swift sampler byte-identical to Electron's ffmpeg sampler — and it need not; DP-match parity is tested on a SHARED precomputed grid fixture, not on live sampling.) → §5.2.
- **[MED][robustness] `defer` temp cleanup.** `defer { try? FileManager.default.removeItem(atPath: tempDir) }` right after mkdir, so a throw/cancel can't leave GB of video in /tmp. → §5.7.
- **[MED][UX] "Analyzing video frames…" progress.** `VideoTimestampDeriver.derive` takes a progress handler (report every N frames sampled); the confirm screen shows an analyzing state so the long sample pass doesn't look hung. → §5.5, §5.8.
- **[MED][clarity] ffmpeg-fallback trigger = hidden `UserDefaults` flag** (e.g. `defaults write … useFfmpegEncoder -bool YES`), read by `VideoDeployerSeams` to inject the encoder — NOT a compile-time flag (brittle; would need a full release to switch) and NOT a user-facing setting (clutter). → §3, §5.4, §5.7.
- **[MED][process] Quality-gate checklist** (objective, transferable): no transition blockiness/artifacts on the ILS deck; text crisp/readable; colors match source; paused keyframes clean (no shimmer from prior frame). → §7.
- **[LOW][robustness] Input validation:** corrupt video / no video track → `probe` throws a descriptive error; stills folder filters `UTType.image` (ignore non-images); large still/video aspect-ratio mismatch → warn (grid 32×18 mitigates but flag). → §5.4, §5.8.
- **[LOW][devex] README ffmpeg dev note** — to work the fallback, install ffmpeg on PATH (Homebrew). → §8 docs.
- **[LOW][code] naturalSort via `String.compare(options: .numeric)`** instead of a hand-port; locale-aware, robust. Parity note: must order the zero-padded/numeric still names (`…001.jpeg`…`…039.jpeg`) identically to the TS `naturalSort` — verify in the parity test. → §5.3.

## Not integrating (or deferring)
- **VFR Option B (full CMTime-grid retiming)** — NOT integrating now. Over-scoped for the weekend; reject-VFR (Option A) is sufficient given Keynote exports CFR. Revisit only if a real VFR source appears.
- Nothing else rejected — all suggestions were sound and cheap; the plan was already protocol/seam/parity-structured so they slot in without redesign.
