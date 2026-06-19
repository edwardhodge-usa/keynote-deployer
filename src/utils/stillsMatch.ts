export function naturalSort(names: string[]): string[] {
  const key = (s: string) => s.split(/(\d+)/).map(p => /^\d+$/.test(p) ? p.padStart(10, '0') : p).join('')
  return [...names].sort((a, b) => key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0)
}
function meanAbs(a: number[], b: number[]): number {
  if (a.length === 0) return 0
  let s = 0; for (let i = 0; i < a.length; i++) s += Math.abs(a[i] - b[i]); return s / a.length
}
// DP: dp[i][f] = min total cost matching stills 0..i with still i -> frame f (f strictly increasing).
export function matchStillsToFrames(stills: number[][], frames: number[][]): number[] {
  const N = stills.length, M = frames.length
  const INF = Infinity
  const cost: number[][] = stills.map(s => frames.map(f => meanAbs(s, f)))
  const dp: number[][] = Array.from({ length: N }, () => new Array(M).fill(INF))
  const back: number[][] = Array.from({ length: N }, () => new Array(M).fill(-1))
  for (let f = 0; f < M; f++) dp[0][f] = cost[0][f]
  for (let i = 1; i < N; i++) {
    let bestPrev = INF, bestPrevIdx = -1
    for (let f = 0; f < M; f++) {
      if (f - 1 >= 0 && dp[i-1][f-1] <= bestPrev) { bestPrev = dp[i-1][f-1]; bestPrevIdx = f - 1 }
      if (bestPrev !== INF) { dp[i][f] = bestPrev + cost[i][f]; back[i][f] = bestPrevIdx }
    }
  }
  let endF = -1, best = INF
  for (let f = 0; f < M; f++) if (dp[N-1][f] < best) { best = dp[N-1][f]; endF = f }
  const out = new Array(N).fill(0); let f = endF
  for (let i = N - 1; i >= 0; i--) { out[i] = f; f = back[i][f] }
  return out
}
