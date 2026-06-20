# Section 03 — Code Review (code-reviewer subagent)

## Important
1. **jsNumber `String(Int(x))` can trap** (VideoViewerGenerator.swift, integer branch).
   `Int(Double)` crashes on integer-valued doubles outside Int range. Goldens (max 12) never exercise it. A parity helper must not become a fatal trap on unanticipated upstream input.
   → Fix: format integer branch without Int bridging (`String(format: "%.0f", x)`).
2. **jsNumber sub-millisecond / >3-decimal divergence.** Hard-codes `%.3f`; JS does shortest-round-trip. For values <0.0005s Swift emits "0" while JS emits e.g. "0.0001". Correct-by-contract (plan bounds inputs to 3-decimal/ms), but the section-03↔section-06 contract is asserted nowhere.
   → Fix: add a contract-bounded parity test (0.001, 0.1, large integer) to lock jsNumber behavior.
3. **Test golden loading via `#filePath` is fragile + inconsistent.** Goldens are ALSO bundled into the test target Resources (pbxproj) yet the test loads them off disk via compile-time absolute path → breaks if build relocated/CI; bundled copies are dead weight.
   → Fix: load goldens from the test bundle (anchor class) and drop #filePath.

## Nit / correct-by-design
4. fatalError-on-missing-template — sanctioned by plan; correct.
5. Single-pass token fill — correct; VIDEO_FILENAME replaced first so the (absurd) `{{VW}}.mp4` filename hazard is moot for bare filenames. No change.
6. Swift 6 concurrency — pure enum/static, trivially Sendable. Correct.
7. Empty secure-token blank-line bytes — captured by goldens, pass. Correct.

## Done-When
Met for golden inputs. Findings 1 (crash guard) recommended before merge; 2–3 for cross-checkout/CI robustness.
