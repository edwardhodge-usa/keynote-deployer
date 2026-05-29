# Session State

**Last updated:** 2026-04-21
**Goal:** Restore app to working state after token expiry
**Plan:** None

## Current Task
**What:** Vercel token expired, app reinstalled to correct location
**Status:** Completed

## Context (for next session)
- v1.0.6 Electron + v1.0.4 Swift — both current, no code changes needed
- Vercel token renewed (vcp_...) — written to settings.json, team-scoped
- App installed at /Applications/Custom/Keynote Deployer.app (was running old v1.0.2 from project folder)
- Auto-Detect re-reads the CLI token which was also expired — always paste manually
- Quit app before manually editing settings.json (running app overwrites with in-memory state)

## Next Step
Pick next feature: Airtable portal integration is fully spec'd in vault (keynote-deployer.md → FUTURE section) — ~2-3 hrs, eliminates the manual /portal-deck step after every deploy.

## Verification Goals
- [x] Token valid — 200 on /v9/projects team endpoint
- [x] App at v1.0.6 in /Applications/Custom/
