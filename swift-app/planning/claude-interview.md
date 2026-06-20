# Interview Transcript — GIF Deploy Swift Port

Date: 2026-06-19. Decisions informed by the staged spec (already had §6 LOCKED decisions) + the research findings (esp. the inverted compositor risk).

## Round 1 — Research scope
- **Codebase research?** → **Yes, full read.** Read canonical Electron source AND the Swift reuse seam to verify "reuse as-is" claims.
- **Web/docs research?** → **Yes, targeted ImageIO disposal check.** De-risk the TOP RISK before planning.

## Round 2 — Core plan decisions
1. **GifCompositor vs ImageIO auto-composite** → **Gate-0 spike, then drop.**
   - Plan a ~30-min Phase-1 spike: decode frame 0 + a late frame N from a real deck GIF via `CGImageSourceCreateImageAtIndex`; eyeball full-slide vs partial patch.
   - If confirmed (research's expected outcome): **drop `GifCompositor` entirely**; the sampler reads ImageIO full frames directly.
   - Keep the disposal-correct compositor ONLY as a documented fallback branch if the spike shows patches.
2. **Scope** → **Phase 1 only.** Reaches "GIF Deploy exists in Swift." Phases 2 (Stills) and 3 (Manual editor) become separate later deep-plans once Phase 1 ships.
3. **Test framework** → **Swift Testing** (`@Test`/`#expect`), greenfield test target (swift-app has none today).
4. **In-app preview** → **Static `restFrame` thumbnails** (one composited CGImage per detected slide). The deployed viewer is the real product; live playback deferred.

## Round 3 — Scope clarifications
5. **Shared viewer template asset (decision #2)** → **Extract asset + Swift emits it; defer the Electron refactor.**
   - Create the canonical placeholder HTML/JS asset (`{{GIF_FILENAME}}` / `{{BAKED_SLIDES}}` / `{{SECURE_EMBED}}`).
   - Swift emits it; **Phase-1 gate = byte-identical output vs the CURRENT Electron-generated viewer** for the same inputs.
   - Refactoring `gifViewerGenerator.ts` to consume the shared asset = separate later task (keeps the shipping Electron app untouched now).
6. **Test GIF fixture** → **Edward will provide a path.** A real exported deck GIF (e.g. 39-slide ILS Quals or 22-slide DUB FDY). Plan references it as `TEST_GIF` for both gates; Edward supplies the actual path at /deep-implement time.

## Derived constraints carried into the plan
- Auto adaptive-median factor is **0.33**, not 0.5 (real code).
- Auto thresholds: QUIET_THRESHOLD 0.3, MIN_QUIET_RUN 8, TRANSITION_PEAK 0.5.
- Sampler: 1000 points → 32×32 grid, RGB only, mean-abs-diff.
- CSP/secure-embed lives in the deployer/`vercel.json`, NOT the viewer HTML.
- Forward-iterate frames 0→N once with caching (do-not-dispose ⇒ not O(1) random access).
- Reuse `VercelDeployer.deploy`, `VercelAPI.ensureProject`, `HistoryEntry` (no migration), `AppSettings`, `NavigationTab` (+`case gifDeploy`), `DeployView.Phase` shape, NSOpenPanel pattern — all verified present.
