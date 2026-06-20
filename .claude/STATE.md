# Session State

**Last updated:** 2026-06-20
**Goal:** Ship Swift video deck-deploy parity, harden, sunset Electron, release.
**Plan:** swift-app/planning/specs/swift-video-parity/ (deep-implement, 9/9 done)

## Current Task
**What:** Video deck-deploy feature + Projects-tab management + Electron sunset + 1.1.2 release.
**Status:** COMPLETE + shipped. Repo is Swift-only. 66/66 tests green.
**Key files:** swift-app/Sources/{Services/Video*,Views/VideoDeployView.swift,Views/ProjectsView.swift}

## Context (for next session)
- Swift is the SOLE app — Electron deleted (src/, electron/, Vite); recover from git history if ever needed.
- v1.1.2 notarized + released (app icon added) (Developer-ID/Sparkle/GitHub); DMG in 03_Custom Apps/KeynoteDeployer/; installed at /Applications/Custom/KeynoteDeployer.app.
- Version source = project.yml `info.properties` (xcodegen bakes Info.plist) — NOT MARKETING_VERSION alone.
- Live-gate + /grill caught all the real bugs (fps divergence, AVKit VideoPlayer macOS-26 crash, rest-frame bias, one-shot preset) — see CLAUDE.md lessons + feedback_swift-video-deploy-livegate-sunset.md.

## Next Step
DECIDED 2026-06-20: stay Developer-ID/Sparkle (option A). App Store/TestFlight is architecturally blocked — the ASC record DOES exist (KeynoteDeployer, Apple ID 6760954499, bundle com.imaginelabstudios.keynote-deployer), but macOS App Store requires the App Sandbox, which forbids this app's `vercel` CLI shell-out + arbitrary file access. Going App Store = a re-architecture project (Vercel REST deployments API + sandbox + security-scoped bookmarks + Apple Distribution signing), NOT an upload. Nothing pending — v1.1.2 shipped (with app icon).

## Verification Goals
- [x] 66/66 tests green, Swift 6 clean
- [x] v1.1.2 notarized, Gatekeeper-clean, on GitHub Releases + Sparkle appcast
- [x] Electron removed, Swift builds self-contained
- [ ] (Optional) TestFlight/App Store setup if desired
