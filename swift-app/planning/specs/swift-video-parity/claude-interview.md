# Interview — Swift Video-Deploy Parity

**Q1. Video encode in Swift — ffmpeg dependency?**
→ **AVFoundation-native, ffmpeg fallback.** Default to pure-Apple encode (AVAssetReader→AVAssetWriter with per-frame `kCMSampleBufferAttachmentKey_ForceKeyFrame`, native frame sampling via AVAssetImageGenerator). Zero bundled binary in the shipping path. Quality-gate against the ffmpeg baseline; bundled-ffmpeg is the fallback ONLY if VideoToolbox quality is inadequate.

**Q2. Sunset scope this weekend?**
→ **Parity + ship Swift, deprecate Electron.** Reach video parity, notarize + DMG + Sparkle appcast release of Swift, mark Electron deprecated (stop building, README/CLAUDE note), but leave Electron code in-repo for one release as a safety net. Full code removal = follow-up next week.

**Q3. AVFoundation quality gate?**
→ **Edward eyeballs both on the real deck.** Deploy the 39-slide ILS Quals deck via BOTH the ffmpeg baseline (already live) and AVFoundation; Edward compares paused slides side-by-side and approves AVFoundation, or we fall back to bundled ffmpeg.

**Derived defaults (not separately asked):**
- VideoDeployView UX mirrors the Electron `VideoViewer.tsx` exactly: drop `.mp4/.mov/.m4v` → confirm (live preview, pick stills folder, fps field default 30, project name kebab+prefix, secure-embed default on) → 4-step progress → complete (Copy URL / Framer Embed / Open).
- Sidebar matches Electron: Deploy HTML, Deploy Video, Projects, History, Settings (no GIF tab). The `.video` NavigationTab case already exists.
- Reuse VercelDeployer/FileOperations/HistoryEntry/DeployProgressView/AppSettings unchanged.
- Confirmed (research): no non-video Electron changes for Swift to chase — only the deck path changed (GIF→video). HTML path stays 100% parity, untouched.
- Do NOT merge `feat/gif-deploy-swift`; salvage patterns only.
