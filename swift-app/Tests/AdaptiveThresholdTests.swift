import Testing
import Foundation
@testable import KeynoteDeployer

/// Section 04 — AdaptiveThreshold. Pure; hand-built `[Double]` signals inline.
/// CRITICAL: includes signals in the 1.5–2.0 dark-fade danger band — the magnitudes
/// the whole feature exists to handle (and that the first cut of this module missed).
@Suite("Section 04 — AdaptiveThreshold")
struct AdaptiveThresholdTests {

    @Test("dualThreshold: gradual < hard, both finite, on a static-dominated signal")
    func dualThresholdStaticDominated() {
        var sig = [Double](repeating: 0.1, count: 40)
        sig += [50, 60, 55]
        let (hard, gradual) = AdaptiveThreshold.dualThreshold(sig)
        #expect(gradual < hard)
        #expect(hard >= AdaptiveThreshold.hardFloor)
        #expect(gradual >= AdaptiveThreshold.gradualFloor)
        #expect(hard > 5)              // not dragged to ~0 by the flat tail
        #expect(0.1 < gradual)         // static noise sits below gradual
    }

    /// THE target case: a dark cross-fade plateau at ~1.8 between static ~0.1 regions.
    /// The detection requirement is `gradual < fadeStep` so each fade frame ENTERS the
    /// gradual band, where §06's twin-comparison accumulates the run. On a fade-only deck
    /// the fade IS the largest diff, so `hard` (≈ 0.5·P95 of the fade) sits BELOW a single
    /// fade frame — that is fine: a lone fade frame still isn't a hard cut (its local ratio
    /// is ~1, not ≥3), and the sustained run is what accumulates. The old implementation
    /// (noiseFloor 2.0, gradual 0.8) FAILED the band-entry requirement — fade 1.8 fell into
    /// the noise band. What matters: gradual separates fade from static.
    @Test("dualThreshold puts a dark-fade step (~1.8) above gradual and gradual above static")
    func dualThresholdDarkFadeBand() {
        var sig = [Double](repeating: 0.1, count: 30)   // static holds
        sig += [Double](repeating: 1.8, count: 10)      // a sustained dark-fade plateau
        let (hard, gradual) = AdaptiveThreshold.dualThreshold(sig)
        #expect(gradual < 1.8)         // a fade frame enters the gradual band
        #expect(gradual > 0.1)         // ...and static noise stays below gradual
        #expect(gradual < hard)        // invariant always holds
    }

    @Test("dualThreshold: a clean-cut deck (sparse 85-spikes) keeps cuts above hard")
    func dualThresholdCleanCut() {
        var sig = [Double](repeating: 0.1, count: 22)
        sig += [85, 85]
        let (hard, gradual) = AdaptiveThreshold.dualThreshold(sig)
        #expect(85 > hard)             // a real cut clears the hard threshold
        #expect(0.1 < gradual)         // static below gradual
    }

    @Test("dualThreshold: degenerate inputs never NaN/Inf and keep gradual < hard")
    func dualThresholdDegenerate() {
        for sig in [[Double](), [5.0], [Double](repeating: 7, count: 10)] {
            let (hard, gradual) = AdaptiveThreshold.dualThreshold(sig)
            #expect(hard.isFinite && gradual.isFinite)
            #expect(gradual < hard)
            #expect(hard >= AdaptiveThreshold.hardFloor)
        }
    }

    @Test("localRatios peak at an injected cut, stay ~1 on a uniform ramp")
    func localRatiosSpikeVsRamp() {
        var spike = [Double](repeating: 0.1, count: 21)
        spike[10] = 40
        let rs = AdaptiveThreshold.localRatios(spike, window: 2)
        #expect(rs[10] >= 3)
        #expect(rs[0] < 3 && rs[20] < 3)

        let ramp = (0..<30).map { Double($0) * 3 + 10 }
        let rr = AdaptiveThreshold.localRatios(ramp, window: 2)
        #expect(rr[5..<25].allSatisfy { $0 < 2.0 })
    }

    @Test("a sparse-cut edge over a near-zero baseline still produces a large ratio")
    func localRatiosCutEdgeOverDarkBaseline() {
        // Even on a dark deck (baseline ~0.1), a hard cut edge must register because the
        // denominator floor (0.3) is at the noise level, not the fade level.
        var sig = [Double](repeating: 0.1, count: 20)
        sig[10] = 5.0                  // a modest cut on a dark deck
        let rs = AdaptiveThreshold.localRatios(sig, window: 2)
        #expect(rs[10] >= 3)
    }

    @Test("window is fps-relative and rounds (NTSC-safe)")
    func windowFpsRelative() {
        #expect(AdaptiveThreshold.window(forFps: 30) == 2)
        #expect(AdaptiveThreshold.window(forFps: 60) == 4)
        #expect(AdaptiveThreshold.window(forFps: 59.94) == 4)   // rounds, not truncates
        #expect(AdaptiveThreshold.window(forFps: 24) < AdaptiveThreshold.window(forFps: 60))
    }

    @Test("noise floor prevents amplification on a dead-still region")
    func noiseFloorGuard() {
        let noise = (0..<25).map { _ in Double.random(in: 0...0.2) }
        let rs = AdaptiveThreshold.localRatios(noise, window: 2)
        // Floored denominator (0.3) keeps noise ratios well below the cut level (~3).
        #expect(rs.allSatisfy { $0 < 2.0 })
    }
}
