# Deck Viewer — Final Architecture: VIDEO (supersedes GIF compositing)

This is the working solution for embedding an interactive, navigable Keynote deck
(with the deck's REAL transition animations) into the Framer client portal.

After a long arc through the GIF path (see "Why not GIF" below), the answer is:
**deploy the deck as an H.264 video and drive it with a tiny player.** No canvas
compositing, no ghosting, hardware-accelerated, ~22MB.

Working reference build: `scripts/video-deck/` (`build.sh`, `derive-timestamps.py`,
`gen-video-viewer.mjs`). Last proven deploy: the 39-slide ILS Quals 2026 deck.

---

## The pipeline (per deck)

Inputs from Keynote → **Export…**:
1. **Movie**: `H.264` (NOT HEVC), `1080p`, **30 FPS Constant**, "Self-Playing"
   (1.0s next-slide / 1.0s next-build). → `Deck.m4v`
2. **Images**: one JPEG per slide. → the **stills folder**. *The JPG count IS the
   slide count* and the stills are the boundary ground-truth.

Then:
```bash
scripts/video-deck/build.sh  Deck.m4v  /path/to/stills  ./out  30
cd out && vercel deploy --prod --yes      # -> public viewer URL
```
`build.sh` does: extract downscaled frames → DP-match stills to frames →
per-slide **timestamps** → re-encode H.264 with a **forced keyframe at each slide
timestamp** (`-force_key_frames`, crisp paused frames + accurate seeking) →
generate `index.html`.

Put the resulting URL in the client's Airtable **`Deck URL`** field → it renders
in the SAME native Framer Embed that renders HTML decks (no custom code).

### Codec
- **H.264 / .mp4** is required — Chrome & Firefox do NOT reliably decode HEVC/H.265.
- We re-encode even an H.264 source so each settled slide is an I-frame.

### Timestamps — re-derive PER export
A fresh Keynote render gives DIFFERENT frame indices even at the same
duration/framecount (V3 ≠ V2). Always re-run `derive-timestamps.py` against the
actual video you will ship. Frame-diff "Auto" detection does NOT work on these
decks (see below) — the **stills** are the only reliable source.

---

## The player (`gen-video-viewer.mjs`)

Single `<video>`, no JPG overlay (avoids any color-space / resolution mismatch).
- **Rest** = the video **paused on the slide's keyframe**.
- **Next** = `play()` from this slide's timestamp → watch `currentTime` →
  `pause()` at the next slide's timestamp. Plays the deck's real transition.
- **Prev / dots** = instant `currentTime` seek (HTML5 can't play video in reverse).

Responsive embed behavior (carried over from the GIF viewer, see
`GIF_EMBED_SOLUTION.md`): fills the iframe, `object-fit:contain`, transparent
background (host site shows through), caps at native width, controls scale with
`clamp(vw)`, auto-fit height via `postMessage`.

### Player gotchas (all handled)
- **Autoplay**: `<video muted playsinline>` + every `play()` is inside a user
  gesture (click / arrow key).
- **Seek race → freeze**: clicking Next while a jump-seek is still running races
  `play()` and hangs. Fix: gate Next on the `seeked` event before playing, plus a
  **stall watchdog** that re-kicks `play()` if `currentTime` stops advancing.
- **Feedback**: a spinner in the **controls row** (never over the slide) shows
  while seeking or transitioning; a full-screen spinner on first load.
- **Phones**: hide the 39-dot strip under **550px** wide (it wraps to rows and the
  dots are too small to tap) — Prev/Next + "X of N" carry mobile nav.

---

## Why NOT the GIF (the long detour, so nobody repeats it)

The deck was first a 2704-frame, ~30MB, `disposalType=1` (do-not-dispose) GIF with
PARTIAL-patch frames over a near-CONSTANT background.

1. **Slide boundaries can't come from pixels.** Frame-diff "Auto" (quiet-runs)
   returned 1 slide; peak-detection returned the wrong count. These held-build /
   constant-bg decks are unsegmentable from the GIF alone. → **N stills = N slides**,
   DP-matched to frames (pixel-verified 39/39, worst mean-abs 8.87/20).
2. **Progressive GIF compositing GHOSTS.** Rendering settled slides by compositing
   the GIF frame-by-frame in canvas accumulates faint residue (old slides' text
   bleeds through) that worsens as you advance — because partial patches on a
   constant bg never fully overwrite. A correct SEQUENTIAL composite (PIL) is
   clean, but the browser canvas/gifuct path drifts.
3. **Stills-at-rest + GIF-transition STILL ghosts.** An independently-exported
   JPEG is not pixel-identical to the GIF's accumulated sub-pixel/anti-aliasing
   state, so GIF patches apply over pixels they weren't computed for → faint delta.
   (Gemini second-opinion confirmed this is inherent to GIF as a medium here.)

→ Video sidesteps all three: native decode = no compositing, no ghost; the stills
still provide the boundary timestamps.

---

## Lessons (durable)

- **GIF is the wrong medium for partial-patch / constant-bg decks.** Use video.
- **The per-slide stills are the source of truth for slide COUNT and boundaries.**
  Ship the stills alongside every deck; the JPG count = the slide count.
- **Re-derive timestamps per video export** (fresh renders differ frame-by-frame).
- **H.264, never HEVC, for web.** Force keyframes at slide boundaries.
- **Framer native Embed**: renders a fixed-size iframe (no content auto-resize) and
  its URL can be **CMS-bound** (`Deck URL`) — same embed shows HTML or video, no
  custom code. The `DeckEmbed` code component built on `/test` (branch
  `golden-ridge`) was a dead end — revert `/test` to the native Embed.
- **The Framer EDITOR canvas does NOT run a cross-origin iframe's resize /
  postMessage loop** — verify embeds on the PUBLISHED/preview page, not the editor.
- **Video player**: muted+playsinline+gesture; gate Next on `seeked` + stall
  watchdog; Prev = instant; spinner off-slide.
- **Process**: self-verify the ACTUAL deployed artifact (a backtick in a CSS
  comment inside a JS template literal once silently broke the generator and a
  stale build shipped). Confirm `<!DOCTYPE` in the generated HTML before deploying.
- **Listen to the user's mental model** — "pause on the still, play to the next"
  was the right framing and led to the video-only design.
