# GIF Slide Viewer Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the standalone GIF Slide Viewer into the Electron app as a 5th sidebar tab ("Preview"), porting the vanilla JS to a React component with Tailwind styling.

**Architecture:** Single new React component (`GifViewer.tsx`) with three UI phases (drop → loading → viewing). Uses `gifuct-js` as an npm dependency. Canvas rendering via `useRef`, UI state via `useState`. No IPC changes — all logic runs in the renderer.

**Tech Stack:** React 18, TypeScript, gifuct-js, HTML5 Canvas, Tailwind CSS

**Spec:** `docs/superpowers/specs/2026-03-24-gif-viewer-integration-design.md`

**Reference implementation:** `gif-slide-viewer.html` (standalone prototype, 714 lines)

**Project root:** `/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer/`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `src/components/GifViewer.tsx` | Full GIF viewer component — drop zone, parsing, canvas viewer, playback controls |
| Modify | `src/types/index.ts` | Add `'preview'` to `TabId` union |
| Modify | `src/components/Sidebar.tsx` | Add Preview tab with icon |
| Modify | `src/App.tsx` | Import GifViewer, render on `preview` tab |
| None | `electron/main.ts`, `electron/preload.ts` | No changes needed |

---

### Task 1: Add gifuct-js dependency and extend TabId type

**Files:**
- Modify: `package.json` (npm install)
- Modify: `src/types/index.ts:91`

- [ ] **Step 1: Install gifuct-js**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && npm install gifuct-js
```

Verify it installed:
```bash
ls node_modules/gifuct-js/lib/index.js
```

- [ ] **Step 2: Add 'preview' to TabId union**

In `src/types/index.ts`, change:
```typescript
export type TabId = 'deploy' | 'projects' | 'history' | 'settings'
```
to:
```typescript
export type TabId = 'deploy' | 'projects' | 'history' | 'preview' | 'settings'
```

- [ ] **Step 3: Verify type check passes**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && npx vite build 2>&1 | tail -5
```

Expected: build succeeds (may show unused-variable warnings, that's fine — the new tab ID isn't referenced yet).

- [ ] **Step 4: Commit**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && git add package.json package-lock.json src/types/index.ts && git commit -m "chore: add gifuct-js dependency and preview tab ID"
```

---

### Task 2: Create GifViewer component — Drop phase

**Files:**
- Create: `src/components/GifViewer.tsx`

Build the component shell with the drop zone UI. This task covers only Phase 1 (drop) — the file validation and ArrayBuffer reading. Parsing and viewing come in Tasks 3 and 4.

- [ ] **Step 1: Create GifViewer.tsx with drop zone**

Create `src/components/GifViewer.tsx`:

```tsx
import { useState, useRef, useCallback, useEffect } from 'react'
import { parseGIF, decompressFrames } from 'gifuct-js'

// ── Types ──

interface SlideInfo {
  restFrame: number
  holdStart: number
  holdEnd: number
  transitionFrames: { start: number; end: number } | null
}

interface ParsedGif {
  frames: ImageBitmap[]
  slides: SlideInfo[]
  width: number
  height: number
  frameDelay: number
}

type Phase = 'drop' | 'loading' | 'viewing'

