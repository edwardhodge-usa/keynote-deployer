import { app, BrowserWindow, Menu, ipcMain, dialog, shell, clipboard, nativeTheme } from 'electron'
import { autoUpdater } from 'electron-updater'
import path from 'path'
import { loadSettings, saveSettings, loadHistory, addHistoryEntry, removeHistoryEntry, validateKeynoteFolder, detectVercelToken } from './fileOperations'
import { processKeynoteFolder } from './keynoteProcessor'
import { deployToVercel } from './vercelDeployer'
import { verifyDeployment } from './verifier'
import { verifyRuntime } from './runtimeVerifier'
import type { ProcessRequest, GifDeployRequest, HistoryEntry, ProcessingStep } from '../src/types/index'
import { generateGifViewerHtml } from './gifViewerGenerator'
import fs from 'fs/promises'

let mainWindow: BrowserWindow | null = null

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 1000,
    minWidth: 900,
    minHeight: 600,
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 16 },
    vibrancy: 'sidebar',
    visualEffectState: 'active',
    backgroundColor: '#00000000',
    roundedCorners: true,
    tabbingIdentifier: 'keynote-deployer',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  })

  if (process.env.VITE_DEV_SERVER_URL) {
    mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL)
  } else {
    mainWindow.loadFile(path.join(__dirname, '../dist/index.html'))
  }

  mainWindow.on('closed', () => {
    mainWindow = null
  })
}

function buildMenu(win: BrowserWindow): void {
  const template: Electron.MenuItemConstructorOptions[] = [
    {
      label: app.name,
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        {
          label: 'Settings\u2026',
          accelerator: 'Cmd+,',
          click: () => win.webContents.send('navigate', 'settings'),
        },
        { type: 'separator' },
        { role: 'services' },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' },
      ],
    },
    {
      label: 'File',
      submenu: [
        {
          label: 'New Deployment',
          accelerator: 'Cmd+N',
          click: () => win.webContents.send('navigate', 'deploy'),
        },
        { type: 'separator' },
        { role: 'close' },
      ],
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'selectAll' },
      ],
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
      ],
    },
    {
      label: 'Window',
      submenu: [
        { role: 'minimize' },
        { role: 'zoom' },
        { type: 'separator' },
        { role: 'front' },
      ],
    },
    {
      role: 'help',
      submenu: [
        {
          label: 'Keynote Deployer Help',
          click: () => shell.openExternal('https://github.com/edwardhodge-usa/keynote-deployer'),
        },
      ],
    },
  ]

  Menu.setApplicationMenu(Menu.buildFromTemplate(template))
}

app.whenReady().then(() => {
  createWindow()
  if (mainWindow) buildMenu(mainWindow)

  // Auto-updater — check for updates silently
  autoUpdater.autoDownload = true
  autoUpdater.autoInstallOnAppQuit = true
  autoUpdater.checkForUpdatesAndNotify()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow()
      if (mainWindow) buildMenu(mainWindow)
    }
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit()
  }
})

// ── IPC Handlers ──

// Folder selection dialog
ipcMain.handle('select-folder', async () => {
  if (!mainWindow) return { success: false, error: 'No window' }

  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openDirectory'],
    title: 'Select Keynote HTML Export Folder',
  })

  if (result.canceled) {
    return { success: true, data: '' }
  }

  return { success: true, data: result.filePaths[0] }
})

// Validate a Keynote export folder
ipcMain.handle('validate-keynote-folder', async (_event, folderPath: string) => {
  try {
    const validation = await validateKeynoteFolder(folderPath)
    return { success: true, data: validation }
  } catch (error) {
    return { success: false, error: String(error) }
  }
})

