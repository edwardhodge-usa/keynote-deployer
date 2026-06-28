# Session State

**Last updated:** 2026-06-28 14:00
**Goal:** Fix the video deck viewer on iPhone (Framer client-page embeds) + shrink decks. SHIPPED v1.2.1.
**Plan:** None yet for next work — see "Next Step" (marker editor = 1.3.0).

## Current Task
**What:** Deck viewer iOS fixes + smooth playback + CRF16 encoder → **v1.2.1 notarized, installed (/Applications), pushed, GitHub release + Sparkle appcast live.**
**Status:** COMPLETE. 68/68 tests. Commits `6b88bfe` (1.2.1 feature) + `4774da6` (lesson). Tag `v1.2.1`.

**Key files (all in `swift-app/`):**
- `Sources/Resources/video-viewer-template.html` — the viewer (blob loader, navBusy lock, stall-aware clock, paintFrame, poster, edge-tap, REST_BIAS=0.08)
- `Sources/Services/FFmpegVideoEncoder.swift` — CRF16 `-bf 0 -g 60`, `isAvailable()`
- `Sources/Services/VideoDeployer.swift` — ffmpeg-preferred seam (`.live`)
- `Sources/Services/VideoViewerGenerator.swift` + `Tests/Fixtures/video-viewer-golden-*.html` (byte-parity)
- `Sources/Services/VideoTimestampDeriver.swift` — produces per-slide `TS` (the markers the editor will let users adjust)

## Context (for next session)
- **Root cause of ALL the stutter/skip/freeze: mid-playback network buffering** (range-fetching unbuffered regions). Fixed by loading the whole deck into an in-memory blob and playing from it. "first-bad/retry-good" = caching, always. (Full arc in CLAUDE.md 2026-06-28.)
- **Rest-frame placement is still imperfect on a few slides** — auto-derived `TS` lands on/near a transition for some; a global `REST_BIAS` constant CANNOT fix it (tried 0 and 0.08 — both wrong for different slides). This is the open problem the marker editor solves.
- Encoder requires ffmpeg installed (Edward has it); AVFoundation is the no-ffmpeg fallback (bigger, B-frames).
- Earlier this session (separate): imaginelab-portal UI-debt cleanup merged to main — done, unrelated to next work.
- Live test rig still up: `wrapper-iota-ten.vercel.app/realdeck.html` (+ `/compare.html`); throwaway Vercel projects `realdeck-crf16`/`realdeck-viewer`/`viewers-opal`/`wrapper-iota-ten` — keep for marker-editor testing, delete when done.

## Next Step
**Build the marker / timeline editor (v1.3.0).** Add a **"Review markers"** phase to the Deploy Video tab between Analyze and Encode: show the auto-derived per-slide rest markers on a scrubber/filmstrip; let the user **drag / add / remove** each with a live frame preview before encoding. The approved marker becomes **BOTH** the viewer's rest point **AND** the forced keyframe (single source of truth → kills REST_BIAS guessing + the off-keyframe-seek bug class). Start `/brainstorm` → `/deep-plan`. Pieces exist: `VideoTimestampDeriver` (markers), `VideoPoster` (frame extraction), `VideoDeployView` (the tab), AVPlayerView NSViewRepresentable pattern.

## Verification Goals (marker editor)
- [ ] User sees all N auto-markers on a timeline + can drag/add/remove before encode.
- [ ] The chosen marker is what the encoder forces a keyframe at AND what the viewer rests on (no REST_BIAS offset).
- [ ] Validated on the real 39-slide deck, on iPhone, in a cross-origin iframe.
