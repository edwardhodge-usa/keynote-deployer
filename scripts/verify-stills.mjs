/**
 * Headless end-to-end verification for the Stills boundary source.
 *
 * Assertions:
 *   A. Exactly N monotonic frame boundaries from matchStillsToFrames
 *   B. For each of the N matched frames, the GIF viewer renders that stop and
 *      the rendered canvas pixels match the corresponding still (mean-abs pixel
 *      distance below tolerance when both are downsampled to the same grid).
 *
 * Usage (deck-agnostic):
 *   node scripts/verify-stills.mjs [gifPath] [stillsDir] [expectedCount]
 *
 * Defaults (deck-1 — 39-slide ILS Quals 2026):
 *   node scripts/verify-stills.mjs
 */

import { createRequire } from 'module';
import { spawn } from 'child_process';
import { mkdtempSync, copyFileSync, writeFileSync, rmSync, readFileSync, existsSync } from 'fs';
import { readdirSync } from 'fs';
import { tmpdir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { execFileSync } from 'child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, '..');

const require = createRequire(join(PROJECT_ROOT, 'package.json'));
const puppeteer = require('puppeteer');

// ── CLI args / defaults ──
const [,, argGifPath, argStillsDir, argExpectedCount] = process.argv;

const GIF_PATH = argGifPath
  ?? "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/01_IMAGINE LAB STUDIOS/05_BUSINESS_DEV/Quals Decks/2026 Master Quals /GIF VERSIONS/ILS_Quals 2026 V2 projects and process.gif";

const STILLS_DIR = argStillsDir
  ?? "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/01_IMAGINE LAB STUDIOS/05_BUSINESS_DEV/Quals Decks/2026 Master Quals /GIF VERSIONS/test jpg/ILS_Quals 2026 V2";

const EXPECTED_SLIDE_COUNT = argExpectedCount != null ? parseInt(argExpectedCount, 10) : 39;

const GIF_FILENAME = 'deck.gif';
// Tolerance: mean absolute pixel difference (0–255 scale) per channel.
// Stills are JPEG exports so there's JPEG compression noise. A threshold of 20
// is generous enough to absorb JPEG artefacts while still catching off-by-one.
const PIXEL_TOLERANCE = 20;

// Port: vary by expected count to allow parallel runs without collision
const port = 18766 + (EXPECTED_SLIDE_COUNT % 100);

// ── Inline helpers (replicated from src/utils/stillsMatch.ts) ──
function naturalSort(names) {
  const key = s => s.split(/(\d+)/).map(p => /^\d+$/.test(p) ? p.padStart(10, '0') : p).join('');
  return [...names].sort((a, b) => key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0);
}

function generateHtml(slides) {
  const genScript = join(tmpdir(), `kd-gen-stills-html-${EXPECTED_SLIDE_COUNT}.mjs`);
  const slidesJson = JSON.stringify(slides);
  writeFileSync(genScript, `
import { generateGifViewerHtml } from './electron/gifViewerGenerator.ts';
const slides = ${slidesJson};
process.stdout.write(generateGifViewerHtml('${GIF_FILENAME}', false, slides));
`);
  const vitNodeBin = join(PROJECT_ROOT, 'node_modules/.bin/vite-node');
  return execFileSync(vitNodeBin, [genScript], {
    cwd: PROJECT_ROOT,
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, FORCE_COLOR: '0' },
  });
}

// Build gifuct-js as a browser-compatible IIFE bundle
function buildGifuctBundle() {
  const esbuildBin = join(PROJECT_ROOT, 'node_modules/.bin/esbuild');
  const gifuctSrc = join(PROJECT_ROOT, 'node_modules/gifuct-js/lib/index.js');
  const outFile = join(tmpdir(), 'kd-gifuct-browser.js');
  execFileSync(esbuildBin, [
    gifuctSrc,
    '--bundle',
    '--format=iife',
    '--global-name=gifuct',
    `--outfile=${outFile}`,
  ]);
  return readFileSync(outFile, 'utf8');
}

