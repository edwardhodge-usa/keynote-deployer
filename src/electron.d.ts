import type {
  AppSettings,
  ProcessRequest,
  GifDeployRequest,
  VideoDeployRequest,
  PipelineResult,
  IpcResponse,
  FolderValidation,
  TokenDetection,
  HistoryEntry,
  ProcessingProgress,
  ThemeState,
  VercelProjectExtended,
} from './types'

export interface ElectronAPI {
  selectFolder: () => Promise<IpcResponse<string>>
  validateKeynoteFolder: (folderPath: string) => Promise<IpcResponse<FolderValidation>>
  processAndDeploy: (request: ProcessRequest) => Promise<IpcResponse<PipelineResult>>
  deployGif: (request: GifDeployRequest) => Promise<IpcResponse<PipelineResult>>
  deployVideo: (request: VideoDeployRequest) => Promise<IpcResponse<PipelineResult>>
  loadSettings: () => Promise<IpcResponse<AppSettings>>
  saveSettings: (settings: Partial<AppSettings>) => Promise<IpcResponse<void>>
  detectVercelToken: () => Promise<IpcResponse<TokenDetection>>
  loadHistory: () => Promise<IpcResponse<HistoryEntry[]>>
  removeHistoryEntry: (id: string) => Promise<IpcResponse<void>>
  fetchVercelProjects: () => Promise<IpcResponse<VercelProjectExtended[]>>
  deleteVercelProject: (projectId: string) => Promise<IpcResponse<void>>
  getAppVersion: () => Promise<string>
  openUrl: (url: string) => Promise<void>
  copyToClipboard: (text: string) => Promise<void>
  getFilePath: (file: File) => string
  getSystemTheme: () => Promise<IpcResponse<ThemeState>>
  selectStillsFolder: () => Promise<IpcResponse<string[]>>
  onProcessingProgress: (callback: (progress: ProcessingProgress) => void) => void
  onThemeChanged: (callback: (theme: ThemeState) => void) => void
  onNavigate: (callback: (tab: string) => void) => void
  removeAllListeners: (channel: string) => void
}

declare global {
  interface Window {
    electron: ElectronAPI
  }
}
