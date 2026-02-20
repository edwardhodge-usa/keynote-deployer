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

    // Check devicePixelRatio
    result.devicePixelRatio = await page.evaluate(() => window.devicePixelRatio)

    // Check canvas elements
    const canvasInfo = await page.evaluate(() => {
      const canvases = document.querySelectorAll('canvas')
      if (canvases.length === 0) {
        return null
      }

      const sample = canvases[0]
      return {
        count: canvases.length,
        sampleWidth: sample.width,
        sampleHeight: sample.height,
        sampleStyleWidth: sample.style.width || '',
        sampleStyleHeight: sample.style.height || '',
      }
    })

    if (canvasInfo) {
      result.canvasElements = {
        ...canvasInfo,
        dprScaling: false, // Will calculate below
      }

      // Check if canvas backing store is scaled by DPR
      // Expected: canvas.width should be ~ 2x canvas.style.width (for DPR=2)
      const styleWidth = parseInt(result.canvasElements.sampleStyleWidth) || 0
      const styleHeight = parseInt(result.canvasElements.sampleStyleHeight) || 0

      if (styleWidth > 0 && styleHeight > 0) {
        const widthRatio = result.canvasElements.sampleWidth / styleWidth
        const heightRatio = result.canvasElements.sampleHeight / styleHeight

        // Check if ratio is approximately 2 (within 0.1 tolerance)
        result.canvasElements.dprScaling =
          Math.abs(widthRatio - 2) < 0.1 && Math.abs(heightRatio - 2) < 0.1
      }
    }

    onProgress({
      id: 15,
      label: 'Runtime verification',
      detail: 'Testing navigation...',
      status: 'active',
    })

    // Test navigation - move to next slide
    let resizeEventFired = false
    await page.exposeFunction('captureResizeEvent', () => {
      resizeEventFired = true
    })

    // Listen for resize events
    await page.evaluate(() => {
      window.addEventListener('resize', () => {
        ;(window as any).captureResizeEvent()
      })
    })

    // Navigate to next slide
    await page.keyboard.press('ArrowRight')
    result.navigationTested = true

    // Wait a bit to see if resize event fires
    await page.waitForTimeout(500)
    result.reRenderTriggered = resizeEventFired

    // Overall success: DPR is 2, canvas is scaled, and re-render works
    result.success =
      result.devicePixelRatio === 2 &&
      result.canvasElements.dprScaling &&
      result.reRenderTriggered

    if (result.success) {
      onProgress({
        id: 15,
        label: 'Runtime verification',
        detail: '✓ Runtime verified',
        status: 'completed',
      })
    } else {
      const issues: string[] = []
      if (result.devicePixelRatio !== 2) {
        issues.push(`DPR=${result.devicePixelRatio}`)
      }
      if (!result.canvasElements.dprScaling) {
        issues.push('canvas not scaled')
      }
      if (!result.reRenderTriggered) {
        issues.push('no re-render')
      }

      onProgress({
        id: 15,
        label: 'Runtime verification',
        detail: `⚠ ${issues.join(', ')}`,
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
