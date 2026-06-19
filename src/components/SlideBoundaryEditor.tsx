import { useEffect, useRef, useState } from 'react'
import { type DetectedSlide } from '../utils/slideDetection'
import { removeStop, insertStop } from '../utils/boundaryEdits'

interface Props {
  frames: ImageBitmap[]
  diffs: number[]
  slides: DetectedSlide[]
  onChange: (slides: DetectedSlide[]) => void
}

const THUMB_W = 96
const THUMB_H = 54

function SlideThumbnail({
  frame,
  index,
  onRemove,
}: {
  frame: ImageBitmap
  index: number
  onRemove: () => void
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    canvas.width = THUMB_W
    canvas.height = THUMB_H
    const ctx = canvas.getContext('2d')
    if (!ctx) return
    ctx.drawImage(frame, 0, 0, THUMB_W, THUMB_H)
  }, [frame])

  return (
    <div className="relative group flex-shrink-0">
      <canvas
        ref={canvasRef}
        width={THUMB_W}
        height={THUMB_H}
        className="rounded border border-gray-600 block"
        style={{ width: THUMB_W, height: THUMB_H }}
      />
      <div className="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
        <button
          onClick={onRemove}
          title="Remove this slide boundary"
          className="w-5 h-5 rounded-full bg-red-500 text-white text-xs font-bold leading-none flex items-center justify-center hover:bg-red-600 active:scale-95 transition-all"
          style={{ cursor: 'default' }}
        >
          ✕
        </button>
      </div>
      <p className="text-[10px] text-center text-gray-400 mt-0.5">{index + 1}</p>
    </div>
  )
}

export default function SlideBoundaryEditor({ frames, diffs, slides, onChange }: Props) {
  const [scrubFrame, setScrubFrame] = useState(0)
  const scrubCanvasRef = useRef<HTMLCanvasElement>(null)

  const maxFrame = Math.max(0, frames.length - 1)

  // Render scrub preview whenever scrubFrame changes
  useEffect(() => {
    const canvas = scrubCanvasRef.current
    if (!canvas || !frames[scrubFrame]) return
    canvas.width = THUMB_W * 2
    canvas.height = THUMB_H * 2
    const ctx = canvas.getContext('2d')
    if (!ctx) return
    ctx.drawImage(frames[scrubFrame], 0, 0, THUMB_W * 2, THUMB_H * 2)
  }, [scrubFrame, frames])

  const nudge = (delta: number) => {
    setScrubFrame(prev => Math.max(0, Math.min(maxFrame, prev + delta)))
  }

  const handleInsert = () => {
    onChange(insertStop(slides, scrubFrame, diffs))
  }

  return (
    <div className="mt-4 space-y-4">
      {/* Slide thumbnail grid */}
      <div>
        <p className="text-[12px] text-gray-400 mb-2">
          Slide boundaries — <span className="font-semibold text-gray-200">{slides.length}</span> slide{slides.length !== 1 ? 's' : ''}.
          Hover a thumbnail and click ✕ to remove.
        </p>
        {slides.length === 0 ? (
          <p className="text-[13px] text-gray-500 italic">No slides. Use the scrubber below to insert one.</p>
        ) : (
          <div className="flex flex-wrap gap-2">
            {slides.map((slide, i) => (
              <SlideThumbnail
                key={`${slide.restFrame}-${i}`}
                frame={frames[slide.restFrame]}
                index={i}
                onRemove={() => onChange(removeStop(slides, slide.restFrame))}
              />
            ))}
          </div>
        )}
      </div>

      {/* Frame scrubber + insert */}
      <div className="p-3 rounded-lg bg-gray-800/60 border border-gray-700 space-y-2">
        <div className="flex items-center gap-2">
          <canvas
            ref={scrubCanvasRef}
            width={THUMB_W * 2}
            height={THUMB_H * 2}
            className="rounded border border-gray-600 flex-shrink-0"
            style={{ width: THUMB_W * 2, height: THUMB_H * 2 }}
          />
          <div className="flex-1 space-y-2">
            <div className="flex items-center gap-1">
              <button
                onClick={() => nudge(-1)}
                disabled={scrubFrame <= 0}
                className="btn btn-secondary btn-sm"
                title="Previous frame"
              >
                ←
              </button>
              <input
                type="range"
                min={0}
                max={maxFrame}
                value={scrubFrame}
                onChange={e => setScrubFrame(Number(e.target.value))}
                className="flex-1 accent-blue-500"
              />
              <button
                onClick={() => nudge(1)}
                disabled={scrubFrame >= maxFrame}
                className="btn btn-secondary btn-sm"
                title="Next frame"
              >
                →
              </button>
            </div>
            <p className="text-[11px] text-gray-400 text-center">
              Frame {scrubFrame} / {maxFrame}
            </p>
            <button
              onClick={handleInsert}
              className="btn btn-secondary btn-sm w-full"
            >
              Insert stop here
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
