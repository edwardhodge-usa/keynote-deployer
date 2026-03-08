import { useState, useEffect } from 'react'
import type { AppSettings } from '../types'

export default function Settings() {
  const [settings, setSettings] = useState<AppSettings>({
    vercelToken: '',
    vercelTeamId: 'team_E1wAzl9zyAPrlGzyjmcXNuxd',
    theme: 'system',
    autoCopyUrl: true,
    enableRuntimeVerification: false,
    projectNamePrefix: '',
    lastFolderPath: '',
  })
  const [loading, setLoading] = useState(true)
  const [saved, setSaved] = useState(false)
  const [detecting, setDetecting] = useState(false)
  const [tokenStatus, setTokenStatus] = useState<'unknown' | 'valid' | 'missing'>('unknown')

  useEffect(() => {
    loadSettings()
  }, [])

  const loadSettings = async () => {
    setLoading(true)
    const res = await window.electron.loadSettings()
    if (res.success && res.data) {
      setSettings(res.data)
      setTokenStatus(res.data.vercelToken ? 'valid' : 'missing')
    }
    setLoading(false)
  }

  const save = async (updates: Partial<AppSettings>) => {
    const merged = { ...settings, ...updates }
    setSettings(merged)

    await window.electron.saveSettings(merged)
    setSaved(true)
    setTimeout(() => setSaved(false), 2000)
  }

  const detectToken = async () => {
    setDetecting(true)
    const res = await window.electron.detectVercelToken()
    setDetecting(false)

    if (res.success && res.data?.found && res.data.token) {
      await save({ vercelToken: res.data.token })
      setTokenStatus('valid')
    } else {
      setTokenStatus('missing')
    }
  }

  if (loading) {
    return (
      <div className="h-full flex items-center justify-center">
        <span className="spinner text-primary" />
      </div>
    )
  }

  return (
    <div className="h-full flex flex-col">
      <div className="window-drag h-14 flex-shrink-0" />

      <div className="flex-1 overflow-y-auto px-8 pb-8">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-semibold">Settings</h1>
          {saved && (
            <span className="badge badge-success">Saved</span>
          )}
        </div>

        <div className="max-w-lg space-y-8">
          {/* Vercel Configuration */}
          <section>
            <h2 className="text-[11px] font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-4">
              Vercel
            </h2>

            <div className="card p-5 space-y-4">
              <div>
                <div className="flex items-center justify-between mb-1.5">
                  <label className="text-[15px] font-medium">Auth Token</label>
                  <div className="flex items-center gap-2">
                    {tokenStatus === 'valid' && (
                      <span className="badge badge-success">Connected</span>
                    )}
                    {tokenStatus === 'missing' && (
                      <span className="badge badge-warning">Not Set</span>
                    )}
                  </div>
                </div>
                <div className="flex gap-2">
                  <input
                    type="password"
                    className="input font-mono text-[13px] flex-1"
                    value={settings.vercelToken}
                    onChange={(e) => save({ vercelToken: e.target.value })}
                    placeholder="Enter Vercel auth token..."
                  />
                  <button
                    onClick={detectToken}
                    disabled={detecting}
                    className="btn btn-secondary btn-sm whitespace-nowrap"
                  >
                    {detecting ? 'Detecting...' : 'Auto-Detect'}
                  </button>
                </div>
                <p className="text-[13px] text-gray-400 mt-1">
                  Auto-detect reads from Vercel CLI config, or paste your token manually.
                </p>
              </div>

              <div>
                <label className="text-[15px] font-medium block mb-1.5">Team ID</label>
                <input
                  type="text"
                  className="input font-mono text-[13px]"
                  value={settings.vercelTeamId}
                  onChange={(e) => save({ vercelTeamId: e.target.value })}
                />
              </div>
            </div>
          </section>

          {/* Deployment Preferences */}
          <section>
            <h2 className="text-[11px] font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-4">
              Deployment
            </h2>

            <div className="card p-5 space-y-4">
              <div>
                <label className="text-[15px] font-medium block mb-1.5">Project Name Prefix</label>
                <input
                  type="text"
                  className="input font-mono text-[13px]"
                  value={settings.projectNamePrefix}
                  onChange={(e) => save({ projectNamePrefix: e.target.value })}
                  placeholder="e.g. ils-"
                />
                <p className="text-[13px] text-gray-400 mt-1">
                  Optional prefix added to auto-generated project names.
                </p>
              </div>

              <div className="flex items-center justify-between">
                <div>
                  <p className="text-[15px] font-medium">Auto-copy URL</p>
                  <p className="text-[13px] text-gray-400">Copy deployment URL to clipboard after deploy</p>
                </div>
                <button
                  onClick={() => save({ autoCopyUrl: !settings.autoCopyUrl })}
                  className={`relative w-9 h-[22px] rounded-full transition-colors duration-250 flex-shrink-0 ${
                    settings.autoCopyUrl ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-600'
                  }`}
                  role="switch"
                  aria-checked={settings.autoCopyUrl}
                  aria-label="Auto-copy URL"
                >
                  <span
                    className={`absolute top-[2px] left-[2px] w-[18px] h-[18px] bg-white rounded-full shadow-sm transition-transform duration-250 ${
                      settings.autoCopyUrl ? 'translate-x-[14px]' : ''
                    }`}
                  />
                </button>
              </div>

              <div className="flex items-center justify-between">
                <div>
                  <p className="text-[15px] font-medium">Runtime Verification</p>
                  <p className="text-[13px] text-gray-400">Use browser automation to test deployed presentations</p>
                </div>
                <button
                  onClick={() => save({ enableRuntimeVerification: !settings.enableRuntimeVerification })}
                  className={`relative w-9 h-[22px] rounded-full transition-colors duration-250 flex-shrink-0 ${
                    settings.enableRuntimeVerification ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-600'
                  }`}
                  role="switch"
                  aria-checked={settings.enableRuntimeVerification}
                  aria-label="Runtime verification"
                >
                  <span
                    className={`absolute top-[2px] left-[2px] w-[18px] h-[18px] bg-white rounded-full shadow-sm transition-transform duration-250 ${
                      settings.enableRuntimeVerification ? 'translate-x-[14px]' : ''
                    }`}
                  />
                </button>
              </div>
            </div>
          </section>
        </div>
      </div>
    </div>
  )
}
