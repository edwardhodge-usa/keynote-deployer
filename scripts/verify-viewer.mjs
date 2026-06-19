/**
 * Headless puppeteer verification that the deployed GIF viewer:
 *   1. Consumes BAKED_SLIDES (no client-side detection)
 *   2. Renders a dot-strip with exactly as many dots as baked slides
 *   3. Updates #slideCounter to "N of M" matching the baked count
 *   4. Advances via Next button (dot active class moves)
 *   5. Produces no console errors
 *
 * Run from the repo root: node scripts/verify-viewer.mjs
 */

import { createRequire } from 'module';
import { spawn } from 'child_process';
import { mkdtempSync, copyFileSync, writeFileSync, rmSync, readFileSync } from 'fs';
import { tmpdir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { execFileSync } from 'child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, '..');

// Load puppeteer via CJS require (it's a CJS package)
const require = createRequire(join(PROJECT_ROOT, 'package.json'));
const puppeteer = require('puppeteer');

// ── Config ──
const REAL_GIF_PATH = "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/01_IMAGINE LAB STUDIOS/05_BUSINESS_DEV/Quals Decks/2026 Master Quals /GIF VERSIONS/ILS_Quals 2026 V2 projects and process.gif";
const GIF_FILENAME = 'deck.gif';

// 3 baked slides with restFrames well within the 2704-frame deck.
// restFrame=10: composited synchronously on first paint; 100 & 200 filled by backgroundFill.
const BAKED_SLIDES = [
  { restFrame: 10,  holdStart: 5,   holdEnd: 20,  transitionFrames: null },
  { restFrame: 100, holdStart: 90,  holdEnd: 110, transitionFrames: { start: 21, end: 89 } },
  { restFrame: 200, holdStart: 190, holdEnd: 210, transitionFrames: { start: 111, end: 189 } },
];

/**
 * Use vite-node (available in node_modules/.bin) to generate the viewer HTML
 * by running a tiny inline generator script that imports the TS source.
 */
function generateHtml(slides) {
  // Write a temp generator script that vite-node can run
  const genScript = join(tmpdir(), 'kd-gen-html.mjs');
  const slidesJson = JSON.stringify(slides);
  writeFileSync(genScript, `
import { generateGifViewerHtml } from './electron/gifViewerGenerator.ts';
const slides = ${slidesJson};
process.stdout.write(generateGifViewerHtml('${GIF_FILENAME}', false, slides));
`);

  const vitNodeBin = join(PROJECT_ROOT, 'node_modules/.bin/vite-node');
  const result = execFileSync(vitNodeBin, [genScript], {
    cwd: PROJECT_ROOT,
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, FORCE_COLOR: '0' },
  });
  // Strip any vite deprecation warnings that might appear on stderr (stdout only is HTML)
  return result;
}

