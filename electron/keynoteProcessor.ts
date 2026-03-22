import fs from 'fs/promises'
import path from 'path'
import type { KeynoteMetadata, ProcessingStep } from '../src/types/index'

// Each fix patches minified Keynote main.js for HiDPI (3x) rendering.
// Search/replace are literal strings (not regex) matched against the minified source.
interface Fix {
  name: string
  search: string
  replace: string
}

const HIDPI_SCALE = 3
const HIDPI_INV = '0.3333'

const FIXES: Fix[] = [
  {
    // Increases PDF rasterization scale factor from 1x to 3x
    name: 'zC scale (PDF rasterization)',
    search: 'qC=!0;const zC=1,',
    replace: `qC=!0;const zC=${HIDPI_SCALE},`,
  },
  {
    // Forces HiDPI rendering path regardless of fullscreen state
    name: 'Fullscreen bypass',
    search: 'UC.isFullscreen||A>this.showWidth',
    replace: '!0||A>this.showWidth',
  },
  {
    // Scales WebGL viewport for sparkle/particle transition effects
    name: 'Viewport A (sparkle/particle effects)',
    search: 'Q.viewport(0,0,Q.viewportWidth,Q.viewportHeight)',
    replace: `Q.viewport(0,0,Q.viewportWidth*${HIDPI_SCALE},Q.viewportHeight*${HIDPI_SCALE})`,
  },
  {
    // Scales WebGL viewport for firework transition effects
    name: 'Viewport B (firework effects)',
    search: 'C.viewport(0,0,C.viewportWidth,C.viewportHeight)',
    replace: `C.viewport(0,0,C.viewportWidth*${HIDPI_SCALE},C.viewportHeight*${HIDPI_SCALE})`,
  },
  {
    // Scales viewport dimensions on browser resize events
    name: 'Resize viewport DPR scaling',
    search: 'B.viewport(0,0,g,C),B.viewportWidth=g,B.viewportHeight=C',
    replace: `B.viewport(0,0,g*${HIDPI_SCALE},C*${HIDPI_SCALE}),B.viewportWidth=g,B.viewportHeight=C`,
  },
  {
    // Compensates for 3x canvas by dividing viewport dimensions in constructor
    name: 'Constructor viewport division',
    search: 'g.viewportWidth=B.width,g.viewportHeight=B.height',
    replace: `g.viewportWidth=B.width/${HIDPI_SCALE},g.viewportHeight=B.height/${HIDPI_SCALE}`,
  },
  {
    // Triples canvas backing store and applies inverse CSS scale for crisp rendering
    name: 'Canvas DPR backing store',
    search: 'B.width=UC.script.slideWidth,B.height=UC.script.slideHeight',
    replace: `B.width=UC.script.slideWidth*${HIDPI_SCALE},B.height=UC.script.slideHeight*${HIDPI_SCALE},B.style.width=UC.script.slideWidth*${HIDPI_SCALE}+"px",B.style.height=UC.script.slideHeight*${HIDPI_SCALE}+"px",B.style.transform="scale(${HIDPI_INV})",B.style.transformOrigin="0 0"`,
  },
]

export interface ProcessResult {
  fixesApplied: number
  fixesSkipped: number
  errors: string[]
}

type ProgressCallback = (step: ProcessingStep) => void

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await fs.access(filePath)
    return true
  } catch {
    return false
  }
}

function reportProgress(
  onProgress: ProgressCallback,
  id: number,
  label: string,
  detail: string,
  status: ProcessingStep['status']
): void {
  onProgress({ id, label, detail, status })
}

