# GIF Slide Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone HTML tool that parses a Keynote-exported animated GIF into slide/transition segments and provides forward/back controls that play transitions at native speed.

**Architecture:** Single HTML file with inlined gifuct-js (7KB IIFE bundle). Three-phase flow: drop GIF → parse frames + detect slides in one pass → canvas-based viewer with forward/back playback. Slide boundaries detected via pixel-diff sampling during the parse loop (not a separate pass).

**Tech Stack:** HTML5 Canvas, gifuct-js (inlined), vanilla JavaScript, no build tools.

**Spec:** `docs/superpowers/specs/2026-03-21-gif-slide-viewer-design.md`

**Test file:** `/Users/EdwardHodge_1/Desktop/ILS_Quals 2026 V1.6.gif` (16MB, 963 frames, 1080x608, 40ms/frame, 20 slides)

**Project root:** `/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer/`

**gifuct-js bundle:** If `/tmp/gifuct-bundle/gifuct.min.js` does not exist, rebuild it:
```bash
mkdir -p /tmp/gifuct-bundle && cd /tmp/gifuct-bundle && npm init -y && npm install gifuct-js && npx esbuild --bundle --format=iife --global-name=gifuct --minify node_modules/gifuct-js/lib/index.js --outfile=gifuct.min.js
```

---

## File Structure

```
Keynote Deployer/
  gif-slide-viewer.html    <- CREATE: standalone viewer (single file, everything inlined)
```

One file. All CSS, JS, and the gifuct-js library inlined.

---

### Task 1: HTML Shell + Dark Theme + Drop Zone

**Files:**
- Create: `gif-slide-viewer.html`

Build the outer HTML structure with dark theme CSS and a functional drag-and-drop zone that reads a GIF file into an ArrayBuffer.

- [ ] **Step 1: Create the HTML file with full structure**

Create `gif-slide-viewer.html` with:
- HTML boilerplate, dark theme CSS (`#0a0a0a` bg, `#111` header, `#222` borders, SF Pro system font)
- Header: "Keynote GIF Slide Viewer" title
- Drop zone: centered card with dashed border, drag-over highlight, click-to-browse via hidden `<input type="file" accept=".gif">`
- Canvas container (hidden initially): full-width `<canvas>` with CSS `max-width: 1080px; width: 100%; height: auto;` and `aspect-ratio: 1080/608;`
- Bottom bar (hidden initially): Previous/Next buttons, slide counter, dot strip, keyboard hint ("Arrow keys: Previous / Next")
- Loading overlay (hidden initially): progress bar with frame count text
- Warning/error display area (hidden initially, red text)
- `showWarning(msg)` and `showError(msg)` helper functions

CSS should match `test-comparison.html` palette exactly:
```css
body { background: #0a0a0a; color: #e5e5e5; font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', system-ui, sans-serif; }
```

Buttons styled like test-comparison.html controls:
```css
button { padding: 8px 16px; background: #222; border: 1px solid #333; border-radius: 6px; color: #ccc; font-size: 13px; cursor: pointer; }
button:hover { background: #333; }
button:disabled { opacity: 0.3; cursor: default; }
```

Progress bar:
```css
.progress-bar { width: 100%; height: 4px; background: #222; border-radius: 2px; overflow: hidden; margin-top: 12px; }
.progress-fill { height: 100%; background: #3b82f6; transition: width 0.1s; width: 0%; }
```

Dot strip:
```css
.dot { width: 8px; height: 8px; border-radius: 50%; background: #333; border: none; padding: 0; margin: 0 2px; cursor: pointer; min-width: 8px; }
.dot.active { background: #3b82f6; }
.dot:hover { background: #555; }
```

- [ ] **Step 2: Wire up drag-and-drop + file input**

JavaScript at bottom of file:
- Prevent default drag events on document (no accidental navigation)
- Drop zone: `dragover` adds highlight class, `dragleave`/`drop` removes it
- On drop or file input change: validate file — check extension is `.gif`, check first 6 bytes are `GIF87a` or `GIF89a`, reject files > 200MB with `showError()`
- On valid file: read as `ArrayBuffer` via `FileReader`, store in global `gifBuffer`
- Show loading overlay, hide drop zone
- Call `loadAndParseGIF(gifBuffer)` (to be implemented in Task 2)

`updateProgress(text, percent)` function: updates loading overlay text and sets progress bar width to `percent%`.

- [ ] **Step 3: Test manually**

Open in Chrome:
```bash
open -a "Google Chrome" "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer/gif-slide-viewer.html"
```

