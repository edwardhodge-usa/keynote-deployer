import { execFile } from 'child_process'
import { promisify } from 'util'
import type { VercelProject, ProcessingStep } from '../src/types/index'

const execFileAsync = promisify(execFile)

type ProgressCallback = (step: ProcessingStep) => void

export interface DeployResult {
  success: boolean
  url: string
  projectId: string
  error?: string
}

// Create or get existing Vercel project via REST API
async function ensureProject(
  projectName: string,
  token: string,
  teamId: string
): Promise<VercelProject> {
  // Try to get existing project first
  const getResponse = await fetch(
    `https://api.vercel.com/v9/projects/${encodeURIComponent(projectName)}?teamId=${teamId}`,
    {
      headers: { Authorization: `Bearer ${token}` },
    }
  )

  if (getResponse.ok) {
    const project = await getResponse.json()
    return { id: project.id, name: project.name, accountId: project.accountId }
  }

  // Create new project
  const createResponse = await fetch(
    `https://api.vercel.com/v10/projects?teamId=${teamId}`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: projectName,
        framework: null,
      }),
    }
  )

  if (!createResponse.ok) {
    const errorBody = await createResponse.text()
    throw new Error(`Failed to create project: ${createResponse.status} ${errorBody}`)
  }

  const project = await createResponse.json()
  return { id: project.id, name: project.name, accountId: project.accountId }
}

// Find vercel CLI binary
async function findVercelCli(): Promise<string> {
  const candidates = [
    '/usr/local/bin/vercel',
    '/opt/homebrew/bin/vercel',
    `${process.env.HOME}/.npm-global/bin/vercel`,
    `${process.env.HOME}/.nvm/versions/node/current/bin/vercel`,
  ]

  // Try `which vercel` first
  try {
    const { stdout } = await execFileAsync('which', ['vercel'])
    const p = stdout.trim()
    if (p) return p
  } catch {
    // Fall through to candidates
  }

  // Try known locations
  const fs = await import('fs/promises')
  for (const candidate of candidates) {
    try {
      await fs.access(candidate)
      return candidate
    } catch {
      // Try next
    }
  }

  throw new Error('Vercel CLI not found. Install with: npm i -g vercel')
}

export async function deployToVercel(
  folderPath: string,
  projectName: string,
  token: string,
  teamId: string,
  onProgress: ProgressCallback
): Promise<DeployResult> {
  // Step 12: Ensure Vercel project exists
  onProgress({ id: 12, label: 'Vercel project', detail: 'Creating or finding project...', status: 'active' })

  let project: VercelProject
  try {
    project = await ensureProject(projectName, token, teamId)
    onProgress({ id: 12, label: 'Vercel project', detail: `Project: ${project.name}`, status: 'completed' })
  } catch (error) {
    onProgress({ id: 12, label: 'Vercel project', detail: String(error), status: 'error' })
    return { success: false, url: '', projectId: '', error: String(error) }
  }

  // Step 13: Deploy via CLI
  onProgress({ id: 13, label: 'Deploy', detail: 'Uploading files...', status: 'active' })

  try {
    const vercelBin = await findVercelCli()

    const { stdout, stderr } = await execFileAsync(
      vercelBin,
      ['--prod', '--yes', '--token', token],
      {
        cwd: folderPath,
        env: {
          ...process.env,
          PATH: `/opt/homebrew/bin:/usr/local/bin:${process.env.PATH || ''}`,
          VERCEL_ORG_ID: teamId,
          VERCEL_PROJECT_ID: project.id,
        },
        maxBuffer: 10 * 1024 * 1024, // 10MB buffer for output
        timeout: 120000, // 2 minute timeout
      }
    )

    // CLI outputs the URL on stdout or stderr
    const output = (stdout + '\n' + stderr).trim()
    const urlMatch = output.match(/https:\/\/[^\s]+\.vercel\.app/g)
    const deployUrl = urlMatch ? urlMatch[urlMatch.length - 1] : ''

    // Verify deployment succeeded (look for "Aliased:" or production URL)
    if (!output.includes('Aliased:') && !output.includes('Production:')) {
      throw new Error(`Deployment may have failed. Output: ${output.slice(0, 500)}`)
    }

    // Construct the clean production URL
    const prodUrl = `https://${projectName}.vercel.app`

    onProgress({ id: 13, label: 'Deploy', detail: 'Deployment complete', status: 'completed' })

    return { success: true, url: prodUrl, projectId: project.id }
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error)
    onProgress({ id: 13, label: 'Deploy', detail: errorMsg, status: 'error' })
    return { success: false, url: '', projectId: project.id, error: errorMsg }
  }
}
