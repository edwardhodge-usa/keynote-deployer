import Foundation

/// Per-frame multi-channel content signals over raw-RGB 32×18 grids (flat `[Double]`,
/// length `GridSampler.valueCount` = 1728, values `0.0...255.0`, row-major R,G,B per cell).
///
/// The core dark-fade-visibility fix lives here. A single mean-abs RGB diff goes to ~0
/// across a cross-fade between two DIFFERENT dark images, so dark-on-dark transitions are
/// invisible to a raw-RGB detector. Decomposing each frame into luma / saturation / chroma
/// and taking a normalized weighted diff makes that transition register.
///
/// Pure; consumed by AdaptiveThreshold (04), RestSelector (05), BoundaryDetector (06).
/// Do NOT normalize anywhere — the formulas and downstream thresholds assume 0–255.
enum FrameSignal {

    /// One frame decomposed into per-cell perceptual channels (each length 576):
    ///   luma   Y = 0.299R + 0.587G + 0.114B          (brightness)
    ///   sat    S = max(R,G,B) − min(R,G,B)            (saturation proxy — dark-fade signal)
    ///   chroma = 0.5·(|R−G| + |G−B|)                 (combined opponent magnitude; true
    ///            hue is unreliable at 32×18, so this summarizes both R−G and G−B opponents)
    static func channels(_ grid: [Double]) -> FrameChannels {
        let cells = grid.count / 3
        var luma = [Double](repeating: 0, count: cells)
        var sat = [Double](repeating: 0, count: cells)
        var chroma = [Double](repeating: 0, count: cells)
        var i = 0
        while i < cells {
            let s = i * 3
            let r = grid[s], g = grid[s + 1], b = grid[s + 2]
            luma[i] = 0.299 * r + 0.587 * g + 0.114 * b
            sat[i] = Swift.max(r, g, b) - Swift.min(r, g, b)
            chroma[i] = 0.5 * (abs(r - g) + abs(g - b))
            i += 1
        }
        return FrameChannels(luma: luma, sat: sat, chroma: chroma)
    }

    /// Consecutive-frame diff as a normalized weighted average of per-channel mean-abs
    /// deltas: `score = Σ(meanAbsDelta_c · w_c) / Σ|w_c|` (default weights 1,1,1).
    /// Returns one value per adjacent frame pair → the deck's diff signal.
    /// Length == frameGrids.count - 1 (empty if fewer than 2 frames).
    static func diffSignal(_ frameGrids: [[Double]], weights: ChannelWeights = .default) -> [Double] {
        guard frameGrids.count > 1 else { return [] }
        let wsum = abs(weights.luma) + abs(weights.sat) + abs(weights.chroma)
        guard wsum > 0 else { return Array(repeating: 0, count: frameGrids.count - 1) }
        var prev = channels(frameGrids[0])
        var out = [Double](); out.reserveCapacity(frameGrids.count - 1)
        for k in 1..<frameGrids.count {
            let cur = channels(frameGrids[k])
            let dl = meanAbs(prev.luma, cur.luma)
            let ds = meanAbs(prev.sat, cur.sat)
            let dc = meanAbs(prev.chroma, cur.chroma)
            out.append((dl * weights.luma + ds * weights.sat + dc * weights.chroma) / wsum)
            prev = cur
        }
        return out
    }

    /// Per-frame spatial variance of LUMA over the grid (monochrome / fade-dip signal):
    /// `mean((lumaCell − meanLuma)^2)`. ~0 for a flat/monochrome frame, high for high-contrast.
    static func frameVariance(_ grid: [Double]) -> Double {
        let luma = channels(grid).luma
        guard !luma.isEmpty else { return 0 }
        let mean = luma.reduce(0, +) / Double(luma.count)
        var acc = 0.0
        for v in luma { let d = v - mean; acc += d * d }
        return acc / Double(luma.count)
    }

    /// Mean absolute difference between two equal-length per-cell channel arrays.
    private static func meanAbs(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var s = 0.0
        for i in a.indices { s += abs(a[i] - b[i]) }
        return s / Double(a.count)
    }
}

/// Per-cell perceptual channels of one frame (each array is one value per grid cell).
struct FrameChannels: Sendable, Equatable {
    let luma: [Double]
    let sat: [Double]
    let chroma: [Double]
}

/// Relative weights for combining the per-channel deltas into the diff signal.
struct ChannelWeights: Sendable, Equatable {
    let luma: Double
    let sat: Double
    let chroma: Double
    /// Default — equal weight. Stays (1,1,1) unless harness evidence (section 08) shows
    /// a channel dominates wrongly.
    static let `default` = ChannelWeights(luma: 1, sat: 1, chroma: 1)
}
