# Section 05 — Review Triage & Decisions

No user-tradeoff decisions. Auto-fixing the two Important + the cancellation nit; probe gets a comment; doc-"High profile" left (parity-correct).

## Auto-fixes applied
- **stderr concurrent drain:** run() now drains stdout AND stderr each on their own background continuation, awaited together before waitUntilExit — the deadlock guard no longer depends on stderr staying small.
- **shared jsNumber:** hoisted `JSNumber.format(_:)` into VideoEncoding.swift; FFmpegVideoEncoder.encodeArgs and VideoViewerGenerator.generate both call it (removed both private/static copies). One determinism-critical formatter → no silent cross-engine drift. Section-03 golden byte-parity test reconfirms.
- **cancellation:** run() throws `.cancelled` when `Task.isCancelled` after waitUntilExit, so a user cancel reads as cancel, not "encoding failed".
- **probe comment:** documented the probe-with-defaults behavior (ffprobe failure → 1920×1080/30, mirrors Electron).

## Not changed
- "High profile" protocol doc — the ffmpeg path intentionally omits -profile:v to byte-match Electron; the AV path (section 04) sets High. No change.
