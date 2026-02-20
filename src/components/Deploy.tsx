import { useState, useEffect, useCallback } from 'react'
import DeployProgress from './DeployProgress'
import type { KeynoteMetadata, ProcessingStep, ProcessingProgress, PipelineResult } from '../types'

interface DeployProps {
  selectedProject?: string
  onProjectUsed: () => void
}

type Phase = 'select' | 'confirm' | 'processing' | 'complete' | 'error'

const INITIAL_STEPS: ProcessingStep[] = Array.from({ length: 15 }, (_, i) => ({
  id: i + 1,
  label: [
    'Validate folder',
    'Read metadata',
    'Backup main.js',
    'Fix 1: zC scale',
    'Fix 2: Fullscreen bypass',
    'Fix 3: Viewport A',
    'Fix 4: Viewport B',
    'Fix 5: Resize viewport',
    'Fix 6: Constructor viewport',
    'Fix 7: Canvas DPR',
    'Generate index.html',
    'Vercel project',
    'Deploy',
    'Verify deployment',
    'Complete',
  ][i],
  detail: '',
  status: 'pending' as const,
}))

function toKebabCase(str: string): string {
  return str
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
}

export default function Deploy({ selectedProject, onProjectUsed }: DeployProps) {
  const [phase, setPhase] = useState<Phase>('select')
  const [folderPath, setFolderPath] = useState('')
  const [metadata, setMetadata] = useState<KeynoteMetadata | null>(null)
  const [projectName, setProjectName] = useState('')
  const [steps, setSteps] = useState<ProcessingStep[]>(INITIAL_STEPS)
  const [result, setResult] = useState<PipelineResult | null>(null)
  const [error, setError] = useState('')
  const [validating, setValidating] = useState(false)
  const [copied, setCopied] = useState<string | null>(null)

  // Listen for processing progress
  useEffect(() => {
    window.electron.onProcessingProgress((progress: ProcessingProgress) => {
      setSteps((prev) =>
        prev.map((s) => (s.id === progress.step.id ? { ...progress.step } : s))
      )
    })

    return () => {
      window.electron.removeAllListeners('processing-progress')
    }
  }, [])

  const selectFolder = useCallback(async () => {
    const res = await window.electron.selectFolder()
    if (res.success && res.data) {
      await validateFolder(res.data)
    }
  }, [])

  const validateFolder = async (path: string) => {
    setValidating(true)
    setError('')

    const res = await window.electron.validateKeynoteFolder(path)
    setValidating(false)

    if (res.success && res.data?.valid && res.data.metadata) {
      setFolderPath(path)
      setMetadata(res.data.metadata)

      // Use selectedProject if provided, otherwise generate from title
      if (selectedProject) {
        setProjectName(selectedProject)
        onProjectUsed() // Clear selected project after using
      } else {
        // Load settings to get prefix
        const settingsRes = await window.electron.loadSettings()
        const prefix = settingsRes.success && settingsRes.data?.projectNamePrefix
          ? settingsRes.data.projectNamePrefix
          : ''

        setProjectName(prefix + toKebabCase(res.data.metadata.title))
      }

      setPhase('confirm')
    } else {
      setError(res.data?.error || res.error || 'Invalid folder')
    }
  }

  const handleDrop = useCallback(async (e: React.DragEvent) => {
    e.preventDefault()
    const items = e.dataTransfer.files
    if (items.length > 0) {
      const droppedPath = (items[0] as File & { path: string }).path
      if (droppedPath) {
        await validateFolder(droppedPath)
      }
    }
  }, [])

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault()
  }

  const startDeploy = async () => {
    if (!metadata) return
    setPhase('processing')
    setSteps(INITIAL_STEPS.map((s) => ({ ...s })))

    const res = await window.electron.processAndDeploy({
      folderPath,
      projectName,
      metadata,
    })

    if (res.success && res.data?.success) {
      setResult(res.data)
      setPhase('complete')
    } else {
      setResult(res.data || null)
      setError(res.error || res.data?.error || 'Pipeline failed')
      setPhase('error')
    }
  }

  const copyText = async (text: string, label: string) => {
    await window.electron.copyToClipboard(text)
    setCopied(label)
    setTimeout(() => setCopied(null), 2000)
  }

  const reset = () => {
    setPhase('select')
    setFolderPath('')
    setMetadata(null)
    setProjectName('')
    setSteps(INITIAL_STEPS)
    setResult(null)
    setError('')
    onProjectUsed() // Clear selectedProject in parent state
  }

  const framerEmbed = result?.url
    ? `<iframe src="${result.url}" style="width:100%;height:100%;border:none" allowfullscreen></iframe>`
    : ''

  return (
    <div className="h-full flex flex-col">
      {/* Titlebar drag area */}
      <div className="window-drag h-14 flex-shrink-0" />

      <div className="flex-1 overflow-y-auto px-8 pb-8">
        {/* ── Select Phase ── */}
        {phase === 'select' && (
          <div className="max-w-lg mx-auto">
            <h1 className="text-2xl font-semibold mb-2">Deploy Keynote</h1>
            <p className="text-sm text-gray-500 dark:text-gray-400 mb-6">
              Select a Keynote HTML export folder to process and deploy.
            </p>

            <div
              onDrop={handleDrop}
              onDragOver={handleDragOver}
              className="card p-12 text-center cursor-pointer hover:border-primary transition-colors"
              onClick={selectFolder}
            >
              <div className="text-4xl mb-4 text-gray-400 dark:text-gray-500">
                {validating ? '' : '\uD83D\uDCC1'}
              </div>
              {validating ? (
                <>
                  <span className="spinner text-primary mb-3 inline-block" />
                  <p className="text-sm text-gray-500">Validating folder...</p>
                </>
              ) : (
                <>
                  <p className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                    Click to browse or drag & drop
                  </p>
                  <p className="text-xs text-gray-400 dark:text-gray-500">
                    Select the exported Keynote folder containing assets/player/main.js
                  </p>
                </>
              )}
            </div>

            {error && (
              <div className="mt-4 p-3 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
                <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
              </div>
            )}
          </div>
        )}

        {/* ── Confirm Phase ── */}
        {phase === 'confirm' && metadata && (
          <div className="max-w-lg mx-auto">
            <h1 className="text-2xl font-semibold mb-6">Confirm & Deploy</h1>

            <div className="card p-5 mb-6 space-y-3">
              <div className="flex justify-between text-sm">
                <span className="text-gray-500 dark:text-gray-400">Title</span>
                <span className="font-medium">{metadata.title}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-500 dark:text-gray-400">Slides</span>
                <span className="font-medium">{metadata.slideCount}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-500 dark:text-gray-400">Dimensions</span>
                <span className="font-medium">{metadata.width} x {metadata.height}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-500 dark:text-gray-400">Folder</span>
                <span className="font-mono text-xs truncate max-w-[280px]">{folderPath}</span>
              </div>
            </div>

            <div className="mb-6">
              <label className="block text-sm font-medium mb-1.5">Project Name</label>
              <input
                type="text"
                className="input font-mono"
                value={projectName}
                onChange={(e) => setProjectName(e.target.value)}
              />
              <p className="text-xs text-gray-400 mt-1">
                {selectedProject
                  ? `⚠ Updating existing project: ${selectedProject}`
                  : `URL will be: https://${projectName}.vercel.app`
                }
              </p>
            </div>

            <div className="flex gap-3">
              <button onClick={reset} className="btn btn-secondary">
                Back
              </button>
              <button
                onClick={startDeploy}
                disabled={!projectName.trim()}
                className="btn btn-primary flex-1"
              >
                Process & Deploy
              </button>
            </div>
          </div>
        )}

        {/* ── Processing Phase ── */}
        {phase === 'processing' && (
          <div className="max-w-lg mx-auto">
            <h1 className="text-2xl font-semibold mb-2">Deploying...</h1>
            <p className="text-sm text-gray-500 dark:text-gray-400 mb-6">
              Applying fixes and deploying to Vercel.
            </p>
            <div className="card p-4">
              <DeployProgress steps={steps} currentStep={0} />
            </div>
          </div>
        )}

        {/* ── Complete Phase ── */}
        {phase === 'complete' && result && (
          <div className="max-w-lg mx-auto">
            <div className="text-center mb-6">
              <div className="text-5xl mb-3">&#10003;</div>
              <h1 className="text-2xl font-semibold text-green-600 dark:text-green-400">
                Deployed Successfully
              </h1>
              <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
                {result.fixesApplied} fixes applied, {result.fixesSkipped} skipped
              </p>
            </div>

            {/* Verification Results */}
            {result.verification && (
              <div className="card p-4 mb-6">
                <h3 className="text-sm font-semibold mb-3 text-gray-700 dark:text-gray-300">
                  Deployment Verification
                </h3>

                {result.verification.success ? (
                  <div className="flex items-center gap-2 text-green-600 dark:text-green-400 text-sm mb-3">
                    <span>✓</span>
                    <span>All {result.verification.totalFixesFound} fixes verified in deployed files</span>
                  </div>
                ) : (
                  <div className="mb-3">
                    <div className="flex items-center gap-2 text-amber-600 dark:text-amber-400 text-sm mb-2">
                      <span>⚠</span>
                      <span>{result.verification.totalFixesMissing} fixes missing in deployment</span>
                    </div>
                  </div>
                )}

                <div className="space-y-1.5 text-xs">
                  {result.verification.fixes.map((fix) => (
                    <div key={fix.fixNumber} className="flex items-center gap-2">
                      <span className={fix.found ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}>
                        {fix.found ? '✓' : '✗'}
                      </span>
                      <span className={fix.found ? 'text-gray-600 dark:text-gray-400' : 'text-red-600 dark:text-red-400'}>
                        Fix {fix.fixNumber}: {fix.name}
                      </span>
                    </div>
                  ))}
                </div>

                {!result.verification.indexHtmlVerified && (
                  <div className="mt-3 text-xs text-amber-600 dark:text-amber-400">
                    ⚠ index.html verification failed
                  </div>
                )}
              </div>
            )}

            <div className="card p-5 mb-6">
              <div className="flex items-center gap-2 mb-4">
                <input
                  type="text"
                  readOnly
                  className="input font-mono text-sm flex-1"
                  value={result.url}
                />
                <button
                  onClick={() => copyText(result.url, 'url')}
                  className="btn btn-primary btn-sm whitespace-nowrap"
                >
                  {copied === 'url' ? 'Copied!' : 'Copy URL'}
                </button>
              </div>

              <div className="flex gap-2">
                <button
                  onClick={() => copyText(framerEmbed, 'embed')}
                  className="btn btn-secondary btn-sm flex-1"
                >
                  {copied === 'embed' ? 'Copied!' : 'Copy Framer Embed'}
                </button>
                <button
                  onClick={() => window.electron.openUrl(result.url)}
                  className="btn btn-ghost btn-sm"
                >
                  Open in Browser
                </button>
              </div>
            </div>

            <button onClick={reset} className="btn btn-secondary w-full">
              Deploy Another
            </button>
          </div>
        )}

        {/* ── Error Phase ── */}
        {phase === 'error' && (
          <div className="max-w-lg mx-auto">
            <div className="text-center mb-6">
              <div className="text-5xl mb-3">&#10007;</div>
              <h1 className="text-2xl font-semibold text-red-600 dark:text-red-400">
                Deployment Failed
              </h1>
            </div>

            <div className="card p-4 mb-6">
              <DeployProgress steps={steps} currentStep={0} />
            </div>

            {error && (
              <div className="p-3 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 mb-6">
                <p className="text-sm text-red-600 dark:text-red-400 font-mono">{error}</p>
              </div>
            )}

            <div className="flex gap-3">
              <button onClick={reset} className="btn btn-secondary flex-1">
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
