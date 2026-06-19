import { describe, it, expect } from 'vitest'
import { naturalSort, matchStillsToFrames } from './stillsMatch'

describe('naturalSort', () => {
  it('orders numerically, not lexically', () => {
    expect(naturalSort(['s.10.jpg','s.2.jpg','s.1.jpg'])).toEqual(['s.1.jpg','s.2.jpg','s.10.jpg'])
  })
})
describe('matchStillsToFrames', () => {
  it('returns monotonic matches and resists greedy poisoning', () => {
    // 3 stills = grids [0],[5],[9]; frames 0..9 are their own value; a decoy: frame 2 also ~5
    const frames = [[0],[1],[5],[3],[4],[5],[6],[7],[8],[9]] // frame2 decoy near still1
    const stills = [[0],[5],[9]]
    const m = matchStillsToFrames(stills, frames)
    expect(m.length).toBe(3)
    expect(m[0] < m[1] && m[1] < m[2]).toBe(true)   // monotonic
    expect(m[2]).toBe(9)                            // last still maps to the true frame 9
    // greedy would grab frame2 for still1 and poison; DP must pick frame5
    expect(m[1]).toBe(5)
  })
})
