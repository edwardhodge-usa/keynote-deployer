import Testing
import Foundation
@testable import KeynoteDeployer

/// Section 06 — BoundaryDetector. Pure over hand-built diff signals + variances.
/// fps=10, minHoldSeconds=0.5 → minHoldFrames=5 throughout.
@Suite("Section 06 — BoundaryDetector")
struct BoundaryDetectorTests {

    private static let fps = 10.0
    private static func flatVar(_ n: Int) -> [Double] { Array(repeating: 100, count: n) }

    @Test("clean hard cut → exactly one .cut span at the cut")
    func hardCut() {
        var sig = [Double](repeating: 0.1, count: 10); sig.append(85); sig += Array(repeating: 0.1, count: 10)
        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: Self.flatVar(sig.count + 1), fps: Self.fps)
        #expect(spans.count == 1)
        #expect(spans.first?.kind == .cut)
        #expect(spans.first?.start == 10)
    }

    @Test("gradual cross-fade → exactly ONE .gradual span over the run (not zero, not split)")
    func gradualFade() {
        var sig = [Double](repeating: 0.1, count: 8); sig += Array(repeating: 1.8, count: 10); sig += Array(repeating: 0.1, count: 8)
        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: Self.flatVar(sig.count + 1), fps: Self.fps)
        #expect(spans.count == 1)
        #expect(spans.first?.kind == .gradual)
        #expect(spans.first?.start == 8)
        #expect((spans.first?.end ?? 0) >= 17)   // covers the fade plateau
    }

    @Test("a single sub-threshold dropout inside a gradual run does NOT split it")
    func gradualGrace() {
        var sig = [Double](repeating: 0.1, count: 4)
        sig += [1.8, 1.8, 1.8, 0.5, 1.8, 1.8, 1.8]   // one 0.5 dropout mid-run
        sig += Array(repeating: 0.1, count: 4)
        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: Self.flatVar(sig.count + 1), fps: Self.fps)
        #expect(spans.count == 1)                    // grace bridges the dropout
        #expect(spans.first?.kind == .gradual)
    }

    @Test("sustained low-variance run (≥ minHold) is a held black SLIDE, not a transition")
    func sustainedBlackIsHold() {
        let variances = Self.flatVar(5) + Array(repeating: 1.0, count: 8) + Self.flatVar(5)   // 18 frames
        let sig = [Double](repeating: 0.1, count: variances.count - 1)                        // benign diffs
        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: variances, fps: Self.fps)
        #expect(spans.isEmpty)
    }

    @Test("a SHORT variance dip (< minHold), flanked by content, IS a transition")
    func shortDipIsTransition() {
        let variances = Self.flatVar(5) + [1.0, 1.0] + Self.flatVar(5)   // dip length 2 < 5
        let sig = [Double](repeating: 0.1, count: variances.count - 1)
        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: variances, fps: Self.fps)
        #expect(spans.count == 1)
        #expect(spans.first?.kind == .gradual)
    }

    @Test("two cuts closer than minHold → only the first registers")
    func minHoldSuppressesSecond() {
        var sig = [Double](repeating: 0.1, count: 3); sig += [85, 0.1, 85]; sig += Array(repeating: 0.1, count: 3)
        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: Self.flatVar(sig.count + 1), fps: Self.fps)
        #expect(spans.count == 1)        // the second cut is within minHold of the first → dropped
        #expect(spans.first?.start == 3)
    }

    @Test("a variance dip BEFORE the diff fade merges into the full fade (no truncation)")
    func dipBeforeFadeMerges() {
        // Fade diffs at indices 8..17 → fade spans frames 8..18. A short monochrome dip at
        // frames 6,7 (BEFORE the diff onset). Merge must yield ONE span covering the FULL
        // fade, never truncate the boundary to the dip (which would land the next Rest mid-fade).
        var sig = [Double](repeating: 0.1, count: 8); sig += Array(repeating: 1.8, count: 10); sig += Array(repeating: 0.1, count: 8)
        var variances = Self.flatVar(sig.count + 1)
        variances[6] = 1.0; variances[7] = 1.0     // a short pre-fade dip
        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: variances, fps: Self.fps)
        #expect(spans.count == 1)
        #expect((spans.first?.end ?? 0) >= 18)     // covers the whole fade, not truncated to ~7
        #expect((spans.first?.start ?? 99) <= 8)
    }

    @Test("a smaller-magnitude cut beside larger cuts is still detected (mixed magnitude)")
    func mixedMagnitudeCuts() {
        // 30-cut next to two 85-cuts. P95 lands on 85 → deck-wide hard ≈ 42.5; gating cuts on
        // the LOCAL ratio (not hard) is what keeps the 30-cut from being dropped.
        var sig = [Double](repeating: 0.1, count: 5); sig.append(30)
        sig += Array(repeating: 0.1, count: 8); sig.append(85)
        sig += Array(repeating: 0.1, count: 8); sig.append(85)
        sig += Array(repeating: 0.1, count: 3)
        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: Self.flatVar(sig.count + 1), fps: Self.fps)
        #expect(spans.count == 3)
        #expect(spans.contains { $0.start == 5 })   // the small 30-cut survived
    }

    @Test("build-heavy intra-slide motion does not explode into transitions (count owned by §07)")
    func buildHeavyBounded() {
        let frames = SeedFixtures.buildHeavy()
        let sig = FrameSignal.diffSignal(frames)
        let variances = frames.map { FrameSignal.frameVariance($0) }
        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: variances, fps: Self.fps)
        // BoundaryDetector can't tell a build from a fade by pixels alone; it must not EXPLODE
        // into many spurious spans (min-hold bounds it). The final per-slide count is enforced
        // by HoldDetector (§07) using the anchor count, not here.
        #expect(spans.count <= 1)
    }
}
