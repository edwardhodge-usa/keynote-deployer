import { app, BrowserWindow, ipcMain, dialog, shell, clipboard, nativeTheme } from 'electron'
import path from 'path'
import { loadSettings, saveSettings, loadHistory, addHistoryEntry, validateKeynoteFolder, detectVercelToken } from './fileOperations'
import { processKeynoteFolder } from './keynoteProcessor'
import { deployToVercel } from './vercelDeployer'
import type { ProcessRequest, HistoryEntry, ProcessingStep } from '../src/types/index'

let mainWindow: BrowserWindow | null = null

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 750,
    minWidth: 900,
    minHeight: 600,
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 20, y: 22 },
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#2c2c2e' : '#ffffff',
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

app.whenReady().then(() => {
  createWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow()
    }
  })

  // Listen for system theme changes
  nativeTheme.on('updated', () => {
    if (mainWindow) {
      mainWindow.webContents.send('theme-changed', {
        shouldUseDarkColors: nativeTheme.shouldUseDarkColors,
      })
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
      sendProgress
    )

    // Steps 12-13: Deploy to Vercel
    const deployResult = await deployToVercel(
      request.folderPath,
      request.projectName,
      settings.vercelToken,
      settings.vercelTeamId,
      sendProgress
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

    // Step 14: Complete
    sendProgress({ id: 14, label: 'Complete', detail: deployResult.url, status: 'completed' })

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

// Open URL in default browser
ipcMain.handle('open-url', async (_event, url: string) => {
  await shell.openExternal(url)
})

// Copy text to system clipboard
ipcMain.handle('copy-to-clipboard', async (_event, text: string) => {
  clipboard.writeText(text)
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
