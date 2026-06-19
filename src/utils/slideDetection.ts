/**
 * GIF slide detection — quiet-run algorithm with adaptive filtering
 * and in-slide-build merging.
 *
 * CANONICAL SOURCE — gifViewerGenerator.ts and gif-slide-viewer.html
 * contain ES5 copies of this algorithm for self-contained HTML output.
 * Any changes here MUST be mirrored to those two files.
 */

export interface QuietRun {
  start: number
  end: number
  length: number
  /** Start frame of the LAST sub-run after build-merging (= this run's own start when un-merged). */
  lastStart: number
  /** End frame of the LAST sub-run after build-merging (= this run's own end when un-merged). */
  lastEnd: number
}

export interface DetectedSlide {
  restFrame: number
  holdStart: number
  holdEnd: number
  transitionFrames: { start: number; end: number } | null
}

const QUIET_THRESHOLD = 0.3
const MIN_QUIET_RUN = 8

/**
 * A gap between two quiet runs is a REAL slide transition only if its peak
 * frame-diff clears this bar. In-slide builds (text reveals, bullet-by-bullet
 * disclosure) produce small, localized diffs that fall well below it, so the
 * two holds they separate belong to the SAME slide and get merged.
 *
 * Scale: diff is mean abs per-channel delta on a 0–255 downsample. Calibrated
 * against a known 39-slide quals deck via headless-browser (canvas-exact) diffs:
 * in-slide build steps peaked ≤0.56 while every real slide change was ≥1.0 — a
 * clean empty gap. 0.9 sits in it and yields exactly 39 on BOTH the raw Keynote
 * export AND the re-encoded deploy (robust across encodes). NOTE: this gap is
 * narrow; a very different deck style may need re-tuning or an adaptive cut.
 * Tunable.
 */
const TRANSITION_PEAK = 0.9

export function findQuietRuns(diffs: number[]): QuietRun[] {
  const runs: QuietRun[] = []
  let runStart: number | null = null
  const push = (start: number, end: number) =>
    runs.push({ start, end, length: end - start + 1, lastStart: start, lastEnd: end })
  for (let i = 0; i < diffs.length; i++) {
    if (diffs[i] <= QUIET_THRESHOLD) {
      if (runStart === null) runStart = i
    } else {
      if (runStart !== null && i - runStart >= MIN_QUIET_RUN) push(runStart, i - 1)
      runStart = null
    }
  }
  if (runStart !== null && diffs.length - runStart >= MIN_QUIET_RUN) push(runStart, diffs.length - 1)
  return runs
}

/** Peak frame-diff in the (exclusive) gap between two adjacent runs. */
function gapPeak(diffs: number[], a: QuietRun, b: QuietRun): number {
  let peak = 0
  for (let k = a.end + 1; k <= b.start - 1; k++) if (diffs[k] > peak) peak = diffs[k]
  return peak
}

/**
 * Merge adjacent quiet runs whose separating gap is a low-energy in-slide build
 * rather than a true transition. The merged run keeps the FIRST sub-run's start
 * (slide entry / incoming transition) and the LAST sub-run's end (fully-built
 * state) — the snapshot is taken from the last sub-run so every build step shows.
 */
export function mergeBuildRuns(runs: QuietRun[], diffs: number[]): QuietRun[] {
  if (runs.length === 0) return runs
  const merged: QuietRun[] = [{ ...runs[0] }]
  for (let i = 1; i < runs.length; i++) {
    const cur = merged[merged.length - 1]
    const next = runs[i]
    if (gapPeak(diffs, cur, next) < TRANSITION_PEAK) {
      // Same slide, later build step → extend, remember the last sub-run.
      cur.end = next.end
      cur.length = cur.end - cur.start + 1
      cur.lastStart = next.start
      cur.lastEnd = next.end
    } else {
      merged.push({ ...next })
    }
  }
  return merged
}

/**
 * Adaptive filtering — remove transition artifact "dark pauses" that
 * barely meet the minimum but are much shorter than real slide holds.
 * Uses median run length * 0.33 as threshold. Skipped for < 3 runs.
 *
 * NOTE: build-merging (above) is now the primary de-duplication mechanism, so
 * this length filter only needs to catch genuine sub-threshold artifacts. The
 * factor was lowered 0.5→0.33 because 0.5 dropped a real briefly-held slide
 * (a legitimate ~12-frame hold on the 39-slide calibration deck).
 */
export function filterTransitionArtifacts(runs: QuietRun[]): QuietRun[] {
  if (runs.length < 3) return runs
  const lengths = runs.map((r) => r.length).sort((a, b) => a - b)
  const median = lengths[Math.floor(lengths.length / 2)]
  const adaptiveMin = Math.max(MIN_QUIET_RUN, Math.floor(median * 0.33))
  return runs.filter((r) => r.length >= adaptiveMin)
}

export function buildSlideMap(quietRuns: QuietRun[]): DetectedSlide[] {
  const slides: DetectedSlide[] = []
  for (let i = 0; i < quietRuns.length; i++) {
    const run = quietRuns[i]
    const prevRun = i > 0 ? quietRuns[i - 1] : null
    // Snapshot the LAST sub-run's midpoint = fully-built slide, clear of edges.
    const restFrame = Math.floor((run.lastStart + run.lastEnd) / 2)
    slides.push({
      restFrame,
      holdStart: run.start,
      holdEnd: run.end,
      transitionFrames: prevRun ? { start: prevRun.end + 1, end: run.start - 1 } : null,
    })
  }
  return slides
}

export function detectSlides(diffs: number[]): DetectedSlide[] {
  const allRuns = findQuietRuns(diffs)
  const mergedRuns = mergeBuildRuns(allRuns, diffs)
  const filteredRuns = filterTransitionArtifacts(mergedRuns)
  return buildSlideMap(filteredRuns)
}
