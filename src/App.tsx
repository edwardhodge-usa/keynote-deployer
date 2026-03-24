import { useState, useEffect } from 'react'
import Sidebar from './components/Sidebar'
import Deploy from './components/Deploy'
import Projects from './components/Projects'
import History from './components/History'
import GifViewer from './components/GifViewer'
import Settings from './components/Settings'
import type { TabId } from './types'

export default function App() {
  const [activeTab, setActiveTab] = useState<TabId>('deploy')
  const [selectedProject, setSelectedProject] = useState<string | undefined>(undefined)

  useEffect(() => {
    // Listen for menu bar navigation (Cmd+, for Settings, Cmd+N for Deploy)
    window.electron.onNavigate((tab: string) => {
      if (tab === 'deploy' || tab === 'projects' || tab === 'history' || tab === 'preview' || tab === 'settings') {
        setActiveTab(tab as TabId)
      }
    })

    return () => {
      window.electron.removeAllListeners('navigate')
    }
  }, [])

  const handleProjectSelect = (projectName: string) => {
    setSelectedProject(projectName)
    setActiveTab('deploy')
  }

  return (
    <div className="app-shell flex h-full">
      <Sidebar activeTab={activeTab} onTabChange={setActiveTab} />
      <main className="flex-1 overflow-y-auto">
        {activeTab === 'deploy' && <Deploy selectedProject={selectedProject} onProjectUsed={() => setSelectedProject(undefined)} />}
        {activeTab === 'projects' && <Projects onSelectProject={handleProjectSelect} />}
        {activeTab === 'history' && <History />}
        {activeTab === 'preview' && <GifViewer />}
        {activeTab === 'settings' && <Settings />}
      </main>
    </div>
  )
}