Verify: dark theme renders, drop zone visible, dragging a non-GIF file shows error, dragging the test GIF reads it (console.log the ArrayBuffer size to confirm: should be ~16MB).

- [ ] **Step 4: Commit**

```bash
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" add gif-slide-viewer.html
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" commit -m "feat: GIF slide viewer — HTML shell with drop zone and dark theme"
```

---

### Task 2: Inline gifuct-js + Frame Parsing + Slide Detection (Single Pass)

**Files:**
- Modify: `gif-slide-viewer.html`

Inline the gifuct-js IIFE bundle and implement GIF parsing with progress reporting AND slide boundary detection in the same loop (per spec: "sample pixels directly from the offscreen canvas before converting to ImageBitmap").

- [ ] **Step 1: Inline the gifuct-js bundle**

Add a `<script>` block at the top of the JS section containing the gifuct-js IIFE bundle (7KB). This creates the global `gifuct` object with `gifuct.parseGIF()` and `gifuct.decompressFrames()`.

If `/tmp/gifuct-bundle/gifuct.min.js` exists, copy its contents. Otherwise rebuild it first (see plan header for command).

- [ ] **Step 2: Implement combined parse + detect function**

After the gifuct-js inline block, implement `async function loadAndParseGIF(arrayBuffer)`:

```javascript
async function loadAndParseGIF(arrayBuffer) {
  updateProgress('Parsing GIF structure...', 0);
  const gif = gifuct.parseGIF(arrayBuffer);
  const rawFrames = gifuct.decompressFrames(gif, true);

  const gifWidth = gif.lsd.width;
  const gifHeight = gif.lsd.height;
  const frameDelay = rawFrames[0]?.delay || 40;

  // Compositing canvas (handles disposal, positioning)
  const compCanvas = document.createElement('canvas');
  compCanvas.width = gifWidth;
  compCanvas.height = gifHeight;
  const compCtx = compCanvas.getContext('2d');

  // Temp canvas for patches
  const tempCanvas = document.createElement('canvas');
  const tempCtx = tempCanvas.getContext('2d');

  // Sample points for diff detection (~1000 points on a grid)
  const samplePoints = [];
  const gridSize = Math.ceil(Math.sqrt(1000));
  const stepX = Math.floor(gifWidth / gridSize);
  const stepY = Math.floor(gifHeight / gridSize);
  for (let y = 0; y < gifHeight; y += stepY) {
    for (let x = 0; x < gifWidth; x += stepX) {
      samplePoints.push(x, y); // flat array for speed
    }
  }

  const frames = []; // ImageBitmaps
  const diffs = [0]; // First frame has no diff
  let prevSamples = null;
  const totalFrames = rawFrames.length;

  for (let i = 0; i < totalFrames; i++) {
    const frame = rawFrames[i];

    // Handle disposal
    if (frame.disposalType === 2) {
      compCtx.clearRect(0, 0, gifWidth, gifHeight);
    }

    // Draw patch to temp canvas, composite onto full canvas
    const dims = frame.dims;
    tempCanvas.width = dims.width;
    tempCanvas.height = dims.height;
    const imageData = tempCtx.createImageData(dims.width, dims.height);
    imageData.data.set(frame.patch);
    tempCtx.putImageData(imageData, 0, 0);
    compCtx.drawImage(tempCanvas, dims.left, dims.top);

    // BEFORE converting to ImageBitmap: sample pixels for diff detection
    const fullImageData = compCtx.getImageData(0, 0, gifWidth, gifHeight);
    const pixels = fullImageData.data;

    // Sample current frame at grid points
    const currentSamples = new Uint8Array(samplePoints.length / 2 * 3);
    for (let s = 0; s < samplePoints.length; s += 2) {
      const idx = (samplePoints[s + 1] * gifWidth + samplePoints[s]) * 4;
      const si = (s / 2) * 3;
      currentSamples[si] = pixels[idx];
      currentSamples[si + 1] = pixels[idx + 1];
      currentSamples[si + 2] = pixels[idx + 2];
    }

    if (prevSamples) {
      let totalDiff = 0;
      for (let s = 0; s < currentSamples.length; s++) {
        totalDiff += Math.abs(currentSamples[s] - prevSamples[s]);
      }
      diffs.push(totalDiff / currentSamples.length);
    }
    prevSamples = currentSamples;

    // NOW convert to ImageBitmap (GPU-friendly, smaller than raw RGBA)
    const bitmap = await createImageBitmap(compCanvas);
    frames.push(bitmap);

    // Free the raw patch data
    frame.patch = null;

    // Progress update every 20 frames
    if (i % 20 === 0) {
      updateProgress(`Parsing frame ${i + 1} of ${totalFrames}...`, Math.round((i / totalFrames) * 100));
      await new Promise(r => setTimeout(r, 0)); // yield to UI
    }
  }

  // Classify frames: diff > 5 = transition, <= 5 = hold
  const THRESHOLD = 5;
  const segments = [];
  let currentType = 'hold'; // First frame is always hold
  let segStart = 0;

  for (let i = 1; i < diffs.length; i++) {
    const type = diffs[i] > THRESHOLD ? 'transition' : 'hold';
    if (type !== currentType) {
      segments.push({ type: currentType, start: segStart, end: i - 1 });
      currentType = type;
      segStart = i;
    }
  }
  segments.push({ type: currentType, start: segStart, end: diffs.length - 1 });

  // Build slide map
  const slides = [];
  for (let i = 0; i < segments.length; i++) {
    if (segments[i].type === 'hold') {
      slides.push({
        restFrame: segments[i].start,
        holdStart: segments[i].start,
        holdEnd: segments[i].end,
        transitionFrames: i > 0 && segments[i - 1].type === 'transition'
          ? { start: segments[i - 1].start, end: segments[i - 1].end }
          : null
      });
    }
  }

  if (slides.length < 2) {
    showWarning('Could not detect slide boundaries. Try re-exporting with longer auto-advance timing (1-2 seconds).');
  }

  console.log(`Detected ${slides.length} slides from ${frames.length} frames`);
  console.log('Segments:', segments);

  return { frames, slides, width: gifWidth, height: gifHeight, frameDelay };
}
```

