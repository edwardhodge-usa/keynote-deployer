import { useState, useEffect } from 'react'
import type { VercelProjectExtended } from '../types'

interface ProjectsProps {
  onSelectProject: (projectName: string) => void
}

export default function Projects({ onSelectProject }: ProjectsProps) {
  const [projects, setProjects] = useState<VercelProjectExtended[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [refreshing, setRefreshing] = useState(false)
  const [confirmingDelete, setConfirmingDelete] = useState<string | null>(null)
  const [deletingId, setDeletingId] = useState<string | null>(null)
  const [copiedId, setCopiedId] = useState<string | null>(null)

  useEffect(() => {
    loadProjects()
  }, [])

  const loadProjects = async () => {
    setLoading(true)
    setError('')

    const res = await window.electron.fetchVercelProjects()

    if (res.success && res.data) {
      const sorted = [...res.data].sort((a, b) =>
        (b.updatedAt || 0) - (a.updatedAt || 0)
      )
      setProjects(sorted)
    } else {
      setError(res.error || 'Failed to load projects')
    }

    setLoading(false)
    setRefreshing(false)
  }

  const handleRefresh = () => {
    setRefreshing(true)
    loadProjects()
  }

  const handleDeleteProject = async (projectId: string) => {
    setDeletingId(projectId)
    const res = await window.electron.deleteVercelProject(projectId)

    if (res.success) {
      setProjects(prev => prev.filter(p => p.id !== projectId))
    }
    setDeletingId(null)
    setConfirmingDelete(null)
  }

  const copyUrl = (url: string, id: string) => {
    window.electron.copyToClipboard(url)
    setCopiedId(id)
    setTimeout(() => setCopiedId(null), 2000)
  }

  const formatDate = (timestamp?: number) => {
    if (!timestamp) return ''
    const date = new Date(timestamp)
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    })
  }

  const getStatusDot = (state?: string) => {
    switch (state) {
      case 'READY':
        return <span className="w-2 h-2 rounded-full bg-green-500 flex-shrink-0" title="Live" />
      case 'ERROR':
        return <span className="w-2 h-2 rounded-full bg-red-500 flex-shrink-0" title="Error" />
      case 'BUILDING':
      case 'QUEUED':
        return <span className="w-2 h-2 rounded-full bg-yellow-500 flex-shrink-0 animate-pulse" title={state} />
      default:
        return <span className="w-2 h-2 rounded-full bg-gray-400 flex-shrink-0" />
    }
  }

  return (
    <div className="h-full flex flex-col">
      <div className="window-drag h-14 flex-shrink-0" />

      <div className="flex-1 overflow-y-auto px-8 pb-8">
        <div className="flex items-center justify-between mb-5">
          <h1 className="text-2xl font-semibold">Projects</h1>
          <button
            onClick={handleRefresh}
            disabled={loading || refreshing}
            className="btn btn-secondary btn-sm"
          >
            {refreshing ? 'Refreshing...' : 'Refresh'}
          </button>
        </div>

        {loading ? (
          <div className="text-center py-12">
            <span className="spinner text-primary" />
            <p className="text-[13px] text-gray-500 dark:text-gray-400 mt-3">
              Loading projects...
            </p>
          </div>
        ) : error ? (
          <div className="text-center py-12">
            <div className="mb-3 flex justify-center">
              <svg className="w-10 h-10 text-red-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
                <line x1="12" y1="9" x2="12" y2="13" /><line x1="12" y1="17" x2="12.01" y2="17" />
              </svg>
            </div>
            <p className="text-[15px] text-red-600 dark:text-red-400 mb-4">{error}</p>
            <button onClick={handleRefresh} className="btn btn-primary">
              Try Again
            </button>
          </div>
        ) : projects.length === 0 ? (
          <div className="text-center py-12">
            <div className="mb-3 flex justify-center">
              <svg className="w-10 h-10 text-gray-300 dark:text-gray-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z" />
                <polyline points="3.27 6.96 12 12.01 20.73 6.96" />
                <line x1="12" y1="22.08" x2="12" y2="12" />
              </svg>
            </div>
            <p className="text-[15px] text-gray-500 dark:text-gray-400">
              No projects found. Deploy your first Keynote presentation!
            </p>
          </div>
        ) : (
          <div className="card overflow-hidden">
            {projects.map((project, i) => {
              const url = `https://${project.productionUrl || project.name + '.vercel.app'}`
              const isConfirming = confirmingDelete === project.id

              return (
                <div key={project.id}>
                  {i > 0 && <div className="border-t border-gray-200/80 dark:border-gray-700/60 mx-4" />}

                  <div className="px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-700/30 transition-colors">
                    <div className="flex gap-3">
                      {/* Mini site preview thumbnail */}
                      {project.latestDeployment?.state === 'READY' ? (
                        <div
                          className="flex-shrink-0 w-[120px] h-[75px] rounded-lg overflow-hidden border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 cursor-default"
                          onClick={() => window.electron.openUrl(url)}
                          title="Open in browser"
                        >
                          <div className="relative w-full h-full">
                            <iframe
                              src={url}
                              title={`Preview of ${project.name}`}
                              className="absolute inset-0 border-0 pointer-events-none"
                              style={{
                                width: '1024px',
                                height: '640px',
                                transform: 'scale(0.117)',
                                transformOrigin: 'top left',
                              }}
                              sandbox="allow-scripts allow-same-origin"
                              tabIndex={-1}
                            />
                          </div>
                        </div>
                      ) : (
                        <div className="flex-shrink-0 w-[120px] h-[75px] rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-100 dark:bg-gray-800 flex items-center justify-center">
                          {getStatusDot(project.latestDeployment?.state)}
                        </div>
                      )}

                      {/* Info column */}
                      <div className="flex-1 min-w-0 flex flex-col justify-center">
                        {/* Name + date row */}
                        <div className="flex items-center gap-2">
                          {getStatusDot(project.latestDeployment?.state)}
                          <span className="text-[17px] font-medium text-gray-900 dark:text-gray-100">
                            {project.name}
                          </span>
                          {project.latestDeployment && (
                            <span className="text-[13px] text-gray-400 dark:text-gray-500">
                              {formatDate(project.latestDeployment.createdAt)}
                            </span>
                          )}
                        </div>

                        {/* URL row */}
                        {project.latestDeployment?.state === 'READY' && (
                          <div className="flex items-center gap-2 mt-0.5">
                            <a
                              href={url}
                              onClick={(e) => {
                                e.preventDefault()
                                window.electron.openUrl(url)
                              }}
                              className="text-[13px] font-mono text-primary hover:underline break-all"
                            >
                              {url}
                            </a>
                            <button
                              onClick={() => copyUrl(url, project.id)}
                              className="flex-shrink-0 p-0.5 rounded hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors"
                              title="Copy URL"
                              aria-label="Copy URL"
                            >
                              {copiedId === project.id ? (
                                <svg className="w-3.5 h-3.5 text-green-500" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                                  <polyline points="3,8 7,12 13,4" />
                                </svg>
                              ) : (
                                <svg className="w-3.5 h-3.5 text-gray-400 dark:text-gray-500" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                                  <rect x="5" y="5" width="9" height="9" rx="1.5" />
                                  <path d="M11,5 V3.5 A1.5,1.5,0,0,0,9.5,2 H3.5 A1.5,1.5,0,0,0,2,3.5 V9.5 A1.5,1.5,0,0,0,3.5,11 H5" />
                                </svg>
                              )}
                            </button>
                          </div>
                        )}

                        {/* Delete confirmation text */}
                        {isConfirming && (
                          <p className="text-[13px] text-red-400 mt-1">
                            This will permanently delete {project.name} from Vercel.
                          </p>
                        )}
                      </div>

                      {/* Actions */}
                      <div className="flex items-center gap-1.5 flex-shrink-0">
                        {isConfirming ? (
                          <>
                            <button
                              onClick={() => setConfirmingDelete(null)}
                              disabled={deletingId === project.id}
                              className="btn btn-secondary btn-sm"
                            >
                              Cancel
                            </button>
                            <button
                              onClick={() => handleDeleteProject(project.id)}
                              disabled={deletingId === project.id}
                              className="btn btn-danger btn-sm"
                            >
                              {deletingId === project.id ? (
                                <span className="spinner spinner-sm" />
                              ) : (
                                'Delete'
                              )}
                            </button>
                          </>
                        ) : (
                          <>
                            <button
                              onClick={() => onSelectProject(project.name)}
                              className="btn btn-primary btn-sm"
                            >
                              Update
                            </button>
                            <button
                              onClick={() => setConfirmingDelete(project.id)}
                              className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors"
                              title="Delete project"
                              aria-label={`Delete ${project.name}`}
                            >
                              <svg className="w-3.5 h-3.5 text-gray-400 dark:text-gray-500" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                                <polyline points="3,4 13,4" />
                                <path d="M6,4 V2.5 a0.5,0.5,0,0,1,0.5,-0.5 h3 a0.5,0.5,0,0,1,0.5,0.5 V4" />
                                <path d="M4,4 L4.5,13.5 a1,1,0,0,0,1,0.5 h5 a1,1,0,0,0,1,-0.5 L12,4" />
                              </svg>
                            </button>
                          </>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
