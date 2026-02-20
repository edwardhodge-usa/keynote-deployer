# Keynote Deployer

One-click GUI app that processes Keynote HTML exports and deploys them to Vercel. Replaces a 12-step manual process with a single drag-and-drop workflow.

## What It Does

1. **Processes** Keynote HTML exports by applying 7 HiDPI rendering fixes to `main.js`
2. **Generates** a custom `index.html` with loading overlay, navigation controls, and slide counter
3. **Deploys** the processed presentation to Vercel with one click
4. **Manages** deployment history with quick-copy URLs

## Tech Stack

- Electron 33 + React 18 + TypeScript 5.7 + Vite 6 + Tailwind 3
- macOS native feel: hidden inset title bar, SF Pro fonts, dark mode
- Vercel REST API (project creation) + CLI (deployment)

## Getting Started

```bash
# Install dependencies
npm install

# Run in development
npm run electron:dev

# Build for production
npm run electron:build
```

## Configuration

On first launch, go to **Settings** and enter your:
- **Vercel Token** — auto-detected from CLI config if available
- **Team ID** — defaults to `team_E1wAzl9zyAPrlGzyjmcXNuxd`

Settings are stored in `~/Library/Application Support/keynote-deployer/`.

## Usage

1. Drag a Keynote HTML export folder onto the app (or click Browse)
2. Confirm/edit the project name
3. Click Deploy — the app applies fixes, generates index.html, and deploys to Vercel
4. Copy the deployment URL from the completion screen or History tab

## The 7 HiDPI Fixes

| # | Fix | Purpose |
|---|-----|---------|
| 1 | zC scale | PDF rasterization at 3x instead of 1x |
| 2 | Fullscreen bypass | Enable rendering without fullscreen mode |
| 3 | Viewport A | DPR scaling for sparkle/particle effects |
| 4 | Viewport B | DPR scaling for firework effects |
| 5 | Resize viewport | DPR scaling in resize handler |
| 6 | Constructor viewport | Divide viewportWidth/Height by DPR |
| 7 | Canvas DPR | Scale canvas backing store + add CSS size |

All fixes are idempotent — re-processing an already-patched file is safe.

## Project Structure

```
├── electron/
│   ├── main.ts              # BrowserWindow + IPC handlers
│   ├── preload.ts           # Context bridge API
│   ├── keynoteProcessor.ts  # 7 HiDPI fixes + index.html generation
│   ├── vercelDeployer.ts    # Vercel REST API + CLI deployment
│   └── fileOperations.ts    # Settings, history, validation
├── src/
│   ├── components/
│   │   ├── Deploy.tsx       # 4-phase workflow UI
│   │   ├── DeployProgress.tsx # 14-step progress indicator
│   │   ├── History.tsx      # Past deployments
│   │   ├── Settings.tsx     # Configuration
│   │   └── Sidebar.tsx      # Navigation
│   ├── styles/globals.css   # Tailwind + macOS components
│   └── types/index.ts       # TypeScript interfaces
└── package.json
```

## Known Limitation

Keynote exports embedded images at low resolution (266x150 thumbnails). The 7 fixes improve text/vector rendering but can't fix image quality. Workaround: save images as PDF before inserting into Keynote.
