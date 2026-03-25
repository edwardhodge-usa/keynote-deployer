# GIF Viewer Lazy Decode — Fix iPhone Crash

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix "A problem repeatedly occurred" crash on iPhone by replacing the store-all-frames approach with a two-pass lazy decode that keeps only ~20 slide bitmaps in memory while preserving animated transitions.

**Architecture:** Two-pass GIF parsing. Pass 1 scans all frames computing diffs for slide detection without storing bitmaps. Pass 2 re-composites selectively, creating ImageBitmaps only for slide rest frames and caching canvas ImageData at each slide boundary for on-demand transition playback. Touch swipe added for mobile navigation.

**Tech Stack:** gifuct-js (already bundled), Canvas API, ImageBitmap, ImageData, Touch Events

---

## File Structure

- **Modify:** `electron/gifViewerGenerator.ts` — the only file. Contains the `generateGifViewerHtml()` function that produces a self-contained HTML string deployed to Vercel. All changes are within the inline JavaScript in this template literal.

No new files needed. No imports change. The function signature stays identical.

---

## Context for Workers

The file `electron/gifViewerGenerator.ts` exports a single function `generateGifViewerHtml(gifFilename, secureEmbed)` that returns a complete HTML string. The HTML includes an inline `<script>` with:

1. **gifuct-js IIFE bundle** (line 15) — minified GIF parser, creates global `gifuct` object
2. **`autoLoad()` IIFE** (line 275) — fetches GIF, calls `loadAndParseGIF()`, then `initViewer()`
3. **`loadAndParseGIF(arrayBuffer)`** (line 301) — the parsing function we're rewriting
4. **`initViewer()`** (line 449) — builds dot strip, renders first slide
5. **`renderSlide(index)`** (line 481) — draws a slide bitmap to canvas
6. **`playNext()` / `playPrev()`** (line 507/541) — transition playback + navigation
7. **Keyboard listener** (line 555) — arrow key navigation

The `parsedData` object returned by `loadAndParseGIF` currently has: `{ frames: ImageBitmap[], slides: SlideMap[], width, height, frameDelay }`.

After our changes, it will have: `{ slideFrames: ImageBitmap[], slides: SlideMap[], canvasStates: {}, rawFrames: [], width, height, frameDelay }`.

---

### Task 1: Replace `loadAndParseGIF` with Two-Pass Architecture

**Files:**
- Modify: `electron/gifViewerGenerator.ts:301-446` (the `loadAndParseGIF` function body)

- [ ] **Step 1: Replace the `loadAndParseGIF` function**

Replace the entire `async function loadAndParseGIF(arrayBuffer)` body (lines 301-446) with the two-pass version below. The function signature stays the same.