export default function GifViewer() {
  const [phase, setPhase] = useState<Phase>('drop')
  const [dragOver, setDragOver] = useState(false)
  const [error, setError] = useState('')
  const [warning, setWarning] = useState('')
  const [progress, setProgress] = useState({ text: '', percent: 0 })
  const [currentSlide, setCurrentSlide] = useState(0)
  const [isPlaying, setIsPlaying] = useState(false)

  const canvasRef = useRef<HTMLCanvasElement>(null)
  const parsedRef = useRef<ParsedGif | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const isPlayingRef = useRef(false)

  // Keep ref in sync with state (for use in animation callbacks)
  useEffect(() => {
    isPlayingRef.current = isPlaying
  }, [isPlaying])

  const clearMessages = useCallback(() => {
    setError('')
    setWarning('')
  }, [])

  const handleFile = useCallback((file: File) => {
    clearMessages()

    // Check extension
    if (!file.name.toLowerCase().endsWith('.gif')) {
      setError(`Please select a GIF file. Got: ${file.name}`)
      return
    }

    // Check size (200 MB limit)
    const MAX_SIZE = 200 * 1024 * 1024
    if (file.size > MAX_SIZE) {
      setError(`File too large (${(file.size / (1024 * 1024)).toFixed(1)} MB). Maximum is 200 MB.`)
      return
    }

    const reader = new FileReader()
    reader.onload = (e) => {
      const buffer = e.target?.result as ArrayBuffer
      if (!buffer) {
        setError('Failed to read file.')
        return
      }

      // Validate GIF magic bytes
      const header = new Uint8Array(buffer, 0, 6)
      const magic = String.fromCharCode(...header)
      if (magic !== 'GIF87a' && magic !== 'GIF89a') {
        setError(`Invalid GIF file. Header: ${magic}`)
        return
      }

      setPhase('loading')
      setProgress({ text: 'Preparing to parse...', percent: 0 })
      parseGifBuffer(buffer)
    }

    reader.onerror = () => {
      setError('Failed to read file.')
    }

    reader.readAsArrayBuffer(file)
  }, [clearMessages])

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    e.stopPropagation()
    setDragOver(false)
    const files = e.dataTransfer.files
    if (files.length > 0) handleFile(files[0])
  }, [handleFile])

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    e.stopPropagation()
    setDragOver(true)
  }, [])

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    e.stopPropagation()
    setDragOver(false)
  }, [])

  // ── Parsing (Task 3 will fill this in) ──

  const parseGifBuffer = async (buffer: ArrayBuffer) => {
    // TODO: implement in Task 3
    console.log('Parse buffer:', buffer.byteLength)
  }

  // ── Rendering (Task 4 will fill this in) ──

  const renderSlide = (index: number) => {
    // TODO: implement in Task 4
    console.log('Render slide:', index)
  }

  const playNext = () => {
    // TODO: implement in Task 4
  }

  const playPrev = () => {
    // TODO: implement in Task 4
  }

  const jumpToSlide = (index: number) => {
    // TODO: implement in Task 4
  }

  const loadAnother = useCallback(() => {
    // Release GPU memory
    if (parsedRef.current?.frames) {
      parsedRef.current.frames.forEach((bmp) => bmp.close())
    }
    parsedRef.current = null
    setCurrentSlide(0)
    setIsPlaying(false)
    setPhase('drop')
    clearMessages()
    if (fileInputRef.current) fileInputRef.current.value = ''
  }, [clearMessages])

  // ── Keyboard controls ──
  useEffect(() => {
    if (phase !== 'viewing') return
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight') playNext()
      if (e.key === 'ArrowLeft') playPrev()
    }
    document.addEventListener('keydown', handler)
    return () => document.removeEventListener('keydown', handler)
  }, [phase, currentSlide, isPlaying])

  // ── Render ──

  const slides = parsedRef.current?.slides ?? []
  const slideCount = slides.length

  return (
    <div className="h-full flex flex-col">
      <div className="window-drag h-14 flex-shrink-0" />

      <div className="flex-1 overflow-y-auto px-8 pb-8">
        {/* Header with Load Another button */}
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-semibold">Preview</h1>
          {phase === 'viewing' && (
            <button onClick={loadAnother} className="btn btn-ghost btn-sm">
              Load Another GIF
            </button>
          )}
        </div>

        {/* Error / Warning messages */}
        {error && (
          <div className="mb-4 p-3 rounded-lg bg-red-500/10 border border-red-500/20 text-red-400 text-[13px]">
            {error}
          </div>
        )}
        {warning && (
          <div className="mb-4 p-3 rounded-lg bg-yellow-500/10 border border-yellow-500/20 text-yellow-400 text-[13px]">
            {warning}
          </div>
        )}

        {/* Phase: Drop */}
        {phase === 'drop' && (
          <div className="flex justify-center pt-12">
            <div
              onDrop={handleDrop}
              onDragOver={handleDragOver}
              onDragLeave={handleDragLeave}
              onClick={() => fileInputRef.current?.click()}
              className={`w-[520px] max-w-full p-16 border-2 border-dashed rounded-xl text-center cursor-pointer transition-colors ${
                dragOver
                  ? 'border-blue-500 bg-blue-500/5'
                  : 'border-gray-300 dark:border-gray-600 bg-gray-50 dark:bg-gray-800/50'
              }`}
            >
              <div className="text-4xl mb-4 opacity-50">📁</div>
              <p className="text-[15px] text-gray-500 dark:text-gray-400">
                <span className="font-medium text-gray-700 dark:text-gray-300">Drop a GIF file here</span>
                <br />or click to browse
              </p>
              <p className="text-[12px] text-gray-400 dark:text-gray-500 mt-2">
                Keynote-exported animated GIFs up to 200 MB
              </p>
            </div>
            <input
              ref={fileInputRef}
              type="file"
              accept=".gif"
              className="hidden"
              onChange={(e) => {
                const file = e.target.files?.[0]
                if (file) handleFile(file)
              }}
            />
          </div>
        )}

        {/* Phase: Loading */}
        {phase === 'loading' && (
          <div className="flex flex-col items-center justify-center py-24">
            <p className="text-[14px] text-gray-500 dark:text-gray-400 mb-3">{progress.text}</p>
            <div className="w-72 h-1 bg-gray-200 dark:bg-gray-700 rounded overflow-hidden">
              <div
                className="h-full bg-blue-500 rounded transition-[width] duration-100"
                style={{ width: `${progress.percent}%` }}
              />
            </div>
          </div>
        )}

        {/* Phase: Viewing */}
        {phase === 'viewing' && (
          <div className="flex flex-col items-center">
            {/* Canvas */}
            <div className="w-full max-w-[1080px]">
              <canvas
                ref={canvasRef}
                className="w-full h-auto rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-100 dark:bg-gray-800"
              />
            </div>

            {/* Controls */}
            <div className="flex items-center gap-4 mt-4">
              <button
                onClick={playPrev}
                disabled={currentSlide <= 0 || isPlaying}
                className="btn btn-secondary btn-sm"
              >
                ◀ Previous
              </button>
              <span className="text-[13px] text-gray-500 dark:text-gray-400 min-w-[80px] text-center">
                {currentSlide + 1} of {slideCount}
              </span>
              <button
                onClick={playNext}
                disabled={currentSlide >= slideCount - 1 || isPlaying}
                className="btn btn-secondary btn-sm"
              >
                Next ▶
              </button>
            </div>

            {/* Dot strip */}
            {slideCount > 1 && (
              <div className="flex items-center justify-center flex-wrap gap-1 mt-3 max-w-full">
                {slides.map((_, i) => (
                  <button
                    key={i}
                    title={`Slide ${i + 1}`}
                    onClick={() => jumpToSlide(i)}
                    className={`w-2 h-2 rounded-full border-none p-0 cursor-pointer transition-colors ${
                      i === currentSlide ? 'bg-blue-500' : 'bg-gray-300 dark:bg-gray-600 hover:bg-gray-400 dark:hover:bg-gray-500'
                    }`}
                  />
                ))}
              </div>
            )}

            <p className="text-[11px] text-gray-400 dark:text-gray-500 mt-3">
              Arrow keys: Previous / Next
            </p>
          </div>
        )}
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Verify file compiles**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && npx vite build 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && git add src/components/GifViewer.tsx && git commit -m "feat: GIF viewer component shell with drop zone and loading UI"
```

---

### Task 3: Implement GIF parsing + slide detection

**Files:**
- Modify: `src/components/GifViewer.tsx`

Port the `loadAndParseGIF` logic from `gif-slide-viewer.html` (lines 421-573) into the `parseGifBuffer` method. This includes: gifuct-js parsing, offscreen canvas compositing, pixel-diff sampling, quiet-run slide detection algorithm.

- [ ] **Step 1: Replace the parseGifBuffer stub**

In `src/components/GifViewer.tsx`, replace the `parseGifBuffer` function (the one with the TODO comment) with the full implementation:

```tsx
  const parseGifBuffer = async (buffer: ArrayBuffer) => {
    try {
      setProgress({ text: 'Parsing GIF structure...', percent: 0 })
      const gif = parseGIF(buffer)
      const rawFrames = decompressFrames(gif, true)

      if (!rawFrames || rawFrames.length === 0) {
        throw new Error('No image frames found in GIF.')
      }

      const gifWidth = gif.lsd.width
      const gifHeight = gif.lsd.height
      const frameDelay = rawFrames[0]?.delay || 40

      // Compositing canvas (handles disposal, positioning)
      const compCanvas = document.createElement('canvas')
      compCanvas.width = gifWidth
      compCanvas.height = gifHeight
      const compCtx = compCanvas.getContext('2d')!

      // Temp canvas for patches
      const tempCanvas = document.createElement('canvas')
      const tempCtx = tempCanvas.getContext('2d')!

      // Sample points for diff detection (~1000 points on a grid)
      const samplePoints: number[] = []
      const gridSize = Math.ceil(Math.sqrt(1000))
      const stepX = Math.floor(gifWidth / gridSize)
      const stepY = Math.floor(gifHeight / gridSize)
      for (let y = 0; y < gifHeight; y += stepY) {
        for (let x = 0; x < gifWidth; x += stepX) {
          samplePoints.push(x, y)
        }
      }

      const frames: ImageBitmap[] = []
      const diffs: number[] = [0]
      let prevSamples: Uint8Array | null = null
      const totalFrames = rawFrames.length

      for (let i = 0; i < totalFrames; i++) {
        const frame = rawFrames[i]

        // Handle disposal
        if (frame.disposalType === 2) {
          compCtx.clearRect(0, 0, gifWidth, gifHeight)
        }

        // Draw patch to temp canvas, composite onto full canvas
        const dims = frame.dims
        tempCanvas.width = dims.width
        tempCanvas.height = dims.height
        const imageData = tempCtx.createImageData(dims.width, dims.height)
        imageData.data.set(frame.patch)
        tempCtx.putImageData(imageData, 0, 0)
        compCtx.drawImage(tempCanvas, dims.left, dims.top)

        // Sample pixels for diff detection before converting to ImageBitmap
        const fullImageData = compCtx.getImageData(0, 0, gifWidth, gifHeight)
        const pixels = fullImageData.data

        const currentSamples = new Uint8Array((samplePoints.length / 2) * 3)
        for (let s = 0; s < samplePoints.length; s += 2) {
          const idx = (samplePoints[s + 1] * gifWidth + samplePoints[s]) * 4
          const si = (s / 2) * 3
          currentSamples[si] = pixels[idx]
          currentSamples[si + 1] = pixels[idx + 1]
          currentSamples[si + 2] = pixels[idx + 2]
        }

        if (prevSamples) {
          let totalDiff = 0
          for (let s = 0; s < currentSamples.length; s++) {
            totalDiff += Math.abs(currentSamples[s] - prevSamples[s])
          }
          diffs.push(totalDiff / currentSamples.length)
        }
        prevSamples = currentSamples

        // Convert to ImageBitmap (GPU-friendly, smaller than raw RGBA)
        const bitmap = await createImageBitmap(compCanvas)
        frames.push(bitmap)

        // Free raw patch data
        ;(frame as any).patch = null

        // Progress update every 20 frames
        if (i % 20 === 0) {
          setProgress({
            text: `Parsing frame ${i + 1} of ${totalFrames}...`,
            percent: Math.round((i / totalFrames) * 100),
          })
          await new Promise((r) => setTimeout(r, 0)) // yield to UI
        }
      }

      // Slide detection: quiet-run algorithm
      const QUIET_THRESHOLD = 0.3
      const MIN_QUIET_RUN = 8

      const quietRuns: { start: number; end: number }[] = []
      let runStart: number | null = null
      for (let i = 0; i < diffs.length; i++) {
        if (diffs[i] <= QUIET_THRESHOLD) {
          if (runStart === null) runStart = i
        } else {
          if (runStart !== null && i - runStart >= MIN_QUIET_RUN) {
            quietRuns.push({ start: runStart, end: i - 1 })
          }
          runStart = null
        }
      }
      if (runStart !== null && diffs.length - runStart >= MIN_QUIET_RUN) {
        quietRuns.push({ start: runStart, end: diffs.length - 1 })
      }

      // Build slide map from quiet runs
      const slides: SlideInfo[] = []
      for (let i = 0; i < quietRuns.length; i++) {
        const run = quietRuns[i]
        const prevRun = i > 0 ? quietRuns[i - 1] : null
        slides.push({
          restFrame: run.start,
          holdStart: run.start,
          holdEnd: run.end,
          transitionFrames: prevRun ? { start: prevRun.end + 1, end: run.start - 1 } : null,
        })
      }

      // Fallback: if no slides found, treat entire GIF as one slide
      if (slides.length === 0) {
        slides.push({
          restFrame: 0,
          holdStart: 0,
          holdEnd: frames.length - 1,
          transitionFrames: null,
        })
      }

      if (slides.length < 2) {
        setWarning('Could not detect slide boundaries. Try re-exporting with longer auto-advance timing (1-2 seconds).')
      }

      console.log(`Detected ${slides.length} slides from ${frames.length} frames`)

      parsedRef.current = { frames, slides, width: gifWidth, height: gifHeight, frameDelay }
      setCurrentSlide(0)
      setPhase('viewing')

      // Render first slide after state update
      requestAnimationFrame(() => {
        renderSlide(0)
      })
    } catch (err) {
      setError(`Failed to parse GIF: ${err instanceof Error ? err.message : String(err)}`)
      setPhase('drop')
    }
  }
```

- [ ] **Step 2: Verify build**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && npx vite build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && git add src/components/GifViewer.tsx && git commit -m "feat: GIF parsing + quiet-run slide detection in viewer component"
```

---

### Task 4: Implement canvas rendering + playback controls

**Files:**
- Modify: `src/components/GifViewer.tsx`

Replace the `renderSlide`, `playNext`, `playPrev`, and `jumpToSlide` stubs with working implementations. Port from `gif-slide-viewer.html` lines 611-673.

- [ ] **Step 1: Replace the rendering and playback stubs**

In `src/components/GifViewer.tsx`, replace the four stub functions with:

```tsx
  const renderSlide = (index: number) => {
    const canvas = canvasRef.current
    const parsed = parsedRef.current
    if (!canvas || !parsed) return

    const ctx = canvas.getContext('2d')
    if (!ctx) return

    // Set canvas resolution to match GIF dimensions
    canvas.width = parsed.width
    canvas.height = parsed.height

    const slide = parsed.slides[index]
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    ctx.drawImage(parsed.frames[slide.restFrame], 0, 0)
    setCurrentSlide(index)
  }

  const playNext = () => {
    if (isPlayingRef.current) return
    const parsed = parsedRef.current
    if (!parsed) return

    // Read current slide from the ref-backed latest value
    setCurrentSlide((prev) => {
      if (prev >= parsed.slides.length - 1) return prev

      const nextSlide = parsed.slides[prev + 1]
      if (!nextSlide.transitionFrames) {
        renderSlide(prev + 1)
        return prev + 1
      }

      // Play transition animation
      setIsPlaying(true)
      isPlayingRef.current = true

      const { start, end } = nextSlide.transitionFrames
      const canvas = canvasRef.current
      const ctx = canvas?.getContext('2d')
      if (!canvas || !ctx) return prev

      let frameIdx = start
      const targetSlide = prev + 1

      const playFrame = () => {
        ctx.clearRect(0, 0, canvas.width, canvas.height)
        ctx.drawImage(parsed.frames[frameIdx], 0, 0)
        frameIdx++

        if (frameIdx <= end) {
          setTimeout(() => requestAnimationFrame(playFrame), parsed.frameDelay)
        } else {
          setIsPlaying(false)
          isPlayingRef.current = false
          renderSlide(targetSlide)
        }
      }

      requestAnimationFrame(playFrame)
      return prev // state updates after animation completes via renderSlide
    })
  }

  const playPrev = () => {
    if (isPlayingRef.current) return
    setCurrentSlide((prev) => {
      if (prev <= 0) return prev
      renderSlide(prev - 1)
      return prev - 1
    })
  }

  const jumpToSlide = (index: number) => {
    if (isPlayingRef.current) return
    renderSlide(index)
  }
```

- [ ] **Step 2: Verify build**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && npx vite build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && git add src/components/GifViewer.tsx && git commit -m "feat: canvas rendering + transition playback in GIF viewer"
```

---

### Task 5: Wire into app — Sidebar tab + App routing

**Files:**
- Modify: `src/components/Sidebar.tsx:47-52`
- Modify: `src/App.tsx:1-42`

Add the Preview tab to the sidebar and route to GifViewer in App.tsx.

- [ ] **Step 1: Add Preview icon and tab to Sidebar.tsx**

In `src/components/Sidebar.tsx`, add a `PreviewIcon` component after the existing icon components (before the `tabs` array):

```tsx
function PreviewIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="3" width="14" height="12" rx="2" />
      <polygon points="7.5,7 7.5,13 12.5,10" fill="currentColor" stroke="none" />
    </svg>
  )
}
```

Then add the Preview entry to the `tabs` array, between `history` and `settings`:

```typescript
const tabs: { id: TabId; label: string; Icon: React.FC<{ className?: string }> }[] = [
  { id: 'deploy', label: 'Deploy', Icon: DeployIcon },
  { id: 'projects', label: 'Projects', Icon: ProjectsIcon },
  { id: 'history', label: 'History', Icon: HistoryIcon },
  { id: 'preview', label: 'Preview', Icon: PreviewIcon },
  { id: 'settings', label: 'Settings', Icon: SettingsIcon },
]
```

- [ ] **Step 2: Add GifViewer route to App.tsx**

In `src/App.tsx`, add the import at the top:

```tsx
import GifViewer from './components/GifViewer'
```

Add `'preview'` to the navigate type guard in the `useEffect`:

```tsx
if (tab === 'deploy' || tab === 'projects' || tab === 'history' || tab === 'preview' || tab === 'settings') {
```

Add the rendering case in the `<main>` section, between History and Settings:

```tsx
{activeTab === 'preview' && <GifViewer />}
```

- [ ] **Step 3: Verify build**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && npx vite build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && git add src/components/Sidebar.tsx src/App.tsx && git commit -m "feat: wire GIF viewer into sidebar as Preview tab"
```

---

### Task 6: Manual test + polish

**Files:**
- Possibly modify: `src/components/GifViewer.tsx` (if issues found)

- [ ] **Step 1: Launch dev mode**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && npm run electron:dev
```

- [ ] **Step 2: Test the full flow**

1. Click "Preview" in the sidebar — verify drop zone appears
2. Drag `/Users/EdwardHodge_1/Desktop/ILS_Quals 2026 V1.6.gif` onto the drop zone (or click Browse)
3. Verify progress bar fills while parsing (~960 frames)
4. Verify slides are detected (check console for "Detected N slides")
5. Click Next — verify transition plays smoothly at native speed, then holds on next slide
6. Click Previous — verify instant jump back (no reverse animation)
7. Click dots to jump directly to a slide
8. Use arrow keys (Right = Next, Left = Previous)
9. Verify buttons are disabled during transition playback
10. Verify Previous disabled on first slide, Next disabled on last slide
11. Click "Load Another GIF" — verify reset to drop zone, no memory leak in Activity Monitor
12. Drop a non-GIF file — verify error message appears
13. Switch tabs away and back to Preview — verify state persists (or resets cleanly)

- [ ] **Step 3: Fix any issues found**

Address any visual or behavioral issues discovered during testing. Common things to watch for:
- Canvas aspect ratio not matching the app's content area width
- Dark mode styling mismatches
- Drop zone not receiving drag events (Electron sometimes needs document-level drag prevention)

- [ ] **Step 4: Final build check**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && npx vite build 2>&1 | tail -5
```

- [ ] **Step 5: Commit any polish fixes**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && git add -A && git commit -m "fix: polish GIF viewer after manual testing"
```

(Skip this step if no changes were needed.)

---

## Execution Route

| Signal | Route |
|--------|-------|
| 6 tasks, multi-file, iterative build | `/do` (subagents) |
