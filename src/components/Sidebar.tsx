import type { TabId } from '../types'

interface SidebarProps {
  activeTab: TabId
  onTabChange: (tab: TabId) => void
  isDark: boolean
}

const tabs: { id: TabId; label: string; icon: string }[] = [
  { id: 'deploy', label: 'Deploy', icon: '\u25B6' },
  { id: 'history', label: 'History', icon: '\u23F3' },
  { id: 'settings', label: 'Settings', icon: '\u2699' },
]

export default function Sidebar({ activeTab, onTabChange }: SidebarProps) {
  return (
    <aside className="w-52 bg-sidebar-light dark:bg-sidebar-dark border-r border-border-light dark:border-border-dark flex flex-col">
      {/* Draggable titlebar area */}
      <div className="window-drag h-14 flex items-end px-5 pb-2">
        <span className="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wider window-no-drag">
          Keynote Deployer
        </span>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-3 py-2 space-y-1">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => onTabChange(tab.id)}
            className={`nav-item w-full window-no-drag ${
              activeTab === tab.id ? 'nav-item-active' : ''
            }`}
          >
            <span className="text-lg">{tab.icon}</span>
            <span className="text-sm font-medium">{tab.label}</span>
          </button>
        ))}
      </nav>

      {/* Version info */}
      <div className="px-5 py-3 border-t border-border-light dark:border-border-dark">
        <p className="text-xxs text-gray-400 dark:text-gray-500">v1.0.0</p>
      </div>
    </aside>
  )
}
