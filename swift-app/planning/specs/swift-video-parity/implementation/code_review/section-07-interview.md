# Section-07 Review Interview — VideoDeployer

## User decisions
1. **Progress-step contamination (Important #1)** → **Remap in live seam.** The `.live`
   seam wraps the onProgress it hands to `VercelDeployer.deploy` so the emitted
   `id:13` steps re-emit as `id:4` detail/status updates — the 4-step contract holds
   regardless of the View. Deploy-seam throws also surface as `id:4 .error`.
2. **Redundant double-probe (Important #2)** → **Remove the standalone probe.** Let
   `VideoTimestampDeriver.derive` be the single probe site (it rejects VFR/corrupt
   before any sampling). Saves a probe per deploy — an `ffprobe` subprocess on the
   ffmpeg path. Documented as a spec deviation in the section doc.

## Auto-fixes (no input needed)
- **Minor #4** — deploy-seam throw now emits `id:4 .error` before rethrowing (was
  stuck `.active`). Folded into the remap work.
- **Minor #3** — added a test: deploy-seam throw cleans the temp dir AND emits the
  Step 4 `.error` (proves the late-throw defer path + the #4 fix).
- **Nitpick #7** — removed the unused `flag` parameter from `makeStub`.

## Let go
- **Minor #5** (cosmetic late-tick) — not reachable given derive's await structure.
- **Minor #6** (temp-dir `-uuid8` suffix) — an improvement (collision-safe); keep.
- **Nitpick #8** (live success-guard + URL fallback untested) — requires a real
  VercelAPI/network; out of scope for the offline test suite. Noted.
