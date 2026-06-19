import { describe, it, expect } from 'vitest'
import { detectSlides } from './slideDetection'

// Build a synthetic diffs array: quiet holds (0) separated by gaps of given peak.
function synth(holds: number, holdLen: number, gapPeaks: number[]): number[] {
  const d: number[] = []
  for (let s = 0; s < holds; s++) {
    for (let i = 0; i < holdLen; i++) d.push(0)        // quiet hold
    if (s < holds - 1) { d.push(gapPeaks[s]); d.push(0.1) } // 1-frame transition spike
  }
  return d
}

describe('conservative Auto threshold', () => {
  it('merges only clearly-tiny micro-build gaps (< 0.5, exclusive), never a real slide change', () => {
    // 4 holds; gaps: 0.7 ambiguous, 1.2 (real change), 0.45 (micro-build)
    const diffs = synth(4, 10, [0.7, 1.2, 0.45])
    const slides = detectSlides(diffs)
    // 0.7 ambiguous, 1.2 stays → 3 slides
    expect(slides.length).toBe(3)
  })

  it('does NOT merge a 1.0 gap (real text-only slide change on constant bg)', () => {
    const diffs = synth(2, 10, [1.0])
    expect(detectSlides(diffs).length).toBe(2)
  })
})
