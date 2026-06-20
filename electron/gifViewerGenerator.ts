// Generates a self-contained HTML page for viewing a deployed GIF as slides.
// Embeds the gifuct-js parser, quiet-run slide detection, and canvas viewer.

export function generateGifViewerHtml(
  gifFilename: string,
  secureEmbed: boolean,
  slides: { restFrame: number; holdStart: number; holdEnd: number; transitionFrames: { start: number; end: number } | null }[]
): string {
  const secureEmbedCss = secureEmbed
    ? 'body { user-select: none; } canvas { pointer-events: none; }'
    : ''

  const secureEmbedScript = secureEmbed
    ? "document.addEventListener('contextmenu', function(e) { e.preventDefault(); });"
    : ''

  // The gifuct-js IIFE bundle (minified ~3KB) — creates global `gifuct` object
  // with parseGIF() and decompressFrames() methods.
  const gifuctBundle = '"use strict";var gifuct=(()=>{var _=(n,e)=>()=>(e||n((e={exports:{}}).exports,e),e.exports);var D=_(y=>{"use strict";Object.defineProperty(y,"__esModule",{value:!0});y.loop=y.conditional=y.parse=void 0;var J=function n(e,r){var t=arguments.length>2&&arguments[2]!==void 0?arguments[2]:{},a=arguments.length>3&&arguments[3]!==void 0?arguments[3]:t;if(Array.isArray(r))r.forEach(function(s){return n(e,s,t,a)});else if(typeof r=="function")r(e,t,a,n);else{var i=Object.keys(r)[0];Array.isArray(r[i])?(a[i]={},n(e,r[i],t,a[i])):a[i]=r[i](e,t,a,n)}return t};y.parse=J;var L=function(e,r){return function(t,a,i,s){r(t,a,i)&&s(t,e,a,i)}};y.conditional=L;var N=function(e,r){return function(t,a,i,s){for(var d=[],u=t.pos;r(t,a,i);){var l={};if(s(t,e,a,l),t.pos===u)break;u=t.pos,d.push(l)}return d}};y.loop=N});var G=_(f=>{"use strict";Object.defineProperty(f,"__esModule",{value:!0});f.readBits=f.readArray=f.readUnsigned=f.readString=f.peekBytes=f.readBytes=f.peekByte=f.readByte=f.buildStream=void 0;var Q=function(e){return{data:e,pos:0}};f.buildStream=Q;var E=function(){return function(e){return e.data[e.pos++]}};f.readByte=E;var V=function(){var e=arguments.length>0&&arguments[0]!==void 0?arguments[0]:0;return function(r){return r.data[r.pos+e]}};f.peekByte=V;var C=function(e){return function(r){return r.data.subarray(r.pos,r.pos+=e)}};f.readBytes=C;var W=function(e){return function(r){return r.data.subarray(r.pos,r.pos+e)}};f.peekBytes=W;var Y=function(e){return function(r){return Array.from(C(e)(r)).map(function(t){return String.fromCharCode(t)}).join("")}};f.readString=Y;var $=function(e){return function(r){var t=C(2)(r);return e?(t[1]<<8)+t[0]:(t[0]<<8)+t[1]}};f.readUnsigned=$;var ee=function(e,r){return function(t,a,i){for(var s=typeof r=="function"?r(t,a,i):r,d=C(e),u=new Array(s),l=0;l<s;l++)u[l]=d(t);return u}};f.readArray=ee;var re=function(e,r,t){for(var a=0,i=0;i<t;i++)a+=e[r+i]&&Math.pow(2,t-i-1);return a},te=function(e){return function(r){for(var t=E()(r),a=new Array(8),i=0;i<8;i++)a[7-i]=!!(t&1<<i);return Object.keys(e).reduce(function(s,d){var u=e[d];return u.length?s[d]=re(a,u.index,u.length):s[d]=a[u.index],s},{})}};f.readBits=te});var R=_(M=>{"use strict";Object.defineProperty(M,"__esModule",{value:!0});M.default=void 0;var x=D(),o=G(),I={blocks:function(e){for(var r=0,t=[],a=e.data.length,i=0,s=(0,o.readByte)()(e);s!==r&&s;s=(0,o.readByte)()(e)){if(e.pos+s>=a){var d=a-e.pos;t.push((0,o.readBytes)(d)(e)),i+=d;break}t.push((0,o.readBytes)(s)(e)),i+=s}for(var u=new Uint8Array(i),l=0,p=0;p<t.length;p++)u.set(t[p],l),l+=t[p].length;return u}},ne=(0,x.conditional)({gce:[{codes:(0,o.readBytes)(2)},{byteSize:(0,o.readByte)()},{extras:(0,o.readBits)({future:{index:0,length:3},disposal:{index:3,length:3},userInput:{index:6},transparentColorGiven:{index:7}})},{delay:(0,o.readUnsigned)(!0)},{transparentColorIndex:(0,o.readByte)()},{terminator:(0,o.readByte)()}]},function(n){var e=(0,o.peekBytes)(2)(n);return e[0]===33&&e[1]===249}),ae=(0,x.conditional)({image:[{code:(0,o.readByte)()},{descriptor:[{left:(0,o.readUnsigned)(!0)},{top:(0,o.readUnsigned)(!0)},{width:(0,o.readUnsigned)(!0)},{height:(0,o.readUnsigned)(!0)},{lct:(0,o.readBits)({exists:{index:0},interlaced:{index:1},sort:{index:2},future:{index:3,length:2},size:{index:5,length:3}})}]},(0,x.conditional)({lct:(0,o.readArray)(3,function(n,e,r){return Math.pow(2,r.descriptor.lct.size+1)})},function(n,e,r){return r.descriptor.lct.exists}),{data:[{minCodeSize:(0,o.readByte)()},I]}]},function(n){return(0,o.peekByte)()(n)===44}),ie=(0,x.conditional)({text:[{codes:(0,o.readBytes)(2)},{blockSize:(0,o.readByte)()},{preData:function(e,r,t){return(0,o.readBytes)(t.text.blockSize)(e)}},I]},function(n){var e=(0,o.peekBytes)(2)(n);return e[0]===33&&e[1]===1}),oe=(0,x.conditional)({application:[{codes:(0,o.readBytes)(2)},{blockSize:(0,o.readByte)()},{id:function(e,r,t){return(0,o.readString)(t.blockSize)(e)}},I]},function(n){var e=(0,o.peekBytes)(2)(n);return e[0]===33&&e[1]===255}),de=(0,x.conditional)({comment:[{codes:(0,o.readBytes)(2)},I]},function(n){var e=(0,o.peekBytes)(2)(n);return e[0]===33&&e[1]===254}),se=[{header:[{signature:(0,o.readString)(3)},{version:(0,o.readString)(3)}]},{lsd:[{width:(0,o.readUnsigned)(!0)},{height:(0,o.readUnsigned)(!0)},{gct:(0,o.readBits)({exists:{index:0},resolution:{index:1,length:3},sort:{index:4},size:{index:5,length:3}})},{backgroundColorIndex:(0,o.readByte)()},{pixelAspectRatio:(0,o.readByte)()}]},(0,x.conditional)({gct:(0,o.readArray)(3,function(n,e){return Math.pow(2,e.lsd.gct.size+1)})},function(n,e){return e.lsd.gct.exists}),{frames:(0,x.loop)([ne,oe,de,ae,ie],function(n){var e=(0,o.peekByte)()(n);return e===33||e===44})}],ue=se;M.default=ue});var K=_(F=>{"use strict";Object.defineProperty(F,"__esModule",{value:!0});F.deinterlace=void 0;var ce=function(e,r){for(var t=new Array(e.length),a=e.length/r,i=function(A,v){var c=e.slice(v*r,(v+1)*r);t.splice.apply(t,[A*r,r].concat(c))},s=[0,4,2,1],d=[8,8,4,2],u=0,l=0;l<4;l++)for(var p=s[l];p<a;p+=d[l])i(p,u),u++;return t};F.deinterlace=ce});var X=_(q=>{"use strict";Object.defineProperty(q,"__esModule",{value:!0});q.lzw=void 0;var le=function(e,r,t){var a=4096,i=-1,s=t,d,u,l,p,j,A,v,m,c,h,w,z,b,g,U,P,T=new Array(t),O=new Array(a),S=new Array(a),k=new Array(a+1);for(z=e,u=1<<z,j=u+1,d=u+2,v=i,p=z+1,l=(1<<p)-1,c=0;c<u;c++)O[c]=0,S[c]=c;var w,m,H,b,g,P,U;for(w=m=H=b=g=P=U=0,h=0;h<s;){if(g===0){if(m<p){w+=r[U]<<m,m+=8,U++;continue}if(c=w&l,w>>=p,m-=p,c>d||c==j)break;if(c==u){p=z+1,l=(1<<p)-1,d=u+2,v=i;continue}if(v==i){k[g++]=S[c],v=c,b=c;continue}for(A=c,c==d&&(k[g++]=b,c=v);c>u;)k[g++]=S[c],c=O[c];b=S[c]&255,k[g++]=b,d<a&&(O[d]=v,S[d]=b,d++,(d&l)===0&&d<a&&(p++,l+=d)),v=A}g--,T[P++]=k[g],h++}for(h=P;h<s;h++)T[h]=0;return T};q.lzw=le});var me=_(B=>{Object.defineProperty(B,"__esModule",{value:!0});B.decompressFrames=B.decompressFrame=B.parseGIF=void 0;var fe=xe(R()),pe=D(),ve=G(),ge=K(),ye=X();function xe(n){return n&&n.__esModule?n:{default:n}}var Be=function(e){var r=new Uint8Array(e);return(0,pe.parse)((0,ve.buildStream)(r),fe.default)};B.parseGIF=Be;var he=function(e){for(var r=e.pixels.length,t=new Uint8ClampedArray(r*4),a=0;a<r;a++){var i=a*4,s=e.pixels[a],d=e.colorTable[s]||[0,0,0];t[i]=d[0],t[i+1]=d[1],t[i+2]=d[2],t[i+3]=s!==e.transparentIndex?255:0}return t},Z=function(e,r,t){if(!e.image){console.warn("gif frame does not have associated image.");return}var a=e.image,i=a.descriptor.width*a.descriptor.height,s=(0,ye.lzw)(a.data.minCodeSize,a.data.blocks,i);a.descriptor.lct.interlaced&&(s=(0,ge.deinterlace)(s,a.descriptor.width));var d={pixels:s,dims:{top:e.image.descriptor.top,left:e.image.descriptor.left,width:e.image.descriptor.width,height:e.image.descriptor.height}};return a.descriptor.lct&&a.descriptor.lct.exists?d.colorTable=a.lct:d.colorTable=r,e.gce&&(d.delay=(e.gce.delay||10)*10,d.disposalType=e.gce.extras.disposal,e.gce.extras.transparentColorGiven&&(d.transparentIndex=e.gce.transparentColorIndex)),t&&(d.patch=he(d)),d};B.decompressFrame=Z;var be=function(e,r){return e.frames.filter(function(t){return t.image}).map(function(t){return Z(t,e.gct,r)})};B.decompressFrames=be});return me();})();'

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Keynote GIF Slide Viewer</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }

    body {
      background: #0a0a0a;
      color: #e5e5e5;
      font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', system-ui, sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
    }

    /* Header */
    header {
      width: 100%;
      background: #111;
      border-bottom: 1px solid #222;
      padding: 14px 24px;
      text-align: center;
      display: flex;
      align-items: center;
      justify-content: center;
      position: relative;
    }
    header h1 {
      font-size: 16px;
      font-weight: 600;
      color: #e5e5e5;
      letter-spacing: -0.2px;
    }

    /* Canvas container */
    #canvasContainer {
      display: none;
      width: 100%;
      max-width: 1080px;
      margin: 24px auto 0;
      padding: 0 16px;
    }
    #slideCanvas {
      width: 100%;
      height: auto;
      aspect-ratio: 1080 / 608;
      background: #111;
      border: 1px solid #222;
      border-radius: 8px;
      display: block;
    }

    /* Bottom bar / viewer controls */
    #viewer {
      display: none;
      width: 100%;
      max-width: 1080px;
      margin: 16px auto 0;
      padding: 0 16px 32px;
      flex-direction: column;
      align-items: center;
      gap: 12px;
    }

    .controls-row {
      display: flex;
      align-items: center;
      gap: 16px;
    }

    #slideCounter {
      font-size: 13px;
      color: #999;
      min-width: 80px;
      text-align: center;
    }

    #dotStrip {
      display: flex;
      align-items: center;
      justify-content: center;
      flex-wrap: wrap;
      gap: 0;
      max-width: 100%;
      padding: 4px 0;
    }

    .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #333;
      border: none;
      padding: 0;
      margin: 0 2px;
      cursor: pointer;
      min-width: 8px;
      transition: background 0.1s;
    }
    .dot.active { background: #3b82f6; }
    .dot:hover { background: #555; }

    .keyboard-hint {
      font-size: 11px;
      color: #555;
    }

    /* Buttons */
    button {
      padding: 8px 16px;
      background: #222;
      border: 1px solid #333;
      border-radius: 6px;
      color: #ccc;
      font-size: 13px;
      cursor: pointer;
      transition: background 0.1s;
    }
    button:hover { background: #333; }
    button:disabled { opacity: 0.3; cursor: default; }

    /* Loading overlay */
    #loading {
      display: none;
      position: fixed;
      top: 0; left: 0; right: 0; bottom: 0;
      background: rgba(10, 10, 10, 0.92);
      z-index: 100;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 16px;
    }
    #loadingText {
      font-size: 14px;
      color: #999;
    }
    .progress-bar {
      width: 280px;
      height: 4px;
      background: #222;
      border-radius: 2px;
      overflow: hidden;
      margin-top: 12px;
    }
    .progress-fill {
      height: 100%;
      background: #3b82f6;
      transition: width 0.1s;
      width: 0%;
    }

    /* Warning / Error */
    #messageArea {
      display: none;
      margin: 24px auto 0;
      max-width: 520px;
      width: 90vw;
      padding: 12px 16px;
      border-radius: 8px;
      font-size: 13px;
      line-height: 1.5;
      text-align: center;
    }
    #messageArea.warning {
      display: block;
      background: #2a1f00;
      border: 1px solid #665200;
      color: #fbbf24;
    }
    #messageArea.error {
      display: block;
      background: #1f0000;
      border: 1px solid #660000;
      color: #ef4444;
    }

    /* Canvas container becomes visible once the GIF is parsed (was inline display:block) */
    body.viewer-ready #canvasContainer { display: block; }

    /* Iframe embed mode — hide chrome, fill the embed box (match the HTML deck viewer).
       The deck wrapper uses 100vw/100vh + overflow:hidden so it scales to whatever
       size Framer's embed gives it; the GIF viewer must do the same instead of
       capping at 1080px and top-aligning. */
    @media all {
      body.in-iframe header,
      body.in-iframe .keyboard-hint,
      body.in-iframe .powered-by { display: none !important; }

      /* Center the deck + its controls together as one group so the controls
         hug the bottom of the deck instead of being pinned to the window edge
         with dead space between. gap ties the two; the 12px top/bottom keeps
         a small breathing margin at extreme sizes.
         - "safe center": if the group is taller than the viewport (e.g. a
           many-slide deck whose dot strip wraps to several rows), fall back to
           top-alignment instead of centering — centering would clip the TOP of
           the deck under overflow:hidden, which is unrecoverable (no scroll).
         - "background: transparent": let the host site (Framer) background show
           through the letterbox around the deck — no black fill. */
      body.in-iframe {
        height: 100vh;
        overflow: hidden;
        justify-content: safe center;
        gap: 14px;
        padding: 12px 0;
        background: transparent;
      }

      body.in-iframe.viewer-ready #canvasContainer {
        display: flex;
        align-items: center;
        justify-content: center;
        flex: 0 1 auto;      /* natural height = the canvas; may shrink, won't grow */
        min-height: 0;
        max-width: none;
        width: 100%;
        margin: 0;
        padding: 0 16px;
      }

      /* Scale to fit the box at the GIF's true aspect ratio (no 1080-cap, no
         hardcoded 1080/608 — width/height:auto means the canvas's own backing
         dimensions drive the ratio, so non-16:9 decks don't distort).
         max-height:100% (NOT a calc(100vh - reserve)) means the canvas sizes
         against its flex parent's RESOLVED height: #viewer (controls) takes its
         natural height first as flex:0 0, then #canvasContainer (flex:0 1,
         min-height:0) shrinks to whatever's left and the canvas fits inside it.
         So the controls can be ANY height (wrapped dot rows, scaled buttons)
         and the canvas never overlaps them — no hardcoded pixel reserve to get
         wrong. object-fit:contain keeps the ratio if the box is ever clamped. */
      body.in-iframe #slideCanvas {
        width: auto;
        height: auto;
        max-width: 100%;
        max-height: 100%;
        object-fit: contain;
        aspect-ratio: auto;
        border: none;
        border-radius: 0;
      }

      body.in-iframe #viewer {
        flex: 0 0 auto;
        max-width: none;
        width: 100%;
        margin: 0;
        padding: 0 16px;
      }

      /* Controls scale with the embed width (1vw = 1% of the iframe width).
         clamp() floors them at today's compact size on small embeds and caps
         them so they never get oversized on a full-bleed embed. */
      body.in-iframe .controls-row { gap: clamp(16px, 1.8vw, 28px); }
      /* Scope to the Prev/Next row only — the dots are also <button>s, in a
         separate #dotStrip, and must NOT pick up this padding (it pills them). */
      body.in-iframe .controls-row button {
        font-size: clamp(13px, 1.4vw, 17px);
        padding: clamp(8px, 0.9vw, 12px) clamp(16px, 1.8vw, 24px);
        border-radius: clamp(6px, 0.6vw, 9px);
      }
      body.in-iframe #slideCounter {
        font-size: clamp(13px, 1.4vw, 17px);
        min-width: clamp(80px, 8vw, 110px);
      }
      body.in-iframe .dot {
        width: clamp(8px, 0.9vw, 11px);
        height: clamp(8px, 0.9vw, 11px);
        min-width: clamp(8px, 0.9vw, 11px);
        margin: 0 clamp(2px, 0.25vw, 4px);
      }
      /* Many-slide decks wrap the dot strip; base gap is 0, so give wrapped
         rows vertical breathing room. */
      body.in-iframe #dotStrip { row-gap: 6px; }

      /* The loading overlay defaults to a near-opaque black sheet
         (rgba(10,10,10,0.92)) — in a transparent embed that would flash a black
         rectangle over the host site while the GIF parses. Make the overlay
         itself transparent and pill just the text + progress bar so the site
         background stays visible during load. */
      body.in-iframe #loading { background: transparent; }
      body.in-iframe #loadingText {
        background: rgba(10, 10, 10, 0.82);
        padding: 8px 16px;
        border-radius: 8px;
        backdrop-filter: blur(4px);
      }
    }

    ${secureEmbedCss}
  </style>
