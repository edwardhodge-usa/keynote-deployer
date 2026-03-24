# GIF Slide Viewer Integration — Design Spec

**Date:** 2026-03-24
**Project:** Keynote Deployer (Electron)
**Status:** Approved
**Approach:** A — Native React Component

## Goal

Integrate the standalone GIF Slide Viewer (currently `gif-slide-viewer.html`) into the Electron app as a 5th sidebar tab called "Preview". Users can drop a Keynote-exported animated GIF, parse it into slides, and step through transitions at native speed — all within the app.

## Scope

- Electron app only. Swift parity is future work.
- No new IPC channels. All logic runs in the renderer process.
- No menu bar shortcut for this tab.

## New Files

- `src/components/GifViewer.tsx` — self-contained viewer component

## Modified Files

- `src/types/index.ts` — add `'preview'` to `TabId` union
- `src/App.tsx` — import GifViewer, render on `preview` tab
- `src/components/Sidebar.tsx` — add Preview tab entry with icon
- `package.json` / `package-lock.json` — add `gifuct-js` dependency

## Dependencies

- `gifuct-js` (npm) — GIF parser. Replaces the inlined IIFE from the standalone HTML.

## Component Design

### GifViewer.tsx

Single component with three UI phases managed by state:

**Phase 1: Drop**
- Centered drop zone card with dashed border, drag-over highlight
- Hidden `<input type="file" accept=".gif">` for click-to-browse
- Validation: `.gif` extension, GIF87a/GIF89a magic bytes (first 6 bytes), reject > 200MB
- On valid file: read as ArrayBuffer, transition to Loading phase

**Phase 2: Loading**
- Progress bar with frame count text ("Parsing frame 240 of 960...")
- Parsing pipeline:
  1. `gifuct.parseGIF(arrayBuffer)` + `gifuct.decompressFrames(gif, true)`
  2. For each frame: composite onto offscreen canvas (handle disposal), sample ~1000 grid pixels for diff, convert to `ImageBitmap`, release raw patch data
  3. Slide detection via quiet-run algorithm: 8+ consecutive frames with diff < 0.3 = slide hold. Everything between = transition.
  4. Build slide map: each slide has `restFrame`, `holdStart`, `holdEnd`, optional `transitionFrames`
- Yield to UI every 20 frames (`setTimeout(0)`)
- On complete: transition to Viewing phase
- Warning if < 2 slides detected

**Phase 3: Viewing**
- `<canvas>` sized to GIF dimensions (e.g. 1080x608), responsive via CSS `max-width: 100%`
- Bottom bar: Previous / Next buttons, slide counter ("3 of 20"), dot strip, keyboard hint
- "Load Another" button in top-right resets to Drop phase

### Playback Behavior

| Action | Behavior |
|--------|----------|
| Next | Play transition frames at native fps via `requestAnimationFrame` + `setTimeout(frameDelay)`, land on rest frame |
| Previous | Jump directly to previous slide's rest frame (no reverse animation) |
| Click dot | Jump directly to that slide (no transition) |
| Arrow Right/Left | Same as Next/Previous |
| During playback | All controls disabled |
| First/last slide | Previous/Next disabled respectively |

No autoplay, no loop.

### State Management

- `useRef<HTMLCanvasElement>` for canvas element
- `useRef` for parsed data (frames array, slide map, dimensions, frameDelay) — avoids re-renders on large arrays
- `useState` for UI: `phase` ('drop' | 'loading' | 'viewing'), `currentSlideIndex`, `isPlaying`, `progress` (text + percent), `error`/`warning`

### Memory Cleanup

"Load Another" calls `.close()` on every `ImageBitmap` in the frames array before resetting state.

## Styling

Tailwind classes matching the existing app. Dark mode via `dark:` variants. No custom CSS file. Key elements:
- Drop zone: `border-2 border-dashed rounded-xl` with drag-over highlight
- Buttons: match existing app button patterns
- Progress bar: `h-1 bg-blue-500 rounded`
- Dots: `w-2 h-2 rounded-full` with active state `bg-blue-500`

## Sidebar Addition

New tab entry in the `tabs` array in `Sidebar.tsx`:
- `id: 'preview'`
- `label: 'Preview'`
- Icon: play/film-style SVG (consistent stroke style with existing icons)
- Position: between History and Settings (4th item)

## What's NOT Included

- No IPC handlers or preload changes
- No Swift parity (separate future task)
- No integration with deploy workflow (standalone tab)
- No sensitivity slider for slide detection
- No comparison/side-by-side mode with deployed presentation

## Success Criteria

1. Drop a Keynote GIF in the Preview tab and see it parsed into slides
2. Forward plays transitions smoothly at native speed
3. Slide detection works without manual configuration
4. Memory stays under 500MB for typical 20-slide GIF
5. UI matches the app's existing look and feel
