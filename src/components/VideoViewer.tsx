import { useState, useRef, useCallback, useEffect } from 'react'
import { toKebabCase } from '../utils/strings'
import type { ProcessingStep } from '../types'

// Deploy a deck VIDEO (H.264) as an interactive slide viewer. Supersedes the GIF
// path for held-build / constant-background decks (see docs/VIDEO_DECK_VIEWER.md).
// The per-slide stills are the slide-count + boundary ground truth; the backend
// (deploy-video → videoDeckPipeline) DP-matches them to video frames to derive
// timestamps, then re-encodes with a forced keyframe at each slide. So this view
// does NOT parse or detect anything client-side — it just collects the video,
// the stills folder, and the frame rate, then hands off to the main process.

type Phase = 'drop' | 'confirm' | 'deploying' | 'complete' | 'error'

const VIDEO_EXT = /\.(mp4|mov|m4v)$/i
const MAX_SIZE = 500 * 1024 * 1024 // 500 MB — video is heavier than GIF

export default function VideoViewer() {
  const [phase, setPhase] = useState<Phase>('drop')
  const [dragOver, setDragOver] = useState(false)
  const [error, setError] = useState('')

  const [videoFilePath, setVideoFilePath] = useState('')
  const [videoFileSize, setVideoFileSize] = useState(0)
  const [videoDims, setVideoDims] = useState<{ w: number; h: number } | null>(null)
  const [fps, setFps] = useState(30)
  const [stillPaths, setStillPaths] = useState<string[]>([])
  const [stillsStatus, setStillsStatus] = useState('')
  const [stillsLoading, setStillsLoading] = useState(false)

  const [projectName, setProjectName] = useState('')
  const [secureEmbed, setSecureEmbed] = useState(true)

  const [deploySteps, setDeploySteps] = useState<ProcessingStep[]>([])
  const [deployResult, setDeployResult] = useState<{ url: string; slideCount: number } | null>(null)
  const [deployError, setDeployError] = useState('')
  const [copied, setCopied] = useState<string | null>(null)

  const fileInputRef = useRef<HTMLInputElement>(null)

  // ── File handling ──

  const baseTitle = useCallback(
    () => videoFilePath.split('/').pop()?.replace(VIDEO_EXT, '') || 'Presentation',
    [videoFilePath]
  )

  const acceptVideo = useCallback(async (path: string, size: number) => {
    setError('')
    if (!VIDEO_EXT.test(path)) {
      setError(`Please select an H.264 video (.mp4 / .mov / .m4v). Got: ${path.split('/').pop()}`)
      return
    }
    if (size > MAX_SIZE) {
      setError(`File too large (${(size / (1024 * 1024)).toFixed(0)} MB). Maximum is 500 MB.`)
      return
    }
    setVideoFilePath(path)
    setVideoFileSize(size)
    setVideoDims(null)
    setStillPaths([])
    setStillsStatus('')

    const settingsRes = await window.electron.loadSettings()
    const prefix = settingsRes.success && settingsRes.data?.projectNamePrefix ? settingsRes.data.projectNamePrefix : ''
    const name = path.split('/').pop()?.replace(VIDEO_EXT, '') || 'presentation'
    setProjectName(prefix + toKebabCase(name))
    setPhase('confirm')
  }, [])

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault(); e.stopPropagation(); setDragOver(false)
    const file = e.dataTransfer.files[0]
    if (file) acceptVideo(window.electron.getFilePath(file), file.size)
  }, [acceptVideo])

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault(); e.stopPropagation(); setDragOver(true)
  }, [])

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault(); e.stopPropagation(); setDragOver(false)
  }, [])

  const pickStillsFolder = useCallback(async () => {
    setStillsLoading(true)
    setStillsStatus('Picking folder…')
    try {
      const res = await window.electron.selectStillsFolder()
      if (!res.success) {
        setStillsStatus(res.error === 'cancelled' ? '' : `Error: ${res.error}`)
        setStillPaths([])
        return
      }
      const paths = res.data!
      setStillPaths(paths)
      setStillsStatus(`${paths.length} stills selected — ${paths.length} slides`)
    } catch (err) {
      setStillsStatus(`Error: ${err instanceof Error ? err.message : String(err)}`)
      setStillPaths([])
    } finally {
      setStillsLoading(false)
    }
  }, [])

  // ── Deploy ──

  const startDeploy = async () => {
    if (!videoFilePath) {
      setDeployError('No video file path available. Try selecting the file again.')
      setPhase('error'); return
    }
    if (stillPaths.length === 0) {
      setDeployError('Pick a stills folder first — the per-slide stills are the slide-count source.')
      setPhase('error'); return
    }

    setPhase('deploying')
    setDeploySteps([
      { id: 1, label: 'Preparing video', detail: '', status: 'pending' },
      { id: 2, label: 'Creating Vercel project', detail: '', status: 'pending' },
      { id: 3, label: 'Deploying to Vercel', detail: '', status: 'pending' },
      { id: 4, label: 'Complete', detail: '', status: 'pending' },
    ])

    const res = await window.electron.deployVideo({
      videoPath: videoFilePath,
      stillPaths,
      fps,
      projectName,
      title: baseTitle(),
      secureEmbed,
    })

    if (res.success && res.data?.success) {
      setDeployResult({ url: res.data.url, slideCount: res.data.slideCount })
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

  const startOver = () => {
    setPhase('drop')
    setVideoFilePath(''); setVideoFileSize(0); setVideoDims(null)
    setStillPaths([]); setStillsStatus(''); setFps(30)
    setProjectName(''); setSecureEmbed(true)
    setDeployResult(null); setDeployError(''); setError('')
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

  // ── Render ──

  return (
    <div className="h-full flex flex-col">
      <div className="window-drag h-14 flex-shrink-0" />

      <div className="flex-1 overflow-y-auto px-8 pb-8">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-semibold">Deploy Video</h1>
          {phase === 'confirm' && (
            <button onClick={startOver} className="btn btn-ghost btn-sm">
              Load Another Video
            </button>
          )}
        </div>

        {error && (
          <div className="mb-4 p-3 rounded-lg bg-red-500/10 border border-red-500/20 text-red-400 text-[13px]">
            {error}
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
              <div className="text-4xl mb-4 opacity-50">🎬</div>
              <p className="text-[15px] text-gray-500 dark:text-gray-400">
                <span className="font-medium text-gray-700 dark:text-gray-300">Drop a deck video here</span>
                <br />or click to browse
              </p>
              <p className="text-[12px] text-gray-400 dark:text-gray-500 mt-2">
                Keynote movie export — H.264 .mp4 / .mov / .m4v up to 500 MB
              </p>
            </div>
            <input
              ref={fileInputRef}
              type="file"
              accept=".mp4,.mov,.m4v,video/mp4,video/quicktime"
              className="hidden"
              onChange={(e) => {
                const file = e.target.files?.[0]
                if (file) acceptVideo(window.electron.getFilePath(file), file.size)
              }}
            />
          </div>
        )}

        {phase === 'confirm' && (
          <div className="max-w-lg mx-auto">
            <div className="rounded-lg overflow-hidden border border-gray-200 dark:border-gray-700 bg-black mb-6">
              <video
                src={`file://${videoFilePath}`}
                controls
                muted
                playsInline
                className="w-full h-auto max-h-[360px] bg-black"
                onLoadedMetadata={(e) => {
                  const v = e.currentTarget
                  if (v.videoWidth && v.videoHeight) setVideoDims({ w: v.videoWidth, h: v.videoHeight })
                }}
              />
            </div>

            <div className="card p-5 mb-6 space-y-3">
              <div className="flex justify-between text-[15px]">
                <span className="text-gray-500 dark:text-gray-400">File</span>
                <span className="font-medium truncate max-w-[280px]">{videoFilePath.split('/').pop()}</span>
              </div>
              <div className="flex justify-between text-[15px]">
                <span className="text-gray-500 dark:text-gray-400">Dimensions</span>
                <span className="font-medium">{videoDims ? `${videoDims.w} x ${videoDims.h}` : '—'}</span>
              </div>
              <div className="flex justify-between text-[15px]">
                <span className="text-gray-500 dark:text-gray-400">Size</span>
                <span className="font-medium">{(videoFileSize / (1024 * 1024)).toFixed(1)} MB</span>
              </div>
              <div className="flex justify-between text-[15px]">
                <span className="text-gray-500 dark:text-gray-400">Slides</span>
                <span className="font-medium">{stillPaths.length || '—'}</span>
              </div>
            </div>

            {/* Stills folder — the slide-count + boundary source */}
            <div className="mb-6">
              <label className="block text-[15px] font-medium mb-2">Per-Slide Stills</label>
              <button
                onClick={pickStillsFolder}
                disabled={stillsLoading}
                className={`w-full px-3 py-2 rounded-lg border text-[13px] transition-all ${
                  stillPaths.length > 0
                    ? 'border-blue-500 bg-blue-500/10 text-blue-400'
                    : stillsLoading
                    ? 'border-gray-700 bg-transparent text-gray-500 cursor-wait'
                    : 'border-gray-600 bg-transparent text-gray-300 hover:border-gray-500'
                }`}
              >
                <div className="font-medium">
                  {stillPaths.length > 0 ? 'Stills folder selected' : 'Pick stills folder…'}
                </div>
                <div className="text-[11px] opacity-70 mt-0.5">
                  {stillPaths.length > 0
                    ? `${stillPaths.length} images — one JPEG/PNG per slide`
                    : 'One image per slide, natural-sorted (slide-01.jpg, slide-02.jpg…)'}
                </div>
              </button>
              {stillsStatus && (
                <p className={`text-[12px] mt-1.5 ${stillsStatus.startsWith('Error') ? 'text-yellow-400' : 'text-gray-400'}`}>
                  {stillsStatus}
                </p>
              )}
            </div>

            <div className="mb-6">
              <label className="block text-[15px] font-medium mb-1.5">Frame Rate (fps)</label>
              <input
                type="number"
                min={1}
                max={120}
                className="input w-32"
                value={fps}
                onChange={(e) => setFps(Math.max(1, Math.min(120, Number(e.target.value) || 30)))}
              />
              <p className="text-[13px] text-gray-400 mt-1">
                The constant frame rate of the Keynote movie export (usually 30).
              </p>
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

            {stillPaths.length === 0 && (
              <p className="text-[12px] text-yellow-400 mb-3">
                Pick a stills folder to deploy — it sets the slide count and boundaries.
              </p>
            )}
            <div className="flex gap-3">
              <button onClick={startOver} className="btn btn-secondary">
                Back
              </button>
              <button
                onClick={startDeploy}
                disabled={!projectName.trim() || stillPaths.length === 0}
                className="btn btn-primary flex-1"
              >
                Deploy Video
              </button>
            </div>
          </div>
        )}

        {phase === 'deploying' && (
          <div className="max-w-lg mx-auto">
            <h1 className="text-2xl font-semibold mb-2">Deploying Video…</h1>
            <p className="text-[15px] text-gray-500 dark:text-gray-400 mb-6">
              Matching slides, encoding keyframes, and deploying to Vercel.
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
                Video Deployed Successfully
              </h1>
              <p className="text-[15px] text-gray-500 dark:text-gray-400 mt-1">
                {deployResult.slideCount} slides, interactive viewer live on Vercel
              </p>
            </div>

            <div className="card p-5 mb-6">
              <div className="flex items-center gap-2 mb-4">
                <input type="text" readOnly className="input font-mono text-[13px] flex-1" value={deployResult.url} />
                <button onClick={() => copyText(deployResult.url, 'url')} className="btn btn-primary btn-sm whitespace-nowrap">
                  {copied === 'url' ? 'Copied!' : 'Copy URL'}
                </button>
              </div>

              <div className="flex gap-2">
                <button
                  onClick={() => {
                    const w = videoDims?.w || 1920
                    const h = videoDims?.h || 1080
                    copyText(`<div style="position:relative;width:100%;aspect-ratio:${w}/${h}"><iframe src="${deployResult.url}" style="position:absolute;inset:0;width:100%;height:100%;border:none" loading="lazy" allowfullscreen></iframe></div>`, 'embed')
                  }}
                  className="btn btn-secondary btn-sm flex-1"
                >
                  {copied === 'embed' ? 'Copied!' : 'Copy Framer Embed'}
                </button>
                <button onClick={() => window.electron.openUrl(deployResult.url)} className="btn btn-ghost btn-sm">
                  Open in Browser
                </button>
              </div>
            </div>

            <button onClick={startOver} className="btn btn-secondary w-full">
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
              <button onClick={startOver} className="btn btn-secondary flex-1">
                Start Over
              </button>
              <button onClick={() => setPhase('confirm')} className="btn btn-primary flex-1">
                Back to Confirm
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
