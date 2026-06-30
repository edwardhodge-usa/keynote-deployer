# Interview Transcript

**Q1. Scope / appetite.**
A: **Harness first, then full upgrade.** Build the measurement harness, rule the MarkStore
shadowing + count bug in/out, then replace fixed thresholds with the adaptive multi-channel +
twin-comparison + settled-frame algorithm.

**Q2. Saved marks on algorithm change.**
A: **Auto re-seed with the new algorithm.** Add an algorithm-version tag to the MarkStore key so a
new algo always shows the fresh seed; old hand-edits are preserved under the old version key but not
shown. This is also the direct fix for the shadowing culprit.

**Q3. Test decks.**
A: **All three archetypes** — fade-on-dark (ILS Quals, already available), a clean-cut deck, and a
build-heavy deck. (Edward will provide/export the clean-cut and build-heavy decks.) Explicitly avoid
re-overfitting to the single fade deck.

**Q4. Accuracy oracle.**
A: **Edward eyeballs the seed in the timeline editor + the final iPhone cross-origin-iframe gate.**
Human is the oracle. → Implication: the harness output should be VISUAL (per-slide montage of the
seeded Rest/Go frames) so eyeballing is fast and unambiguous, not just a numeric dump.

## Derived decisions (planner defaults, not separately asked)
- The new algorithm **replaces** the fixed-threshold path; the verbatim-anchor Rest is retired, not
  kept as a toggle (Edward wants it fixed, not optional).
- Keep compute bounded: multi-channel score + ratio run on the existing 32×18 grid; variance-of-
  Laplacian for REST sharpness may sample a higher-res crop only for the few REST CANDIDATE frames.
- Build phase: implement via deep-implement (TDD sections). A /workflow can fan out the 3-deck
  measurement + an adversarial review of the algorithm change (Edward invited "/workflow as needed").
