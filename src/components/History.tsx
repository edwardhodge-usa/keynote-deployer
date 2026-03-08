import { useState, useEffect } from 'react'
import type { HistoryEntry } from '../types'

export default function History() {
  const [entries, setEntries] = useState<HistoryEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [copied, setCopied] = useState<string | null>(null)
  const [confirmingDelete, setConfirmingDelete] = useState<string | null>(null)
  const [deletingId, setDeletingId] = useState<string | null>(null)
  const [deleteError, setDeleteError] = useState<Record<string, string>>({})

  useEffect(() => {
    loadHistory()
  }, [])

  const loadHistory = async () => {
    setLoading(true)
    const res = await window.electron.loadHistory()
    if (res.success && res.data) {
      setEntries(res.data)
    }
    setLoading(false)
  }

  const copyUrl = async (url: string, id: string) => {
    await window.electron.copyToClipboard(url)
    setCopied(id)
    setTimeout(() => setCopied(null), 2000)
  }

  const handleDelete = async (entry: HistoryEntry) => {
    setDeletingId(entry.id)
    setDeleteError((prev) => ({ ...prev, [entry.id]: '' }))

    try {
      const vercelResult = await window.electron.deleteVercelProject(entry.projectName)
      if (!vercelResult.success) {
        setDeleteError((prev) => ({
          ...prev,
          [entry.id]: vercelResult.error || 'Vercel deletion failed',
        }))
      }
    } catch {
      // Vercel delete failed — still clean up locally
    }

    await window.electron.removeHistoryEntry(entry.id)
    setEntries((prev) => prev.filter((e) => e.id !== entry.id))
    setDeletingId(null)
    setConfirmingDelete(null)
  }

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr)
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    })
  }

  return (
    <div className="h-full flex flex-col">
      <div className="window-drag h-14 flex-shrink-0" />

      <div className="flex-1 overflow-y-auto px-8 pb-8">
        <h1 className="text-2xl font-semibold mb-6">Deployment History</h1>

        {loading ? (
          <div className="text-center py-12">
            <span className="spinner text-primary" />
          </div>
        ) : entries.length === 0 ? (
          <div className="text-center py-12">
            <div className="mb-3 flex justify-center">
              <svg className="w-10 h-10 text-gray-300 dark:text-gray-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="10" />
                <polyline points="12,6 12,12 16,14" />
              </svg>
            </div>
            <p className="text-[15px] text-gray-500 dark:text-gray-400">
              No deployments yet. Deploy your first Keynote presentation!
            </p>
          </div>
        ) : (
          <div className="space-y-3">
            {entries.map((entry) => (
              <div key={entry.id} className="card p-4">
                <div className="flex items-start justify-between gap-4">
                  <div className="flex-1 min-w-0">
                    <h3 className="text-[15px] font-semibold truncate">{entry.title}</h3>
                    <p className="text-[13px] text-gray-500 dark:text-gray-400 mt-0.5">
                      {entry.projectName} &middot; {entry.slideCount} slides &middot; {entry.fixesApplied} fixes
                    </p>
                    <p className="text-[13px] text-gray-400 dark:text-gray-500 mt-1">
                      {formatDate(entry.date)}
                    </p>
                  </div>

                  <div className="flex gap-2 flex-shrink-0">
                    {confirmingDelete === entry.id ? (
                      <>
                        <button
                          onClick={() => setConfirmingDelete(null)}
                          disabled={deletingId === entry.id}
                          className="btn btn-ghost btn-sm"
                        >
                          Cancel
                        </button>
                        <button
                          onClick={() => handleDelete(entry)}
                          disabled={deletingId === entry.id}
                          className="btn btn-danger btn-sm"
                        >
                          {deletingId === entry.id ? (
                            <span className="spinner spinner-sm" />
                          ) : (
                            'Confirm Delete'
                          )}
                        </button>
                      </>
                    ) : (
                      <>
                        <button
                          onClick={() => copyUrl(entry.url, entry.id)}
                          className="btn btn-secondary btn-sm"
                        >
                          {copied === entry.id ? 'Copied!' : 'Copy URL'}
                        </button>
                        <button
                          onClick={() => window.electron.openUrl(entry.url)}
                          className="btn btn-ghost btn-sm"
                        >
                          Open
                        </button>
                        <button
                          onClick={() => setConfirmingDelete(entry.id)}
                          className="btn btn-danger btn-sm"
                        >
                          Delete
                        </button>
                      </>
                    )}
                  </div>
                </div>

                {confirmingDelete === entry.id && (
                  <p className="text-[13px] text-red-400 mt-2">
                    This will permanently delete {entry.projectName}.vercel.app
                  </p>
                )}

                {deleteError[entry.id] && (
                  <p className="text-[13px] text-red-400 mt-2">
                    {deleteError[entry.id]} — removed from history
                  </p>
                )}

                <div className="mt-2 px-2 py-1 rounded bg-gray-100 dark:bg-gray-700/50">
                  <p className="text-[13px] font-mono text-gray-600 dark:text-gray-400 truncate">
                    {entry.url}
                  </p>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
