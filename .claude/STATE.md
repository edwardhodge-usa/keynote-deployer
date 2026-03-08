# Session State

**Last updated:** 2026-03-08 evening
**Goal:** Fix 404 URL bug, filter projects, full HIG compliance pass, UI redesign
**Plan:** None

## Current Task
**What:** Complete HIG overhaul + URL fix + Projects redesign + build + ship
**Status:** Completed — committed, pushed, built, deployed to /Applications/Custom/

## Context (for next session)
- Vercel truncates long subdomains — app now reads `targets.production.alias` from API
- Projects view filtered by cross-referencing with local `history.json`
- ILS typography override applied: 15px body, 13px supporting, 11px captions
- Projects view has inline iframe preview thumbnails (120x75, scaled from 1024x640)
- Pre-existing TS6305 error (composite build artifact) — doesn't affect Vite build

## Next Step
Bump version to 1.1.0 and create a GitHub Release with `/release` if auto-updater distribution is desired.

## Verification Goals
- [x] URLs in app match Vercel dashboard URLs
- [x] Projects view only shows Keynote Deployer projects
- [x] HIG violation checklist passes (Section 13)
- [x] Build succeeds and .app copied to /Applications/Custom/
- [x] All changes committed and pushed to GitHub
