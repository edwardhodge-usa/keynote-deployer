import { findQuietRuns, type DetectedSlide } from './slideDetection'

export function removeStop(slides: DetectedSlide[], restFrame: number): DetectedSlide[] {
  return recomputeTransitions(slides.filter(s => s.restFrame !== restFrame))
}

export function insertStop(slides: DetectedSlide[], frame: number, diffs: number[]): DetectedSlide[] {
  const runs = findQuietRuns(diffs)
  const run = runs.find(r => frame >= r.start && frame <= r.end)
    ?? runs.reduce((best, r) => Math.abs((r.start+r.end)/2 - frame) < Math.abs((best.start+best.end)/2 - frame) ? r : best, runs[0])
  const slide: DetectedSlide = { restFrame: frame, holdStart: run?.start ?? frame, holdEnd: run?.end ?? frame, transitionFrames: null }
  const next = [...slides, slide].sort((a,b) => a.restFrame - b.restFrame)
  return recomputeTransitions(next)
}

function recomputeTransitions(slides: DetectedSlide[]): DetectedSlide[] {
  return slides.map((s, i) => ({ ...s, transitionFrames: i > 0 ? { start: slides[i-1].holdEnd + 1, end: s.holdStart - 1 } : null }))
}
