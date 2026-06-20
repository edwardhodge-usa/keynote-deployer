I have all context needed. The `Sources/Resources` bundling entry and test target are set up in section-01 (a dependency). Now I'll write the section content.

# Section 03 — VideoViewerGenerator + Bundled Template

## Objective

Port the Electron `videoViewerGenerator.ts` to a Swift `VideoViewerGenerator` enum that returns the deployable `index.html` for the H.264 video deck viewer. The full HTML/CSS/JS is extracted **verbatim** into a bundled resource `Sources/Resources/video-viewer-template.html` with the interpolated values replaced by placeholder tokens. `VideoViewerGenerator.generate(...)` loads the template from `Bundle.main`, fills the tokens in a **single pass** (no re-scan of injected values — matches the GIF port's parity discipline), and returns the result.

The hard requirement is **byte-parity** with the Electron `generateVideoViewerHtml(...)` output for identical inputs.

## Background / Context

This is part of the Swift video-deploy parity work. The Swift video path mirrors the Electron flow (`videoDeckPipeline.ts` + `videoViewerGenerator.ts` + `deploy-video` IPC + `VideoViewer.tsx`) and reuses existing Swift deploy infrastructure unchanged.

**Why a video viewer exists:** Keynote's HTML export rasters images as low-res thumbnails, and progressive GIF compositing ghosts on held-build / constant-background decks. The fix is to deploy the deck as an H.264 video. The viewer is a single `<video>` player (no JPG overlay, so no color-space/resolution mismatch):
- **rest** = the video paused on the slide's (forced) keyframe
- **Next** = play the real transition, then pause on the next slide
- **Prev / dots** = instant seek (HTML5 can't play video in reverse)

`VideoViewerGenerator.generate(...)` is consumed later by `VideoDeployer` (section-07), which writes the returned string to `index.html` in the temp deploy dir alongside `deck.mp4`.

### Dependencies (already met — do not re-implement)

- **section-01-models-project** — adds the Swift Testing test target to `project.yml` and a `Sources/Resources` resources bundling entry, and bumps `CURRENT_PROJECT_VERSION`. This section's bundled-template loading and tests rely on both being present. If you find `Sources/Resources` is not yet a bundled resources path in `project.yml`, that is section-01's responsibility; this section only *adds the `.html` file* to that directory.

No other sections are required for this one.

## The Electron Source (the oracle for byte-parity)

The Swift output must match this Electron function byte-for-byte for identical inputs. Full source at `electron/videoViewerGenerator.ts`:

```ts
export function generateVideoViewerHtml(
  videoFilename: string,
  secureEmbed: boolean,
  timestamps: number[],
  videoWidth = 1920,
  videoHeight = 1080
): string {
  const VW = videoWidth
  const VH = videoHeight
  const TS = JSON.stringify(timestamps)

  const secureEmbedCss = secureEmbed
    ? 'body { user-select: none; } #deck video { pointer-events: none; }'
    : ''
  const secureEmbedScript = secureEmbed
    ? "document.addEventListener('contextmenu', function(e){ e.preventDefault(); });"
    : ''

  return `<!DOCTYPE html> ... `  // full template below
}
```

### Interpolated values and their token mapping

| Electron expression | Swift token | Notes |
|---|---|---|
| `${videoFilename}` (in `src="./${videoFilename}"`) | `{{VIDEO_FILENAME}}` | bare filename, e.g. `deck.mp4` |
| `${VW}` (appears multiple times) | `{{VW}}` | `videoWidth`, default 1920 |
| `${VH}` (appears multiple times) | `{{VH}}` | `videoHeight`, default 1080 |
| `${TS}` (= `JSON.stringify(timestamps)`) | `{{TS}}` | **compact** JSON array, NO spaces |
| `${secureEmbedCss}` | `{{SECURE_EMBED_CSS}}` | empty string when `secureEmbed=false` |
| `${secureEmbedScript}` | `{{SECURE_EMBED_SCRIPT}}` | empty string when `secureEmbed=false` |

**Critical parity points:**

1. **`{{TS}}` must be compact JSON** matching JS `JSON.stringify([…])` exactly: `[0,1.234,5.6]` — no spaces after commas, no surrounding whitespace. In Swift, do **not** use `JSONEncoder` with `.prettyPrinted`. Build the string manually or via a compact encoder so the numeric formatting matches. JS `JSON.stringify` formats numbers without trailing zeros (`5` not `5.0`, `1.234` not `1.2340`). The upstream `VideoTimestampDeriver` (section-06) produces timestamps rounded to 3 decimals (`round((t/fps)*1000)/1000`); emit each value the way JS would (integers with no decimal point, fractionals with no trailing zeros). A small helper that formats a `Double` the way `JSON.stringify` does, then joins with `,` inside `[...]`, is the safest approach.

2. **`VW`/`VH` appear in many places** — the `#deckContainer` max-width, the `aspect-ratio:${VW}/${VH}` CSS (two occurrences), the JS `VW=${VW}, VH=${VH}`, and the `in-iframe #deck` aspect-ratio. The template must keep `{{VW}}` / `{{VH}}` tokens at **every** location the Electron source interpolates. Replace ALL occurrences in the single fill pass.

3. **Secure-embed strings must match exactly:**
   - CSS (when on): `body { user-select: none; } #deck video { pointer-events: none; }`
   - Script (when on): `document.addEventListener('contextmenu', function(e){ e.preventDefault(); });`
   - When `secureEmbed=false`, both tokens fill with the empty string `""` (the lines collapse exactly as Electron's empty interpolation does — the `${secureEmbedCss}` sits on its own line inside `<style>`, and `${secureEmbedScript}` sits on its own line inside the script). Preserve the surrounding whitespace/newlines so an empty fill produces the same bytes Electron does.

4. **Preserve the iframe-fill responsive behavior and the `kd-viewer-height` postMessage** — these live entirely in the verbatim template; just don't alter them.

### The verbatim template (extract into `Sources/Resources/video-viewer-template.html`)

Copy the Electron template literal **exactly** as it appears between the backticks in `generateVideoViewerHtml`, replacing only the interpolations with the tokens above. The full template is reproduced here (this is the file content, token-substituted):

```html
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Keynote Slide Viewer</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { background:#0a0a0a; color:#e5e5e5; font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif; min-height:100vh; display:flex; flex-direction:column; align-items:center; }
  header { width:100%; background:#111; border-bottom:1px solid #222; padding:14px 24px; text-align:center; } header h1 { font-size:16px; font-weight:600; }
  #deckContainer { display:none; width:100%; max-width:{{VW}}px; margin:24px auto 0; padding:0 16px; }
  #deck { position:relative; width:100%; aspect-ratio:{{VW}}/{{VH}}; background:#111; border:1px solid #222; border-radius:8px; overflow:hidden; }
  #deck video { position:absolute; inset:0; width:100%; height:100%; object-fit:contain; display:block; background:#0a0a0a; }
  #viewer { display:none; width:100%; max-width:{{VW}}px; margin:16px auto 0; padding:0 16px 32px; flex-direction:column; align-items:center; gap:12px; }
  .controls-row { display:flex; align-items:center; gap:16px; }
  #slideCounter { font-size:13px; color:#999; min-width:80px; text-align:center; }
  #dotStrip { display:flex; align-items:center; justify-content:center; flex-wrap:wrap; gap:0; max-width:100%; padding:4px 0; }
  .dot { width:8px; height:8px; border-radius:50%; background:#333; border:none; padding:0; margin:0 2px; cursor:pointer; min-width:8px; transition:background .1s; } .dot.active{background:#3b82f6;} .dot:hover{background:#555;}
  button { padding:8px 16px; background:#222; border:1px solid #333; border-radius:6px; color:#ccc; font-size:13px; cursor:pointer; } button:hover{background:#333;} button:disabled{opacity:.3;cursor:default;}
  .keyboard-hint { font-size:11px; color:#555; }
  #spinner { width:14px; height:14px; border:2px solid #333; border-top-color:#3b82f6; border-radius:50%; display:none; flex:0 0 auto; }
  body.busy #spinner { display:inline-block; animation:kd-spin .7s linear infinite; }
  @keyframes kd-spin { to { transform:rotate(360deg); } }
  body.in-iframe #spinner { width:clamp(14px,1.5vw,20px); height:clamp(14px,1.5vw,20px); }
  #loading { display:flex; position:fixed; inset:0; background:rgba(10,10,10,.92); z-index:100; flex-direction:column; align-items:center; justify-content:center; gap:16px; } #loadingText{font-size:14px;color:#999;}
  #loadSpinner { width:40px; height:40px; border:3px solid rgba(255,255,255,.12); border-top-color:#3b82f6; border-radius:50%; animation:kd-spin .8s linear infinite; }
  body.viewer-ready #deckContainer { display:block; }
  @media all {
    body.in-iframe header, body.in-iframe .keyboard-hint, body.in-iframe .powered-by { display:none !important; }
    body.in-iframe { height:100vh; overflow:hidden; justify-content:safe center; gap:14px; padding:12px 0; background:transparent; }
    body.in-iframe.viewer-ready #deckContainer { display:flex; align-items:center; justify-content:center; flex:1 1 auto; min-height:0; max-width:none; width:100%; margin:0; padding:0 16px; }
    body.in-iframe #deck { width:auto; height:100%; max-width:100%; aspect-ratio:{{VW}}/{{VH}}; background:transparent; border:none; border-radius:0; }
    body.in-iframe #deck video { background:transparent; }
    body.in-iframe #viewer { flex:0 0 auto; max-width:none; width:100%; margin:0; padding:0 16px; }
    body.in-iframe .controls-row { gap:clamp(16px,1.8vw,28px); }
    body.in-iframe .controls-row button { font-size:clamp(13px,1.4vw,17px); padding:clamp(8px,.9vw,12px) clamp(16px,1.8vw,24px); border-radius:clamp(6px,.6vw,9px); }
    body.in-iframe #slideCounter { font-size:clamp(13px,1.4vw,17px); min-width:clamp(80px,8vw,110px); }
    body.in-iframe .dot { width:clamp(8px,.9vw,11px); height:clamp(8px,.9vw,11px); min-width:clamp(8px,.9vw,11px); margin:0 clamp(2px,.25vw,4px); }
    body.in-iframe #dotStrip { row-gap:6px; }
    body.in-iframe #loading { background:transparent; } body.in-iframe #loadingText { background:rgba(10,10,10,.82); padding:8px 16px; border-radius:8px; backdrop-filter:blur(4px); }
  }
  /* Narrow embeds (phones): the dots wrap into rows and waste height + are too
     small to tap — drop them, keep Prev/Next + the "X of N" counter. */
  @media (max-width:549px){ #dotStrip { display:none !important; } }
  {{SECURE_EMBED_CSS}}
</style></head>
<body>
  <header><h1>Keynote Slide Viewer</h1></header>
  <div id="deckContainer"><div id="deck"><video id="vid" muted playsinline preload="auto" src="./{{VIDEO_FILENAME}}"></video></div></div>
  <div id="viewer">
    <div class="controls-row"><button id="prevBtn" disabled>&#9664; Previous</button><span id="slideCounter">Slide 0 / 0</span><button id="nextBtn" disabled>Next &#9654;</button><span id="spinner" aria-hidden="true"></span></div>
    <div id="dotStrip"></div><div class="keyboard-hint">Arrow keys: Previous / Next</div>
  </div>
  <div id="loading"><div id="loadSpinner"></div><div id="loadingText">Loading presentation…</div></div>
  <script>if (window.self !== window.top) document.body.classList.add('in-iframe');</script>
  <script>
    var TS = {{TS}};
    var N = TS.length, VW={{VW}}, VH={{VH}}, EPS=0.03;
    var vid = document.getElementById('vid'), deckContainer = document.getElementById('deckContainer'), loading = document.getElementById('loading');
    var current = 0, playing = false;
    {{SECURE_EMBED_SCRIPT}}

    // Rest = the PAUSED video frame at this slide's keyframe timestamp.
    function settleOn(i){
      current = i; playing = false;
      try { vid.pause(); vid.currentTime = TS[i]; } catch(e){}
      updateControls(); reportHeight();
    }
    function updateControls(){
      document.getElementById('prevBtn').disabled = current<=0 || playing;
      document.getElementById('nextBtn').disabled = current>=N-1 || playing;
      document.getElementById('slideCounter').textContent = (current+1)+' of '+N;
      var dots = document.querySelectorAll('.dot');
      for (var k=0;k<dots.length;k++) dots[k].classList.toggle('active', k===current);
    }
    // Next: play the real transition to the next slide, then pause on its keyframe.
    function next(){
      if (playing || current>=N-1) return;
      playing = true; setBusy(true); updateControls();
      var target = TS[current+1];
      function go(){
        var lastT = -1, stalls = 0;
        var pp = vid.play(); if (pp && pp.catch) pp.catch(function(){});
        function watch(){
          if (!playing) return;
          var t = vid.currentTime;
          if (t >= target - EPS || vid.ended){
            vid.pause(); current++; playing = false;
            try { vid.currentTime = TS[current]; } catch(e){}
            setBusy(false); updateControls(); reportHeight(); return;
          }
          if (!vid.seeking && Math.abs(t - lastT) < 0.0004){
            if (++stalls > 20){ var p2 = vid.play(); if (p2 && p2.catch) p2.catch(function(){}); stalls = 0; }
          } else stalls = 0;
          lastT = t;
          requestAnimationFrame(watch);
        }
        requestAnimationFrame(watch);
      }
      // Don't start the transition until any in-progress seek settles AND we're
      // parked at this slide's frame — otherwise play() races the seek and freezes.
      if (vid.seeking || Math.abs(vid.currentTime - TS[current]) > 0.1){
        var onSeeked = function(){ vid.removeEventListener('seeked', onSeeked); go(); };
        vid.addEventListener('seeked', onSeeked);
        try { vid.currentTime = TS[current]; } catch(e){ vid.removeEventListener('seeked', onSeeked); go(); }
      } else { go(); }
    }
    function prev(){ if (playing || current<=0) return; settleOn(current-1); }
    function jump(i){ if (playing) return; settleOn(i); }

    function reportHeight(){
      if (window.self===window.top) return;
      var avail = document.documentElement.clientWidth - 32, dw=Math.min(avail,VW), dh=dw*(VH/VW);
      var v=document.getElementById('viewer'); var ch=v?v.offsetHeight:80;
      window.parent.postMessage({ type:'kd-viewer-height', height: Math.ceil(dh+ch+14+24+8) }, '*');
    }
    var rt=null; function sched(){ if(rt)clearTimeout(rt); rt=setTimeout(reportHeight,80); }
    window.addEventListener('resize', sched);
    if (window.ResizeObserver){ try{ new ResizeObserver(sched).observe(document.documentElement);}catch(e){} }

    var dotStrip = document.getElementById('dotStrip');
    for (var i=0;i<N;i++){ (function(idx){ var d=document.createElement('button'); d.className='dot'; d.title='Slide '+(idx+1); d.onclick=function(){ jump(idx); }; dotStrip.appendChild(d); })(i); }
    document.getElementById('nextBtn').onclick = next;
    document.getElementById('prevBtn').onclick = prev;
    document.addEventListener('keydown', function(e){ if(e.key==='ArrowRight')next(); if(e.key==='ArrowLeft')prev(); });

    // Busy spinner (controls row only) — shows while seeking (jumps) or playing a
    // transition; never overlays the slide.
    function setBusy(b){ document.body.classList.toggle('busy', b); }
    vid.addEventListener('seeking', function(){ setBusy(true); });
    vid.addEventListener('seeked', function(){ if(!playing && !vid.seeking) setBusy(false); });

    function startUp(){
      loading.style.display='none'; document.getElementById('viewer').style.display='flex'; document.body.classList.add('viewer-ready');
      if (document.body.classList.contains('in-iframe')) deckContainer.style.maxWidth = VW+'px';
      settleOn(0); setTimeout(reportHeight,250); setTimeout(reportHeight,700);
    }
    if (vid.readyState >= 1) startUp(); else vid.addEventListener('loadedmetadata', startUp, { once:true });
    vid.addEventListener('error', function(){ document.getElementById('loadingText').textContent='Video failed to load.'; });
  </script>
</body></html>
```

> **Trailing-newline caution:** The Electron template literal ends at `</body></html>\`` with **no trailing newline** after `</html>`. When you create the `.html` file, ensure it does **not** end with an extra newline (many editors auto-append one). The byte-parity golden test will catch this. If your editor force-appends a newline, either disable that for this file or trim the loaded template's trailing whitespace in `generate(...)` — but do so deliberately and verify against the golden fixture, since trimming could mask other issues.

## Files to Create / Modify

- **Create** `swift-app/Sources/Resources/video-viewer-template.html` — the verbatim token-substituted template above.
- **Create** `swift-app/Sources/Services/VideoViewerGenerator.swift` — the generator enum.
- **Create** the test file (Swift Testing) under the test target added in section-01, e.g. `swift-app/Tests/VideoViewerGeneratorTests.swift` (match whatever test directory section-01 wired into `project.yml`).
- **Create** a golden fixture file holding the exact Electron output, e.g. `swift-app/Tests/Fixtures/video-viewer-golden.html` (see "Generating the golden fixture" below).
- **Verify** (do not duplicate) that `project.yml` bundles `Sources/Resources` so the `.html` reaches `Bundle.main` — section-01 owns this. If the template doesn't load at runtime in the test, this is the first thing to check.

## Implementation: `VideoViewerGenerator`

Signature (from the plan):

```swift
import Foundation

enum VideoViewerGenerator {
    /// Returns the deployable index.html for the video viewer.
    /// Mirrors Electron's generateVideoViewerHtml() (electron/videoViewerGenerator.ts).
    /// Loads the bundled `video-viewer-template.html`, fills tokens in a single
    /// pass, and returns the result. Output is byte-identical to Electron for
    /// identical inputs.
    static func generate(videoFilename: String, secureEmbed: Bool,
                         timestamps: [Double], videoWidth: Int, videoHeight: Int) -> String
}
```

**Behavior / implementation notes:**

1. **Load the template** from `Bundle.main` (e.g. `Bundle.main.url(forResource: "video-viewer-template", withExtension: "html")` then `String(contentsOf:encoding: .utf8)`). The template is a required bundled resource; if it is missing this is a build/packaging bug, not a runtime-recoverable condition — `fatalError`/`precondition` with a clear message is acceptable (it can never legitimately be nil in a shipped build), or `try!` if you prefer. The TDD test asserts it loads (not nil).

2. **Default parameters:** Electron defaults `videoWidth = 1920`, `videoHeight = 1080`. Mirror those as default argument values on `generate(...)` so callers (and tests) can omit them. (`VideoDeployer` passes the probed dimensions.)

3. **Compute the fill values:**
   - `VW` = `String(videoWidth)`, `VH` = `String(videoHeight)`.
   - `TS` = compact JSON of `timestamps` matching JS `JSON.stringify`. Write a helper that formats each `Double` the way JS does (no trailing zeros; integer-valued doubles render with no decimal point), then `"[" + values.joined(separator: ",") + "]"`. Empty array → `"[]"`.
   - `SECURE_EMBED_CSS` = `secureEmbed ? "body { user-select: none; } #deck video { pointer-events: none; }" : ""`
   - `SECURE_EMBED_SCRIPT` = `secureEmbed ? "document.addEventListener('contextmenu', function(e){ e.preventDefault(); });" : ""`
   - `VIDEO_FILENAME` = `videoFilename` (passed through unchanged; the caller supplies the bare name like `deck.mp4`).

4. **Single-pass fill (parity discipline):** Replace each `{{TOKEN}}` with its value. Because `{{VW}}` and `{{VH}}` appear multiple times, use `replacingOccurrences(of:with:)` per token (each call replaces all occurrences of that one token). The "single pass" rule means: do **not** re-scan injected values for further tokens. Injected values (filename, timestamps) cannot themselves contain `{{...}}` tokens in practice, but ordering must not allow an injected value to be re-interpreted — replacing token-by-token over the original template (not iteratively over already-substituted output looking for new tokens) satisfies this. The token strings `{{VW}}`, `{{VH}}`, etc. do not overlap, so replacement order does not matter for correctness; still, replace each token exactly once across the whole string.

5. **Return** the filled string. No trimming unless required to match the golden fixture's exact bytes (see trailing-newline caution).

### JSON number formatting helper

The `{{TS}}` value is the single most likely source of a byte-parity failure. JS `JSON.stringify([0, 1.234, 5])` → `[0,1.234,5]`. Swift's default `Double` description gives `0.0`, `5.0` etc., which would **not** match. Implement a helper such as:

```swift
/// Format a Double the way JavaScript JSON.stringify would (no trailing
/// zeros; integer values have no decimal point). Used to keep {{TS}} byte-
/// identical to the Electron viewer.
private static func jsNumber(_ x: Double) -> String
```

For the timestamps produced upstream (rounded to 3 decimal places via `round((t/fps)*1000)/1000`), formatting with up to 3 significant fractional digits and stripping trailing zeros and a trailing `.` matches JS for all expected inputs. Confirm with the byte-parity golden test (which uses real derived timestamps). Do not over-engineer full IEEE-754 shortest-round-trip formatting; the inputs are bounded 3-decimal values.

## Tests (write FIRST)

Use **Swift Testing** (`@Test` / `#expect`) in the test target added by section-01. Test stubs are prose/signatures — write the assertions.

```swift
import Testing
@testable import KeynoteDeployer  // or the module name the test target imports

@Suite struct VideoViewerGeneratorTests {

    /// The bundled template loads from Bundle.main at runtime (not nil).
    /// Guards the resource-bundling wiring from section-01.
    @Test func templateBundleResourceLoads() throws { /* ... */ }

    /// BYTE-PARITY: generate(...) output == the Electron generateVideoViewerHtml(...)
    /// golden fixture for identical inputs. The golden file is the exact Electron
    /// output captured for a fixed (filename, secureEmbed, timestamps, w, h).
    @Test func byteParityWithElectronGolden() throws { /* compare full strings */ }

    /// {{TS}} is emitted as compact JSON with no spaces, matching JS JSON.stringify.
    /// e.g. timestamps [0, 1.234, 5.6] -> the output contains "var TS = [0,1.234,5.6];"
    /// Also: integers render with no decimal point (5 not 5.0); empty -> [].
    @Test func timestampsAreCompactJson() { /* ... */ }

    /// secureEmbed=true injects the EXACT css + contextmenu script strings;
    /// secureEmbed=false omits both (the tokens fill with "").
    @Test func secureEmbedStringsExact() { /* check presence on true, absence on false */ }

    /// filename + width/height land in src="./<file>" and the aspect-ratio CSS.
    /// e.g. src="./deck.mp4", and aspect-ratio:1920/1080 (and VW/VH in JS vars).
    @Test func filenameAndDimensionsLandInTokens() { /* ... */ }
}
```

**Test guidance:**

- **`byteParityWithElectronGolden`** is the authoritative gate. Compare the **entire** generated string against the golden fixture with `#expect(output == golden)`. On failure, diffing the two strings (or first-differing index) will pinpoint the mismatch — most commonly the `{{TS}}` number formatting or a trailing newline.
- For `secureEmbed=false`, assert the output does **not** contain `user-select: none` nor `contextmenu` / `preventDefault`. For `=true`, assert it contains the exact strings.
- Build the golden inputs to exercise: at least one integer timestamp, at least one 3-decimal fractional, and a non-default dimension pair to confirm all `{{VW}}`/`{{VH}}` sites fill.

### Generating the golden fixture

Capture the Electron output for the exact same inputs your byte-parity test uses, and save it as `swift-app/Tests/Fixtures/video-viewer-golden.html`. A quick way (offline, no app):

1. Compile/run `electron/videoViewerGenerator.ts`'s `generateVideoViewerHtml(...)` with the chosen fixture inputs (e.g. via a tiny `ts-node`/`node` one-off or by transpiling), and write the returned string to `video-viewer-golden.html`.
2. Use the **same** `(videoFilename, secureEmbed, timestamps, videoWidth, videoHeight)` tuple in both the golden capture and the Swift test.
3. Commit the fixture. The Swift test loads it and compares.

Pick inputs that are realistic and exercise the tricky paths, e.g.:
`videoFilename = "deck.mp4"`, `secureEmbed = true`, `timestamps = [0, 1.234, 5.6, 12]`, `videoWidth = 1920`, `videoHeight = 1080`. Consider a second golden with `secureEmbed = false` and a non-16:9 dimension pair to cover both branches.

## Verification

```bash
cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -quiet
```

- All four+ tests pass; byte-parity test green.
- Build is Swift 6 strict-concurrency clean (the generator is a pure `enum` with `static` funcs — trivially `Sendable`/concurrency-safe; no shared mutable state).
- Settle the verdict on the **exit code** (`echo $?`), not stdout. If a stale `.xcresult` is suspected, force a fresh result bundle.

## Done When

- `Sources/Resources/video-viewer-template.html` exists, is bundled, and loads from `Bundle.main`.
- `VideoViewerGenerator.generate(...)` produces byte-identical output to Electron's `generateVideoViewerHtml(...)` for the golden inputs (both secure-embed branches).
- All Swift Testing tests in this section pass; the suite builds clean under Swift 6.

## Notes / Findings for the Parent

- Electron source of truth: `/Users/EdwardHodge_1/Code/keynote-deployer/electron/videoViewerGenerator.ts` (the function ends with no trailing newline after `</html>` — load-bearing for byte-parity).
- This section diverges from the existing `IndexHtmlGenerator.swift` pattern (which builds HTML inline from string parts). The plan explicitly mandates a **bundled template + single-pass token fill** here (matching the GIF port's discipline), so do not inline the template.
- The `Sources/Resources` bundling and the Swift Testing test target are provided by **section-01**; this section depends on both being present in `project.yml`.
---

## Actual Implementation (2026-06-20)

Built as planned. 29/29 tests green (suite "Section 3 — VideoViewerGenerator parity"), byte-parity confirmed both branches, Swift 6 clean, EXIT=0.

**Files:**
- `Sources/Services/VideoViewerGenerator.swift` — `enum` + `static generate(...)` + private `jsNumber`.
- `Sources/Resources/video-viewer-template.html` — derived **programmatically** from `electron/videoViewerGenerator.ts` (extracted the template literal, replaced each `${…}` interpolation with its `{{TOKEN}}`; tokens: VW×5, VH×3, TS/VIDEO_FILENAME/SECURE_EMBED_CSS/SECURE_EMBED_SCRIPT ×1). No trailing newline.
- `Tests/VideoViewerGeneratorTests.swift` — 7 tests.
- `Tests/Fixtures/video-viewer-golden-secure.html` (9940 B) + `video-viewer-golden-plain.html` (9790 B) — captured by running the **real** Electron `.ts` (types stripped) through `node` for the exact test input tuples → golden == true Electron output (no transcription drift).

**Deviations / decisions from code review (all auto-fixed):**
- `jsNumber` integer branch uses `String(format: "%.0f", x)` not `String(Int(x))` — avoids `Int(Double)` trap on out-of-range integer-valued doubles.
- Added `timestampParityForContractBoundedValues` test locking jsNumber to the 3-decimal/ms contract (`[0.001,0.1,100,12]` → `[0.001,0.1,100,12]`).
- Goldens load from the **test bundle** via a `BundleAnchor` class (`Bundle(for:)`), not `#filePath` — survives relocated builds / CI; uses the Resources entries XcodeGen already wired.

**Contract note for section-06:** `jsNumber` byte-parity assumes timestamps are pre-rounded to ≤3 decimals (`round((t/fps)*1000)/1000`). Values <0.0005s or with >3 significant decimals would diverge from JS. The `VideoTimestampDeriver` must honor that rounding.

**Wiring confirmed:** `project.yml` app target `sources: path: Sources` auto-categorizes the `.html` into Copy Bundle Resources → reaches `Bundle.main` (hosted tests see it). `template loads (not nil)` test green.
