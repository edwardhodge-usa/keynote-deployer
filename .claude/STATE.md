# Session State

**Last updated:** 2026-06-30 23:20
**Goal:** Validate the rebuilt seed live on a real deck, then audit/clean the backlog.
**Plan:** docs/superpowers/specs/freeze-marker-accuracy/ (shipped v1.3.5)

## Current Task
**What:** Seed validated LIVE + secure-embed second-opinion + full backlog audit + MarkStore test isolation.
**Status:** COMPLETE. main @ 534e824 (all pushed). 131 tests green.

## Context (for next session)
- **Seed CLOSED on the hard archetype:** real ILS Quals deck (fade-on-dark) → app Analyze 39/39, Rests settled, Encode & Deploy → functions on Safari + iPhone. Deployed `ilsquals-2026-v3` (client-facing, secure-embed ON). Edward wires the Deck URL via the CRM app himself.
- **Secure-embed reality (Gemini /second-opinion):** "Secured" = friction only; raw `/deck.mp4` is public+auth-less. The `frame-ancestors` CSP (blocks re-hosting) is the one real control, already active. Two enhancements logged (P2 Sec-Fetch 403 + rename→"Protected Embed"; P3 screen-record = DRM-only, won't-build). Proportionate for a sales deck as-is.
- **MarkStore tests** now use a per-test temp dir via `nonisolated(unsafe) storeDirectoryOverride` + `.serialized` suite (killed the shared-store cold-start flake).
- App-window-on-another-Space blocks Peekaboo/SCK (clicks + full screenshots time out); `screencapture -l<id>` pixel reads still work — drove the whole eyeball via Edward's manual screenshots.

## Next Step
Two Open items are BLOCKED on Edward, not on code: (1) seed param-lock needs a clean-cut + a build-heavy real deck (movie + stills) run through the app; (2) App Store/TestFlight is its own `/plan` (sandbox vs Vercel CLI). Also: `~/CLAUDE.md` is 108KB → due for an archive pass (trim older-than-30-day lessons to the vault).

## Verification Goals
- [x] Adaptive seed validated live on the real ILS Quals deck (Safari + iPhone)
- [x] MarkStore tests isolated to temp dir — 131 green
- [x] Backlog audited: 5 redundant removed, done items completed, blockers named
- [ ] Seed params formally locked across ≥2 more real archetypes (needs Edward's decks)
- [ ] App Store/TestFlight migration (own /plan)

## Open follow-ups (Edward)
- Supply a clean-cut + build-heavy deck to finish the seed param-lock (optional).
- Deck URL for ilsquals-2026-v3 → set via CRM app (Client Pages → Deck URL).
- `~/CLAUDE.md` archive pass (108KB, past the 40KB warn threshold).