// Full process + deploy pipeline
ipcMain.handle('process-and-deploy', async (event, request: ProcessRequest) => {
  const sendProgress = (step: ProcessingStep) => {
    event.sender.send('processing-progress', {
      currentStep: step.id,
      totalSteps: 14,
      step,
    })
  }

  try {
    // Load settings for Vercel credentials
    const settings = await loadSettings()
    if (!settings.vercelToken) {
      return { success: false, error: 'Vercel token not configured. Go to Settings first.' }
    }

    // Steps 1-11: Process keynote folder (fixes + index.html)
    const processResult = await processKeynoteFolder(
      request.folderPath,
      request.metadata,
      sendProgress,
      request.secureEmbed ?? false
    )

    // Steps 12-13: Deploy to Vercel
    const deployResult = await deployToVercel(
      request.folderPath,
      request.projectName,
      settings.vercelToken,
      settings.vercelTeamId,
      sendProgress,
      request.secureEmbed ?? false,
      settings.embedAllowedDomains ?? ''
    )

    if (!deployResult.success) {
      return {
        success: false,
        error: deployResult.error || 'Deployment failed',
        data: {
          success: false,
          projectName: request.projectName,
          title: request.metadata.title,
          slideCount: request.metadata.slideCount,
          url: '',
          fixesApplied: processResult.fixesApplied,
          fixesSkipped: processResult.fixesSkipped,
          error: deployResult.error,
        },
      }
    }

    // Step 14: Verify deployment
    const verificationResult = await verifyDeployment(deployResult.url, sendProgress)

    // Step 15: Runtime verification (if enabled)
    if (settings.enableRuntimeVerification) {
      const runtimeResult = await verifyRuntime(deployResult.url, sendProgress)
      verificationResult.runtime = runtimeResult
    } else {
      // Skip runtime verification
      sendProgress({ id: 15, label: 'Runtime verification', detail: 'Skipped (disabled in settings)', status: 'skipped' })
    }

    // Step 16: Complete
    sendProgress({ id: 16, label: 'Complete', detail: deployResult.url, status: 'completed' })

    // Save to history
    const historyEntry: HistoryEntry = {
      id: Date.now().toString(),
      projectName: request.projectName,
      title: request.metadata.title,
      slideCount: request.metadata.slideCount,
      url: deployResult.url,
      folderPath: request.folderPath,
      date: new Date().toISOString(),
      fixesApplied: processResult.fixesApplied,
    }
    await addHistoryEntry(historyEntry)

    // Auto-copy URL if enabled
    if (settings.autoCopyUrl) {
      clipboard.writeText(deployResult.url)
    }

    // Save last folder path
    await saveSettings({ lastFolderPath: request.folderPath })

    return {
      success: true,
      data: {
        success: true,
        projectName: request.projectName,
        title: request.metadata.title,
        slideCount: request.metadata.slideCount,
        url: deployResult.url,
        fixesApplied: processResult.fixesApplied,
        fixesSkipped: processResult.fixesSkipped,
        verification: verificationResult,
      },
    }
  } catch (error) {
    return { success: false, error: String(error) }
  }
})

// Settings
ipcMain.handle('load-settings', async () => {
  try {
    const settings = await loadSettings()
    return { success: true, data: settings }
  } catch (error) {
    return { success: false, error: String(error) }
  }
})

ipcMain.handle('save-settings', async (_event, settings) => {
  try {
    await saveSettings(settings)
    return { success: true }
  } catch (error) {
    return { success: false, error: String(error) }
  }
})

// Detect Vercel token from CLI config
ipcMain.handle('detect-vercel-token', async () => {
  try {
    const result = await detectVercelToken()
    return { success: true, data: result }
  } catch (error) {
    return { success: false, error: String(error) }
  }
})

// Load deployment history
ipcMain.handle('load-history', async () => {
  try {
    const history = await loadHistory()
    return { success: true, data: history }
  } catch (error) {
    return { success: false, error: String(error) }
  }
})

// Remove a history entry by ID
ipcMain.handle('remove-history-entry', async (_event, id: string) => {
  try {
    await removeHistoryEntry(id)
    return { success: true }
  } catch (error) {
    return { success: false, error: String(error) }
  }
})

// Fetch all Vercel projects
ipcMain.handle('fetch-vercel-projects', async () => {
  try {
    const settings = await loadSettings()
    if (!settings.vercelToken) {
      return { success: false, error: 'Vercel token not configured' }
    }

    const response = await fetch(
      `https://api.vercel.com/v9/projects?teamId=${settings.vercelTeamId}&limit=100`,
      { headers: { Authorization: `Bearer ${settings.vercelToken}` } }
    )

    if (!response.ok) {
      const errorBody = await response.text()
      return { success: false, error: `API error: ${response.status} ${errorBody}` }
    }

    const data = await response.json()

    // Only show projects that were deployed by Keynote Deployer
    const history = await loadHistory()
    const deployedProjectNames = new Set(history.map((h: any) => h.projectName))

    const allProjects = (data.projects || [])
      .filter((p: any) => deployedProjectNames.has(p.name))
      .map((p: any) => {
        // Get the actual .vercel.app domain (may be truncated for long names)
        const prodAliases: string[] = p.targets?.production?.alias || []
        const vercelDomain = prodAliases.find((a: string) =>
          a.endsWith('.vercel.app') && !a.includes('-edward-hodges-')
        ) || prodAliases.find((a: string) => a.endsWith('.vercel.app'))

        return {
          id: p.id,
          name: p.name,
          accountId: p.accountId,
          createdAt: p.createdAt,
          updatedAt: p.updatedAt,
          productionUrl: vercelDomain || `${p.name}.vercel.app`,
          latestDeployment: p.latestDeployments?.[0] ? {
            url: p.latestDeployments[0].url,
            createdAt: p.latestDeployments[0].createdAt,
            state: p.latestDeployments[0].readyState || p.latestDeployments[0].state,
          } : undefined,
        }
      })

    return { success: true, data: allProjects }
  } catch (error) {
    return { success: false, error: String(error) }
  }
})