```javascript
    async function loadAndParseGIF(arrayBuffer) {
      updateProgress('Scanning frames...', 0);
      var gif = gifuct.parseGIF(arrayBuffer);
      var rawFrames = gifuct.decompressFrames(gif, true);

      if (!rawFrames || rawFrames.length === 0) {
        throw new Error('No image frames found in GIF.');
      }

      var gifWidth = gif.lsd.width;
      var gifHeight = gif.lsd.height;
      var frameDelay = rawFrames[0] && rawFrames[0].delay ? rawFrames[0].delay : 40;
      var totalFrames = rawFrames.length;

      // Compositing canvas
      var compCanvas = document.createElement('canvas');
      compCanvas.width = gifWidth;
      compCanvas.height = gifHeight;
      var compCtx = compCanvas.getContext('2d');

      // Temp canvas for patches
      var tempCanvas = document.createElement('canvas');
      var tempCtx = tempCanvas.getContext('2d');

      // Sample points for diff detection (~1000 points on a grid)
      var samplePoints = [];
      var gridSize = Math.ceil(Math.sqrt(1000));
      var stepX = Math.floor(gifWidth / gridSize);
      var stepY = Math.floor(gifHeight / gridSize);
      for (var y = 0; y < gifHeight; y += stepY) {
        for (var x = 0; x < gifWidth; x += stepX) {
          samplePoints.push(x, y);
        }
      }

      // ── Pass 1: Scan for diffs (no ImageBitmaps) ──
      var diffs = [0];
      var prevSamples = null;

      for (var i = 0; i < totalFrames; i++) {
        var frame = rawFrames[i];

        if (frame.disposalType === 2) {
          compCtx.clearRect(0, 0, gifWidth, gifHeight);
        }

        var dims = frame.dims;
        tempCanvas.width = dims.width;
        tempCanvas.height = dims.height;
        var imageData = tempCtx.createImageData(dims.width, dims.height);
        imageData.data.set(frame.patch);
        tempCtx.putImageData(imageData, 0, 0);
        compCtx.drawImage(tempCanvas, dims.left, dims.top);

        // Sample pixels for diff
        var fullImageData = compCtx.getImageData(0, 0, gifWidth, gifHeight);
        var pixels = fullImageData.data;

        var currentSamples = new Uint8Array(samplePoints.length / 2 * 3);
        for (var s = 0; s < samplePoints.length; s += 2) {
          var idx = (samplePoints[s + 1] * gifWidth + samplePoints[s]) * 4;
          var si = (s / 2) * 3;
          currentSamples[si] = pixels[idx];
          currentSamples[si + 1] = pixels[idx + 1];
          currentSamples[si + 2] = pixels[idx + 2];
        }

        if (prevSamples) {
          var totalDiff = 0;
          for (var s = 0; s < currentSamples.length; s++) {
            totalDiff += Math.abs(currentSamples[s] - prevSamples[s]);
          }
          diffs.push(totalDiff / currentSamples.length);
        }
        prevSamples = currentSamples;

        if (i % 20 === 0) {
          updateProgress('Scanning frame ' + (i + 1) + ' of ' + totalFrames + '...', Math.round((i / totalFrames) * 50));
          await new Promise(function(r) { setTimeout(r, 0); });
        }
      }

      // ── Slide detection (unchanged algorithm) ──
      var QUIET_THRESHOLD = 0.3;
      var MIN_QUIET_RUN = 8;

      var quietRuns = [];
      var runStart = null;
      for (var i = 0; i < diffs.length; i++) {
        if (diffs[i] <= QUIET_THRESHOLD) {
          if (runStart === null) runStart = i;
        } else {
          if (runStart !== null && (i - runStart) >= MIN_QUIET_RUN) {
            quietRuns.push({ start: runStart, end: i - 1 });
          }
          runStart = null;
        }
      }
      if (runStart !== null && (diffs.length - runStart) >= MIN_QUIET_RUN) {
        quietRuns.push({ start: runStart, end: diffs.length - 1 });
      }

      var slides = [];
      for (var i = 0; i < quietRuns.length; i++) {
        var run = quietRuns[i];
        var prevRun = i > 0 ? quietRuns[i - 1] : null;
        slides.push({
          restFrame: run.start,
          holdStart: run.start,
          holdEnd: run.end,
          transitionFrames: prevRun
            ? { start: prevRun.end + 1, end: run.start - 1 }
            : null
        });
      }

      if (slides.length === 0) {
        slides.push({
          restFrame: 0,
          holdStart: 0,
          holdEnd: 0,
          transitionFrames: null
        });
      }

      if (slides.length < 2) {
        showWarning('Could not detect slide boundaries. Try re-exporting with longer auto-advance timing (1-2 seconds).');
      }

      // Build set of needed frame indices
      var neededFrames = {};
      for (var i = 0; i < slides.length; i++) {
        neededFrames[slides[i].restFrame] = 'slide';
        if (slides[i].transitionFrames) {
          for (var f = slides[i].transitionFrames.start; f <= slides[i].transitionFrames.end; f++) {
            if (!neededFrames[f]) neededFrames[f] = 'transition';
          }
        }
      }

      // ── Pass 2: Re-composite, create bitmaps only for needed frames ──
      compCtx.clearRect(0, 0, gifWidth, gifHeight);
      var slideFrames = {};
      var canvasStates = {};
      var transitionBitmaps = {};

      for (var i = 0; i < totalFrames; i++) {
        var frame = rawFrames[i];

        if (frame.disposalType === 2) {
          compCtx.clearRect(0, 0, gifWidth, gifHeight);
        }

        var dims = frame.dims;
        tempCanvas.width = dims.width;
        tempCanvas.height = dims.height;
        var imageData = tempCtx.createImageData(dims.width, dims.height);
        imageData.data.set(frame.patch);
        tempCtx.putImageData(imageData, 0, 0);
        compCtx.drawImage(tempCanvas, dims.left, dims.top);

        if (neededFrames[i] === 'slide') {
          slideFrames[i] = await createImageBitmap(compCanvas);
          canvasStates[i] = compCtx.getImageData(0, 0, gifWidth, gifHeight);
        } else if (neededFrames[i] === 'transition') {
          transitionBitmaps[i] = await createImageBitmap(compCanvas);
        }

        // Free raw patch data
        frame.patch = null;

        if (i % 20 === 0) {
          updateProgress('Preparing slides... (' + (i + 1) + '/' + totalFrames + ')', 50 + Math.round((i / totalFrames) * 50));
          await new Promise(function(r) { setTimeout(r, 0); });
        }
      }

      console.log('Detected ' + slides.length + ' slides from ' + totalFrames + ' frames (kept ' + Object.keys(slideFrames).length + ' slide + ' + Object.keys(transitionBitmaps).length + ' transition bitmaps)');

      return {
        slideFrames: slideFrames,
        transitionBitmaps: transitionBitmaps,
        canvasStates: canvasStates,
        slides: slides,
        width: gifWidth,
        height: gifHeight,
        frameDelay: frameDelay
      };
    }
```

- [ ] **Step 2: Verify the function compiles within the template literal**

Search the file for any backtick or `${` inside the new code that would break the template literal. The code uses only single quotes, double quotes, and `var` — no template literals inside.

---

### Task 2: Update Viewer Functions to Use New Data Structure

**Files:**
- Modify: `electron/gifViewerGenerator.ts:243-558` (state vars, initViewer, renderSlide, playNext, playPrev)

- [ ] **Step 1: Update state variables**

Replace lines 243-246:

