import puppeteer from 'puppeteer'
import type { RuntimeVerificationResult, ProcessingStep } from '../src/types/index'

type ProgressCallback = (step: ProcessingStep) => void

export async function verifyRuntime(
  deployUrl: string,
  onProgress: ProgressCallback
): Promise<RuntimeVerificationResult> {
  const result: RuntimeVerificationResult = {
    success: false,
    devicePixelRatio: 0,
    canvasElements: {
      count: 0,
      sampleWidth: 0,
      sampleHeight: 0,
      sampleStyleWidth: '',
      sampleStyleHeight: '',
      dprScaling: false,
    },
    navigationTested: false,
    reRenderTriggered: false,
  }

  let browser
  try {
    onProgress({
      id: 15,
      label: 'Runtime verification',
      detail: 'Launching browser...',
      status: 'active',
    })

    // Launch headless browser
    browser = await puppeteer.launch({
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
    })

    const page = await browser.newPage()

    // Set viewport to simulate retina display (2x DPR)
    await page.setViewport({
      width: 1920,
      height: 1080,
      deviceScaleFactor: 2,
    })

    onProgress({
      id: 15,
      label: 'Runtime verification',
      detail: 'Loading presentation...',
      status: 'active',
    })

    // Navigate to deployed URL
    await page.goto(deployUrl, { waitUntil: 'networkidle0', timeout: 30000 })

    // Wait for canvas to appear (presentation loaded)
    await page.waitForSelector('canvas', { timeout: 15000 })

    // Wait a bit for initialization
    await page.waitForTimeout(1000)

    onProgress({
      id: 15,
      label: 'Runtime verification',
      detail: 'Checking DPR and canvas...',
      status: 'active',
    })

    // Check devicePixelRatio with better error handling
    const dpr = await page.evaluate(() => {
      try {
        return window.devicePixelRatio || 0
      } catch (e) {
        return 0
      }
    })
    result.devicePixelRatio = dpr || 0

    // Check canvas elements with computed styles
    const canvasInfo = await page.evaluate(() => {
      try {
        const canvases = document.querySelectorAll('canvas')
        if (canvases.length === 0) {
          return null
        }

        const sample = canvases[0]
        const computedStyle = window.getComputedStyle(sample)

        return {
          count: canvases.length,
          sampleWidth: sample.width,
          sampleHeight: sample.height,
          // Use computed style instead of inline style
          sampleStyleWidth: computedStyle.width,
          sampleStyleHeight: computedStyle.height,
        }
      } catch (e) {
        return null
      }
    })

    if (canvasInfo) {
      result.canvasElements = {
        ...canvasInfo,
        dprScaling: false, // Will calculate below
      }

      // Check if canvas backing store is scaled by DPR
      // Expected: canvas.width should be ~ 2x computed style width (for DPR=2)
      const styleWidth = parseFloat(result.canvasElements.sampleStyleWidth) || 0
      const styleHeight = parseFloat(result.canvasElements.sampleStyleHeight) || 0

      if (styleWidth > 0 && styleHeight > 0) {
        const widthRatio = result.canvasElements.sampleWidth / styleWidth
        const heightRatio = result.canvasElements.sampleHeight / styleHeight

        // Check if ratio is approximately 3 (our HiDPI fix) - within 0.3 tolerance for flexibility
        result.canvasElements.dprScaling =
          Math.abs(widthRatio - 3) < 0.3 && Math.abs(heightRatio - 3) < 0.3
      }
    }

    onProgress({
      id: 15,
      label: 'Runtime verification',
      detail: 'Testing navigation...',
      status: 'active',
    })

    // Test navigation - move to next slide and verify canvas updates
    const beforeNavigation = await page.evaluate(() => {
      try {
        const canvas = document.querySelector('canvas') as HTMLCanvasElement
        if (!canvas) return null
        // Get a sample of canvas data to detect changes
        const ctx = canvas.getContext('2d')
        if (!ctx) return null
        const imageData = ctx.getImageData(0, 0, Math.min(10, canvas.width), Math.min(10, canvas.height))
        return Array.from(imageData.data).slice(0, 40).join(',')
      } catch (e) {
        return null
      }
    })

    // Navigate to next slide
    await page.keyboard.press('ArrowRight')
    result.navigationTested = true

    // Wait for potential animation/re-render
    await page.waitForTimeout(500)

    // Check if canvas content changed (indicates re-render)
    const afterNavigation = await page.evaluate(() => {
      try {
        const canvas = document.querySelector('canvas') as HTMLCanvasElement
        if (!canvas) return null
        const ctx = canvas.getContext('2d')
        if (!ctx) return null
        const imageData = ctx.getImageData(0, 0, Math.min(10, canvas.width), Math.min(10, canvas.height))
        return Array.from(imageData.data).slice(0, 40).join(',')
      } catch (e) {
        return null
      }
    })

    // If canvas data changed, re-render happened
    result.reRenderTriggered = beforeNavigation !== null && afterNavigation !== null && beforeNavigation !== afterNavigation

    // Overall success: canvas is scaled by 3x (our HiDPI fix)
    // DPR and re-render are informational but not critical for success
    result.success = result.canvasElements.dprScaling

    if (result.success) {
      const extras: string[] = []
      if (result.reRenderTriggered) {
        extras.push('re-render ✓')
      }
      onProgress({
        id: 15,
        label: 'Runtime verification',
        detail: extras.length > 0 ? `✓ Runtime verified (${extras.join(', ')})` : '✓ Runtime verified',
        status: 'completed',
      })
    } else {
      const issues: string[] = []
      if (!result.canvasElements.dprScaling) {
        issues.push('canvas not 3x scaled')
      }
      if (result.devicePixelRatio !== 2) {
        issues.push(`DPR=${result.devicePixelRatio} (informational)`)
      }

      // Re-render is informational only, not an error
      const notes: string[] = []
      if (!result.reRenderTriggered && result.navigationTested) {
        notes.push('(no slide change detected)')
      }

      onProgress({
        id: 15,
        label: 'Runtime verification',
        detail: `⚠ ${issues.join(', ')} ${notes.join(' ')}`,
        status: 'error',
      })
    }

    return result
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error)
    result.error = errorMsg
    onProgress({
      id: 15,
      label: 'Runtime verification',
      detail: errorMsg.slice(0, 50),
      status: 'error',
    })
    return result
  } finally {
    if (browser) {
      await browser.close()
    }
  }
}