</head>
<body>

  <header>
    <h1>Keynote GIF Slide Viewer</h1>
  </header>

  <!-- Message area for warnings/errors -->
  <div id="messageArea"></div>

  <!-- Canvas container -->
  <div id="canvasContainer">
    <canvas id="slideCanvas" width="1080" height="608"></canvas>
  </div>

  <!-- Bottom bar / viewer controls -->
  <div id="viewer">
    <div class="controls-row">
      <button id="prevBtn" disabled>&#9664; Previous</button>
      <span id="slideCounter">Slide 0 / 0</span>
      <button id="nextBtn" disabled>Next &#9654;</button>
    </div>
    <div id="dotStrip"></div>
    <div class="keyboard-hint">Arrow keys: Previous / Next</div>
  </div>

  <!-- Loading overlay -->
  <div id="loading">
    <div id="loadingText">Loading...</div>
    <div class="progress-bar">
      <div class="progress-fill" id="progressFill"></div>
    </div>
  </div>

  <p class="powered-by" style="text-align:center;font-size:11px;color:#555;margin-top:16px;">Powered by Keynote Deployer</p>

  <script>if(window.self!==window.top)document.body.classList.add('in-iframe');</script>
  <script>${gifuctBundle}</script>

  <script>
    // ── Baked slide boundaries (build-time, from Keynote Deployer) ──
    var BAKED_SLIDES = ${JSON.stringify(slides)};

    // ── Secure embed ──
    ${secureEmbedScript}

    // ── State ──
    var parsedData = null;
    var slideMap = null;
    var currentSlideIndex = 0;
    var isPlaying = false;

    // ── DOM refs ──
    var canvasContainer = document.getElementById('canvasContainer');
    var viewer = document.getElementById('viewer');
    var loading = document.getElementById('loading');
    var loadingText = document.getElementById('loadingText');
    var progressFill = document.getElementById('progressFill');
    var messageArea = document.getElementById('messageArea');

    // ── Helpers ──
    function showWarning(msg) {
      messageArea.className = 'warning';
      messageArea.textContent = msg;
      messageArea.style.display = 'block';
    }

    function showError(msg) {
      messageArea.className = 'error';
      messageArea.textContent = msg;
      messageArea.style.display = 'block';
    }

    function updateProgress(text, percent) {
      loadingText.textContent = text;
      progressFill.style.width = percent + '%';
    }

    // ── Auto-load GIF on page open ──
    (function autoLoad() {
      loading.style.display = 'flex';
      updateProgress('Fetching GIF...', 0);

      fetch('./${gifFilename}')
        .then(function(response) {
          if (!response.ok) throw new Error('Failed to fetch GIF: ' + response.status);
          return response.arrayBuffer();
        })
        .then(function(arrayBuffer) {
          updateProgress('Parsing GIF structure...', 10);
          return loadAndParseGIF(arrayBuffer);
        })
        .then(function(result) {
          parsedData = result;
          slideMap = result.slides;
          initViewer();
        })
        .catch(function(err) {
          loading.style.display = 'none';
          showError('Failed to load GIF: ' + err.message);
          console.error(err);
        });
    })();

    // ── GIF Parser — parse structure + build snapshots from BAKED_SLIDES ──
    async function loadAndParseGIF(arrayBuffer) {
      updateProgress('Parsing GIF structure...', 10);
      var gif = gifuct.parseGIF(arrayBuffer);

      // Filter to image frames only (each may also carry .gce data)
      var imageFrames = gif.frames.filter(function(f) { return f.image; });
      var gct = gif.gct;

      if (!imageFrames || imageFrames.length === 0) {
        throw new Error('No image frames found in GIF.');
      }

      var gifWidth = gif.lsd.width;
      var gifHeight = gif.lsd.height;
      var totalFrames = imageFrames.length;

      // Get frame delay from first frame
      var firstDecoded = gifuct.decompressFrame(imageFrames[0], gct, true);
      var frameDelay = (firstDecoded && firstDecoded.delay) ? firstDecoded.delay : 40;
      firstDecoded = null; // free patch buffer early — frame 0 composited normally by ensureCompositedTo

      // Compositing canvas
      var compCanvas = document.createElement('canvas');
      compCanvas.width = gifWidth;
      compCanvas.height = gifHeight;
      var compCtx = compCanvas.getContext('2d');

      // Temp canvas for patches
      var tempCanvas = document.createElement('canvas');
      var tempCtx = tempCanvas.getContext('2d');

      // Helper: composite a decoded frame onto compCanvas
      function compositeDecoded(decoded) {
        if (decoded.disposalType === 2) {
          compCtx.clearRect(0, 0, gifWidth, gifHeight);
        }
        var dims = decoded.dims;
        tempCanvas.width = dims.width;
        tempCanvas.height = dims.height;
        var imgData = tempCtx.createImageData(dims.width, dims.height);
        imgData.data.set(decoded.patch);
        tempCtx.putImageData(imgData, 0, 0);
        compCtx.drawImage(tempCanvas, dims.left, dims.top);
      }

      // ── Boundaries are baked at build time (BAKED_SLIDES). The viewer never detects. ──
      var slides = BAKED_SLIDES;
      var slideSnapshots = {}; // restFrame -> ImageData, filled lazily during the composite pass

      // Progressive sequential composite (GIF is do-not-dispose + partial-patch: no random access).
      // Composite frame-by-frame; cache the snapshot when we reach each slide's restFrame.
      var restFrameSet = {}; slides.forEach(function(s){ restFrameSet[s.restFrame] = true; });
      var compositedUpTo = -1;
      function ensureCompositedTo(targetFrame) {
        for (var i = compositedUpTo + 1; i <= targetFrame; i++) {
          var decoded = gifuct.decompressFrame(imageFrames[i], gct, true);
          if (decoded) compositeDecoded(decoded);
          if (restFrameSet[i]) slideSnapshots[i] = compCtx.getImageData(0, 0, gifWidth, gifHeight);
          compositedUpTo = i;
        }
      }

      // First paint: composite up to slide 1's restFrame, then background-fill the rest.
      if (!slides || slides.length === 0) {
        var noSlidesDiv = document.createElement('div');
        noSlidesDiv.style.cssText = 'display:flex;align-items:center;justify-content:center;height:100vh;font-family:system-ui,sans-serif;color:#e5e5e5;background:#0a0a0a;font-size:16px;';
        noSlidesDiv.textContent = 'No slides to display';
        document.body.appendChild(noSlidesDiv);
        return;
      }
      ensureCompositedTo(slides[0].restFrame);
      console.log('Loaded ' + slides.length + ' baked slides from ' + totalFrames + ' frames');
      (function backgroundFill(){
        if (compositedUpTo >= totalFrames - 1) return;
        // Pause while a transition is playing to avoid corrupting compCtx mid-animation.
        if (isPlaying) { setTimeout(backgroundFill, 16); return; }
        ensureCompositedTo(Math.min(totalFrames - 1, compositedUpTo + 60));
        setTimeout(backgroundFill, 0);
      })();

      return {
        slideSnapshots: slideSnapshots,
        ensureCompositedTo: ensureCompositedTo,
        slides: slides,
        width: gifWidth,
        height: gifHeight,
        frameDelay: frameDelay,
        // For lazy transition playback (re-decompress on demand):
        imageFrames: imageFrames,
        gct: gct,
        compositeDecoded: compositeDecoded,
        compCanvas: compCanvas,
        compCtx: compCtx
      };
    }

    // ── Viewer ──
    function initViewer() {
      document.getElementById('loading').style.display = 'none';
      document.getElementById('viewer').style.display = 'flex';
      // Reveal the canvas via a body class so CSS controls its display mode
      // (block when standalone, flex-centered when embedded in an iframe).
      document.body.classList.add('viewer-ready');

      var canvas = document.getElementById('slideCanvas');
      canvas.width = parsedData.width;
      canvas.height = parsedData.height;

      // Build dot strip
      var dotStrip = document.getElementById('dotStrip');
      dotStrip.innerHTML = '';
      if (slideMap.length > 1) {
        dotStrip.style.display = 'flex';
        for (var i = 0; i < slideMap.length; i++) {
          (function(idx) {
            var dot = document.createElement('button');
            dot.className = 'dot';
            dot.title = 'Slide ' + (idx + 1);
            dot.onclick = function() { jumpToSlide(idx); };
            dotStrip.appendChild(dot);
          })(i);
        }
      } else {
        dotStrip.style.display = 'none';
      }

      currentSlideIndex = 0;
      renderSlide(0);
      updateControls();
    }

    function renderSlide(index) {
      var canvas = document.getElementById('slideCanvas');
      var ctx = canvas.getContext('2d');
      var slide = slideMap[index];
      // Ensure frames up to this slide's restFrame have been composited (progressive fill).
      parsedData.ensureCompositedTo(slide.restFrame);
      var snapshot = parsedData.slideSnapshots[slide.restFrame];
      if (snapshot) {
        ctx.putImageData(snapshot, 0, 0);
      }
      currentSlideIndex = index;
      updateControls();
    }

    function updateControls() {
      document.getElementById('prevBtn').disabled = currentSlideIndex <= 0 || isPlaying;
      document.getElementById('nextBtn').disabled = currentSlideIndex >= slideMap.length - 1 || isPlaying;
      document.getElementById('slideCounter').textContent = (currentSlideIndex + 1) + ' of ' + slideMap.length;

      var dots = document.querySelectorAll('.dot');
      for (var i = 0; i < dots.length; i++) {
        if (i === currentSlideIndex) {
          dots[i].classList.add('active');
        } else {
          dots[i].classList.remove('active');
        }
      }
    }

    // ── Playback ──
    function playNext() {
      if (isPlaying || currentSlideIndex >= slideMap.length - 1) return;

      var nextSlide = slideMap[currentSlideIndex + 1];
      if (!nextSlide.transitionFrames) {
        renderSlide(currentSlideIndex + 1);
        return;
      }

      isPlaying = true;
      updateControls();

      // Restore compCanvas to current slide's settled snapshot
      var currentSlide = slideMap[currentSlideIndex];
      var snapshot = parsedData.slideSnapshots[currentSlide.restFrame];
      if (snapshot) {
        parsedData.compCtx.putImageData(snapshot, 0, 0);
      }

      var start = nextSlide.transitionFrames.start;
      var end = nextSlide.transitionFrames.end;
      var canvas = document.getElementById('slideCanvas');
      var ctx = canvas.getContext('2d');
      var frameIdx = start;

      function playFrame() {
        try {
          var decoded = gifuct.decompressFrame(parsedData.imageFrames[frameIdx], parsedData.gct, true);
          if (decoded) {
            parsedData.compositeDecoded(decoded);
          }
          ctx.clearRect(0, 0, canvas.width, canvas.height);
          ctx.drawImage(parsedData.compCanvas, 0, 0);
        } catch(e) {
          console.error('Transition frame ' + frameIdx + ' error:', e);
          isPlaying = false;
          renderSlide(currentSlideIndex + 1);
          return;
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

    function playPrev() {
      if (isPlaying || currentSlideIndex <= 0) return;
      renderSlide(currentSlideIndex - 1);
    }

    function jumpToSlide(index) {
      if (isPlaying) return;
      renderSlide(index);
    }

    // ── Wire buttons and keyboard ──
    document.getElementById('nextBtn').onclick = playNext;
    document.getElementById('prevBtn').onclick = playPrev;

    document.addEventListener('keydown', function(e) {
      if (e.key === 'ArrowRight') playNext();
      if (e.key === 'ArrowLeft') playPrev();
    });

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
      if (Math.abs(dx) > SWIPE_THRESHOLD && Math.abs(dx) > Math.abs(dy) * 1.5) {
        if (dx < 0) playNext();
        else playPrev();
      }
    }, { passive: true });
  </script>

</body>
</html>`
}
