# GIF Viewer — Responsive Embed Solution (Framer portal)

Branch: `fix/gif-viewer-iframe-resize`. All changes are in
`electron/gifViewerGenerator.ts` (the generator that emits the deployed viewer
HTML). Nothing else in the app changed.

## Problem
The deployed GIF slide viewer did not resize inside a Framer **Embed** (iframe):
it capped at `max-width:1080px`, top-aligned, rendered tiny / cut off, and
painted a black letterbox over the host site. The HTML (Keynote) deploy was
always fine — it fills `100vw/100vh` and self-resizes; only the GIF path needed
work.

## Fix (all inside the `body.in-iframe` CSS + a little JS, gated to iframe mode)
Added when `window.self !== window.top` (class `in-iframe`); standalone view
unchanged.

1. **Fill the box** — `body.in-iframe` fills `100vh`, `overflow:hidden`,
   `justify-content: safe center` (the `safe` keyword prevents top-clipping when
   content is taller than the viewport — clipping the top of a deck is
   unrecoverable).
2. **Canvas fills its container** — `#slideCanvas { width:100%; height:100%;
   object-fit:contain }` inside a `flex:1 1 auto; min-height:0` container. This
   is what makes the deck scale UP. `width/height:auto + max-height` pins a
   `<canvas>` to its intrinsic px and collapses to min-content in a flex-shrunk
   parent (the deck rendered tiny in Framer).
3. **Cap at native width** — at init (JS), `canvasContainer.style.maxWidth =
   parsedData.width + 'px'`. Deck never upscales past the GIF's real resolution
   (stays crisp); host site shows through the margins beyond native width.
4. **Never cut off** — `object-fit:contain` guarantees the whole deck shows
   (letterboxed, never cropped).
5. **Transparent** — `body.in-iframe { background: transparent }` +
   `#slideCanvas { background: transparent }` + a transparent loading overlay
   (the default `rgba(10,10,10,0.92)` would flash a black sheet over the host
   site during GIF parse). The site background shows through the letterbox.
6. **Controls scale with embed width** via `clamp(vw)` — scoped to
   `.controls-row button` so the dot `<button>`s in `#dotStrip` don't get
   pilled. `row-gap` on the dot strip for wrapped rows.
7. **Auto-fit height reporting** (`postMessage`) — the viewer reports its ideal
   height (`{type:'kd-viewer-height', height}`) on load + resize. A host that
   listens can size the iframe to the deck (no slack). Robust via a
   `ResizeObserver` on `document.documentElement` + delayed re-reports
   (250/700/1500ms) because the host sizes the iframe AFTER first paint.

Gotcha learned: **never put backticks in CSS comments inside the HTML template
literal** — a stray `` ` `` terminates the JS template string.

## Framer architecture decision (IMPORTANT)
The production portal is the CMS detail page `/ils-clients/:Airtable`. Its viewer
is a **native Framer Embed whose URL is CMS-bound to the `Deck URL` field**
(synced from Airtable/CRM, per client). The SAME embed must render either an
HTML deck or a GIF deck depending on what `Deck URL` points to.

- **No custom code is needed for the portal.** Native Embeds render a fixed-size
  iframe; both the HTML viewer and (now) the GIF viewer fill that box. The GIF
  changes above make it behave like the HTML deck there: fills, contains, never
  cut off, transparent letterbox.
- The **DeckEmbed code component** (created on the `/test` page, branch
  `golden-ridge`) was only a sandbox experiment for "zero-slack auto-fit" via the
  postMessage host. It cannot be used on the portal anyway (URL is CMS-bound) and
  is not needed. `/test` should be reverted to a native Embed.
- Tradeoff vs the code component: in a native Embed, a deck whose aspect ≠ the
  embed box gets transparent letterbox slack (never cropped) — exactly how the
  HTML deck behaves there today. Consistent.

## Rollout
1. Merge `fix/gif-viewer-iframe-resize` → main, **rebuild the Electron app,
   reinstall**. New GIF deploys then carry the fix.
2. **Existing live GIF decks have OLD HTML baked in → re-deploy through the
   updated app** to get the fix. HTML decks unaffected.
3. **Swift parity**: the `feat/gif-deploy-swift` port must mirror this CSS/JS in
   its bundled viewer HTML, or Swift GIF deploys won't be responsive.

## Verification done
- Local iframe harnesses: wide (1200×520), tall (560×680), iPhone 390, iPad 820,
  full-window resize, auto-fit host (reported 890px, filled) — all fill + center
  + no distortion + transparent letterbox.
- Live Framer branch-preview `/test` with the DeckEmbed component: deck filled
  the embed near edge-to-edge, controls hugging, capped native width.
- Test decks deployed (manual, from branch code): `kd-deploy.vercel.app` (4:3),
  `kd-deploy16.vercel.app` (1920×1080 6-slide), plus the real ILS Quals deck.

Note: the Framer EDITOR canvas does NOT run a cross-origin iframe's resize loop —
it shows the deck small. Only the PUBLISHED/preview page runs it. Verify there.
