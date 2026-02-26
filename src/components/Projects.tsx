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

  useEffect(() => {
    loadProjects()
  }, [])

  const loadProjects = async () => {
    setLoading(true)
    setError('')

    const res = await window.electron.fetchVercelProjects()

    if (res.success && res.data) {
      // Sort by most recently updated first
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

  const handleUpdateProject = (projectName: string) => {
    onSelectProject(projectName)
  }

  const handleDeleteProject = async (projectId: string, projectName: string) => {
    const confirmed = confirm(
      `Delete project "${projectName}"?\n\nThis will permanently delete the project from Vercel. This cannot be undone.`
    )

    if (!confirmed) return

    const res = await window.electron.deleteVercelProject(projectId)

    if (res.success) {
      // Remove from local list
      setProjects(prev => prev.filter(p => p.id !== projectId))
    } else {
      alert(`Failed to delete project: ${res.error}`)
    }
  }

  const formatDate = (timestamp?: number) => {
    if (!timestamp) return 'N/A'
    const date = new Date(timestamp)
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    })
  }

  const getStatusBadge = (state?: string) => {
    if (!state) return null

    switch (state) {
      case 'READY':
        return <span className="badge badge-success">Live</span>
      case 'ERROR':
        return <span className="badge badge-danger">Error</span>
      case 'BUILDING':
        return <span className="badge badge-warning">Building</span>
      case 'QUEUED':
        return <span className="badge badge-warning">Queued</span>
      default:
        return <span className="badge">{state}</span>
    }
  }

  return (
    <div className="h-full flex flex-col">
      {/* Titlebar drag area */}
      <div className="window-drag h-14 flex-shrink-0" />

      <div className="flex-1 overflow-y-auto px-8 pb-8">
        {/* Header with refresh */}
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-semibold">Vercel Projects</h1>
          <button
            onClick={handleRefresh}
            disabled={loading || refreshing}
            className="btn btn-secondary btn-sm"
          >
            {refreshing ? 'Refreshing...' : 'Refresh'}
          </button>
        </div>

        {/* Loading State */}
        {loading ? (
          <div className="text-center py-12">
            <span className="spinner text-primary" />
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-3">
              Loading projects...
            </p>
          </div>
        ) : error ? (
          /* Error State */
          <div className="text-center py-12">
            <div className="text-4xl mb-3 text-red-400">⚠</div>
            <p className="text-sm text-red-600 dark:text-red-400 mb-4">{error}</p>
            <button onClick={handleRefresh} className="btn btn-primary">
              Try Again
            </button>
          </div>
        ) : projects.length === 0 ? (
          /* Empty State */
          <div className="text-center py-12">
            <div className="text-4xl mb-3 text-gray-300 dark:text-gray-600">📦</div>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              No projects found. Deploy your first Keynote presentation!
            </p>
          </div>
        ) : (
          /* Projects Grid */
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {projects.map((project) => (
              <div key={project.id} className="card p-5">
                {/* Project Header */}
                <div className="flex items-start justify-between mb-3">
                  <div className="flex-1 min-w-0">
                    <h3 className="text-base font-semibold truncate mb-1">
                      {project.name}
                    </h3>
                    {project.latestDeployment && (
                      <div className="flex items-center gap-2">
                        {getStatusBadge(project.latestDeployment.state)}
                        <span className="text-xs text-gray-500 dark:text-gray-400">
                          Updated {formatDate(project.latestDeployment.createdAt)}
                        </span>
                      </div>
                    )}
                  </div>
                </div>

                {/* Production URL */}
                {project.latestDeployment?.state === 'READY' && (
                  <div className="mb-3 px-2 py-1.5 rounded bg-gray-100 dark:bg-gray-700/50">
                    <a
                      href={`https://${project.name}.vercel.app`}
                      onClick={(e) => {
                        e.preventDefault()
                        window.electron.openUrl(`https://${project.name}.vercel.app`)
                      }}
                      className="text-xs font-mono text-primary hover:underline truncate block"
                    >
                      https://{project.name}.vercel.app
                    </a>
                  </div>
                )}

                {/* Action Buttons */}
                <div className="flex gap-2">
                  <button
                    onClick={() => handleUpdateProject(project.name)}
                    className="btn btn-primary flex-1"
                  >
                    Update
                  </button>
                  <button
                    onClick={() => handleDeleteProject(project.id, project.name)}
                    className="btn btn-secondary"
                    title="Delete project"
                  >
                    🗑️
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