export async function processKeynoteFolder(
  folderPath: string,
  metadata: KeynoteMetadata,
  onProgress: ProgressCallback,
  secureEmbed: boolean = false
): Promise<ProcessResult> {
  const mainJsPath = path.join(folderPath, 'assets', 'player', 'main.js')
  const backupPath = path.join(folderPath, 'assets', 'player', 'main.js.backup')
  let fixesApplied = 0
  let fixesSkipped = 0
  const errors: string[] = []

  // Step 1: Validate folder structure
  reportProgress(onProgress, 1, 'Validate folder', 'Checking folder structure...', 'active')
  if (!(await fileExists(mainJsPath))) {
    reportProgress(onProgress, 1, 'Validate folder', 'main.js not found', 'error')
    return { fixesApplied: 0, fixesSkipped: 0, errors: ['main.js not found'] }
  }
  reportProgress(onProgress, 1, 'Validate folder', 'Folder validated', 'completed')

  // Step 2: Confirm metadata
  const metadataSummary = `${metadata.title} — ${metadata.slideCount} slides`
  reportProgress(onProgress, 2, 'Read metadata', metadataSummary, 'completed')

  // Step 3: Ensure clean main.js from backup (or create initial backup)
  reportProgress(onProgress, 3, 'Backup main.js', 'Checking backup...', 'active')
  if (await fileExists(backupPath)) {
    await fs.copyFile(backupPath, mainJsPath)
    reportProgress(onProgress, 3, 'Backup main.js', 'Restored from backup', 'completed')
  } else {
    await fs.copyFile(mainJsPath, backupPath)
    reportProgress(onProgress, 3, 'Backup main.js', 'Backup created', 'completed')
  }

  // Read main.js content (now guaranteed to be the original/clean version)
  let content = await fs.readFile(mainJsPath, 'utf-8')

  // Steps 4-10: Apply HiDPI fixes
  for (let i = 0; i < FIXES.length; i++) {
    const fix = FIXES[i]
    const stepId = i + 4
    const stepLabel = `Fix ${i + 1}: ${fix.name}`
    reportProgress(onProgress, stepId, stepLabel, 'Applying...', 'active')

    if (content.includes(fix.search)) {
      content = content.replace(fix.search, fix.replace)
      fixesApplied++
      reportProgress(onProgress, stepId, stepLabel, 'Applied', 'completed')
    } else if (content.includes(fix.replace)) {
      fixesSkipped++
      reportProgress(onProgress, stepId, stepLabel, 'Already applied — skipped', 'skipped')
    } else {
      errors.push(`Fix ${i + 1} (${fix.name}): pattern not found`)
      reportProgress(onProgress, stepId, stepLabel, 'Pattern not found', 'error')
    }
  }

  // Write modified content and verify
  await fs.writeFile(mainJsPath, content, 'utf-8')
  const verifyContent = await fs.readFile(mainJsPath, 'utf-8')
  if (verifyContent !== content) {
    throw new Error('File write verification failed - content mismatch')
  }

  // Step 11: Generate index.html wrapper
  reportProgress(onProgress, 11, 'Generate index.html', 'Creating wrapper...', 'active')
  const indexHtml = generateIndexHtml(metadata.slideCount, secureEmbed)
  await fs.writeFile(path.join(folderPath, 'index.html'), indexHtml, 'utf-8')
  reportProgress(onProgress, 11, 'Generate index.html', 'index.html created', 'completed')

  return { fixesApplied, fixesSkipped, errors }
}

// ---------------------------------------------------------------------------
// Index HTML generation
// ---------------------------------------------------------------------------

const SYSTEM_FONT_STACK = '-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif'

// Navigation bar height (px) - reserves space at bottom to prevent overlap with presentation
// Calculation: button height (~30px) + bottom margin (20px) + internal gaps (20px) = 70px rounded to 80px
const NAV_BAR_RESERVED_HEIGHT = 80

// Delays (ms) at which to fire resize events after slide transitions,
// ensuring Keynote's renderer repaints at the correct HiDPI resolution.
const RE_RENDER_DELAYS = [20, 50, 100, 200, 400]
const RE_RENDER_POLL_INTERVAL = 100
const RE_RENDER_POLL_COUNT = 20

