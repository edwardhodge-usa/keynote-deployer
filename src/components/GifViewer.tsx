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

type Phase = 'drop' | 'loading' | 'viewing' | 'confirm' | 'deploying' | 'complete' | 'error'

function toKebabCase(str: string): string {
  return str.toLowerCase().replace(/[^a-z0-9\s-]/g, '').replace(/\s+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '')
}

export default function GifViewer() {
  const [phase, setPhase] = useState<Phase>('drop')
  const [dragOver, setDragOver] = useState(false)
  const [error, setError] = useState('')
  const [warning, setWarning] = useState('')
  const [progress, setProgress] = useState({ text: '', percent: 0 })
  const [currentSlide, setCurrentSlide] = useState(0)
  const [isPlaying, setIsPlaying] = useState(false)
  const [projectName, setProjectName] = useState('')
  const [secureEmbed, setSecureEmbed] = useState(true)
  const [deployResult, setDeployResult] = useState<{ url: string } | null>(null)
  const [deployError, setDeployError] = useState('')
  const [deploySteps, setDeploySteps] = useState<any[]>([])
  const [copied, setCopied] = useState<string | null>(null)
  const [gifFilePath, setGifFilePath] = useState('')
  const [gifFileSize, setGifFileSize] = useState(0)

  const canvasRef = useRef<HTMLCanvasElement>(null)
  const parsedRef = useRef<ParsedGif | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const isPlayingRef = useRef(false)

  // Keep ref in sync with state for animation callbacks
  useEffect(() => {
    isPlayingRef.current = isPlaying
  }, [isPlaying])

  const clearMessages = useCallback(() => {
    setError('')
    setWarning('')
  }, [])

  // ── File handling ──

  const handleFile = useCallback((file: File) => {
    clearMessages()

    if (!file.name.toLowerCase().endsWith('.gif')) {
      setError(`Please select a GIF file. Got: ${file.name}`)
      return
    }

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
    const file = e.dataTransfer.files[0]
    if (file) {
      setGifFilePath(window.electron.getFilePath(file))
      setGifFileSize(file.size)
      handleFile(file)
    }
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

  // ── GIF Parsing + Slide Detection ──

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

      const compCanvas = document.createElement('canvas')
      compCanvas.width = gifWidth
      compCanvas.height = gifHeight
      const compCtx = compCanvas.getContext('2d')!

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

        if (frame.disposalType === 2) {
          compCtx.clearRect(0, 0, gifWidth, gifHeight)
        }

        const dims = frame.dims
        tempCanvas.width = dims.width
        tempCanvas.height = dims.height
        const imageData = tempCtx.createImageData(dims.width, dims.height)
        imageData.data.set(frame.patch)
        tempCtx.putImageData(imageData, 0, 0)
        compCtx.drawImage(tempCanvas, dims.left, dims.top)

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

        const bitmap = await createImageBitmap(compCanvas)
        frames.push(bitmap)

        ;(frame as any).patch = null

        if (i % 20 === 0) {
          setProgress({
            text: `Parsing frame ${i + 1} of ${totalFrames}...`,
            percent: Math.round((i / totalFrames) * 100),
          })
          await new Promise((r) => setTimeout(r, 0))
        }
      }

      // Quiet-run slide detection algorithm
      const QUIET_THRESHOLD = 0.3
      const MIN_QUIET_RUN = 8

      const allQuietRuns: { start: number; end: number; length: number }[] = []
      let runStart: number | null = null
      for (let i = 0; i < diffs.length; i++) {
        if (diffs[i] <= QUIET_THRESHOLD) {
          if (runStart === null) runStart = i
        } else {
          if (runStart !== null && i - runStart >= MIN_QUIET_RUN) {
            allQuietRuns.push({ start: runStart, end: i - 1, length: i - runStart })
          }
          runStart = null
        }
      }
      if (runStart !== null && diffs.length - runStart >= MIN_QUIET_RUN) {
        allQuietRuns.push({ start: runStart, end: diffs.length - 1, length: diffs.length - runStart })
      }

      // Adaptive filtering: remove transition artifact "dark pauses" that
      // barely meet the minimum but are much shorter than real slide holds.
      // Real slides are held 1-3+ seconds; transition pauses are sub-second.
      let quietRuns = allQuietRuns
      if (allQuietRuns.length >= 3) {
        const lengths = allQuietRuns.map((r) => r.length).sort((a, b) => a - b)
        const median = lengths[Math.floor(lengths.length / 2)]
        const adaptiveMin = Math.max(MIN_QUIET_RUN, Math.floor(median * 0.5))
        quietRuns = allQuietRuns.filter((r) => r.length >= adaptiveMin)
      }

      const detectedSlides: SlideInfo[] = []
      for (let i = 0; i < quietRuns.length; i++) {
        const run = quietRuns[i]
        const prevRun = i > 0 ? quietRuns[i - 1] : null
        // Use middle of quiet run as display frame (most settled, avoids transition edges)
        const midFrame = Math.floor((run.start + run.end) / 2)
        detectedSlides.push({
          restFrame: midFrame,
          holdStart: run.start,
          holdEnd: run.end,
          transitionFrames: prevRun ? { start: prevRun.end + 1, end: run.start - 1 } : null,
        })
      }

      if (detectedSlides.length === 0) {
        detectedSlides.push({
          restFrame: 0,
          holdStart: 0,
          holdEnd: frames.length - 1,
          transitionFrames: null,
        })
      }

      if (detectedSlides.length < 2) {
        setWarning('Could not detect slide boundaries. Try re-exporting with longer auto-advance timing (1-2 seconds).')
      }

      console.log(`Detected ${detectedSlides.length} slides from ${frames.length} frames`)

      parsedRef.current = { frames, slides: detectedSlides, width: gifWidth, height: gifHeight, frameDelay }
      setCurrentSlide(0)
      setPhase('viewing')

      requestAnimationFrame(() => {
        renderSlideToCanvas(0)
      })
    } catch (err) {
      setError(`Failed to parse GIF: ${err instanceof Error ? err.message : String(err)}`)
      setPhase('drop')
    }
  }

  // ── Canvas Rendering + Playback ──

  const renderSlideToCanvas = (index: number) => {
    const canvas = canvasRef.current
    const parsed = parsedRef.current
    if (!canvas || !parsed) return

    const ctx = canvas.getContext('2d')
    if (!ctx) return

    canvas.width = parsed.width
    canvas.height = parsed.height

    const slide = parsed.slides[index]
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    ctx.drawImage(parsed.frames[slide.restFrame], 0, 0)
    setCurrentSlide(index)
  }

  const playNext = useCallback(() => {
    if (isPlayingRef.current) return
    const parsed = parsedRef.current
    if (!parsed) return

    setCurrentSlide((prev) => {
      if (prev >= parsed.slides.length - 1) return prev

      const nextSlide = parsed.slides[prev + 1]
      if (!nextSlide.transitionFrames) {
        renderSlideToCanvas(prev + 1)
        return prev + 1
      }

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
          renderSlideToCanvas(targetSlide)
        }
      }

      requestAnimationFrame(playFrame)
      return prev
    })
  }, [])

  const playPrev = useCallback(() => {
    if (isPlayingRef.current) return
    setCurrentSlide((prev) => {
      if (prev <= 0) return prev
      renderSlideToCanvas(prev - 1)
      return prev - 1
    })
  }, [])

  const jumpToSlide = useCallback((index: number) => {
    if (isPlayingRef.current) return
    renderSlideToCanvas(index)
  }, [])

  const loadAnother = useCallback(() => {
    if (parsedRef.current?.frames) {
      parsedRef.current.frames.forEach((bmp) => bmp.close())
    }
    parsedRef.current = null
    setCurrentSlide(0)
    setIsPlaying(false)
    setPhase('drop')
    clearMessages()
    setProjectName('')
    setSecureEmbed(true)
    setDeployResult(null)
    setDeployError('')
    setDeploySteps([])
    setCopied(null)
    setGifFilePath('')
    setGifFileSize(0)
    if (fileInputRef.current) fileInputRef.current.value = ''
  }, [clearMessages])

  // ── Deploy Functions ──

  const startConfirm = async () => {
    const settingsRes = await window.electron.loadSettings()
    const prefix = settingsRes.success && settingsRes.data?.projectNamePrefix
      ? settingsRes.data.projectNamePrefix
      : ''
    const baseName = gifFilePath
      ? gifFilePath.split('/').pop()?.replace(/\.gif$/i, '') || 'presentation'
      : 'presentation'
    setProjectName(prefix + toKebabCase(baseName))
    setPhase('confirm')
  }

  const startDeploy = async () => {
    if (!gifFilePath) {
      setDeployError('No GIF file path available. Try dropping the file again.')
      setPhase('error')
      return
    }
    setPhase('deploying')
    setDeploySteps([
      { id: 1, label: 'Preparing files', detail: '', status: 'pending' },
      { id: 2, label: 'Creating Vercel project', detail: '', status: 'pending' },
      { id: 3, label: 'Deploying to Vercel', detail: '', status: 'pending' },
      { id: 4, label: 'Complete', detail: '', status: 'pending' },
    ])

    const res = await window.electron.deployGif({
      gifPath: gifFilePath,
      projectName,
      slideCount: parsedRef.current?.slides.length ?? 0,
      title: gifFilePath.split('/').pop()?.replace(/\.gif$/i, '') || 'GIF Presentation',
      secureEmbed,
    })

    if (res.success && res.data?.success) {
      setDeployResult({ url: res.data.url })
      setPhase('complete')
    } else {
      setDeployError(res.error || res.data?.error || 'Deployment failed')
      setPhase('error')
    }
  }

  const copyText = async (text: string, label: string) => {
    await window.electron.copyToClipboard(text)
    setCopied(label)
    setTimeout(() => setCopied(null), 2000)
  }

  // Deploy progress listener
  useEffect(() => {
    if (phase !== 'deploying') return
    const handler = (progress: any) => {
      setDeploySteps(prev => prev.map(s => s.id === progress.step.id ? { ...progress.step } : s))
    }
    window.electron.onProcessingProgress(handler)
    return () => { window.electron.removeAllListeners('processing-progress') }
  }, [phase])

  // Keyboard controls
  useEffect(() => {
    if (phase !== 'viewing') return
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight') playNext()
      if (e.key === 'ArrowLeft') playPrev()
    }
    document.addEventListener('keydown', handler)
    return () => document.removeEventListener('keydown', handler)
  }, [phase, playNext, playPrev])

  // ── Render ──

  const slides = parsedRef.current?.slides ?? []
  const slideCount = slides.length

  return (
    <div className="h-full flex flex-col">
      <div className="window-drag h-14 flex-shrink-0" />

      <div className="flex-1 overflow-y-auto px-8 pb-8">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-semibold">Preview</h1>
          {phase === 'viewing' && (
            <button onClick={loadAnother} className="btn btn-ghost btn-sm">
              Load Another GIF
            </button>
          )}
        </div>

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
                if (file) {
                  setGifFilePath(window.electron.getFilePath(file))
                  setGifFileSize(file.size)
                  handleFile(file)
                }
              }}
            />
          </div>
        )}

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

        {phase === 'viewing' && (
          <div className="flex flex-col items-center">
            <div className="w-full max-w-[1080px]">
              <canvas
                ref={canvasRef}
                className="w-full h-auto rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-100 dark:bg-gray-800"
              />
            </div>

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

            <div className="mt-8 pt-6 border-t border-gray-200 dark:border-gray-700">
              <button
                onClick={startConfirm}
                className="btn btn-primary w-full"
              >
                Deploy to Vercel
              </button>
            </div>
          </div>
        )}

        {phase === 'confirm' && (
          <div className="max-w-lg mx-auto">
            <h1 className="text-2xl font-semibold mb-6">Confirm & Deploy GIF</h1>

            <div className="card p-5 mb-6 space-y-3">
              <div className="flex justify-between text-[15px]">
                <span className="text-gray-500 dark:text-gray-400">File</span>
                <span className="font-medium truncate max-w-[280px]">{gifFilePath.split('/').pop()}</span>
              </div>
              <div className="flex justify-between text-[15px]">
                <span className="text-gray-500 dark:text-gray-400">Slides</span>
                <span className="font-medium">{parsedRef.current?.slides.length ?? 0}</span>
              </div>
              <div className="flex justify-between text-[15px]">
                <span className="text-gray-500 dark:text-gray-400">Dimensions</span>
                <span className="font-medium">{parsedRef.current?.width ?? 0} x {parsedRef.current?.height ?? 0}</span>
              </div>
              <div className="flex justify-between text-[15px]">
                <span className="text-gray-500 dark:text-gray-400">Size</span>
                <span className="font-medium">{(gifFileSize / (1024 * 1024)).toFixed(1)} MB</span>
              </div>
            </div>

            <div className="mb-6">
              <label className="block text-[15px] font-medium mb-1.5">Project Name</label>
              <input
                type="text"
                className="input font-mono"
                value={projectName}
                onChange={(e) => setProjectName(e.target.value.toLowerCase())}
                onBlur={(e) => setProjectName(toKebabCase(e.target.value))}
                placeholder="my-project-name"
              />
              <p className="text-[13px] text-gray-400 mt-1">
                {projectName ? `URL will be: https://${projectName}.vercel.app` : 'Lowercase letters, numbers, and hyphens only'}
              </p>
            </div>

            <label className="flex items-center gap-2 mb-4 text-[13px] text-gray-500 dark:text-gray-400 cursor-pointer">
              <input
                type="checkbox"
                checked={secureEmbed}
                onChange={(e) => setSecureEmbed(e.target.checked)}
                className="rounded"
              />
              Secure Embed — disable downloads, restrict embedding to portal
            </label>

            <div className="flex gap-3">
              <button onClick={() => setPhase('viewing')} className="btn btn-secondary">
                Back
              </button>
              <button
                onClick={startDeploy}
                disabled={!projectName.trim()}
                className="btn btn-primary flex-1"
              >
                Deploy GIF
              </button>
            </div>
          </div>
        )}

        {phase === 'deploying' && (
          <div className="max-w-lg mx-auto">
            <h1 className="text-2xl font-semibold mb-2">Deploying GIF...</h1>
            <p className="text-[15px] text-gray-500 dark:text-gray-400 mb-6">
              Generating viewer and deploying to Vercel.
            </p>
            <div className="card p-4 space-y-2">
              {deploySteps.map(step => (
                <div key={step.id} className="flex items-center gap-2 text-[13px]">
                  {step.status === 'completed' ? (
                    <span className="text-green-500">&#10003;</span>
                  ) : step.status === 'active' ? (
                    <span className="spinner spinner-sm text-primary" />
                  ) : step.status === 'error' ? (
                    <span className="text-red-500">&#10007;</span>
                  ) : (
                    <span className="text-gray-400">&#9675;</span>
                  )}
                  <span className={step.status === 'active' ? 'text-gray-200' : 'text-gray-500'}>{step.label}</span>
                  {step.detail && <span className="text-gray-500 ml-auto text-[11px]">{step.detail}</span>}
                </div>
              ))}
            </div>
          </div>
        )}

        {phase === 'complete' && deployResult && (
          <div className="max-w-lg mx-auto">
            <div className="text-center mb-6">
              <div className="mb-3 flex justify-center">
                <svg className="w-12 h-12 text-green-500 dark:text-green-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <circle cx="12" cy="12" r="10" />
                  <polyline points="8,12 11,15 16,9" />
                </svg>
              </div>
              <h1 className="text-2xl font-semibold text-green-600 dark:text-green-400">
                GIF Deployed Successfully
              </h1>
              <p className="text-[15px] text-gray-500 dark:text-gray-400 mt-1">
                {parsedRef.current?.slides.length ?? 0} slides, interactive viewer live on Vercel
              </p>
            </div>

            <div className="card p-5 mb-6">
              <div className="flex items-center gap-2 mb-4">
                <input
                  type="text"
                  readOnly
                  className="input font-mono text-[13px] flex-1"
                  value={deployResult.url}
                />
                <button
                  onClick={() => copyText(deployResult.url, 'url')}
                  className="btn btn-primary btn-sm whitespace-nowrap"
                >
                  {copied === 'url' ? 'Copied!' : 'Copy URL'}
                </button>
              </div>

              <div className="flex gap-2">
                <button
                  onClick={() => {
                    const w = parsedRef.current?.width || 1080
                    const h = parsedRef.current?.height || 608
                    copyText(`<div style="position:relative;width:100%;aspect-ratio:${w}/${h}"><iframe src="${deployResult.url}" style="position:absolute;inset:0;width:100%;height:100%;border:none" loading="lazy" allowfullscreen></iframe></div>`, 'embed')
                  }}
                  className="btn btn-secondary btn-sm flex-1"
                >
                  {copied === 'embed' ? 'Copied!' : 'Copy Framer Embed'}
                </button>
                <button
                  onClick={() => window.electron.openUrl(deployResult.url)}
                  className="btn btn-ghost btn-sm"
                >
                  Open in Browser
                </button>
              </div>
            </div>

            <button onClick={loadAnother} className="btn btn-secondary w-full">
              Deploy Another
            </button>
          </div>
        )}

        {phase === 'error' && (
          <div className="max-w-lg mx-auto">
            <div className="text-center mb-6">
              <div className="mb-3 flex justify-center">
                <svg className="w-12 h-12 text-red-500 dark:text-red-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <circle cx="12" cy="12" r="10" />
                  <line x1="15" y1="9" x2="9" y2="15" />
                  <line x1="9" y1="9" x2="15" y2="15" />
                </svg>
              </div>
              <h1 className="text-2xl font-semibold text-red-600 dark:text-red-400">
                Deployment Failed
              </h1>
            </div>

            {deployError && (
              <div className="p-3 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 mb-6">
                <p className="text-[15px] text-red-600 dark:text-red-400 font-mono">{deployError}</p>
              </div>
            )}

            <div className="flex gap-3">
              <button onClick={loadAnother} className="btn btn-secondary flex-1">
                Start Over
              </button>
              <button onClick={startDeploy} className="btn btn-primary flex-1">
                Retry
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
