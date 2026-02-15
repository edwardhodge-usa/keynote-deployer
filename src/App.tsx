import { useState, useEffect } from 'react'
import Sidebar from './components/Sidebar'
import Deploy from './components/Deploy'
import History from './components/History'
import Settings from './components/Settings'
import type { TabId } from './types'

export default function App() {
  const [activeTab, setActiveTab] = useState<TabId>('deploy')
  const [isDark, setIsDark] = useState(false)

  useEffect(() => {
    // Get initial theme
    window.electron.getSystemTheme().then((res) => {
      if (res.success && res.data) {
        setIsDark(res.data.shouldUseDarkColors)
      }
    })

    // Listen for theme changes
    window.electron.onThemeChanged((theme) => {
      setIsDark(theme.shouldUseDarkColors)
    })

    // Load saved theme preference
    window.electron.loadSettings().then((res) => {
      if (res.success && res.data) {
        const pref = res.data.theme
        if (pref === 'dark') setIsDark(true)
        else if (pref === 'light') setIsDark(false)
        // 'system' uses the detected value
      }
    })

    return () => {
      window.electron.removeAllListeners('theme-changed')
    }
  }, [])

  useEffect(() => {
    document.documentElement.classList.toggle('dark', isDark)
  }, [isDark])

  const handleThemeChange = (theme: 'light' | 'dark' | 'system') => {
    if (theme === 'dark') setIsDark(true)
    else if (theme === 'light') setIsDark(false)
    else {
      window.electron.getSystemTheme().then((res) => {
        if (res.success && res.data) setIsDark(res.data.shouldUseDarkColors)
      })
    }
  }

  return (
    <div className="flex h-full">
      <Sidebar activeTab={activeTab} onTabChange={setActiveTab} isDark={isDark} />
      <main className="flex-1 overflow-y-auto">
        {activeTab === 'deploy' && <Deploy />}
        {activeTab === 'history' && <History />}
        {activeTab === 'settings' && <Settings onThemeChange={handleThemeChange} />}
      </main>
    </div>
  )
}
