# Section-09 Review — Parity/Sunset + whole-subsystem hardening pass

Section 09 is docs + ship (no new feature code). The "review" for this section is a
**final whole-subsystem adversarial review** of the integrated video pipeline
(sections 01–08) before ship — the class of integration bug per-section reviews miss.
Reviewer: deep-implement code-reviewer over VideoEncoding / AVFoundationVideoEncoder /
FFmpegVideoEncoder / StillsMatch / GridSampler / VideoTimestampDeriver /
VideoViewerGenerator / VideoDeployer / VideoDeployView.

## Critical
- **C1 — fps divergence (SHIP-BLOCKER, fixed).** Two independent fps sources: the View's
  fps field (defaulted to a hardcoded 30) drove timestamp derivation, while
  `AVFoundationVideoEncoder` re-derived its own fps from `track.nominalFrameRate` for
  forced-keyframe placement + output timing. Unless they were equal, every keyframe
  landed on the wrong output frame → the paused "rest" frame shows a transition/wrong
  slide. Passed all offline stub tests (fakes return matching dims); only fails on a real
  deck whose export fps ≠ 30.
- **C2 — (already fixed in section-08)** framerEmbed sourced ratio from racy probe state.
  `VideoDeployResult.width/height` added; embed uses them.
- **C3 — `writer.finishWriting()` not cancellable.** Cancel during the final VideoToolbox
  flush is ignored (the per-frame loop IS cancellable). ACCEPTED: AVFoundation's
  finishWriting isn't cancellable by API; cancel still works between frames. Minor lag on
  a large real-deck finalize only.

## Important
- **I4 — `StillsMatchError` propagated raw to the user (fixed).** Added `LocalizedError`
  messages so "more stills than frames" / "can't align in order" read as guidance.
- **I1 — `https://<name>.vercel.app` fallback URL** (resolveProductionUrl nil). ACCEPTED:
  identical to the shipped HTML `DeployView` fallback (parity); only fires on API-lookup
  failure. Truncation risk noted; not a regression introduced here.
- **I2 — secureEmbed + empty allowed-domains deploys without CSP.** ACCEPTED: shared with
  the HTML path via `VercelDeployer`; default `embedAllowedDomains` is non-empty
  (`*.imaginelabstudios.com *.framer.app`), so it only bites if a user clears the field.
- **I3 — naturalSort on full paths vs basenames.** ACCEPTED: within a single stills folder
  all paths share the prefix, so numeric ordering is decided by the slide-N suffix —
  correct in practice. Low real risk; would only diverge if the parent dir embeds
  interacting digits.

## Fixes applied this section
1. C1: `VideoEncoder.encodeWithKeyframes` gained `fps:`; `AVFoundationVideoEncoder` uses
   the passed fps (nominalFrameRate only as last-resort fallback); `VideoDeployer` passes
   `analysis.fps`; `VideoDeployView.probeDimensions` defaults the fps field to the PROBED
   rate (matches Electron, which derives timestamps from the real fps).
2. I4: `StillsMatchError: LocalizedError`.
3. Regression test `encodeHonorsPassedFpsNotTrackRate` (source 30fps, encode at 15fps →
   keyframes follow 15fps) — would have caught C1.

## Verified clean by the reviewer
JSNumber/{{TS}}/-force_key_frames share one formatter; grid shapes agree across both
encoders + StillsMatch; sRGB pinned on stills+frames; frames.count==timestamps.count==
slideCount; temp-dir defer cleanup; ffmpeg drains both pipes concurrently + stall
watchdog; H.264/High/no-frame-reorder forced (never HEVC); cancel funneling + output
cleanup; View cancel→.confirm; history+clipboard fire once on MainActor.

Result: 65/65 tests green, Swift 6 strict-concurrency clean.
