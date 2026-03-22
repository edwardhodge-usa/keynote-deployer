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
  secureEmbed?: boolean
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
  verification?: VerificationResult
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
  enableRuntimeVerification: boolean
  projectNamePrefix: string
  lastFolderPath: string
  secureEmbed: boolean
  embedAllowedDomains: string
}

// Navigation tabs
export type TabId = 'deploy' | 'projects' | 'history' | 'settings'

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

// Extended Vercel project info with deployment metadata
export interface VercelProjectExtended {
  id: string
  name: string
  accountId: string
  createdAt?: number
  updatedAt?: number
  productionUrl?: string
  latestDeployment?: {
    url: string
    createdAt: number
    state: 'READY' | 'ERROR' | 'BUILDING' | 'QUEUED' | 'CANCELED'
  }
}

// Verification result for a single fix
export interface FixVerification {
  fixNumber: number
  name: string
  found: boolean
  pattern: string
}

// Runtime verification result from browser automation
export interface RuntimeVerificationResult {
  success: boolean
  devicePixelRatio: number
  canvasElements: {
    count: number
    sampleWidth: number
    sampleHeight: number
    sampleStyleWidth: string
    sampleStyleHeight: string
    dprScaling: boolean
  }
  navigationTested: boolean
  reRenderTriggered: boolean
  error?: string
}

// Full deployment verification result
export interface VerificationResult {
  success: boolean
  url: string
  mainJsVerified: boolean
  indexHtmlVerified: boolean
  fixes: FixVerification[]
  totalFixesFound: number
  totalFixesMissing: number
  runtime?: RuntimeVerificationResult
  error?: string
}

// IPC response wrapper
export interface IpcResponse<T = unknown> {
  success: boolean
  data?: T
  error?: string
}