async function main() {
  let tempDir = null;
  let serverProc = null;
  let browser = null;

  console.log('[verify-stills] Config:');
  console.log(`  GIF:            ${GIF_PATH}`);
  console.log(`  Stills dir:     ${STILLS_DIR}`);
  console.log(`  Expected count: ${EXPECTED_SLIDE_COUNT}`);
  console.log(`  Pixel tol:      ${PIXEL_TOLERANCE}`);
  console.log(`  HTTP port:      ${port}`);

  // Sanity checks
  if (!existsSync(GIF_PATH)) {
    console.error('[verify-stills] FATAL: GIF not found at:', GIF_PATH);
    process.exit(1);
  }
  if (!existsSync(STILLS_DIR)) {
    console.error('[verify-stills] FATAL: Stills dir not found at:', STILLS_DIR);
    process.exit(1);
  }

  // Collect stills
  const allFiles = readdirSync(STILLS_DIR);
  const imageFiles = naturalSort(allFiles.filter(f => /\.(jpe?g|png|webp)$/i.test(f)));
  if (imageFiles.length !== EXPECTED_SLIDE_COUNT) {
    console.error(`[verify-stills] FATAL: Expected ${EXPECTED_SLIDE_COUNT} stills, found ${imageFiles.length}`);
    process.exit(1);
  }
  const stillPaths = imageFiles.map(f => join(STILLS_DIR, f));
  console.log(`[verify-stills] Found ${stillPaths.length} stills`);

  // Build gifuct browser bundle
  console.log('[verify-stills] Bundling gifuct-js for browser...');
  const gifuctBundle = buildGifuctBundle();
  console.log(`[verify-stills] gifuct bundle: ${(gifuctBundle.length / 1024).toFixed(1)} KB`);

  try {
    browser = await puppeteer.launch({
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
    });

    // ── Phase 1: GIF parsing + stills matching in browser ──
    console.log('[verify-stills] Phase 1: Parsing GIF and matching stills in headless browser...');

    const matchPage = await browser.newPage();
    const matchErrors = [];
    matchPage.on('console', msg => {
      if (msg.type() === 'error') {
        matchErrors.push(msg.text());
        console.error('[browser-match error]', msg.text());
      } else if (process.env.VERBOSE) {
        console.log('[browser-match]', msg.text());
      }
    });
    matchPage.on('pageerror', err => {
      matchErrors.push(err.message);
      console.error('[browser-match pageerror]', err.message);
    });

    await matchPage.setContent(`<!DOCTYPE html><html><head></head><body></body></html>`);

    // Inject gifuct-js bundle via evaluate (avoids file:// path issues)
    await matchPage.evaluate(gifuctBundle);
    // Verify it's available
    const gifuctOk = await matchPage.evaluate(() => typeof gifuct !== 'undefined' && typeof gifuct.parseGIF === 'function');
    if (!gifuctOk) throw new Error('gifuct.parseGIF not available after bundle injection');
    console.log('[verify-stills] gifuct-js injected ✓');

    // Read GIF as base64 to inject into browser
    console.log('[verify-stills] Reading GIF file...');
    const gifBuffer = readFileSync(GIF_PATH);
    const gifBase64 = gifBuffer.toString('base64');
    console.log(`[verify-stills] GIF size: ${(gifBuffer.length / (1024 * 1024)).toFixed(1)} MB`);

    // Read all stills as base64
    console.log('[verify-stills] Reading stills...');
    const stillsBase64 = stillPaths.map(p => readFileSync(p).toString('base64'));
    console.log(`[verify-stills] Loaded ${stillsBase64.length} stills`);

    // Run everything in the browser (chunked to avoid serialization limits)
    console.log(`[verify-stills] Running GIF parse + stills match in browser (may take 30-90s)...`);

    // First: parse GIF and build frame grids
    const gifResult = await matchPage.evaluate(async (gifBase64) => {
      function samplePixels(imageData, width, height) {
        const gridSize = Math.ceil(Math.sqrt(1000));
        const stepX = Math.floor(width / gridSize);
        const stepY = Math.floor(height / gridSize);
        const pixels = imageData.data;
        const samples = [];
        for (let y = 0; y < height; y += stepY) {
          for (let x = 0; x < width; x += stepX) {
            const idx = (y * width + x) * 4;
            samples.push(pixels[idx], pixels[idx + 1], pixels[idx + 2]);
          }
        }
        return samples;
      }

      const gifBytes = Uint8Array.from(atob(gifBase64), c => c.charCodeAt(0));
      const parsed = gifuct.parseGIF(gifBytes.buffer);
      const rawFrames = gifuct.decompressFrames(parsed, true);

      const gifWidth = parsed.lsd.width;
      const gifHeight = parsed.lsd.height;

      const compCanvas = document.createElement('canvas');
      compCanvas.width = gifWidth;
      compCanvas.height = gifHeight;
      const compCtx = compCanvas.getContext('2d');

      const tempCanvas = document.createElement('canvas');
      const tempCtx = tempCanvas.getContext('2d');

      const frameGrids = [];
      const totalFrames = rawFrames.length;

      for (let i = 0; i < totalFrames; i++) {
        const frame = rawFrames[i];
        if (frame.disposalType === 2) compCtx.clearRect(0, 0, gifWidth, gifHeight);
        const dims = frame.dims;
        tempCanvas.width = dims.width;
        tempCanvas.height = dims.height;
        const imageData = tempCtx.createImageData(dims.width, dims.height);
        imageData.data.set(frame.patch);
        tempCtx.putImageData(imageData, 0, 0);
        compCtx.drawImage(tempCanvas, dims.left, dims.top);
        const fullImageData = compCtx.getImageData(0, 0, gifWidth, gifHeight);
        frameGrids.push(samplePixels(fullImageData, gifWidth, gifHeight));
        frame.patch = null; // release RGBA memory
      }

      // Store frame grids on window for the stills pass
      window._kd_frameGrids = frameGrids;
      window._kd_gifWidth = gifWidth;
      window._kd_gifHeight = gifHeight;

      return { gifWidth, gifHeight, totalFrames };
    }, gifBase64);

    console.log(`[verify-stills] GIF parsed: ${gifResult.gifWidth}x${gifResult.gifHeight}, ${gifResult.totalFrames} frames ✓`);

    // Second: load stills and sample to same grid (in batches to avoid timeout)
    console.log('[verify-stills] Sampling stills...');
    const BATCH_SIZE = 10;
    for (let batchStart = 0; batchStart < stillsBase64.length; batchStart += BATCH_SIZE) {
      const batch = stillsBase64.slice(batchStart, batchStart + BATCH_SIZE);
      const batchEnd = Math.min(batchStart + BATCH_SIZE, stillsBase64.length);
      await matchPage.evaluate(async (batch, startIdx, totalCount) => {
        function samplePixels(imageData, width, height) {
          const gridSize = Math.ceil(Math.sqrt(1000));
          const stepX = Math.floor(width / gridSize);
          const stepY = Math.floor(height / gridSize);
          const pixels = imageData.data;
          const samples = [];
          for (let y = 0; y < height; y += stepY) {
            for (let x = 0; x < width; x += stepX) {
              const idx = (y * width + x) * 4;
              samples.push(pixels[idx], pixels[idx + 1], pixels[idx + 2]);
            }
          }
          return samples;
        }

        const gifWidth = window._kd_gifWidth;
        const gifHeight = window._kd_gifHeight;
        if (!window._kd_stillGrids) window._kd_stillGrids = new Array(totalCount);

        const sc = document.createElement('canvas');
        sc.width = gifWidth; sc.height = gifHeight;
        const sctx = sc.getContext('2d');

        for (let i = 0; i < batch.length; i++) {
          await new Promise((resolve, reject) => {
            const img = new Image();
            img.onload = () => {
              sctx.clearRect(0, 0, gifWidth, gifHeight);
              sctx.drawImage(img, 0, 0, gifWidth, gifHeight);
              const imgData = sctx.getImageData(0, 0, gifWidth, gifHeight);
              window._kd_stillGrids[startIdx + i] = samplePixels(imgData, gifWidth, gifHeight);
              resolve();
            };
            img.onerror = reject;
            img.src = `data:image/jpeg;base64,${batch[i]}`;
          });
        }
      }, batch, batchStart, EXPECTED_SLIDE_COUNT);
      console.log(`[verify-stills] Sampled stills ${batchStart + 1}-${batchEnd}`);
    }

    // Third: run matchStillsToFrames
    console.log('[verify-stills] Running matchStillsToFrames...');
    const matchResult = await matchPage.evaluate(() => {
      function meanAbs(a, b) {
        let s = 0; for (let i = 0; i < a.length; i++) s += Math.abs(a[i] - b[i]); return s / a.length;
      }
      function matchStillsToFrames(stills, frames) {
        const N = stills.length, M = frames.length;
        const INF = Infinity;
        const cost = stills.map(s => frames.map(f => meanAbs(s, f)));
        const dp = Array.from({ length: N }, () => new Array(M).fill(INF));
        const back = Array.from({ length: N }, () => new Array(M).fill(-1));
        for (let f = 0; f < M; f++) dp[0][f] = cost[0][f];
        for (let i = 1; i < N; i++) {
          let bestPrev = INF, bestPrevIdx = -1;
          for (let f = 0; f < M; f++) {
            if (f - 1 >= 0 && dp[i-1][f-1] <= bestPrev) { bestPrev = dp[i-1][f-1]; bestPrevIdx = f - 1; }
            if (bestPrev !== INF) { dp[i][f] = bestPrev + cost[i][f]; back[i][f] = bestPrevIdx; }
          }
        }
        let endF = -1, best = INF;
        for (let f = 0; f < M; f++) if (dp[N-1][f] < best) { best = dp[N-1][f]; endF = f; }
        const out = new Array(N).fill(0); let f = endF;
        for (let i = N - 1; i >= 0; i--) { out[i] = f; f = back[i][f]; }
        return out;
      }

      const stills = window._kd_stillGrids;
      const frames = window._kd_frameGrids;
      return matchStillsToFrames(stills, frames);
    });

    await matchPage.close();

    console.log(`[verify-stills] Matched frames: [${matchResult.slice(0, 5).join(', ')}...${matchResult.slice(-3).join(', ')}]`);

    if (matchErrors.length > 0) {
      throw new Error('Browser errors during matching:\n' + matchErrors.join('\n'));
    }

    // ── Assert A: exactly N monotonic boundaries ──
    if (matchResult.length !== EXPECTED_SLIDE_COUNT) {
      throw new Error(`Assertion A FAILED: expected ${EXPECTED_SLIDE_COUNT} matched frames, got ${matchResult.length}`);
    }
    console.log(`[verify-stills] A: Boundary count = ${matchResult.length} ✓`);

    const isMonotonic = matchResult.every((f, i) => i === 0 || f > matchResult[i - 1]);
    if (!isMonotonic) {
      throw new Error(`Assertion A FAILED: matched frames not strictly monotonic: ${JSON.stringify(matchResult)}`);
    }
    console.log('[verify-stills] A: Monotonic ✓');

    // ── Build DetectedSlide[] for the viewer ──
    const slides = matchResult.map((frameIdx, i) => ({
      restFrame: frameIdx,
      holdStart: Math.max(0, frameIdx - 5),
      holdEnd: Math.min(gifResult.totalFrames - 1, frameIdx + 5),
      transitionFrames: i > 0 ? { start: matchResult[i - 1] + 1, end: frameIdx - 1 } : null,
    }));

    // ── Set up temp dir for viewer ──
    tempDir = mkdtempSync(join(tmpdir(), 'kd-stills-verify-'));
    console.log('[verify-stills] Temp dir:', tempDir);

    copyFileSync(GIF_PATH, join(tempDir, GIF_FILENAME));

    console.log('[verify-stills] Generating viewer HTML...');
    const html = generateHtml(slides);
    writeFileSync(join(tempDir, 'index.html'), html, 'utf8');
    console.log(`[verify-stills] Generated viewer HTML (${html.length} bytes)`);

    if (!html.includes(`"restFrame":${matchResult[0]}`)) {
      throw new Error('First matched restFrame not found in generated HTML');
    }

    // ── Start HTTP server ──
    serverProc = spawn('python3', ['-m', 'http.server', String(port)], {
      cwd: tempDir,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    await new Promise(r => setTimeout(r, 1000));
    console.log(`[verify-stills] HTTP server on port ${port}`);

    // ── Phase 2: Viewer rendering + per-stop pixel comparison ──
    console.log(`\n[verify-stills] Phase 2: Rendering ${EXPECTED_SLIDE_COUNT} stops and comparing to stills...`);

    const viewerPage = await browser.newPage();
    const viewerErrors = [];
    viewerPage.on('console', msg => {
      if (msg.type() === 'error') {
        const t = msg.text();
        if (!t.includes('404') && !t.includes('File not found') && !t.includes('favicon')) {
          viewerErrors.push(t);
          console.error('[browser-viewer error]', t);
        }
      }
    });
    viewerPage.on('pageerror', err => {
      viewerErrors.push(err.message);
      console.error('[browser-viewer pageerror]', err.message);
    });

    await viewerPage.goto(`http://localhost:${port}/index.html`, { waitUntil: 'domcontentloaded' });

    const expectedCounter = `1 of ${EXPECTED_SLIDE_COUNT}`;
    console.log(`[verify-stills] Waiting for viewer ready: "${expectedCounter}" (may take ~60s for large GIF)...`);
    await viewerPage.waitForFunction(
      (expected) => {
        const el = document.getElementById('slideCounter');
        return el && el.textContent === expected;
      },
      { timeout: 120000 },
      expectedCounter
    );
    console.log(`[verify-stills] Viewer ready ✓`);

    let matchedStops = 0;
    const failures = [];
    let worstDiff = 0;

    for (let slideIdx = 0; slideIdx < EXPECTED_SLIDE_COUNT; slideIdx++) {
      // Navigate to slide
      if (slideIdx > 0) {
        await viewerPage.evaluate((idx) => {
          const dots = document.querySelectorAll('#dotStrip .dot');
          if (dots[idx]) dots[idx].click();
        }, slideIdx);
        await viewerPage.waitForFunction(
          (expected) => {
            const el = document.getElementById('slideCounter');
            return el && el.textContent === expected;
          },
          { timeout: 15000 },
          `${slideIdx + 1} of ${EXPECTED_SLIDE_COUNT}`
        );
      }

      // Get canvas pixels and compare to still
      const pixelResult = await viewerPage.evaluate(async (stillBase64) => {
        const canvas = document.getElementById('slideCanvas');
        if (!canvas) return { error: 'no #slideCanvas element' };
        const w = canvas.width;
        const h = canvas.height;
        if (w === 0 || h === 0) return { error: `canvas has zero dimensions: ${w}x${h}` };

        const ctx = canvas.getContext('2d');
        const canvasData = ctx.getImageData(0, 0, w, h);

        // Load still and draw at same dimensions
        const stillData = await new Promise((resolve, reject) => {
          const img = new Image();
          img.onload = () => {
            const sc = document.createElement('canvas');
            sc.width = w; sc.height = h;
            const sctx = sc.getContext('2d');
            sctx.drawImage(img, 0, 0, w, h);
            resolve(sctx.getImageData(0, 0, w, h));
          };
          img.onerror = () => reject(new Error('failed to load still'));
          img.src = `data:image/jpeg;base64,${stillBase64}`;
        });

        // Mean absolute diff over RGB, sampled every 4th pixel
        const gridStep = 4;
        let totalDiff = 0;
        let count = 0;
        for (let y = 0; y < h; y += gridStep) {
          for (let x = 0; x < w; x += gridStep) {
            const idx = (y * w + x) * 4;
            totalDiff += Math.abs(canvasData.data[idx] - stillData.data[idx]);
            totalDiff += Math.abs(canvasData.data[idx + 1] - stillData.data[idx + 1]);
            totalDiff += Math.abs(canvasData.data[idx + 2] - stillData.data[idx + 2]);
            count++;
          }
        }
        const meanDiff = totalDiff / (count * 3);
        return { meanDiff, w, h };
      }, stillsBase64[slideIdx]);

      if (pixelResult.error) {
        failures.push({ slideIdx, error: pixelResult.error });
        console.error(`[verify-stills] Stop ${String(slideIdx + 1).padStart(2)}: ERROR — ${pixelResult.error}`);
      } else {
        const passed = pixelResult.meanDiff <= PIXEL_TOLERANCE;
        if (passed) matchedStops++;
        else failures.push({ slideIdx, meanDiff: pixelResult.meanDiff });
        if (pixelResult.meanDiff > worstDiff) worstDiff = pixelResult.meanDiff;
        const mark = passed ? '✓' : '✗';
        const line = `[verify-stills] Stop ${String(slideIdx + 1).padStart(2)}: mean_diff=${pixelResult.meanDiff.toFixed(2)} (tol=${PIXEL_TOLERANCE}) ${mark}`;
        if (!passed || process.env.VERBOSE || slideIdx < 3 || slideIdx >= EXPECTED_SLIDE_COUNT - 3) {
          console.log(line);
        }
      }
    }

    if (viewerErrors.length > 0) {
      throw new Error('Viewer console errors:\n' + viewerErrors.join('\n'));
    }

    // ── Summary ──
    console.log('\n[verify-stills] ─── RESULTS ───');
    console.log(`  GIF frames:        ${gifResult.totalFrames}`);
    console.log(`  Stills loaded:     ${EXPECTED_SLIDE_COUNT}`);
    console.log(`  Matched frames:    ${matchResult.length}`);
    console.log(`  Monotonic:         ${isMonotonic ? 'yes' : 'NO'}`);
    console.log(`  Pixel tolerance:   ${PIXEL_TOLERANCE}`);
    console.log(`  Worst diff:        ${worstDiff.toFixed(2)}`);
    console.log(`  Stops matched:     ${matchedStops} / ${EXPECTED_SLIDE_COUNT}`);

    if (failures.length > 0) {
      console.error('\n[verify-stills] FAILURES:');
      failures.forEach(f => {
        if (f.error) console.error(`  Stop ${f.slideIdx + 1}: ${f.error}`);
        else console.error(`  Stop ${f.slideIdx + 1}: mean_diff=${f.meanDiff.toFixed(2)} > tolerance ${PIXEL_TOLERANCE}`);
      });
    }

    if (matchResult.length !== EXPECTED_SLIDE_COUNT || !isMonotonic) {
      throw new Error('Assertion A failed — see above');
    }
    if (matchedStops !== EXPECTED_SLIDE_COUNT) {
      console.error(`\n[verify-stills] DONE_WITH_CONCERNS: only ${matchedStops}/${EXPECTED_SLIDE_COUNT} stops matched their still (worst_diff=${worstDiff.toFixed(2)}, tolerance=${PIXEL_TOLERANCE})`);
      process.exit(1);
    }

    console.log(`\n[verify-stills] ALL ASSERTIONS PASSED ✓`);
    console.log(`  A: ${EXPECTED_SLIDE_COUNT} monotonic boundaries ✓`);
    console.log(`  B: All ${EXPECTED_SLIDE_COUNT} stops match their still (worst_diff=${worstDiff.toFixed(2)}, tolerance=${PIXEL_TOLERANCE}) ✓`);
    process.exit(0);

  } catch (err) {
    console.error('\n[verify-stills] FAILED:', err.message);
    process.exit(1);
  } finally {
    if (browser) await browser.close();
    if (serverProc) serverProc.kill();
    if (tempDir) {
      try { rmSync(tempDir, { recursive: true, force: true }); } catch(_) {}
    }
  }
}

main();
