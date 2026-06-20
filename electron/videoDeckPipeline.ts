// Video deck pipeline: derive per-slide timestamps from a deck video + its
// per-slide stills, and re-encode the video with a keyframe at each slide.
//
// Dependency-light: shells out to ffmpeg only (no image-decode library). ffmpeg
// decodes both the video and the JPEG stills to raw rgb24, which we downsample
// and feed to the existing DP matcher (src/utils/stillsMatch.ts). ffmpeg must be
// on PATH or provided via opts.ffmpegPath (bundle it with the app for release).
//
// See docs/VIDEO_DECK_VIEWER.md.
import { execFile } from 'child_process'
import { promisify } from 'util'
import { matchStillsToFrames, naturalSort } from '../src/utils/stillsMatch'

const execFileAsync = promisify(execFile)

const SAMPLE_W = 32
const SAMPLE_H = 18
const MAX_BUFFER = 256 * 1024 * 1024 // rawvideo can be large

// Decode `input` to a sequence of downsampled rgb24 grids (one number[] per frame).
async function sampleGrids(ffmpegPath: string, input: string): Promise<number[][]> {
  const { stdout } = await execFileAsync(
    ffmpegPath,
    ['-v', 'error', '-i', input, '-vf', `scale=${SAMPLE_W}:${SAMPLE_H}`, '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
    { encoding: 'buffer', maxBuffer: MAX_BUFFER }
  )
  const buf = stdout as unknown as Buffer
  const frameBytes = SAMPLE_W * SAMPLE_H * 3
  const count = Math.floor(buf.length / frameBytes)
  const grids: number[][] = []
  for (let i = 0; i < count; i++) {
    const start = i * frameBytes
    const g = new Array<number>(frameBytes)
    for (let j = 0; j < frameBytes; j++) g[j] = buf[start + j]
    grids.push(g)
  }
  return grids
}

export interface DeriveResult {
  frames: number[]       // matched frame index per slide (monotonic)
  timestamps: number[]   // seconds (frame / fps)
  slideCount: number
}

// Derive the settled-slide timestamps by DP-matching the stills to video frames.
// stillPaths are matched in natural-sorted order (slide 1..N).
export async function deriveTimestamps(opts: {
  ffmpegPath?: string
  videoPath: string
  stillPaths: string[]
  fps: number
}): Promise<DeriveResult> {
  const ffmpeg = opts.ffmpegPath ?? 'ffmpeg'
  const stills = naturalSort(opts.stillPaths)
  const frameGrids = await sampleGrids(ffmpeg, opts.videoPath)
  const stillGrids: number[][] = []
  for (const p of stills) {
    const g = await sampleGrids(ffmpeg, p) // a still decodes to exactly 1 frame
    if (g[0]) stillGrids.push(g[0])
  }
  const frames = matchStillsToFrames(stillGrids, frameGrids)
  return {
    frames,
    timestamps: frames.map(f => Math.round((f / opts.fps) * 1000) / 1000),
    slideCount: stillGrids.length,
  }
}

// Re-encode to web H.264 with a forced keyframe at each slide timestamp (crisp
// paused frames + accurate seeking) and +faststart for streaming.
export async function encodeWithKeyframes(opts: {
  ffmpegPath?: string
  input: string
  output: string
  timestamps: number[]
  crf?: number
}): Promise<void> {
  const ffmpeg = opts.ffmpegPath ?? 'ffmpeg'
  const kf = opts.timestamps.join(',')
  await execFileAsync(
    ffmpeg,
    [
      '-y', '-i', opts.input,
      '-c:v', 'libx264', '-crf', String(opts.crf ?? 18), '-preset', 'medium',
      '-pix_fmt', 'yuv420p',
      '-force_key_frames', kf,
      '-movflags', '+faststart', '-an',
      opts.output,
    ],
    { maxBuffer: MAX_BUFFER }
  )
}

// Probe width/height/fps of a video (for the viewer aspect ratio).
export async function probeVideo(opts: { ffprobePath?: string; input: string }): Promise<{ width: number; height: number; fps: number }> {
  const ffprobe = opts.ffprobePath ?? 'ffprobe'
  const { stdout } = await execFileAsync(
    ffprobe,
    ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height,r_frame_rate', '-of', 'default=noprint_wrappers=1', opts.input],
    { encoding: 'utf8', maxBuffer: 1024 * 1024 }
  )
  const out = stdout as unknown as string
  const w = Number((out.match(/width=(\d+)/) || [])[1] || 1920)
  const h = Number((out.match(/height=(\d+)/) || [])[1] || 1080)
  const rate = (out.match(/r_frame_rate=(\d+)\/(\d+)/) || [])
  const fps = rate[1] && rate[2] ? Number(rate[1]) / Number(rate[2]) : 30
  return { width: w, height: h, fps }
}
