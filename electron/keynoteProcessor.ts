import fs from 'fs/promises'
import path from 'path'
import type { KeynoteMetadata, ProcessingStep } from '../src/types/index'

// Each fix: search string → replacement string (literal, not regex)
interface Fix {
  name: string
  search: string
  replace: string
}

const FIXES: Fix[] = [
  {
    name: 'zC scale (PDF rasterization)',
    search: 'qC=!0;const zC=1,',
    replace: 'qC=!0;const zC=3,',
  },
  {
    name: 'Fullscreen bypass',
    search: 'UC.isFullscreen||A>this.showWidth',
    replace: '!0||A>this.showWidth',
  },
  {
    name: 'Viewport A (sparkle/particle effects)',
    search: 'Q.viewport(0,0,Q.viewportWidth,Q.viewportHeight)',
    replace: 'Q.viewport(0,0,Q.viewportWidth*Math.max(window.devicePixelRatio||1,2),Q.viewportHeight*Math.max(window.devicePixelRatio||1,2))',
  },
  {
    name: 'Viewport B (firework effects)',
    search: 'C.viewport(0,0,C.viewportWidth,C.viewportHeight)',
    replace: 'C.viewport(0,0,C.viewportWidth*Math.max(window.devicePixelRatio||1,2),C.viewportHeight*Math.max(window.devicePixelRatio||1,2))',
  },
  {
    name: 'Resize viewport DPR scaling',
    search: 'B.viewport(0,0,g,C),B.viewportWidth=g,B.viewportHeight=C',
    replace: 'B.viewport(0,0,g*Math.max(window.devicePixelRatio||1,2),C*Math.max(window.devicePixelRatio||1,2)),B.viewportWidth=g,B.viewportHeight=C',
  },
  {
    name: 'Constructor viewport division',
    search: 'g.viewportWidth=B.width,g.viewportHeight=B.height',
    replace: 'g.viewportWidth=B.width/Math.max(window.devicePixelRatio||1,2),g.viewportHeight=B.height/Math.max(window.devicePixelRatio||1,2)',
  },
  {
    name: 'Canvas DPR backing store',
    search: 'B.width=UC.script.slideWidth,B.height=UC.script.slideHeight',
    replace: 'B.width=UC.script.slideWidth*Math.max(window.devicePixelRatio||1,2),B.height=UC.script.slideHeight*Math.max(window.devicePixelRatio||1,2),B.style.width=UC.script.slideWidth+"px",B.style.height=UC.script.slideHeight+"px"',
  },
]

export interface ProcessResult {
  fixesApplied: number
  fixesSkipped: number
  errors: string[]
}

type ProgressCallback = (step: ProcessingStep) => void

