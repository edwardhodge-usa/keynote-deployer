import type { ProcessingStep, StepStatus } from '../types'

interface DeployProgressProps {
  steps: ProcessingStep[]
  currentStep: number
}

function statusIcon(status: StepStatus): string {
  switch (status) {
    case 'completed': return '\u2713'
    case 'skipped': return '\u2212'
    case 'error': return '\u2717'
    case 'active': return '\u25CF'
    default: return '\u25CB'
  }
}

function statusColor(status: StepStatus): string {
  switch (status) {
    case 'completed': return 'text-green-500'
    case 'skipped': return 'text-yellow-500'
    case 'error': return 'text-red-500'
    case 'active': return 'text-primary animate-pulse'
    default: return 'text-gray-400 dark:text-gray-600'
  }
}

function detailColor(status: StepStatus): string {
  switch (status) {
    case 'error': return 'text-red-400'
    case 'skipped': return 'text-yellow-500 dark:text-yellow-400'
    default: return 'text-gray-500 dark:text-gray-400'
  }
}

export default function DeployProgress({ steps }: DeployProgressProps) {
  return (
    <div className="space-y-1">
      {steps.map((step) => (
        <div
          key={step.id}
          className={`flex items-start gap-3 px-3 py-1.5 rounded-lg transition-colors ${
            step.status === 'active' ? 'bg-blue-50 dark:bg-blue-900/20' : ''
          }`}
        >
          <span className={`mt-0.5 text-[15px] font-mono w-5 text-center ${statusColor(step.status)}`}>
            {statusIcon(step.status)}
          </span>
          <div className="flex-1 min-w-0">
            <p className={`text-[15px] ${
              step.status === 'pending' ? 'text-gray-400 dark:text-gray-600' : 'text-gray-800 dark:text-gray-200'
            }`}>
              {step.label}
            </p>
            {step.detail && step.status !== 'pending' && (
              <p className={`text-[13px] truncate ${detailColor(step.status)}`}>
                {step.detail}
              </p>
            )}
          </div>
          {step.status === 'active' && (
            <span className="spinner w-4 h-4 text-primary mt-0.5" />
          )}
        </div>
      ))}
    </div>
  )
}