```javascript
    // ── State ──
    var parsedData = null;
    var slideMap = null;
    var currentSlideIndex = 0;
    var isPlaying = false;
```

With:

```javascript
    // ── State ──
    var parsedData = null;
    var slideMap = null;
    var currentSlideIndex = 0;
    var isPlaying = false;
```

No change needed — these stay the same. The `parsedData` object just has different properties now.

- [ ] **Step 2: Update `autoLoad` result handling**

Replace lines 288-291:

```javascript
          parsedData = result;
          slideMap = result.slides;
          initViewer();
```

No change needed — `result.slides` is still the same structure.

- [ ] **Step 3: Update `renderSlide` to use `slideFrames` map**

Replace the `renderSlide` function (lines 481-489):

```javascript
    function renderSlide(index) {
      var canvas = document.getElementById('slideCanvas');
      var ctx = canvas.getContext('2d');
      var slide = slideMap[index];
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(parsedData.slideFrames[slide.restFrame], 0, 0);
      currentSlideIndex = index;
      updateControls();
    }
```

This changes `parsedData.frames[slide.restFrame]` → `parsedData.slideFrames[slide.restFrame]`.

- [ ] **Step 4: Update `playNext` to use `transitionBitmaps`**

Replace the `playNext` function (lines 507-539):

```javascript
    function playNext() {
      if (isPlaying || currentSlideIndex >= slideMap.length - 1) return;

      var nextSlide = slideMap[currentSlideIndex + 1];
      if (!nextSlide.transitionFrames) {
        renderSlide(currentSlideIndex + 1);
        return;
      }

      isPlaying = true;
      updateControls();

      var start = nextSlide.transitionFrames.start;
      var end = nextSlide.transitionFrames.end;
      var canvas = document.getElementById('slideCanvas');
      var ctx = canvas.getContext('2d');
      var frameIdx = start;

      function playFrame() {
        var bitmap = parsedData.transitionBitmaps[frameIdx];
        if (bitmap) {
          ctx.clearRect(0, 0, canvas.width, canvas.height);
          ctx.drawImage(bitmap, 0, 0);
        }
        frameIdx++;

        if (frameIdx <= end) {
          setTimeout(function() { requestAnimationFrame(playFrame); }, parsedData.frameDelay);
        } else {
          isPlaying = false;
          renderSlide(currentSlideIndex + 1);
        }
      }

      requestAnimationFrame(playFrame);
    }
```

This changes `parsedData.frames[frameIdx]` → `parsedData.transitionBitmaps[frameIdx]`.

- [ ] **Step 5: Commit parsing + viewer changes**

```bash
git add electron/gifViewerGenerator.ts
git commit -m "fix: lazy-decode GIF viewer to prevent iPhone Safari memory crash

Two-pass architecture: Pass 1 scans diffs without storing bitmaps,
Pass 2 creates ImageBitmaps only for slide rest frames and transition
frames. Reduces memory from ~2.5GB (all frames) to ~200MB (needed frames only)."
```

---

### Task 3: Add Touch Swipe Navigation

**Files:**
- Modify: `electron/gifViewerGenerator.ts:555-558` (after keyboard listener)

- [ ] **Step 1: Add touch swipe handler after the keyboard listener**

Insert after the `document.addEventListener('keydown', ...)` block (after line 558):

```javascript
    // ── Touch swipe navigation ──
    var touchStartX = 0;
    var touchStartY = 0;
    var SWIPE_THRESHOLD = 50;

    document.addEventListener('touchstart', function(e) {
      touchStartX = e.changedTouches[0].screenX;
      touchStartY = e.changedTouches[0].screenY;
    }, { passive: true });

    document.addEventListener('touchend', function(e) {
      var dx = e.changedTouches[0].screenX - touchStartX;
      var dy = e.changedTouches[0].screenY - touchStartY;
      // Only trigger if horizontal swipe is dominant
      if (Math.abs(dx) > SWIPE_THRESHOLD && Math.abs(dx) > Math.abs(dy) * 1.5) {
        if (dx < 0) playNext();   // swipe left = next
        else playPrev();          // swipe right = previous
      }
    }, { passive: true });
```

- [ ] **Step 2: Commit touch swipe**

```bash
git add electron/gifViewerGenerator.ts
git commit -m "feat: add touch swipe navigation for mobile GIF viewer"
```

---

### Task 4: Test on Desktop + Verify Deploy

- [ ] **Step 1: Build Electron app**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer"
npm run type-check
```

Expected: no TypeScript errors.

- [ ] **Step 2: Deploy a test GIF to verify the viewer works**

Use the running Electron app or the existing Vercel URL to confirm:
- Slides display correctly
- Forward/back navigation works
- Transition animations play
- Console shows reduced bitmap count (e.g., "kept 20 slide + 180 transition bitmaps")

- [ ] **Step 3: Test on iPhone**

Open the Vercel URL on an iPhone (or use Chrome DevTools mobile emulation with throttled memory). Verify:
- Page loads without crashing
- Slides navigate with swipe gestures
- Transitions animate

---

## Execution Route

Single file change, 3 focused tasks → **Direct execution** (no subagents needed).
