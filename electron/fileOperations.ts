import { app } from 'electron'
import fs from 'fs/promises'
import path from 'path'
import type { AppSettings, HistoryEntry, FolderValidation, KeynoteMetadata, TokenDetection } from '../src/types/index'

const DEFAULT_SETTINGS: AppSettings = {
  vercelToken: '',
  vercelTeamId: 'team_E1wAzl9zyAPrlGzyjmcXNuxd',
  theme: 'system',
  autoCopyUrl: true,
  projectNamePrefix: '',
  lastFolderPath: '',
}

function getDataDir(): string {
  return path.join(app.getPath('userData'))
}

function getSettingsPath(): string {
  return path.join(getDataDir(), 'settings.json')
}

function getHistoryPath(): string {
  return path.join(getDataDir(), 'history.json')
}

export async function loadSettings(): Promise<AppSettings> {
  try {
    const data = await fs.readFile(getSettingsPath(), 'utf-8')
    return { ...DEFAULT_SETTINGS, ...JSON.parse(data) }
  } catch {
    return { ...DEFAULT_SETTINGS }
  }
}

export async function saveSettings(settings: Partial<AppSettings>): Promise<void> {
  const current = await loadSettings()
  const merged = { ...current, ...settings }
  await fs.mkdir(getDataDir(), { recursive: true })
  await fs.writeFile(getSettingsPath(), JSON.stringify(merged, null, 2), 'utf-8')
}

export async function loadHistory(): Promise<HistoryEntry[]> {
  try {
    const data = await fs.readFile(getHistoryPath(), 'utf-8')
    return JSON.parse(data)
  } catch {
    return []
  }
}

export async function addHistoryEntry(entry: HistoryEntry): Promise<void> {
  const history = await loadHistory()
  history.unshift(entry)
  await fs.mkdir(getDataDir(), { recursive: true })
  await fs.writeFile(getHistoryPath(), JSON.stringify(history, null, 2), 'utf-8')
}

export async function validateKeynoteFolder(folderPath: string): Promise<FolderValidation> {
  try {
    const headerPath = path.join(folderPath, 'assets', 'header.json')
    const mainJsPath = path.join(folderPath, 'assets', 'player', 'main.js')

    // Check header.json exists
    try {
      await fs.access(headerPath)
    } catch {
      return { valid: false, folderPath, error: 'Missing assets/header.json — not a Keynote HTML export' }
    }

    // Check main.js exists
    try {
      await fs.access(mainJsPath)
    } catch {
      return { valid: false, folderPath, error: 'Missing assets/player/main.js — not a Keynote HTML export' }
    }

    // Parse header.json for metadata
    const headerData = await fs.readFile(headerPath, 'utf-8')
    const header = JSON.parse(headerData)

    const metadata: KeynoteMetadata = {
      title: header.title || header.name || path.basename(folderPath),
      slideCount: header.slideCount || header.slides?.length || 0,
      width: header.width || 1920,
      height: header.height || 1080,
      raw: header,
    }

    return { valid: true, folderPath, metadata }
  } catch (error) {
    return { valid: false, folderPath, error: `Validation failed: ${String(error)}` }
  }
}

export async function detectVercelToken(): Promise<TokenDetection> {
  const locations = [
    path.join(process.env.HOME || '', '.local', 'share', 'com.vercel.cli', 'auth.json'),
    path.join(process.env.HOME || '', 'Library', 'Application Support', 'com.vercel.cli', 'auth.json'),
  ]

  for (const loc of locations) {
    try {
      const data = await fs.readFile(loc, 'utf-8')
      const parsed = JSON.parse(data)
      if (parsed.token) {
        return { found: true, token: parsed.token, source: loc }
      }
    } catch {
      // Try next location
    }
  }

  return { found: false }
}
