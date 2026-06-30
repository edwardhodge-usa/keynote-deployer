# Integration Notes — Gemini Review (iteration 1)

Gemini (gemini-2.5-pro) called the plan "exemplary," all points refinements. Verdicts below.

## Integrating

1. **First/last slide boundaries** (real gap). Plan only defined transitions BETWEEN slides. Add explicit
   rule: slide-0 `holdStart` = settled frame in `[0, transitions[0].start]`; last slide `holdEnd` =
   `frameCount - 1`. → Plan §7.3.

2. **Low-confidence anchor flag** (real). A wildly-wrong DP anchor could snap into the wrong hold. Add: when
   the anchor-to-hold distance exceeds a threshold (seconds), flag "low-confidence match" in the harness
   report — signals StillsMatch (not BoundaryDetector) as the root cause. → Plan §7.3 + harness diagnostic.

3. **Dark slide vs fade-to-black** (real). A legitimately black slide also has near-zero variance. Distinguish
   TRANSIENT variance dip (transition) from SUSTAINED low variance (real hold) via duration ≥ minHoldSeconds.
   → Plan §7.2.3.

4. **Local-ratio window as fps-relative** (fair). Replace the magic `window=2` with `max(2, Int(fps/15))` and
   note sensitivity is checked in Phase 0/early Phase 3. → Plan §7.1.

5. **Parameter Tuning Strategy** (real). The plan trades 2 bad constants for several better ones; must state
   they are validated ONCE across the 3 archetype decks via the harness then hard-coded as GLOBAL constants —
   not per-deck knobs (the anti-overfit promise). Channel weights `(1,1,1)` fall under this. → New Plan §9.5.

6. **Memory for long videos** (real risk). `sampleGrids → [[Double]]` loads all grids (~42MB/min → ~2.5GB/hr).
   Decks are short (minutes) so not blocking, but add a documented limitation + a guard that warns/fails
   gracefully past ~20 min. Streaming/AsyncSequence refactor stays out of scope. → Plan §11.

7. **Off-main + cancellable NFR** (real). Make explicit: the whole seed pipeline runs off the main thread and
   is cancellable (document close / new import). → Plan §11 (new NFR).

8. **Grid value range note** (trivial). Document `GridSampler.sample` returns raw RGB `0.0...255.0`, no
   normalization, since the signal formulas assume that range. → Plan §2.

9. **Path-traversal note in harness** (minor). Construct report output paths via `URL` APIs; mind `deckName`
   in filenames. → Plan §4.1 impl note.

## Integrating as OPTIONAL / deferred

10. **One-time "we re-seeded your markers" UI notice.** Genuinely good UX, but touches the editor UI that the
    interview scoped OUT, and is non-essential to accuracy. Note it as an optional follow-up (a non-blocking
    toast tracked in UserDefaults), not a required section. → Plan §5.1 note.

## Not changing
- Gemini's streaming-pipeline refactor — correctly self-identified as out of scope; documented as a known
  limitation instead. The DP-match-as-count-authority and the overall phase structure stand unchanged.