// Delete Vercel project
ipcMain.handle('delete-vercel-project', async (_event, projectId: string) => {
  try {
    const settings = await loadSettings()
    if (!settings.vercelToken) {
      return { success: false, error: 'Vercel token not configured' }
    }

    const response = await fetch(
      `https://api.vercel.com/v9/projects/${projectId}?teamId=${settings.vercelTeamId}`,
      {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${settings.vercelToken}` },
      }
    )

    if (!response.ok && response.status !== 404) {
      const errorBody = await response.text()
      return { success: false, error: `API error: ${response.status} ${errorBody}` }
    }

    return { success: true }
  } catch (error) {
    return { success: false, error: String(error) }
  }
})

// Get app version from package.json
ipcMain.handle('get-app-version', () => {
  return app.getVersion()
})

// Open URL in default browser
ipcMain.handle('open-url', async (_event, url: string) => {
  await shell.openExternal(url)
})

// Copy text to system clipboard
ipcMain.handle('copy-to-clipboard', async (_event, text: string) => {
  clipboard.writeText(text)
})

// Deploy GIF to Vercel
ipcMain.handle('deploy-gif', async (event, request: GifDeployRequest) => {
  const sendProgress = (currentStep: number, label: string, detail: string, status: 'pending' | 'active' | 'completed' | 'error') => {
    event.sender.send('processing-progress', {
      currentStep,
      totalSteps: 4,
      step: { id: currentStep, label, detail, status },
    })
  }

  try {
    // Step 1: Prepare files
    sendProgress(1, 'Preparing files', 'Creating deployment folder...', 'active')

    const tempFolder = `/tmp/keynote-deployer-gif-${Date.now()}`
    await fs.mkdir(tempFolder, { recursive: true })

    // Copy GIF into temp folder
    const gifFilename = path.basename(request.gifPath)
    await fs.copyFile(request.gifPath, path.join(tempFolder, gifFilename))

    // Generate index.html viewer
    const indexHtml = generateGifViewerHtml(gifFilename, request.secureEmbed)
    await fs.writeFile(path.join(tempFolder, 'index.html'), indexHtml, 'utf-8')

    sendProgress(1, 'Preparing files', 'Files ready', 'completed')

    // Load settings for Vercel credentials
    const settings = await loadSettings()
    if (!settings.vercelToken) {
      sendProgress(2, 'Creating Vercel project', 'No token configured', 'error')
      return { success: false, error: 'Vercel token not configured. Go to Settings first.' }
    }

    // Step 2: Create Vercel project
    sendProgress(2, 'Creating Vercel project', 'Setting up project...', 'active')

    // Step 3: Deploy to Vercel
    const noopProgress = () => {} // GIF deploy sends its own progress
    const deployResult = await deployToVercel(
      tempFolder,
      request.projectName,
      settings.vercelToken,
      settings.vercelTeamId,
      noopProgress,
      request.secureEmbed,
      settings.embedAllowedDomains ?? ''
    )

    if (!deployResult.success) {
      sendProgress(3, 'Deploying to Vercel', deployResult.error || 'Deployment failed', 'error')
      return {
        success: false,
        error: deployResult.error || 'Deployment failed',
        data: {
          success: false,
          projectName: request.projectName,
          title: request.title,
          slideCount: request.slideCount,
          url: '',
          fixesApplied: 0,
          fixesSkipped: 0,
          error: deployResult.error,
        },
      }
    }

    sendProgress(2, 'Creating Vercel project', 'Project ready', 'completed')
    sendProgress(3, 'Deploying to Vercel', 'Deployment complete', 'completed')

    // Step 4: Complete
    sendProgress(4, 'Complete', deployResult.url, 'completed')

    // Save to history
    const historyEntry: HistoryEntry = {
      id: Date.now().toString(),
      projectName: request.projectName,
      title: request.title,
      slideCount: request.slideCount,
      url: deployResult.url,
      folderPath: request.gifPath,
      date: new Date().toISOString(),
      fixesApplied: 0,
    }
    await addHistoryEntry(historyEntry)

    // Auto-copy URL if enabled
    if (settings.autoCopyUrl) {
      clipboard.writeText(deployResult.url)
    }

    // Clean up temp folder
    await fs.rm(tempFolder, { recursive: true, force: true })

    return {
      success: true,
      data: {
        success: true,
        projectName: request.projectName,
        title: request.title,
        slideCount: request.slideCount,
        url: deployResult.url,
        fixesApplied: 0,
        fixesSkipped: 0,
      },
    }
  } catch (error) {
    return { success: false, error: String(error) }
  }
})

// Get system theme
ipcMain.handle('get-system-theme', async () => {
  return {
    success: true,
    data: {
      shouldUseDarkColors: nativeTheme.shouldUseDarkColors,
    },
  }
})
