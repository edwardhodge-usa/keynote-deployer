/**
 * GIF slide detection — quiet-run algorithm with adaptive filtering.
 *
 * CANONICAL SOURCE — gifViewerGenerator.ts and gif-slide-viewer.html
 * contain ES5 copies of this algorithm for self-contained HTML output.
 * Any changes here MUST be mirrored to those two files.
 */

export interface QuietRun {
  start: number
  end: number
  length: number
}

export interface DetectedSlide {
  restFrame: number
  holdStart: number
  holdEnd: number
  transitionFrames: { start: number; end: number } | null
}

const QUIET_THRESHOLD = 0.3
const MIN_QUIET_RUN = 8

export function findQuietRuns(diffs: number[]): QuietRun[] {
  const runs: QuietRun[] = []
  let runStart: number | null = null
  for (let i = 0; i < diffs.length; i++) {
    if (diffs[i] <= QUIET_THRESHOLD) {
      if (runStart === null) runStart = i
    } else {
      if (runStart !== null && i - runStart >= MIN_QUIET_RUN) {
        runs.push({ start: runStart, end: i - 1, length: i - runStart })
      }
      runStart = null
    }
  }
  if (runStart !== null && diffs.length - runStart >= MIN_QUIET_RUN) {
    runs.push({ start: runStart, end: diffs.length - 1, length: diffs.length - runStart })
  }
  return runs
}

/**
 * Adaptive filtering — remove transition artifact "dark pauses" that
 * barely meet the minimum but are much shorter than real slide holds.
 * Uses median run length * 0.5 as threshold. Skipped for < 3 runs.
 */
export function filterTransitionArtifacts(runs: QuietRun[]): QuietRun[] {
  if (runs.length < 3) return runs
  const lengths = runs.map((r) => r.length).sort((a, b) => a - b)
  const median = lengths[Math.floor(lengths.length / 2)]
  const adaptiveMin = Math.max(MIN_QUIET_RUN, Math.floor(median * 0.5))
  return runs.filter((r) => r.length >= adaptiveMin)
}

export function buildSlideMap(quietRuns: QuietRun[]): DetectedSlide[] {
  const slides: DetectedSlide[] = []
  for (let i = 0; i < quietRuns.length; i++) {
    const run = quietRuns[i]
    const prevRun = i > 0 ? quietRuns[i - 1] : null
    const midFrame = Math.floor((run.start + run.end) / 2)
    slides.push({
      restFrame: midFrame,
      holdStart: run.start,
      holdEnd: run.end,
      transitionFrames: prevRun ? { start: prevRun.end + 1, end: run.start - 1 } : null,
    })
  }
  return slides
}

export function detectSlides(diffs: number[]): DetectedSlide[] {
  const allRuns = findQuietRuns(diffs)
  const filteredRuns = filterTransitionArtifacts(allRuns)
  return buildSlideMap(filteredRuns)
}
