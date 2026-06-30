import Foundation

/// Picks the Rest frame (the settled, sharp frame a viewer pauses on) inside a known
/// hold span. The Rest is the temporally-CALMEST frame (argmin of the consecutive diff
/// signal over the hold interior), with near-ties broken by maximum SHARPNESS
/// (variance-of-Laplacian on the luma grid) so a half-faded / motion-blurred frame
/// never wins over a crisp held frame.
///
/// This replaces "Rest = the verbatim DP anchor", which could land on a transition
/// trailing edge or a motion-blurred frame. Pure over `[[Double]]` grids; consumed by
/// `HoldDetector` (section 07), which supplies each slide's hold range.
enum RestSelector {

    /// Frames within this absolute diff (0–255 scale) of the calmest are "equally calm"
    /// → the sharpness tie-break decides among them. Lets a marginally-less-calm but
    /// sharp frame beat a marginally-calmer blurred one.
    static let calmTieBand = 0.5

    /// Pick the Rest frame inside a hold. `hold` is a half-open `start..<end` of frame
    /// indices. `diffSignal` is `FrameSignal.diffSignal` (length frameGrids.count-1).
    /// `margin` keeps the choice off the hold's transition-adjacent edges when interior
    /// frames exist. Always returns an in-range frame index; never crashes.
    static func restFrame(in hold: Range<Int>,
                          diffSignal: [Double],
                          frameGrids: [[Double]],
                          margin: Int = 1) -> Int {
        let n = frameGrids.count
        guard n > 0 else { return 0 }
        let lo = Swift.max(0, hold.lowerBound)
        let hi = Swift.min(n - 1, hold.upperBound - 1)
        guard lo <= hi else { return Swift.min(Swift.max(0, hold.lowerBound), n - 1) }

        // Interior window (off the edges) when it's non-empty; else the whole hold.
        var clo = lo + margin, chi = hi - margin
        if clo > chi { clo = lo; chi = hi }

        // Calmest frame(s): argmin local diff (motion entering + leaving the frame).
        var minLocal = Double.greatestFiniteMagnitude
        for f in clo...chi { minLocal = Swift.min(minLocal, localDiff(f, diffSignal)) }

        // Among the near-calmest (within calmTieBand), pick the sharpest (max VoL).
        var best = clo
        var bestSharp = -Double.greatestFiniteMagnitude
        for f in clo...chi where localDiff(f, diffSignal) <= minLocal + calmTieBand {
            let s = sharpness(frameGrids[f])
            if s > bestSharp { bestSharp = s; best = f }
        }
        return best
    }

    /// Local temporal motion attributable to frame `f`: the diff entering it plus the
    /// diff leaving it. `diffSignal[i]` is the diff between frame i and i+1, so frame f
    /// is calm when both `diffSignal[f-1]` and `diffSignal[f]` are near zero.
    static func localDiff(_ f: Int, _ diffSignal: [Double]) -> Double {
        let entering = f - 1 >= 0 && f - 1 < diffSignal.count ? diffSignal[f - 1] : 0
        let leaving = f >= 0 && f < diffSignal.count ? diffSignal[f] : 0
        return entering + leaving
    }

    /// Sharpness = variance-of-Laplacian on the grayscale (luma) grid. Higher = sharper;
    /// a motion-blurred / half-faded frame has a near-flat luma image → low VoL. Only
    /// comparable WITHIN one hold (content-dependent), never across slides. Coarse on a
    /// 32×18 grid but adequate to separate a held frame from a half-faded one.
    static func sharpness(_ grid: [Double]) -> Double {
        let luma = FrameSignal.channels(grid).luma
        let w = GridSampler.width, h = GridSampler.height
        guard luma.count == w * h, w >= 3, h >= 3 else { return 0 }
        // Discrete Laplacian over the interior cells (skip the border, no neighbors).
        var responses = [Double](); responses.reserveCapacity((w - 2) * (h - 2))
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c = luma[y * w + x]
                let lap = 4 * c - luma[y * w + (x - 1)] - luma[y * w + (x + 1)]
                    - luma[(y - 1) * w + x] - luma[(y + 1) * w + x]
                responses.append(lap)
            }
        }
        guard !responses.isEmpty else { return 0 }
        let mean = responses.reduce(0, +) / Double(responses.count)
        var acc = 0.0
        for r in responses { let d = r - mean; acc += d * d }
        return acc / Double(responses.count)
    }
}
