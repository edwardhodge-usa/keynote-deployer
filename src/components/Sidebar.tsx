import { useState, useEffect } from 'react'
import type { TabId } from '../types'

interface SidebarProps {
  activeTab: TabId
  onTabChange: (tab: TabId) => void
}

function DeployIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <polygon points="9,2 16,6 16,12 9,16 2,12 2,6" />
      <polyline points="9,16 9,10" />
      <polyline points="16,6 9,10 2,6" />
    </svg>
  )
}

function ProjectsIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="3" width="14" height="12" rx="2" />
      <line x1="2" y1="7" x2="16" y2="7" />
      <line x1="6" y1="7" x2="6" y2="15" />
    </svg>
  )
}

function HistoryIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="9" cy="9" r="7" />
      <polyline points="9,5 9,9 12,11" />
    </svg>
  )
}

function SettingsIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="9" cy="9" r="2.5" />
      <path d="M9,1.5 L9,3.5 M9,14.5 L9,16.5 M2.7,4.5 L4.4,5.5 M13.6,12.5 L15.3,13.5 M1.5,9 L3.5,9 M14.5,9 L16.5,9 M2.7,13.5 L4.4,12.5 M13.6,5.5 L15.3,4.5" />
    </svg>
  )
}

function PreviewIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="3" width="14" height="12" rx="2" />
      <polygon points="7.5,7 7.5,13 12.5,10" fill="currentColor" stroke="none" />
    </svg>
  )
}

const tabs: { id: TabId; label: string; Icon: React.FC<{ className?: string }> }[] = [
  { id: 'deploy', label: 'Deploy HTML', Icon: DeployIcon },
  { id: 'preview', label: 'Deploy GIF', Icon: PreviewIcon },
  { id: 'projects', label: 'Projects', Icon: ProjectsIcon },
  { id: 'history', label: 'History', Icon: HistoryIcon },
  { id: 'settings', label: 'Settings', Icon: SettingsIcon },
]

export default function Sidebar({ activeTab, onTabChange }: SidebarProps) {
  const [version, setVersion] = useState('')

  useEffect(() => {
    window.electron.getAppVersion().then((v) => setVersion(v))
  }, [])

  return (
    <aside className="w-52 bg-sidebar-light dark:bg-sidebar-dark border-r border-border-light dark:border-border-dark flex flex-col">
      {/* Draggable titlebar area — clears traffic lights */}
      <div className="window-drag h-14 flex-shrink-0" />

      {/* App title */}
      <div className="px-4 pb-3">
        <span className="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wider">
          Keynote Deployer
        </span>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-3 py-1 space-y-0.5">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => onTabChange(tab.id)}
            className={`nav-item w-full ${
              activeTab === tab.id ? 'nav-item-active' : ''
            }`}
          >
            <tab.Icon className="w-[18px] h-[18px] flex-shrink-0" />
            <span className="text-[15px]">{tab.label}</span>
          </button>
        ))}
      </nav>

      {/* Version info */}
      <div className="px-4 py-3 border-t border-border-light dark:border-border-dark">
        <p className="text-[10px] text-gray-400 dark:text-gray-500">v{version}</p>
      </div>
    </aside>
  )
}
