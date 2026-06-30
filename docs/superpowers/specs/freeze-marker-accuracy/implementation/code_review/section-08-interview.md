# Section 08 — Review (self-review + LIVE harness run on real video)

The big §08 work was the LIVE run, which caught a real harness bug + proved the structural
guarantees end-to-end:

## Live-run finding (caught what unit tests couldn't)
- The §01 harness mapped anchor→mark by holdStart, but the new detector's holdStart = the Rest
  (≠ anchor) → mis-mapping produced bogus zero-length holds + wrong flags in the FIRST report.
  Fixed: harness now consumes HoldDetector.detectDetailed (marks + flags 1:1 with anchors).
  Also threaded the REAL probed fps (was default 30) so min-hold/far-threshold are deck-correct.
- Re-run result: 10/10 count, strictly increasing, all isValid; 8/10 real holds; 2 zero-length on
  tightly-spaced anchors; 8/10 lowConf (anchors on trailing/transition frames). See harness-triage.md.

## Regression guard
SeedRegressionTests (3 tests × 3 archetypes): count==anchors, isValid, Rest-never-inside-transition.
Locks the invariants offline so future timeline-editor work can't silently regress the seed.

## Held (Edward's manual gate — per the plan)
Parameter lock + visual eyeball + iPhone cross-origin-iframe gate on the REAL deck. NOT tuning to the
single synthetic test deck (re-overfit trap). 129/129 green; Release build pending.