- [ ] **Step 3: Wire load→parse→viewer pipeline**

In the drop handler, after validation:
```javascript
loadAndParseGIF(arrayBuffer).then(result => {
  parsedData = result;
  slideMap = result.slides;
  initViewer(); // Task 3
}).catch(err => {
  showError('Failed to parse GIF: ' + err.message);
  console.error(err);
});
```

- [ ] **Step 4: Test with real GIF**

Drop `/Users/EdwardHodge_1/Desktop/ILS_Quals 2026 V1.6.gif` onto the viewer. Verify:
- Progress updates show frame count advancing to 963
- No console errors
- Console shows "Detected N slides from 963 frames" where N is between 15 and 40 (exact count depends on in-slide builds being treated as boundaries)
- `parsedData.frameDelay` should be approximately 40 (check console)
- Segments log shows alternating hold/transition pattern

- [ ] **Step 5: Commit**

```bash
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" add gif-slide-viewer.html
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" commit -m "feat: GIF slide viewer — gifuct-js parser with single-pass slide detection"
```

---

### Task 3: Canvas Viewer + Forward/Back Playback

**Files:**
- Modify: `gif-slide-viewer.html`

Implement the viewer: canvas rendering, forward/back with transition animation, slide counter, dot strip, keyboard controls.

- [ ] **Step 1: Implement initViewer()**

```javascript
function initViewer() {
  // Hide loading, show viewer
  document.getElementById('loading').style.display = 'none';
  document.getElementById('viewer').style.display = 'block';

  // Set canvas dimensions
  const canvas = document.getElementById('slideCanvas');
  canvas.width = parsedData.width;
  canvas.height = parsedData.height;

  // Build dot strip
  const dotStrip = document.getElementById('dotStrip');
  dotStrip.innerHTML = '';
  slideMap.forEach((slide, i) => {
    const dot = document.createElement('button');
    dot.className = 'dot';
    dot.title = `Slide ${i + 1}`;
    dot.onclick = () => jumpToSlide(i);
    dotStrip.appendChild(dot);
  });

  // Show first slide
  currentSlideIndex = 0;
  renderSlide(0);
  updateControls();
}
```

- [ ] **Step 2: Implement renderSlide() and updateControls()**

```javascript
function renderSlide(index) {
  const canvas = document.getElementById('slideCanvas');
  const ctx = canvas.getContext('2d');
  const slide = slideMap[index];
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(parsedData.frames[slide.restFrame], 0, 0);
  currentSlideIndex = index;
  updateControls();
}

function updateControls() {
  document.getElementById('prevBtn').disabled = currentSlideIndex <= 0 || isPlaying;
  document.getElementById('nextBtn').disabled = currentSlideIndex >= slideMap.length - 1 || isPlaying;
  document.getElementById('slideCounter').textContent = `${currentSlideIndex + 1} of ${slideMap.length}`;

  // Update dots
  document.querySelectorAll('.dot').forEach((dot, i) => {
    dot.classList.toggle('active', i === currentSlideIndex);
  });
}
```

