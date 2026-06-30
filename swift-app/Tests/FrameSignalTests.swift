import Testing
import Foundation
@testable import KeynoteDeployer

/// Section 03 — FrameSignal. Pure over raw-RGB 1728-value grids; synthetic grids inline.
@Suite("Section 03 — FrameSignal")
struct FrameSignalTests {

    private static func solid(_ r: Double, _ g: Double, _ b: Double) -> [Double] {
        var grid = [Double](); grid.reserveCapacity(GridSampler.valueCount)
        for _ in 0..<(GridSampler.width * GridSampler.height) { grid += [r, g, b] }
        return grid
    }

    /// Raw-RGB mean-abs diff (the OLD detector's metric) for baseline comparison.
    private static func rawMeanAbs(_ a: [Double], _ b: [Double]) -> Double {
        var s = 0.0; for i in a.indices { s += abs(a[i] - b[i]) }; return s / Double(a.count)
    }

    @Test("channels on a solid grid match the hand-computed formulas")
    func channelsSolid() {
        let ch = FrameSignal.channels(Self.solid(200, 0, 0))
        #expect(ch.luma.count == GridSampler.width * GridSampler.height)
        // luma = 0.299*200 = 59.8 ; sat = 200-0 = 200 ; chroma = 0.5*(|200-0|+|0-0|) = 100
        #expect(abs(ch.luma[0] - 59.8) < 1e-6)
        #expect(abs(ch.sat[0] - 200) < 1e-6)
        #expect(abs(ch.chroma[0] - 100) < 1e-6)
        // A grey grid: luma == value, sat == 0, chroma == 0.
        let grey = FrameSignal.channels(Self.solid(120, 120, 120))
        #expect(abs(grey.luma[0] - 120) < 1e-6)
        #expect(grey.sat[0] == 0 && grey.chroma[0] == 0)
    }

    @Test("diffSignal is ~0 for identical frames, large for black↔white")
    func diffMagnitudes() {
        let black = Self.solid(0, 0, 0), white = Self.solid(255, 255, 255)
        #expect(FrameSignal.diffSignal([black, black]) == [0])
        let bw = FrameSignal.diffSignal([black, white])[0]
        #expect(bw > 50)   // luma swings the full range
    }

    @Test("diffSignal REGISTERS a dark-fade step but only as a small absolute value")
    func darkFadeRegistersSmall() {
        // The real failure case: a slow cross-fade on dark colors. Each step is a
        // genuine transition, but its ABSOLUTE diff is tiny — which is exactly why a
        // fixed absolute threshold misses it and adaptive thresholding (§04) is needed.
        let frames = SeedFixtures.crossFadeOnDark(holdLen: 4, fadeLen: 10)
        let sig = FrameSignal.diffSignal(frames)
        let staticPair = sig.prefix(3).max() ?? 0          // diffs within the held region ≈ 0
        let fadeStep = sig.max() ?? 0                       // the largest fade-step diff
        #expect(fadeStep > 0)                               // it DOES register the fade
        #expect(fadeStep > staticPair)                      // fade > static hold
        // Same fade vs a hard black→white cut: the fade step is far smaller in absolute terms.
        let bw = FrameSignal.diffSignal([Self.solid(0, 0, 0), Self.solid(255, 255, 255)])[0]
        #expect(fadeStep < bw / 5)
    }

    @Test("frameVariance ~0 for monochrome, high for high-contrast")
    func variance() {
        #expect(FrameSignal.frameVariance(Self.solid(40, 40, 40)) < 1e-6)
        // Half black, half white cells → high luma variance.
        var grid = [Double]()
        let cells = GridSampler.width * GridSampler.height
        for c in 0..<cells { let v: Double = c < cells / 2 ? 0 : 255; grid += [v, v, v] }
        #expect(FrameSignal.frameVariance(grid) > 1000)
    }

    @Test("diffSignal length == frameGrids.count - 1; empty/single sane")
    func diffLength() {
        let f = [Self.solid(0, 0, 0), Self.solid(10, 10, 10), Self.solid(20, 20, 20)]
        #expect(FrameSignal.diffSignal(f).count == 2)
        #expect(FrameSignal.diffSignal([]).isEmpty)
        #expect(FrameSignal.diffSignal([Self.solid(0, 0, 0)]).isEmpty)
    }
}
