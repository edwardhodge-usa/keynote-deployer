I now have everything I need. Note Electron removed the GIF UI and replaced it with VIDEO — so the "GIF Deploy" section in PARITY.md no longer reflects Electron's current state. The CLAUDE.md is at the repo root. Now I'll write the section content.

# Section 09 — PARITY.md + CLAUDE.md + Sunset (Ship Swift, Deprecate Electron)

## Goal

This is the final, **non-code** section of the Swift video-deploy parity effort. By now (after section-08) the Swift app has a fully working `Deploy Video` tab that drops an H.264 video, picks the per-slide stills folder, sets the frame rate, and deploys an interactive single-`<video>` slide viewer to Vercel — at parity with the Electron `VideoViewer.tsx`. This section does the cutover work that makes Swift the sole shipping app:

1. Flip the parity tracker (`PARITY.md`) so the deck-deploy rows point at the **video** path and retire the GIF rows.
2. Add a README ffmpeg developer note (amendment A9) and the human quality-gate checklist (amendment A7).
3. Update `CLAUDE.md` to document the new Swift video services and mark Electron deprecated.
4. Run `/notarize` on the Swift app → DMG + Sparkle appcast, Gatekeeper-clean.
5. Verify the client-portal workflow renders a **Swift-deployed** video URL.
6. Deprecate Electron (documentation + stop-building note only; the code stays for one release as a safety net).

There is **no unit test** for this section. From `claude-plan-tdd.md` (Section 9): *"Not unit-tested. Verification = doc review + the live gate + `/notarize` Gatekeeper check + portal-render check (manual)."*

## Dependencies

- **section-08-video-deploy-view** must be complete and merged: the `Deploy Video` tab exists, wired into `ContentView`/`SidebarView` (no GIF tab), persists a `HistoryEntry`, and auto-copies the URL. The live quality gate and `/notarize` in this section operate on the binary produced after section-08.
- The full offline suite must be green via the project test command before you start the ship steps:
  ```
  cd swift-app && xcodegen generate && xcodebuild test -scheme KeynoteDeployer -destination "platform=macOS" -quiet
  ```
  Settle the verdict on the **exit code** (`; echo $?` → `0`), not on stdout presence. Swift 6 strict-concurrency must be clean.

Do NOT begin the irreversible ship steps (step 6 `/notarize`, step 8 deprecation) until the quality gate (step 5) is signed off by Edward.

## Background an implementer needs

**What the app does.** Keynote Deployer turns a Keynote deck into a shareable, embeddable web viewer hosted on Vercel. It exists as two parallel builds sharing one settings file (`~/Library/Application Support/keynote-deployer/settings.json`): an Electron app (primary, being retired here) and a Swift/SwiftUI app (becoming the sole app).

**The three historical deploy paths.**
- **HTML** path — process a Keynote HTML export with 7 HiDPI fixes, deploy. Both apps already have this at 100% parity. It stays.
- **GIF** path — abandoned (GIF compositing ghosts on held-build / constant-background decks; GIF is 256-color). Electron **removed** the GIF deploy UI and replaced it with the video path. The Swift GIF port was shelved on branch `feat/gif-deploy-swift` and is NOT to be merged.
- **VIDEO** path — deploy an H.264 movie export of the deck as a single-`<video>` slide viewer that plays the real transitions and pauses crisply on each slide. Electron shipped it; this whole spec added it to Swift.

**Why video needs per-slide stills (so the PARITY.md notes are accurate):** slide boundaries cannot be recovered from video pixels alone (a build/fade step looks identical to a real slide on a constant background). The user exports one still image per slide; the count of stills IS the slide count, and each still is matched to the video frame it appears on (DP-match) to derive that slide's timestamp. The stills are a **build-time input only** — never inserted into the video, never deployed. The deployed artifact is `deck.mp4` + `index.html`.

**Key locked decisions relevant to the docs you write:**
- Encode is **AVFoundation-native by default**; ffmpeg is a **fallback** selected only via a hidden `UserDefaults` flag (amendment A6: `defaults write <bundleid> useFfmpegEncoder -bool YES`). ffmpeg is **NOT bundled** in the shipping binary unless the quality gate forces it.
- Sunset = **parity + ship + deprecate**. Electron code stays one release as a safety net — do NOT remove Electron source this section.
- Quality gate = **human side-by-side** on the real 39-slide ILS Quals deck.

