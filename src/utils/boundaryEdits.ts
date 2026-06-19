import { findQuietRuns, type DetectedSlide } from './slideDetection'

export function removeStop(slides: DetectedSlide[], restFrame: number): DetectedSlide[] {
  return recomputeTransitions(slides.filter(s => s.restFrame !== restFrame))
}

export function insertStop(slides: DetectedSlide[], frame: number, diffs: number[]): DetectedSlide[] {
  if (slides.some(s => s.restFrame === frame)) return slides // already a stop at this frame
  const runs = findQuietRuns(diffs)
  const run = runs.find(r => frame >= r.start && frame <= r.end)
    ?? runs.reduce((best, r) => Math.abs((r.start+r.end)/2 - frame) < Math.abs((best.start+best.end)/2 - frame) ? r : best, runs[0])
  const slide: DetectedSlide = { restFrame: frame, holdStart: run?.start ?? frame, holdEnd: run?.end ?? frame, transitionFrames: null }
  const next = [...slides, slide].sort((a,b) => a.restFrame - b.restFrame)
  return recomputeTransitions(next)
}

function recomputeTransitions(slides: DetectedSlide[]): DetectedSlide[] {
  return slides.map((s, i) => {
    if (i === 0) return { ...s, transitionFrames: null }
    const start = slides[i - 1].holdEnd + 1
    const end = s.holdStart - 1
    // Inverted/empty range (overlapping holds) → no transition, just a cut.
    return { ...s, transitionFrames: start <= end ? { start, end } : null }
  })
}
