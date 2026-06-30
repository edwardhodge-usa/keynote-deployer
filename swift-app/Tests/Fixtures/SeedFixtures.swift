import Foundation
@testable import KeynoteDeployer

/// Synthetic frame-grid sequences for the seed-detection suites (sections 03–08).
/// Grids are full 1728-value raw-RGB (`GridSampler.valueCount`) so they exercise the
/// real signal math. These are the OFFLINE fixtures; the CAPTURED real-fade-deck grids
/// (the accuracy oracle) come from running `kd-seed-harness` on the real deck and are
/// added in the section-08 validation pass.
///
/// Three archetypes mirror the decks the algorithm must not over-fit to:
///   - clean-cut: hard cuts between solid slides (one big diff spike per boundary).
///   - cross-fade-on-dark: linear cross-fade between two DIFFERENT dark images — every
///     per-frame RGB diff is tiny (the case that broke; raw mean-abs stays under threshold).
///   - build-heavy: a held slide with small incremental intra-slide motion (no real cut).
enum SeedFixtures {

    /// A uniform grid of one RGB triple, length `GridSampler.valueCount`.
    static func solid(_ r: Double, _ g: Double, _ b: Double) -> [Double] {
        var grid = [Double](); grid.reserveCapacity(GridSampler.valueCount)
        for _ in 0..<(GridSampler.width * GridSampler.height) { grid += [r, g, b] }
        return grid
    }

    /// Linear blend of two grids: `(1-t)·a + t·b`, t in 0...1.
    static func blend(_ a: [Double], _ b: [Double], _ t: Double) -> [Double] {
        zip(a, b).map { (1 - t) * $0 + t * $1 }
    }

    /// Clean-cut deck: `holdLen` frames of slide A, a hard cut, `holdLen` of slide B,
    /// hard cut, `holdLen` of slide C. Returns (frames, expectedSlideAnchorsApprox).
    static func cleanCut(holdLen: Int = 8) -> [[Double]] {
        let a = solid(20, 20, 20), b = solid(200, 60, 60), c = solid(60, 200, 60)
        return Array(repeating: a, count: holdLen)
            + Array(repeating: b, count: holdLen)
            + Array(repeating: c, count: holdLen)
    }

    /// Cross-fade-on-dark deck: hold dark-blue, linear cross-fade to dark-red over
    /// `fadeLen` frames, hold dark-red. Every consecutive diff is TINY (the dark-fade
    /// case): per-frame change ≈ (color delta)/fadeLen on near-black colors.
    static func crossFadeOnDark(holdLen: Int = 8, fadeLen: Int = 10) -> [[Double]] {
        let darkBlue = solid(6, 8, 34), darkRed = solid(34, 8, 6)
        var frames = Array(repeating: darkBlue, count: holdLen)
        for k in 1...fadeLen { frames.append(blend(darkBlue, darkRed, Double(k) / Double(fadeLen))) }
        frames += Array(repeating: darkRed, count: holdLen)
        return frames
    }

    /// Build-heavy deck: one slide held while a small region brightens incrementally
    /// (a bullet appearing) — intra-slide motion that must NOT register as a new slide.
    static func buildHeavy(holdLen: Int = 6, steps: Int = 5) -> [[Double]] {
        let base = solid(30, 30, 40)
        var frames = Array(repeating: base, count: holdLen)
        for s in 1...steps {
            var g = base
            // brighten the first ~10% of cells a little per step (a small on-slide build).
            let cells = max(1, (GridSampler.width * GridSampler.height) / 10)
            for cell in 0..<cells {
                let d = cell * 3
                let bump = Double(s) * 6
                g[d] = min(255, g[d] + bump); g[d + 1] = min(255, g[d + 1] + bump); g[d + 2] = min(255, g[d + 2] + bump)
            }
            frames.append(g)
        }
        frames += Array(repeating: frames.last!, count: holdLen)
        return frames
    }
}