## File paths (all absolute)

- Parity tracker: `/Users/EdwardHodge_1/Code/keynote-deployer/PARITY.md`
- Project guidance: `/Users/EdwardHodge_1/Code/keynote-deployer/CLAUDE.md`
- Public README: `/Users/EdwardHodge_1/Code/keynote-deployer/README.md`
- Swift project: `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/` (`project.yml`, `xcodegen generate`)
- Sparkle config (public values only, committed): `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sparkle.xcconfig`

## Task list (implement in order)

### 1. Flip PARITY.md deck rows to the video path

Open `/Users/EdwardHodge_1/Code/keynote-deployer/PARITY.md`.

**Replace the entire `## GIF Deploy` section (current lines ~97–107).** Electron no longer has a GIF deploy UI — it has the video path — so the GIF rows are stale on BOTH columns. Retire them and add a `## Video Deploy` section that reflects the now-shipped Swift parity. Mark each row `Done | Done` and reference the actual Swift type/file from the completed sections. Suggested rows (one per Swift component delivered by sections 01–08):

| Feature | Primary | Swift | Notes |
|---|---|---|---|
| Drop H.264 video + video preview | Done | Done | `VideoDeployView` drop phase (section-08) |
| Pick per-slide stills folder (image-only filter) | Done | Done | `UTType.image` filter (amendment A8) |
| Frame-rate field + project name (prefix + kebab) | Done | Done | `VideoDeployView` confirm phase |
| Probe input (reject VFR / corrupt / no-track) | Done | Done | `AVFoundationVideoEncoder.probe` (A2, A8) |
| Stills→frame DP-match + timestamp derivation | Done | Done | `StillsMatch` + `VideoTimestampDeriver` (sections 02, 06) |
| H.264 encode with forced keyframe per slide | Done | Done | `AVFoundationVideoEncoder.encodeWithKeyframes` (section-04) |
| ffmpeg fallback encoder (hidden flag, not bundled) | Done | Done | `FFmpegVideoEncoder` via `useFfmpegEncoder` (A1, A6) |
| Single-`<video>` viewer HTML generation | Done | Done | `VideoViewerGenerator` byte-parity (section-03) |
| Deploy to Vercel + URL resolution | Done | Done | `VideoDeployer` reuses `VercelDeployer` (section-07) |
| Analyzing-progress + 4-step deploy progress | Done | Done | progress handler (A5) → `DeployProgressView` |
| Complete (URL copy, Framer embed, open) | Done | Done | mirrors HTML deploy complete phase |
| Secure embed toggle | Done | Done | reuses HTML secure-embed path |
| Persist HistoryEntry + auto-copy on completion | Done | Done | SwiftData + `settings.autoCopyUrl` |

(Use the exact type/file names the implementer actually shipped in sections 01–08; the names above match the section manifest. If a row has no Swift equivalent by design, mark it `N/A` with a one-line reason, mirroring the existing `Runtime verification (Puppeteer)` / `Inline iframe preview` rows.)

**Confirm all non-deck rows remain `Done | Done`** on both apps — do not regress the HTML Processing Pipeline, Deployment, Deploy View, Projects, History, Settings, or App Chrome sections. These should be unchanged.

**Update the `## Summary` block** (current lines ~109–114) to reflect the new totals: video rows added and Done on both, GIF rows removed, and a parity statement that the **video deck-deploy path is at Swift parity**. Note that Swift is now the shipping app and Electron is deprecated.

### 2. README ffmpeg dev note (A9) + quality-gate checklist (A7)

Open `/Users/EdwardHodge_1/Code/keynote-deployer/README.md`.

**Add a short "Video deploy — developing the ffmpeg fallback" note (amendment A9):** the shipping path is AVFoundation-native and requires nothing extra. To develop/test the fallback encoder you must install `ffmpeg` + `ffprobe` on PATH (Homebrew: `brew install ffmpeg`) and enable the hidden flag (`defaults write <bundleid> useFfmpegEncoder -bool YES`). The fallback is **not bundled** in the shipping binary.