export async function processKeynoteFolder(
  folderPath: string,
  metadata: KeynoteMetadata,
  onProgress: ProgressCallback
): Promise<ProcessResult> {
  const mainJsPath = path.join(folderPath, 'assets', 'player', 'main.js')
  const backupPath = path.join(folderPath, 'assets', 'player', 'main.js.backup')
  let fixesApplied = 0
  let fixesSkipped = 0
  const errors: string[] = []

  // Step 1: Validate folder
  onProgress({ id: 1, label: 'Validate folder', detail: 'Checking folder structure...', status: 'active' })
  try {
    await fs.access(mainJsPath)
    onProgress({ id: 1, label: 'Validate folder', detail: 'Folder validated', status: 'completed' })
  } catch {
    onProgress({ id: 1, label: 'Validate folder', detail: 'main.js not found', status: 'error' })
    return { fixesApplied: 0, fixesSkipped: 0, errors: ['main.js not found'] }
  }

  // Step 2: Read metadata
  onProgress({ id: 2, label: 'Read metadata', detail: `${metadata.title} — ${metadata.slideCount} slides`, status: 'active' })
  onProgress({ id: 2, label: 'Read metadata', detail: `${metadata.title} — ${metadata.slideCount} slides`, status: 'completed' })

  // Step 3: Backup and restore main.js
  onProgress({ id: 3, label: 'Backup main.js', detail: 'Checking backup...', status: 'active' })

  let backupExists = false
  try {
    await fs.access(backupPath)
    backupExists = true
  } catch {
    // No backup exists
  }

  if (backupExists) {
    // Restore from backup to ensure clean starting point
    await fs.copyFile(backupPath, mainJsPath)
    onProgress({ id: 3, label: 'Backup main.js', detail: 'Restored from backup', status: 'completed' })
  } else {
    // Create initial backup from original
    await fs.copyFile(mainJsPath, backupPath)
    onProgress({ id: 3, label: 'Backup main.js', detail: 'Backup created', status: 'completed' })
  }

  // Read main.js content (now guaranteed to be original/clean)
  let content = await fs.readFile(mainJsPath, 'utf-8')

  // Steps 4-10: Apply fixes
  for (let i = 0; i < FIXES.length; i++) {
    const fix = FIXES[i]
    const stepId = i + 4
    onProgress({ id: stepId, label: `Fix ${i + 1}: ${fix.name}`, detail: 'Applying...', status: 'active' })

    if (content.includes(fix.search)) {
      content = content.replace(fix.search, fix.replace)
      fixesApplied++
      onProgress({ id: stepId, label: `Fix ${i + 1}: ${fix.name}`, detail: 'Applied', status: 'completed' })
    } else if (content.includes(fix.replace)) {
      fixesSkipped++
      onProgress({ id: stepId, label: `Fix ${i + 1}: ${fix.name}`, detail: 'Already applied — skipped', status: 'skipped' })
    } else {
      errors.push(`Fix ${i + 1} (${fix.name}): pattern not found`)
      onProgress({ id: stepId, label: `Fix ${i + 1}: ${fix.name}`, detail: 'Pattern not found', status: 'error' })
    }
  }

  // Write modified content back
  await fs.writeFile(mainJsPath, content, 'utf-8')

  // Step 11: Generate index.html
  onProgress({ id: 11, label: 'Generate index.html', detail: 'Creating wrapper...', status: 'active' })
  const indexHtml = generateIndexHtml(metadata.slideCount)
  await fs.writeFile(path.join(folderPath, 'index.html'), indexHtml, 'utf-8')
  onProgress({ id: 11, label: 'Generate index.html', detail: 'index.html created', status: 'completed' })

  return { fixesApplied, fixesSkipped, errors }
}

function generateIndexHtml(slideCount: number): string {
  return `<!doctype html><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Keynote</title><meta name="viewport" content="initial-scale=1,minimum-scale=1,maximum-scale=1,user-scalable=no,width=device-width"/><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/><style>
html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#000}
#stageArea{width:100vw;height:100vh;position:relative}
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
#loadingText{color:rgba(255,255,255,0.4);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;font-size:13px;margin-top:16px}
#navBar{
  position:fixed;bottom:20px;left:0;right:0;
  display:flex;align-items:center;justify-content:center;gap:20px;z-index:9999;
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;
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
</style></head><body id="body" bgcolor="black">
<div id="loadingOverlay"><div id="loadingSpinner"></div><div id="loadingText">Loading presentation&hellip;</div></div>
<div id="stageArea"><div id="stage" class="stage"></div><div id="hyperlinkPlane" class="stage"></div></div><div id="slideshowNavigator"></div><div id="slideNumberControl"></div><div id="slideNumberDisplay"></div><div id="helpPlacard"></div><div id="waitingIndicator"><div id="waitingSpinner"></div></div><div id="navBar">
<button id="btnPrev">&#8592; Previous</button>
<span id="slideCounter"></span>
<button id="btnNext">Next &#8594;</button>
</div>
<script src="assets/player/main.js"></script>
<script>
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

  var checkReady=setInterval(function(){
    var canvases=document.querySelectorAll('#stage canvas, #stageArea canvas');
    if(canvases.length>0){
      clearInterval(checkReady);
      setTimeout(removeOverlay,300);
    }
  },100);

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

  function doNext(e){
    e.stopPropagation();
    e.preventDefault();
    document.dispatchEvent(new KeyboardEvent('keydown',{keyCode:39,key:'ArrowRight',bubbles:true}));
    setTimeout(updateCounter,200);
  }

  function doPrev(e){
    e.stopPropagation();
    e.preventDefault();
    document.dispatchEvent(new KeyboardEvent('keydown',{keyCode:37,key:'ArrowLeft',bubbles:true}));
    setTimeout(updateCounter,200);
  }

  document.getElementById('btnNext').addEventListener('click',doNext);
  document.getElementById('btnPrev').addEventListener('click',doPrev);

  var reRenderTimer=null;
  window.addEventListener('hashchange',function(){
    clearTimeout(reRenderTimer);
    reRenderTimer=setTimeout(function(){
      window.dispatchEvent(new Event('resize'));
    },1800);
  });

  window.addEventListener('hashchange',updateCounter);
  updateCounter();
  setTimeout(updateCounter,1000);
  setInterval(updateCounter,1000);
})();
</script></body></html>`
}
