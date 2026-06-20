# Section 05 — Review Triage + Interview

No items required user decision (no real tradeoffs / security calls for Edward). All resolved as auto-fix or let-go.

## AUTO-FIX (applied)
- **IMPORTANT-1**: Replaced 4 chained `replacingOccurrences` with a SINGLE-PASS scanner (`fill(_:_:)`) that never rescans injected values. This both fixes the latent parity bug AND tightens GATE-1. Added test `filenameWithBracesNotReprocessed` (a `{{BAKED_SLIDES}}.gif` filename survives verbatim, matching Electron's single-interpolation behavior).
- **IMPORTANT-2**: Reworded the XSS WARNING comment — gifFilename is "trusted because app-controlled (a validated `.gif` name)", NOT safe-by-nature; escaping would break GATE-1; upstream validation is the right guard.
- **NIT-4**: Added test `bakedSlidesLargeAndNegative` asserting JSON.stringify parity for a negative restFrame (-5) and a large holdEnd (9999999999).

## LET GO
- **NIT-3 (fatalError)**: Section signature is non-throwing `-> String`; the template is a build-time-guaranteed bundled resource; fatalError with a clear packaging-error message is consistent and documented. Not changed.
- **NIT-5 (single-slide/large-N coverage)**: comma-join is trivially correct; NIT-4 already adds a non-trivial-value case. Not changed.
