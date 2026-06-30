# Section 01 — Code Review Triage

Reviewer: deep-implement code-reviewer. No Critical findings (path guard sound, integer
clamping safe). Triage below — all auto-fixed (clear improvements, no user tradeoffs).

## MAJOR GROUND-TRUTH FINDING (surfaced, carried forward — not a section-01 code bug)
With `StillsMatch` producing strictly-increasing anchors AND the current `HoldDetector`
clamping each `holdEnd` to `nextAnchor-1 < next holdStart`, **markCount == slideCount is
structurally guaranteed** on every valid pipeline run. The "two stills → same frame → dedup"
count-loss the spec/research assumed is UNREACHABLE; the overlap-drop never fires either.
→ Edward's "wrong COUNT" symptom is therefore almost certainly **MarkStore shadowing**
(stale saved marks from a prior algo/edit), which section-02's algorithmVersion key fixes —
NOT an algorithmic count-loss. Recorded for section-07 (never drop a mark) and section-08
(the count regression test should assert the structural guarantee, not a reproduced drop).

## Auto-fixed
- **Important 1 — mislabeled count signal.** Relabeled `anchorCollidedWithPrevious` doc as an
  invariant guard (unreachable while StillsMatch is monotonic). Added an honest `markReused`
  flag set when a slide's anchor has no own mark (markByStart miss → borrowed a neighbor's
  mark), so a borrowed Rest/Go is visibly flagged. Header COUNT-MISMATCH branch kept (harmless).
- **Important 2 — lowConfidence disabled on fade decks.** The absolute `localMax > 1.0` floor
  disabled the flag exactly on dark-fade decks (the target). Rescaled to the deck's GLOBAL diff
  distribution (fraction of global max) instead of an absolute unit.
- **Minor 1 — ASCII bars uncalibrated.** Now prints the absolute max alongside the bars.
- **Minor 2 — writeThumb returned a path to a maybe-unwritten file.** Returns "" when no PNG.
- **Minor 3 — asciiBars zero-branch inconsistency** + **Nitpick** `Data(html().utf8)` (dropped `!`).

## Deferred (runtime / Edward-provided, documented)
- **Important 3 — captured fade-deck fixture + harness-triage.md.** Added a synthetic fixture
  factory (`Tests/Fixtures/SeedFixtures.swift`: clean-cut / cross-fade-on-dark / build sequences)
  so sections 03–08 have offline fixtures. The CAPTURED real-fade-deck grids + `harness-triage.md`
  require running `kd-seed-harness` on the real iCloud deck — a runtime step (the harness binary
  is built and ready). Flagged for the live pass; the real deck is the accuracy oracle per the spec.

## Let go
- Symlink-in-outputDir traversal (resolvingSymlinksInPath) — low risk for a local diagnostic tool.
- Dedup the file-private `subscript(safe:)` helper; guard-let the always-valid sRGB colorspace.
