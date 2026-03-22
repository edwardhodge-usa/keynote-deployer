# GIF Slide Viewer — Design Spec

**Date:** 2026-03-21
**Project:** Keynote Deployer
**Status:** Approved

## Problem

Apple's iCloud Keynote embed viewer (`?embed=true`) strips out all transitions and builds. When comparing the original Keynote presentation against the HiDPI-patched Vercel deployment, there's no way to see transitions side by side. The existing `test-comparison.html` works for static slide comparison but can't show transition quality.

## Solution

A standalone HTML tool that loads a Keynote-exported animated GIF, parses it into slide and transition segments, and provides forward/back controls that play transitions at native speed before holding on the next slide.

## Approach

Client-side JS GIF parser (Approach A). Single HTML file with `gifuct-js` inlined. No server, no build step, no pre-processing.

### Why not the alternatives

- **Python pre-processing (B):** Adds a two-step workflow and generates hundreds of PNG files on disk. Unnecessary complexity for a test tool.
- **MP4 video (C):** Smaller file but less precise frame-seeking. GIF gives exact frame-by-frame control.

## Architecture

### Three Phases

1. **Load** — User drags/drops or file-picks a Keynote-exported animated GIF. Validate file type (check `GIF87a`/`GIF89a` magic bytes) and reject files over 200 MB.
2. **Parse** — `gifuct-js` decomposes the GIF into raw frames. Each frame is rendered to an offscreen canvas and stored as an `ImageBitmap` (not raw RGBA arrays) to keep memory under ~200 MB. A detection pass groups frames into segments: `[slide, transition, slide, transition, ...]`.
3. **View** — Canvas renders the current held slide. Forward/Back buttons play the transition segment at native fps, then hold on the next/previous slide.

### Memory Management

At 1080x608 RGBA, each raw frame is ~2.6 MB. Holding ~960 frames as raw pixel arrays would consume ~2.5 GB. Instead:

- During parse, render each decoded frame to a temporary offscreen canvas.
- Convert to `ImageBitmap` (browser-managed GPU-friendly format, much smaller than raw RGBA).
- Release the raw GIF frame data after conversion.
- During the diff detection pass, sample pixels directly from the offscreen canvas before converting to ImageBitmap.

### Slide Detection Algorithm

Compare each frame to the previous using a pixel-diff metric: mean per-pixel delta across a sampled grid of ~1000 pixels. Threshold: mean delta > 5 (out of 255) = transition frame; <= 5 = hold frame.

If the detection finds fewer than 2 slides, show a warning: "Could not detect slide boundaries. Try re-exporting with longer auto-advance timing (1-2 seconds)."

In-slide builds (bullet points appearing) will register as transitions. This is acceptable for this test tool — the viewer will treat each build step as a separate "slide." A future version could add a sensitivity slider.

This produces a segment map:

```
frames 0-23:   slide 1 (hold)
frames 24-47:  transition 1→2
frames 48-71:  slide 2 (hold)
frames 72-95:  transition 2→3
...
```

The first frame of each hold group becomes the "rest frame" — what's shown when parked on that slide.

### Expected Input

Keynote Animated GIF export with these settings:
- Resolution: Extra Large (1080x608)
- Frame Rate: 24 fps
- Auto-advance: ~1 sec
- Typical: 20 slides, 40 sec duration, ~960 frames

## UI Design

Dark theme matching existing app aesthetic (`#0a0a0a` background, `#111` header, `#222` borders, SF Pro system font).

### Components

- **Drop zone** — Drag-and-drop area (or click to browse) for the GIF file.
- **Canvas** — Full-width, maintains 1080x608 aspect ratio.
- **Bottom bar** — Previous / Next buttons, slide counter ("3 of 20"), progress strip showing all slides as clickable dots (current one highlighted). Clicking a dot jumps directly to that slide (no transition animation).
- **Loading state** — Progress bar during parse phase ("Parsing frame 240 of 960...").
- **Keyboard hint** — Small text below controls: "Arrow keys: Previous / Next"

### Playback Behavior

| Action | Behavior |
|--------|----------|
| Next | Plays transition frames at 24fps (~1 sec), lands on next slide's rest frame, holds |
| Previous | Jumps directly to previous slide's rest frame (no reverse animation — reverse transitions look unnatural for directional effects like wipes) |
| Next on last slide | Button disabled |
| Previous on first slide | Button disabled |
| During playback | Buttons disabled until transition completes |
| Keyboard | Right arrow = Next, Left arrow = Previous |
| Click dot | Jump directly to that slide (no transition) |

No autoplay, no loop. User-controlled only.

## File Structure

```
Keynote Deployer/
  gif-slide-viewer.html    <- standalone tool (single file, gifuct-js inlined)
  test-comparison.html     <- existing comparison tool, untouched
```

## Future Integration

This is a standalone test. If the approach works well, it will be integrated into the Keynote Deployer app as a feature — potentially replacing the iCloud embed pane in the comparison view, or as a standalone "Transition Preview" mode.

## Dependencies

- `gifuct-js` — GIF parser library, inlined directly in the HTML file. This ensures the tool works from `file://` without CDN/CORS issues.

## Success Criteria

1. Drop a Keynote-exported GIF and see it parsed into slides within a few seconds.
2. Forward button plays transitions smoothly at native speed.
3. Slide detection correctly identifies all 20 slides without manual configuration.
4. Works from `file://` (no server required).
5. Memory usage stays under ~500 MB for a typical 20-slide GIF.
