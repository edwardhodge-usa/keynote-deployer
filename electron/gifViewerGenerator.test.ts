import { describe, it, expect } from 'vitest'
import { generateGifViewerHtml } from './gifViewerGenerator'

const slides = [
  { restFrame: 10, holdStart: 5, holdEnd: 15, transitionFrames: null },
  { restFrame: 40, holdStart: 35, holdEnd: 45, transitionFrames: { start: 16, end: 34 } },
]

describe('generateGifViewerHtml', () => {
  it('bakes the slides array as a JSON literal', () => {
    const html = generateGifViewerHtml('deck.gif', false, slides)
    expect(html).toContain('"restFrame":10')
    expect(html).toContain('"restFrame":40')
  })
  it('does NOT run client-side quiet-run detection', () => {
    const html = generateGifViewerHtml('deck.gif', false, slides)
    expect(html).not.toContain('findQuietRuns')
    expect(html).not.toContain('mergeBuildRuns')
  })
})
