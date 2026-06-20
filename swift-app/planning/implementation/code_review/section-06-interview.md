# Section 06 — Review Triage + Interview

No items required user decision. Resolved as auto-fix or let-go.

## AUTO-FIX (applied)
- **IMPORTANT-1**: Softened the temp-dir cleanup comment — `defer` covers throw + normal return; an un-cooperative cancellation may bypass it (OS reaps `itemReplacementDirectory` regardless). No longer claims full cancellation-safety.
- **IMPORTANT-3**: Added test `emptyTokenFailsClearly` covering the no-token branch (throws GifDeployError without touching the network seams).
- **NIT-4**: Strengthened `emitsProgressSteps` to assert the FIRST progress id is 12 (ensure project) and the LAST is 16 (complete), i.e. project-step precedes completion.

## LET GO (with rationale)
- **IMPORTANT-2** (unlogged cleanup): the repo has NO logging infrastructure (no os.Logger anywhere in Sources/); `itemReplacementDirectory` lives under the user temp domain and is OS-reclaimed; best-effort `try?` cleanup is the idiomatic Swift pattern. Adding os.Logger for one line would introduce an inconsistent pattern for marginal benefit.
- **IMPORTANT-3 (error semantics)**: `GifDeployError` (owned by section-01) has no clean config/precondition case; `vercelDeployFailed` is the closest existing surface and the Section-07 view pre-checks the token anyway. Adding a new enum case is out of scope for this section. Kept the mapping; added the test instead.
- **NIT-5**: `@unchecked Sendable Box` is safe for these deterministic same-task stubs; flagged so the pattern isn't copied into a concurrent context.
- **NIT-7**: plan-sanctioned nil fallback; noted in the section doc that Section 07 should treat the returned URL as best-effort when resolution fails.
