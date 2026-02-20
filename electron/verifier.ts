import type { VerificationResult, FixVerification, ProcessingStep } from '../src/types/index'

// Expected replacement patterns (what should exist in deployed main.js)
const EXPECTED_FIXES = [
  {
    number: 1,
    name: 'zC scale (PDF rasterization)',
    pattern: 'qC=!0;const zC=3,',
  },
  {
    number: 2,
    name: 'Fullscreen bypass',
    pattern: '!0||A>this.showWidth',
  },
  {
    number: 3,
    name: 'Viewport A (sparkle/particle effects)',
    pattern: 'Q.viewport(0,0,Q.viewportWidth*Math.max(window.devicePixelRatio||1,2),Q.viewportHeight*Math.max(window.devicePixelRatio||1,2))',
  },
  {
    number: 4,
    name: 'Viewport B (firework effects)',
    pattern: 'C.viewport(0,0,C.viewportWidth*Math.max(window.devicePixelRatio||1,2),C.viewportHeight*Math.max(window.devicePixelRatio||1,2))',
  },
  {
    number: 5,
    name: 'Resize viewport DPR scaling',
    pattern: 'B.viewport(0,0,g*Math.max(window.devicePixelRatio||1,2),C*Math.max(window.devicePixelRatio||1,2)),B.viewportWidth=g,B.viewportHeight=C',
  },
  {
    number: 6,
    name: 'Constructor viewport division',
    pattern: 'g.viewportWidth=B.width/Math.max(window.devicePixelRatio||1,2),g.viewportHeight=B.height/Math.max(window.devicePixelRatio||1,2)',
  },
  {
    number: 7,
    name: 'Canvas DPR backing store',
    pattern: 'B.width=UC.script.slideWidth*Math.max(window.devicePixelRatio||1,2),B.height=UC.script.slideHeight*Math.max(window.devicePixelRatio||1,2),B.style.width=UC.script.slideWidth+"px",B.style.height=UC.script.slideHeight+"px"',
  },
]

type ProgressCallback = (step: ProcessingStep) => void

export async function verifyDeployment(
  deployUrl: string,
  onProgress: ProgressCallback
): Promise<VerificationResult> {
  const result: VerificationResult = {
    success: false,
    url: deployUrl,
    mainJsVerified: false,
    indexHtmlVerified: false,
    fixes: [],
    totalFixesFound: 0,
    totalFixesMissing: 0,
  }

  try {
    // Step 14: Verify deployment
    onProgress({ id: 14, label: 'Verify deployment', detail: 'Fetching deployed files...', status: 'active' })

    // Fetch main.js from deployed URL
    const mainJsUrl = `${deployUrl}/assets/player/main.js`
    const mainJsResponse = await fetch(mainJsUrl)

    if (!mainJsResponse.ok) {
      throw new Error(`Failed to fetch main.js: ${mainJsResponse.status}`)
    }

    const mainJsContent = await mainJsResponse.text()
    onProgress({ id: 14, label: 'Verify deployment', detail: 'Checking fixes...', status: 'active' })

    // Verify each fix
    for (const expectedFix of EXPECTED_FIXES) {
      const found = mainJsContent.includes(expectedFix.pattern)
      const verification: FixVerification = {
        fixNumber: expectedFix.number,
        name: expectedFix.name,
        found,
        pattern: expectedFix.pattern.slice(0, 50) + '...', // Truncate for display
      }
      result.fixes.push(verification)

      if (found) {
        result.totalFixesFound++
      } else {
        result.totalFixesMissing++
      }
    }

    result.mainJsVerified = result.totalFixesMissing === 0

    // Fetch and verify index.html
    const indexHtmlResponse = await fetch(deployUrl)
    if (!indexHtmlResponse.ok) {
      throw new Error(`Failed to fetch index.html: ${indexHtmlResponse.status}`)
    }

    const indexHtmlContent = await indexHtmlResponse.text()

    // Verify index.html contains re-render polling logic
    const hasPolling = indexHtmlContent.includes('pollingInterval=setInterval') &&
                      indexHtmlContent.includes('triggerReRenders')
    const hasNavBar = indexHtmlContent.includes('id="navBar"')
    const hasLoadingOverlay = indexHtmlContent.includes('id="loadingOverlay"')

    result.indexHtmlVerified = hasPolling && hasNavBar && hasLoadingOverlay

    // Overall success: all fixes found and index.html verified
    result.success = result.mainJsVerified && result.indexHtmlVerified

    if (result.success) {
      onProgress({
        id: 14,
        label: 'Verify deployment',
        detail: `✓ All ${result.totalFixesFound} fixes verified`,
        status: 'completed',
      })
    } else {
      const issues: string[] = []
      if (!result.mainJsVerified) {
        issues.push(`${result.totalFixesMissing} fixes missing`)
      }
      if (!result.indexHtmlVerified) {
        issues.push('index.html issues')
      }

      onProgress({
        id: 14,
        label: 'Verify deployment',
        detail: `⚠ ${issues.join(', ')}`,
        status: 'error',
      })
    }

    return result
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error)
    result.error = errorMsg
    onProgress({
      id: 14,
      label: 'Verify deployment',
      detail: errorMsg,
      status: 'error',
    })
    return result
  }
}
