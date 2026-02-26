import { contextBridge, ipcRenderer } from 'electron'
import type { AppSettings, ProcessRequest, IpcResponse, FolderValidation, TokenDetection, HistoryEntry, ProcessingProgress, ThemeState, VercelProjectExtended } from '../src/types/index'

export interface ElectronAPI {
  selectFolder: () => Promise<IpcResponse<string>>
  validateKeynoteFolder: (folderPath: string) => Promise<IpcResponse<FolderValidation>>
  processAndDeploy: (request: ProcessRequest) => Promise<IpcResponse<import('../src/types/index').PipelineResult>>
  loadSettings: () => Promise<IpcResponse<AppSettings>>
  saveSettings: (settings: Partial<AppSettings>) => Promise<IpcResponse<void>>
  detectVercelToken: () => Promise<IpcResponse<TokenDetection>>
  loadHistory: () => Promise<IpcResponse<HistoryEntry[]>>
  fetchVercelProjects: () => Promise<IpcResponse<VercelProjectExtended[]>>
  deleteVercelProject: (projectId: string) => Promise<IpcResponse<void>>
  openUrl: (url: string) => Promise<void>
  copyToClipboard: (text: string) => Promise<void>
  getSystemTheme: () => Promise<IpcResponse<ThemeState>>
  onProcessingProgress: (callback: (progress: ProcessingProgress) => void) => void
  onThemeChanged: (callback: (theme: ThemeState) => void) => void
  removeAllListeners: (channel: string) => void
}

const electronAPI: ElectronAPI = {
  selectFolder: () => ipcRenderer.invoke('select-folder'),

  validateKeynoteFolder: (folderPath: string) =>
    ipcRenderer.invoke('validate-keynote-folder', folderPath),

  processAndDeploy: (request: ProcessRequest) =>
    ipcRenderer.invoke('process-and-deploy', request),

  loadSettings: () => ipcRenderer.invoke('load-settings'),

  saveSettings: (settings: Partial<AppSettings>) =>
    ipcRenderer.invoke('save-settings', settings),

  detectVercelToken: () => ipcRenderer.invoke('detect-vercel-token'),

  loadHistory: () => ipcRenderer.invoke('load-history'),

  fetchVercelProjects: () => ipcRenderer.invoke('fetch-vercel-projects'),

  deleteVercelProject: (projectId: string) => ipcRenderer.invoke('delete-vercel-project', projectId),

  openUrl: (url: string) => ipcRenderer.invoke('open-url', url),

  copyToClipboard: (text: string) => ipcRenderer.invoke('copy-to-clipboard', text),

  getSystemTheme: () => ipcRenderer.invoke('get-system-theme'),

  onProcessingProgress: (callback: (progress: ProcessingProgress) => void) => {
    ipcRenderer.on('processing-progress', (_event, progress) => callback(progress))
  },

  onThemeChanged: (callback: (theme: ThemeState) => void) => {
    ipcRenderer.on('theme-changed', (_event, theme) => callback(theme))
  },

  removeAllListeners: (channel: string) => {
    ipcRenderer.removeAllListeners(channel)
  },
}

contextBridge.exposeInMainWorld('electron', electronAPI)

declare global {
  interface Window {
    electron: ElectronAPI
  }
}
