# Section 07 — Code Review (deep-implement:code-reviewer)

Concurrency VERDICT: PASS. `runPipeline` is `nonisolated async` → runs off the global executor (off-main) per SE-0338; the View's `Task{}` inherits @MainActor for UI mutation. Cancellation propagates (GridSampler checks at loop top). `@unchecked Sendable PipelineOutput` ferrying `[Int:CGImage]` = no real race (built once off-main, read-only on main). No critical issues. All 7 hard requirements met.

## Findings
- **IMPORTANT-1** — re-selection double-state-mutation is PREVENTED but fragile; relies on cancelled task re-checking before its MainActor.run.
- **IMPORTANT-2** — `frames(at:)` thumbnail pass has NO cancellation check mid-decode; a Cancel during it won't abort until the whole pass finishes (meaningful for large decks).
- **CAVEAT** — off-main + Cancel-promptness are correct-by-reading but the mandatory runtime/Peekaboo gate has NOT been run (no TEST_GIF). Per repo CLAUDE.md, "done" needs the live run.
- NIT-3 — NSOpenPanel restricted to [.gif] but drop UTI is [.fileURL] (validated in accept()); minor inconsistency.
- NIT-9 — processing phase has no Cancel (deploy Task not retained); plan made this optional.
- NIT-10 — resetToSelect doesn't reset secureEmbed; self-heals (accept() re-reads from settings).
- PASS confirmations: history fields (folderPath==gifPath, fixesApplied==0, slideCount==count), confirm renders exactly slides.count thumbnails + seed note, CancellationError not treated as error, userMessage mapping, retry routing.
