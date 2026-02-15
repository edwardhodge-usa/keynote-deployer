// Keynote metadata from header.json
export interface KeynoteMetadata {
  title: string
  slideCount: number
  width: number
  height: number
  raw: Record<string, unknown>
}

// Folder validation result
export interface FolderValidation {
  valid: boolean
  folderPath: string
  metadata?: KeynoteMetadata
  error?: string
}

// Processing step status
export type StepStatus = 'pending' | 'active' | 'completed' | 'skipped' | 'error'

export interface ProcessingStep {
  id: number
  label: string
  detail: string
  status: StepStatus
  error?: string
}

// Processing progress event
export interface ProcessingProgress {
  currentStep: number
  totalSteps: number
  step: ProcessingStep
}

// Deployment result
export interface DeploymentResult {
  success: boolean
  projectName: string
  url: string
  error?: string
}

// Processing + deployment request
export interface ProcessRequest {
  folderPath: string
  projectName: string
  metadata: KeynoteMetadata
}

// Full pipeline result
export interface PipelineResult {
  success: boolean
  projectName: string
  title: string
  slideCount: number
  url: string
  fixesApplied: number
  fixesSkipped: number
  error?: string
}

// Deployment history entry
export interface HistoryEntry {
  id: string
  projectName: string
  title: string
  slideCount: number
  url: string
  folderPath: string
  date: string
  fixesApplied: number
}

// App settings
export interface AppSettings {
  vercelToken: string
  vercelTeamId: string
  theme: 'light' | 'dark' | 'system'
  autoCopyUrl: boolean
  projectNamePrefix: string
  lastFolderPath: string
}

// Navigation tabs
export type TabId = 'deploy' | 'history' | 'settings'

// Theme state
export interface ThemeState {
  shouldUseDarkColors: boolean
}

// Vercel token detection result
export interface TokenDetection {
  found: boolean
  token?: string
  source?: string
}

// Vercel project info from REST API
export interface VercelProject {
  id: string
  name: string
  accountId: string
}

// IPC response wrapper
export interface IpcResponse<T = unknown> {
  success: boolean
  data?: T
  error?: string
}