async function main() {
  let tempDir = null;
  let serverProc = null;
  let browser = null;
  const port = 18765;

  try {
    // ── 1. Set up temp dir with GIF + viewer HTML ──
    tempDir = mkdtempSync(join(tmpdir(), 'kd-viewer-verify-'));
    console.log('[verify-viewer] Temp dir:', tempDir);

    copyFileSync(REAL_GIF_PATH, join(tempDir, GIF_FILENAME));
    console.log('[verify-viewer] Copied GIF to temp dir');

    console.log('[verify-viewer] Generating viewer HTML via vite-node...');
    const html = generateHtml(BAKED_SLIDES);
    writeFileSync(join(tempDir, 'index.html'), html, 'utf8');
    console.log('[verify-viewer] Generated viewer HTML (' + html.length + ' bytes)');

    // Confirm BAKED_SLIDES is present and detection strings are absent
    if (!html.includes('"restFrame":10')) {
      throw new Error('BAKED_SLIDES not found in generated HTML');
    }
    if (html.includes('findQuietRuns') || html.includes('mergeBuildRuns')) {
      throw new Error('Detection strings found in generated HTML — client-side detection was NOT removed');
    }
    if (html.includes('QUIET_THRESHOLD') || html.includes('SNAPSHOT_SETTLE')) {
      throw new Error('Old detection variables (QUIET_THRESHOLD/SNAPSHOT_SETTLE) still present in generated HTML');
    }
    console.log('[verify-viewer] HTML content assertions passed ✓');

    // ── 2. Start HTTP server ──
    serverProc = spawn('python3', ['-m', 'http.server', String(port)], {
      cwd: tempDir,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    // Give server a moment to start
    await new Promise(r => setTimeout(r, 800));
    console.log('[verify-viewer] HTTP server started on port', port);

    // ── 3. Launch headless browser ──
    browser = await puppeteer.launch({
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
    });
    const page = await browser.newPage();

    // Collect console messages and errors
    const consoleErrors = [];
    page.on('console', msg => {
      const text = msg.text();
      if (msg.type() === 'error') {
        // Filter out harmless 404s for browser-injected resources (favicon, service workers, etc.)
        // The GIF fetch failure would appear in a pageerror or as a caught JS error, not just a 404 status.
        if (text.includes('404') && text.includes('File not found')) {
          console.log('[browser] (ignored 404 for browser-injected resource)');
        } else {
          consoleErrors.push(text);
          console.error('[browser error]', text);
        }
      } else {
        console.log('[browser]', text);
      }
    });
    page.on('pageerror', err => {
      consoleErrors.push(err.message);
      console.error('[browser pageerror]', err.message);
    });

    // ── 4. Navigate to viewer ──
    console.log('[verify-viewer] Navigating to viewer...');
    await page.goto(`http://localhost:${port}/index.html`, { waitUntil: 'domcontentloaded' });

    // ── 5. Wait for #slideCounter to show "1 of N" ──
    const expectedTotal = BAKED_SLIDES.length;
    const expectedCounter = `1 of ${expectedTotal}`;
    console.log('[verify-viewer] Waiting for slideCounter to show:', expectedCounter);

    // ensureCompositedTo(slides[0].restFrame=10) runs synchronously before returning.
    // But the GIF fetch is async. Give it up to 45s (large GIF over localhost).
    await page.waitForFunction(
      (expected) => {
        const el = document.getElementById('slideCounter');
        return el && el.textContent === expected;
      },
      { timeout: 45000 },
      expectedCounter
    );
    console.log('[verify-viewer] slideCounter shows:', expectedCounter, '✓');

    // ── 6. Assert dot count equals baked slide count ──
    const dotCount = await page.evaluate(() => {
      return document.querySelectorAll('#dotStrip .dot').length;
    });
    console.log(`[verify-viewer] Dot count: ${dotCount}, expected: ${expectedTotal}`);
    if (dotCount !== expectedTotal) {
      throw new Error(`Dot count mismatch: got ${dotCount}, expected ${expectedTotal}`);
    }
    console.log('[verify-viewer] Dot count assertion passed ✓');

    // ── 7. Assert first dot is active ──
    const firstDotActive = await page.evaluate(() => {
      const dots = document.querySelectorAll('#dotStrip .dot');
      return dots.length > 0 && dots[0].classList.contains('active');
    });
    if (!firstDotActive) throw new Error('First dot should be active on load');
    console.log('[verify-viewer] First dot active ✓');

    // ── 8. Click Next and assert counter advances to "2 of N" ──
    await page.click('#nextBtn');
    await page.waitForFunction(
      (expected) => {
        const el = document.getElementById('slideCounter');
        return el && el.textContent === expected;
      },
      { timeout: 20000 },
      `2 of ${expectedTotal}`
    );
    console.log(`[verify-viewer] Counter advanced to "2 of ${expectedTotal}" ✓`);

    // ── 9. Assert second dot is now active ──
    const secondDotActive = await page.evaluate(() => {
      const dots = document.querySelectorAll('#dotStrip .dot');
      return dots.length > 1 && dots[1].classList.contains('active');
    });
    if (!secondDotActive) throw new Error('Second dot should be active after Next');
    console.log('[verify-viewer] Second dot active after Next ✓');

    // ── 10. Check no console errors ──
    if (consoleErrors.length > 0) {
      throw new Error('Console errors detected:\n' + consoleErrors.join('\n'));
    }
    console.log('[verify-viewer] No console errors ✓');

    // ── Summary ──
    console.log('\n[verify-viewer] ALL ASSERTIONS PASSED');
    console.log(`  Baked slides:      ${expectedTotal}`);
    console.log(`  Dot count:         ${dotCount}`);
    console.log(`  Navigation:        1→2 of ${expectedTotal} ✓`);
    console.log(`  No console errors: ✓`);
    process.exit(0);

  } catch (err) {
    console.error('\n[verify-viewer] FAILED:', err.message);
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