// Navigation key codes: ArrowLeft, ArrowRight, PageUp, PageDown
const NAV_KEY_CODES = [37, 39, 33, 34]

function buildStyles(): string {
  return `
html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#000}
canvas{image-rendering:optimizeSpeed!important;image-rendering:-webkit-optimize-contrast!important;image-rendering:crisp-edges!important;image-rendering:pixelated!important;-ms-interpolation-mode:nearest-neighbor!important}
#stageArea{width:100vw;height:calc(100vh - ${NAV_BAR_RESERVED_HEIGHT}px);position:relative;display:flex;align-items:center;justify-content:center}
#loadingOverlay{
  position:fixed;top:0;left:0;width:100%;height:100%;background:#000;z-index:10000;
  display:flex;align-items:center;justify-content:center;flex-direction:column;
  transition:opacity 0.4s ease;
}
#loadingOverlay.fade-out{opacity:0;pointer-events:none}
#loadingSpinner{
  width:36px;height:36px;border:3px solid rgba(255,255,255,0.1);border-top-color:rgba(255,255,255,0.6);
  border-radius:50%;animation:spin 0.8s linear infinite;
}
@keyframes spin{to{transform:rotate(360deg)}}
#loadingText{color:rgba(255,255,255,0.4);font-family:${SYSTEM_FONT_STACK};font-size:13px;margin-top:16px}
#navBar{
  position:fixed;bottom:20px;left:0;right:0;
  display:flex;align-items:center;justify-content:center;gap:20px;z-index:9999;
  font-family:${SYSTEM_FONT_STACK};
  user-select:none;-webkit-user-select:none;pointer-events:none;
}
#navBar button{
  background:rgba(50,50,50,0.7);color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:6px;padding:8px 20px;
  font-size:14px;cursor:pointer;transition:background 0.2s,border-color 0.2s;
  pointer-events:auto;backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px);
}
#navBar button:hover{background:rgba(80,80,80,0.8);border-color:rgba(255,255,255,0.3)}
#navBar button:active{background:rgba(30,30,30,0.8)}
#slideCounter{color:rgba(255,255,255,0.5);font-size:14px;min-width:80px;text-align:center;pointer-events:auto}
`.trim()
}

function buildBodyHtml(): string {
  return [
    '<div id="loadingOverlay"><div id="loadingSpinner"></div><div id="loadingText">Loading presentation&hellip;</div></div>',
    '<div id="stageArea"><div id="stage" class="stage"></div><div id="hyperlinkPlane" class="stage"></div></div>',
    '<div id="slideshowNavigator"></div>',
    '<div id="slideNumberControl"></div>',
    '<div id="slideNumberDisplay"></div>',
    '<div id="helpPlacard"></div>',
    '<div id="waitingIndicator"><div id="waitingSpinner"></div></div>',
    '<div id="navBar">',
    '  <button id="btnPrev">&#8592; Previous</button>',
    '  <span id="slideCounter"></span>',
    '  <button id="btnNext">Next &#8594;</button>',
    '</div>',
  ].join('\n')
}

