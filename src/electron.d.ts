import type {
  AppSettings,
  ProcessRequest,
  PipelineResult,
  IpcResponse,
  FolderValidation,
  TokenDetection,
  HistoryEntry,
  ProcessingProgress,
  ThemeState,
} from './types'

export interface ElectronAPI {
  selectFolder: () => Promise<IpcResponse<string>>
  validateKeynoteFolder: (folderPath: string) => Promise<IpcResponse<FolderValidation>>
  processAndDeploy: (request: ProcessRequest) => Promise<IpcResponse<PipelineResult>>
  loadSettings: () => Promise<IpcResponse<AppSettings>>
  saveSettings: (settings: Partial<AppSettings>) => Promise<IpcResponse<void>>
  detectVercelToken: () => Promise<IpcResponse<TokenDetection>>
  loadHistory: () => Promise<IpcResponse<HistoryEntry[]>>
  openUrl: (url: string) => Promise<void>
  copyToClipboard: (text: string) => Promise<void>
  getSystemTheme: () => Promise<IpcResponse<ThemeState>>
  onProcessingProgress: (callback: (progress: ProcessingProgress) => void) => void
  onThemeChanged: (callback: (theme: ThemeState) => void) => void
  removeAllListeners: (channel: string) => void
}

declare global {
  interface Window {
    electron: ElectronAPI
  }
}