**Add the objective video quality-gate checklist (amendment A7)** — this is the transferable, deck-agnostic checklist Edward signs off against before approving the AVFoundation encoder for ship:

> Video deploy quality gate (human sign-off, run on the real 39-slide ILS Quals deck, side-by-side against the ffmpeg-baseline deploy):
> - (a) No transition blockiness / compression artifacts on the deck transitions.
> - (b) Slide text is crisp and readable.
> - (c) Colors match the source Keynote.
> - (d) Paused keyframes are clean — no shimmer / ghosting from the prior frame.
>
> If AVFoundation passes (a)–(d), it ships. If it fails, switch to the ffmpeg fallback (then ffmpeg must be bundled + notarized as a nested binary — out of scope for this release).

### 3. Update CLAUDE.md

Open `/Users/EdwardHodge_1/Code/keynote-deployer/CLAUDE.md`.

- **Status line / Quick Context:** change from "Both apps at feature parity (45/45)" to note the Swift app now also has the **video deck-deploy path** and is the **sole shipping app**; Electron is **deprecated** (one release retained as a safety net, full removal scheduled as a follow-up).
- **Swift Code Organization section:** add the new video services delivered by this spec, e.g. under `swift-app/Sources/Services/`: `VideoEncoder` protocol + `AVFoundationVideoEncoder` + `FFmpegVideoEncoder` (fallback, hidden-flag-gated, not bundled), `VideoViewerGenerator`, `VideoTimestampDeriver`, `StillsMatch`, `GridSampler`, `VideoDeployer` (+ `VideoDeployerSeams`); and the view `VideoDeployView` under `swift-app/Sources/Views/`. Note the bundled `video-viewer-template.html` under `Sources/Resources`. (Use the exact paths/names from the shipped sections.)
- **Deprecated-Electron note:** add a clear "Electron app is deprecated — do not build new features on it; the Swift app is the shipping app" line near the Parallel Build Architecture section. Keep the existing dual-stack docs but mark Electron as stop-building.
- **Lessons Learned:** append a dated one-liner (`### 2026-06-19 —` style or the home-CLAUDE `**YYYY-MM-DD**` style used in this repo's "Lessons Learned" block) capturing the sunset: Swift reached video deck-deploy parity and became the sole shipping app; Electron deprecated (code kept one release).

### 4. Confirm shared settings compatibility

Before shipping, confirm the shared `~/Library/Application Support/keynote-deployer/settings.json` schema is unchanged by the video path so a user running either app during the transition is not broken. The video path reuses the existing settings keys (Vercel token, team ID, project prefix, auto-copy URL, secure embed, allowed domains) — it must NOT have introduced a settings migration. Spot-check that the Swift app reads/writes the same keys. No new required key may be added.

### 5. Live quality gate (human sign-off — BLOCKING)

This gate gates the ship. Per `/Users/EdwardHodge_1/.claude/CLAUDE.md` Swift verify loop:

- **Stage 1 (build/test):** full suite green via the project test command (exit 0), Swift 6 strict-concurrency clean.
- **Stage 2 (runtime/Peekaboo):** dev-launch the FRESH DerivedData build (never a stale `/Applications` copy) → `Deploy Video` tab → drop the ILS Quals video → pick the 39 stills folder → deploy → reach the complete URL. Use Peekaboo `image` + `see`/`inspect_ui` as the two-read gate; capture `log stream` if needed.
- **Live acceptance:** deploy the 39-slide ILS Quals deck via the default (AVFoundation) encoder → open the resulting Vercel viewer URL → confirm **39 baked stops**, monotonic navigation, real transitions, crisp paused keyframes.
- **Quality gate:** Edward reviews AVFoundation output **side-by-side against the already-live ffmpeg-baseline deploy** using the A7 checklist. **STOP and hand the interactive eyeball to Edward — do not self-certify the visual gate.** If approved → proceed to ship. If rejected → switch the default to the ffmpeg fallback (then ffmpeg bundling + notarization becomes required, which is out of scope for this release; report the blocker).

### 6. Notarize → DMG + Sparkle appcast

After Edward signs off the quality gate:

- Bump `CURRENT_PROJECT_VERSION` / `CFBundleShortVersionString` if not already bumped (section-01 bumped `CURRENT_PROJECT_VERSION`; verify the marketing version is the intended release version for this video-parity ship).
- Run `/notarize` on the Swift app to produce a Developer-ID-signed, hardened-runtime, notarized DMG and the Sparkle appcast entry.
  - Release archive (per repo CLAUDE.md):
    ```
    cd swift-app && xcodegen generate && xcodebuild archive -scheme KeynoteDeployer -archivePath /tmp/KeynoteDeployer.xcarchive -destination "generic/platform=macOS"
    ```
  - **Build output must be outside iCloud** — codesign fails on resource-fork detritus inside iCloud Drive. Use `/tmp/`.
  - Notarize with the keychain profile `notarytool`:
    ```
    xcrun notarytool submit /path/to/KeynoteDeployer.dmg --keychain-profile "notarytool" --wait
    xcrun stapler staple /path/to/KeynoteDeployer.dmg
    ```
  - **Re-sign Sparkle nested binaries** with `--options runtime --timestamp` before notarizing (per repo CLAUDE.md "must re-sign Sparkle nested binaries"). `Sparkle.xcconfig` holds only public values (feed URL + EdDSA public key) and is committed — do NOT gitignore it (that breaks Xcode Cloud archives).
- **Update the Sparkle appcast** with the new version entry (EdDSA-signed), so existing users auto-update from the prior Swift release to this one.
- **Verify Gatekeeper-clean on a clean machine** (or at minimum `spctl -a -vvv /path/to/KeynoteDeployer.app` → `accepted` source=Notarized Developer ID, and `stapler validate`).

Settle every build/notarize verdict on the **exit code**, not stdout. A stale `.xcresult` is a false green — force `rm -rf` DerivedData + fresh `-resultBundlePath` if anything looks off.

### 7. Verify the portal workflow with a Swift-deployed video URL

Confirm the downstream client-portal pipeline renders a **Swift-deployed** video URL end-to-end (this is what the whole effort feeds):

- Run the portal-deck workflow (`/portal-deck`) to push the Swift-deployed video URL into the Airtable `Deck URL` field.
- Confirm the Framer native Embed (CMS-bound `Deck URL`) renders the video viewer on the **PUBLISHED** Framer page (per the home-CLAUDE lesson: the Framer EDITOR canvas does NOT run a cross-origin iframe's resize/postMessage — verify on the published page, not the editor).
- Confirm the deployed viewer is H.264 (never HEVC — Chrome/Firefox don't decode HEVC), plays the real transitions, pauses on each slide, and the per-slide stops match the deck. (This is a property of the deployed artifact from section-03/section-07; you are verifying the Swift-produced URL behaves identically to the Electron-produced one in the portal.)

### 8. Deprecate Electron (documentation only)

- Mark Electron **deprecated** in `README.md` and `CLAUDE.md` (a clear stop-building note): the Swift app is the shipping app; do not add new features to Electron.
- **Leave the Electron code in place for one release** as a safety net — do NOT delete `src/`, `electron/`, or the GIF/video TS pipeline this section. Schedule the full Electron removal as a separate follow-up task (note it in the README/CLAUDE deprecation note and/or the project backlog).

## Definition of done

- [ ] `PARITY.md`: GIF rows retired; a `## Video Deploy` section added with the shipped Swift components marked `Done | Done` (or justified `N/A`); all non-deck rows confirmed unchanged/`Done`; Summary updated to reflect Swift parity + Electron deprecated.
- [ ] `README.md`: ffmpeg dev note (A9) + quality-gate checklist (A7) + Electron deprecation note added.
- [ ] `CLAUDE.md`: status updated; new Swift video services + `VideoDeployView` documented; Electron marked deprecated (stop-building, code kept one release); dated Lessons-Learned one-liner appended.
- [ ] Shared `settings.json` confirmed compatible (no new required key, no migration).
- [ ] Full Swift suite green (exit 0), Swift 6 strict-concurrency clean.
- [ ] Live: 39-slide ILS Quals deck deployed via Swift (default AVFoundation) → reachable viewer URL with 39 baked stops; runtime/Peekaboo dev-launch flow verified.
- [ ] **Edward signs off** the A7 quality gate side-by-side vs the ffmpeg-baseline deploy (this is the blocking human gate).
- [ ] `/notarize` → notarized, stapled DMG + Sparkle appcast updated; Gatekeeper-clean verified.
- [ ] Portal workflow verified rendering a Swift-deployed video URL on the **published** Framer page.
- [ ] Electron deprecated in docs; code left intact for one release; full-removal follow-up scheduled.

## Notes / gotchas (from project memory)

- **Verdict oracle = exit code, not stdout.** Blank/late output is "don't know yet," not failure. Force-clean stale `.xcresult`/DerivedData before trusting a green.
- **Build outside iCloud** (`/tmp/`) — resource forks break codesign inside iCloud Drive.
- **`Sparkle.xcconfig` is committed** (public values only); gitignoring it breaks Xcode Cloud archives. Re-sign nested Sparkle binaries with `--options runtime --timestamp` before notarizing.
- **Self-verify the actual deployed artifact**, not a build log — confirm the Swift-deployed viewer is real H.264 video and renders on the published Framer page.
- **Reinstalling under a placed copy can serve stale code** — confirm `pgrep -af` points at the fresh build path before trusting a runtime verify; quit any running `/Applications` copy first.
- **Do not merge `feat/gif-deploy-swift`** and do not add a GIF UI to Swift.

---

Relevant absolute paths for this section:
- `/Users/EdwardHodge_1/Code/keynote-deployer/PARITY.md` — flip deck rows / retire GIF / add Video Deploy section + Summary
- `/Users/EdwardHodge_1/Code/keynote-deployer/README.md` — A9 ffmpeg dev note + A7 quality-gate checklist + Electron deprecation
- `/Users/EdwardHodge_1/Code/keynote-deployer/CLAUDE.md` — status, new Swift video services, Electron-deprecated note, dated lesson
- `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/` — `xcodegen generate`, archive, `/notarize`
- `/Users/EdwardHodge_1/Code/keynote-deployer/swift-app/Sparkle.xcconfig` — appcast feed URL + EdDSA public key (committed)

One important ground-truth I confirmed while researching: the existing `PARITY.md` still has a `## GIF Deploy` section listing GIF rows as `Done` for Electron and `N/A` for Swift. That is now **stale** — Electron removed the GIF UI and replaced it with the video path. The implementer should replace (not append to) that section, since leaving it would misrepresent Electron's current state.

---

## As-built — docs done + hardening pass; ship steps handed to Edward

**Docs (tasks 1–4) — DONE, committed:**
- `PARITY.md`: GIF section retired → `## Video Deploy` (13 rows, Done|Done); chrome "4 tabs"→"5 tabs"; Summary updated (66 features, Swift sole shipping app, Electron deprecated).
- `README.md`: Video Deck Deploy section + A9 ffmpeg dev note + A7 quality-gate checklist + "Swift is the shipping app / Electron deprecated" note.
- `CLAUDE.md`: status line + dual-stack reordered (Swift shipping / Electron deprecated), new video services documented under Swift Code Organization, deprecation banner at Parallel Build Architecture, dated Lessons-Learned line.
- Settings compat: `AppSettings.swift` untouched on the whole branch (`git log main..HEAD` empty) → no migration, no new required key. ✓

**Hardening pass (Edward asked) — DONE, committed:** a final whole-subsystem adversarial
review (see `implementation/code_review/section-09-*`) found a **ship-blocker (C1: fps
divergence)** that all offline stub tests passed. Fixed: one authoritative fps threaded
through `encodeWithKeyframes(fps:)` + the View defaults its fps field to the probed rate;
+ a C1 regression test + `StillsMatchError` friendly messages. 65/65 green, Swift 6 clean.
I1/I2/I3/C3 accepted as parity/low-risk (rationale in the review doc).

**Ship steps (5–8) — BLOCKING, require Edward (sign-in / human eyeball):**
- Step 5 live quality gate (A7) — deploy the real 39-slide ILS Quals deck via Vercel
  (needs the Vercel token) → human side-by-side vs the ffmpeg-baseline. NOT self-certified.
- Step 6 `/notarize` — Developer-ID DMG + Sparkle appcast (keychain `notarytool` + EdDSA).
- Step 7 `/portal-deck` → confirm render on the PUBLISHED Framer page.
- Step 8 Electron deprecation — done in docs; code left intact for one release; full
  removal is a scheduled follow-up.