- [ ] **Step 3: Implement forward transition playback**

```javascript
let isPlaying = false;

function playNext() {
  if (isPlaying || currentSlideIndex >= slideMap.length - 1) return;

  const nextSlide = slideMap[currentSlideIndex + 1];
  if (!nextSlide.transitionFrames) {
    // No transition, just jump
    renderSlide(currentSlideIndex + 1);
    return;
  }

  isPlaying = true;
  updateControls();

  const { start, end } = nextSlide.transitionFrames;
  const canvas = document.getElementById('slideCanvas');
  const ctx = canvas.getContext('2d');
  let frameIdx = start;

  function playFrame() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(parsedData.frames[frameIdx], 0, 0);
    frameIdx++;

    if (frameIdx <= end) {
      setTimeout(() => requestAnimationFrame(playFrame), parsedData.frameDelay);
    } else {
      // Transition done, land on next slide's rest frame
      isPlaying = false;
      renderSlide(currentSlideIndex + 1);
    }
  }

  requestAnimationFrame(playFrame);
}

function playPrev() {
  if (isPlaying || currentSlideIndex <= 0) return;
  // Jump directly — no reverse animation per spec
  renderSlide(currentSlideIndex - 1);
}

function jumpToSlide(index) {
  if (isPlaying) return;
  renderSlide(index);
}
```

- [ ] **Step 4: Wire buttons and keyboard**

```javascript
document.getElementById('nextBtn').onclick = playNext;
document.getElementById('prevBtn').onclick = playPrev;

document.addEventListener('keydown', (e) => {
  if (e.key === 'ArrowRight') playNext();
  if (e.key === 'ArrowLeft') playPrev();
});
```

- [ ] **Step 5: Test with real GIF**

Drop the test GIF. Verify:
- First slide renders on canvas at full resolution
- Next button plays the transition smoothly (~1 sec animation) then holds on next slide
- Previous button jumps back instantly (no reverse animation)
- Slide counter updates correctly ("1 of N", "2 of N", etc.)
- Dots highlight the current slide (blue dot)
- Clicking a dot jumps directly to that slide (no transition)
- Arrow keys work (Right = Next, Left = Previous)
- Buttons disabled during transition playback
- Previous disabled on first slide, Next disabled on last slide
- Reaching the last slide does NOT restart or loop

Take a screenshot to verify visual quality.

- [ ] **Step 6: Commit**

```bash
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" add gif-slide-viewer.html
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" commit -m "feat: GIF slide viewer — canvas viewer with forward/back transition playback"
```

---

### Task 4: Polish + Final Test

**Files:**
- Modify: `gif-slide-viewer.html`

Final polish: "Load Another" button, edge cases, cleanup, and end-to-end test.

- [ ] **Step 1: Add "Load Another GIF" button**

In the viewer header area, add a small "Load Another GIF" button that:
- Calls `.close()` on every ImageBitmap in `parsedData.frames` to release GPU memory
- Clears `parsedData`, `slideMap`, `currentSlideIndex`
- Shows the drop zone again
- Hides the viewer

- [ ] **Step 2: Handle edge cases**

- Single-slide GIF: show the slide, Previous/Next both disabled, no dots needed
- Very large GIF (> 200MB): `showError('File too large. Maximum size is 200 MB.')` — don't attempt parse
- Non-GIF file: `showError('Not a GIF file. Please drop an animated GIF.')` — check magic bytes
- Parse failure: try/catch around `parseGIF` and `decompressFrames`, show `showError('Failed to parse GIF: ' + err.message)`

- [ ] **Step 3: End-to-end test**

Full test with `/Users/EdwardHodge_1/Desktop/ILS_Quals 2026 V1.6.gif`:
1. Open `gif-slide-viewer.html` in Chrome (use `file://` protocol — no server)
2. Drop the GIF file
3. Watch progress bar fill
4. Verify slide count (between 15-40 slides)
5. Click through all slides with Next, verify transitions play at ~1 sec each
6. Click Previous, verify instant jump back
7. Click dots to jump around
8. Use arrow keys
9. Verify reaching last slide does NOT loop
10. Click "Load Another GIF" and re-drop the same file
11. Check memory in Activity Monitor (should be < 500MB)

Take a screenshot showing the viewer with a slide loaded.

- [ ] **Step 4: Final commit**

```bash
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" add gif-slide-viewer.html
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" commit -m "feat: GIF slide viewer — polish, error handling, and load-another flow"
```

---

## Execution Route

| Signal | Route |
|--------|-------|
| 4 tasks, single file, iterative build | `/do` (subagents) |
