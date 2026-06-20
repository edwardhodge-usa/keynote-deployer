import { describe, it, expect } from 'vitest'
import { generateVideoViewerHtml } from './videoViewerGenerator'

const timestamps = [1.033, 2.567, 5.567]

describe('generateVideoViewerHtml', () => {
  it('bakes the timestamps array', () => {
    const html = generateVideoViewerHtml('deck.mp4', false, timestamps)
    expect(html).toContain('[1.033,2.567,5.567]')
  })
  it('references the given video filename', () => {
    const html = generateVideoViewerHtml('mydeck.mp4', false, timestamps)
    expect(html).toContain('./mydeck.mp4')
  })
  it('honors secure embed', () => {
    const html = generateVideoViewerHtml('deck.mp4', true, timestamps)
    expect(html).toContain('user-select: none')
    expect(html).toContain('contextmenu')
  })
})
