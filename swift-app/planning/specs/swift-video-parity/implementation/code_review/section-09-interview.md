# Section-09 Review Interview — hardening pass

No user interview needed for the code fixes — C1 is an unambiguous ship-blocker and the
fix is the correct engineering resolution (one authoritative fps through the pipeline).
All applied as auto-fixes; accepted/deferred items documented in section-09-review.md.

## Auto-fixed
- **C1** (ship-blocker): single authoritative fps — `encodeWithKeyframes(..., fps:)`,
  AVFoundation uses it, `VideoDeployer` passes `analysis.fps`, View defaults the fps field
  to the probed rate. + regression test `encodeHonorsPassedFpsNotTrackRate`.
- **I4**: `StillsMatchError: LocalizedError` (actionable messages).

## Accepted (parity / low-risk / API-bound) — see review for rationale
- I1 (vercel.app fallback URL) — parity with HTML DeployView.
- I2 (secureEmbed + empty domains) — shared with HTML path; safe non-empty default.
- I3 (naturalSort on paths) — shared-prefix folder makes it correct in practice.
- C3 (finishWriting not cancellable) — AVFoundation API limitation; cancel works between frames.

## BLOCKING — handed to Edward (ship steps, need sign-in / human eyeball)
- **Step 5 live quality gate (A7)** — deploy the real 39-slide ILS Quals deck via the
  default AVFoundation encoder, then human side-by-side vs the ffmpeg-baseline deploy.
  Claude must NOT self-certify the visual gate. Needs the Vercel token.
- **Step 6 `/notarize`** — Developer-ID archive + DMG + Sparkle appcast (Edward's keychain
  notarytool profile + EdDSA signing).
- **Step 7 portal verify** — `/portal-deck` push + confirm render on the PUBLISHED Framer page.
