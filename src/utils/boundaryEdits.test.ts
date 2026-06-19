import { describe, it, expect } from 'vitest'
import { removeStop, insertStop } from './boundaryEdits'

const base = [
  { restFrame: 10, holdStart: 5, holdEnd: 15, transitionFrames: null },
  { restFrame: 40, holdStart: 35, holdEnd: 45, transitionFrames: { start: 16, end: 34 } },
]

describe('boundaryEdits', () => {
  it('removes a stop and recomputes transitions', () => {
    expect(removeStop(base, 10).length).toBe(1)
  })
  it('inserts a stop in sorted order with a recomputed transition', () => {
    const diffs = new Array(50).fill(0); diffs[25] = 2  // quiet around frame 25
    const out = insertStop(base, 25, diffs)
    expect(out.map(s => s.restFrame)).toEqual([10, 25, 40])
    expect(out[1].transitionFrames).not.toBeNull()
  })
})