function buildScript(slideCount: number): string {
  return `
(function(){
  var overlay=document.getElementById('loadingOverlay');
  var counter=document.getElementById('slideCounter');
  var totalSlides=${slideCount};
  var overlayRemoved=false;

  function removeOverlay(){
    if(overlayRemoved)return;
    overlayRemoved=true;
    overlay.classList.add('fade-out');
    setTimeout(function(){overlay.style.display='none'},500);
  }

  // Poll for canvas elements indicating Keynote has rendered, then hide loader
  var checkReady=setInterval(function(){
    var canvases=document.querySelectorAll('#stage canvas, #stageArea canvas');
    if(canvases.length>0){
      clearInterval(checkReady);
      setTimeout(removeOverlay,300);
    }
  },100);

  // Fallback: remove overlay after 5 seconds regardless
  setTimeout(function(){
    clearInterval(checkReady);
    removeOverlay();
  },5000);

  function getSlideFromHash(){
    var h=window.location.hash.replace('#','');
    var n=parseInt(h,10);
    return isNaN(n)?0:n;
  }

  function updateCounter(){
    var scene=getSlideFromHash();
    var display=Math.min(scene+1,totalSlides);
    counter.textContent=display+' / '+totalSlides;
  }

  function navigateSlide(e,keyCode,keyName){
    e.stopPropagation();
    e.preventDefault();
    document.dispatchEvent(new KeyboardEvent('keydown',{keyCode:keyCode,key:keyName,bubbles:true}));
    setTimeout(updateCounter,200);
  }

  document.getElementById('btnNext').addEventListener('click',function(e){navigateSlide(e,39,'ArrowRight')});
  document.getElementById('btnPrev').addEventListener('click',function(e){navigateSlide(e,37,'ArrowLeft')});

  // HiDPI re-render: dispatch resize events at staggered intervals so Keynote
  // repaints canvases at 3x resolution after each slide transition.
  var reRenderTimers=[];
  var pollingInterval=null;
  var delays=${JSON.stringify(RE_RENDER_DELAYS)};
  var navKeyCodes=${JSON.stringify(NAV_KEY_CODES)};

  function fireResize(){window.dispatchEvent(new Event('resize'))}

  function triggerReRenders(){
    reRenderTimers.forEach(function(t){clearTimeout(t)});
    reRenderTimers=[];
    if(pollingInterval){clearInterval(pollingInterval);pollingInterval=null;}

    fireResize();
    for(var i=0;i<delays.length;i++){
      reRenderTimers.push(setTimeout(fireResize,delays[i]));
    }

    // Continuous polling for ${RE_RENDER_POLL_COUNT * RE_RENDER_POLL_INTERVAL / 1000} seconds to catch late renders
    var pollCount=0;
    pollingInterval=setInterval(function(){
      fireResize();
      pollCount++;
      if(pollCount>=${RE_RENDER_POLL_COUNT}){clearInterval(pollingInterval);pollingInterval=null;}
    },${RE_RENDER_POLL_INTERVAL});
  }

  window.addEventListener('hashchange',triggerReRenders);

  document.addEventListener('keydown',function(e){
    for(var i=0;i<navKeyCodes.length;i++){
      if(e.keyCode===navKeyCodes[i]){triggerReRenders();return;}
    }
  });

  window.addEventListener('hashchange',updateCounter);
  updateCounter();
  setTimeout(updateCounter,1000);
  setInterval(updateCounter,1000);
})();
`.trim()
}

function buildSecureEmbedScript(): string {
  return `
(function(){
  document.addEventListener('contextmenu',function(e){e.preventDefault()});
  document.addEventListener('dragstart',function(e){e.preventDefault()});
  document.body.style.userSelect='none';
  document.body.style.webkitUserSelect='none';
  document.addEventListener('keydown',function(e){
    if((e.ctrlKey||e.metaKey)&&['s','p','u'].indexOf(e.key.toLowerCase())!==-1){
      e.preventDefault();
    }
  });
})();
`.trim()
}

function generateIndexHtml(slideCount: number, secureEmbed: boolean = false): string {
  return [
    '<!doctype html>',
    '<html xmlns="http://www.w3.org/1999/xhtml">',
    '<head>',
    '  <title>Keynote</title>',
    '  <meta name="viewport" content="initial-scale=1,minimum-scale=1,maximum-scale=1,user-scalable=no,width=device-width"/>',
    '  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>',
    `  <style>${buildStyles()}</style>`,
    '</head>',
    '<body id="body" bgcolor="black">',
    buildBodyHtml(),
    '<script src="assets/player/main.js"></script>',
    `<script>${buildScript(slideCount)}</script>`,
    ...(secureEmbed ? [`<script>${buildSecureEmbedScript()}</script>`] : []),
    '</body>',
    '</html>',
  ].join('\n')
}
