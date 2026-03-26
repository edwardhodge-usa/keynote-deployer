# Session State

**Last updated:** 2026-03-25 22:15
**Goal:** Fix GIF viewer iPhone crash + make Framer embeds responsive
**Plan:** None active

## Current Task
**What:** Both backlog items completed and released
**Status:** Completed — Electron v1.0.4 + Swift v1.0.3 released

## Context (for next session)
- GIF viewer uses per-frame `decompressFrame()` with scaled 32x18 diff sampling — never bulk decode
- Framer embed code now includes `aspect-ratio` wrapper div (16:9 for Keynote HTML, GIF native for GIF deploys)
- GIF viewer hides chrome (header/footer/keyboard hint) when loaded in an iframe
- Sparkle.xcconfig is now committed (was gitignored) — only contains public values
- Xcode had IDESimulatorFoundation plugin issue, fixed with `xcodebuild -runFirstLaunch`

## Next Step
Backlog is empty. Check for new feature requests or move to another project.
