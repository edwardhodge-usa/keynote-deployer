# Section 02 — Code Review Triage & Fixes

Reviewer verdict: DP port faithful; both load-bearing comparisons preserved
(`<=` prior-frame sweep at StillsMatch.swift, strict `<` end-state scan). No
Critical issues. Swift 6 strict-concurrency clean (stateless enums). meanAbs
faithful to TS.

No items required a user-decision (no real tradeoffs / security). All resolved
as auto-fix or let-go.

## Findings

### #1 (Important) — M<N throw is a behavioral divergence; TS caller softens
- **Triage:** In-spec — the section plan explicitly allowed "clamp OR throw". The
  real risk is integration-level: the live TS consumer (`GifViewer.tsx`
  non-monotonic fallback) treats a bad match as a soft warning (clear slides,
  fall back to `auto`), not a hard failure. Section 06 (`VideoTimestampDeriver`)
  must catch + degrade, else it's a parity regression.
- **Fix (auto):** Added an `- Important:` doc-comment on `matchStillsToFrames`
  spelling out the caller contract (catch the throw, degrade gracefully, mirror
  the GifViewer fallback). Surfaces when Section 06 is implemented.

### #2 (Important) — backtrack could trap on a -1 pointer
- **Triage:** Analyzed as structurally unreachable under the `M>=N` guard: a
  finite `dp[N-1][endF]` guarantees an all-≥0 back-chain (a dp entry is only
  finite when assigned a ≥0 back-pointer; row 0's -1 is consumed last and
  discarded). Reviewer's "degenerate ties" concern doesn't apply — chain
  validity is structural, independent of cost values. But a defensive guard is
  cheap insurance against future refactors and makes the invariant explicit.
- **Fix (auto):** Added `guard f >= 0 else { throw .noValidAssignment }` at the
  top of the backtrack loop + a new `StillsMatchError.noValidAssignment` case.
  No test added — the branch is unreachable for valid `M>=N` input (cannot be
  constructed), so it is a documented defensive invariant only.

### #3 (Minor) — naturalSort `.numeric` weaker than TS key on exotic names
- **Triage:** `.numeric` and the TS `padStart(10)` key trivially agree on the
  uniform `slide-0NN.jpeg` names that real decks produce; they could diverge on
  multi-digit-run / leading-zero exotic names the test set doesn't cover. Real
  slide names are uniform.
- **Resolution:** Let go. Already documented in the doc-comment (A10 fallback to
  a TS-key port if `.numeric` ever diverges). Not claiming general TS-parity for
  naturalSort beyond the uniform set.

### #4 (Minor) — GridSampler `premultipliedLast` scales RGB if alpha < 255
- **Triage:** Opaque stills/frames make this a no-op today, but `.noneSkipLast`
  is the premultiply-free, more faithful choice (matches the Electron canvas
  read) and the section plan explicitly offered it. Cheap correctness hygiene.
- **Fix (auto):** Switched the GridSampler context bitmapInfo from
  `.premultipliedLast` to `.noneSkipLast`.

### #5 (Minor) — GridSampler nil-context returns silent all-zero grid
- **Triage:** Context creation with fixed valid sRGB 32×18 params won't
  realistically fail. The `sample` signature is non-throwing per the section
  spec (Section 04 callers depend on it). A silent all-zero grid is a degenerate
  but unreachable path.
- **Resolution:** Let go. Keeping the non-throwing signature; the fallback path
  is effectively dead code for the fixed params.

## Post-fix verification
Re-ran the full suite after applying #1, #2, #4 — all 21 tests pass (exit 0).
