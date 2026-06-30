import Testing
import Foundation
@testable import KeynoteDeployer

/// Section 05 — RestSelector. Pure; synthetic grids + their real diffSignal inline.
@Suite("Section 05 — RestSelector")
struct RestSelectorTests {

    private static func solid(_ v: Double) -> [Double] {
        var g = [Double](); g.reserveCapacity(GridSampler.valueCount)
        for _ in 0..<(GridSampler.width * GridSampler.height) { g += [v, v, v] }
        return g
    }

    /// A high-contrast (sharp) grid: half the cells black, half white → high VoL.
    private static func sharp() -> [Double] {
        var g = [Double](); let cells = GridSampler.width * GridSampler.height
        for c in 0..<cells { let v: Double = (c % 2 == 0) ? 0 : 255; g += [v, v, v] }
        return g
    }

    @Test("picks a calm interior frame, not a moving edge")
    func picksCalmInterior() {
        // Moving edges, a calm middle run (frames 2,3,4 identical).
        let f = [Self.solid(0), Self.solid(50), Self.solid(100), Self.solid(100), Self.solid(100), Self.solid(50), Self.solid(0)]
        let sig = FrameSignal.diffSignal(f)
        let rest = RestSelector.restFrame(in: 0..<7, diffSignal: sig, frameGrids: f)
        #expect(rest >= 2 && rest <= 4)   // interior calm run
        #expect(rest != 0 && rest != 6)   // not an edge
    }

    @Test("sharper frame wins the calm tie")
    func sharperWinsTie() {
        // Two equally-calm runs: a SHARP run (f0..f2) and a FLAT run (f4..f6),
        // separated by a transition at f3. f1 and f5 are both perfectly calm (diff 0);
        // the sharper (f1) must win.
        let s = Self.sharp(), flat = Self.solid(120)
        let f = [s, s, s, Self.solid(255), flat, flat, flat]
        let sig = FrameSignal.diffSignal(f)
        let rest = RestSelector.restFrame(in: 0..<7, diffSignal: sig, frameGrids: f)
        #expect(rest == 1)   // the sharp calm frame, not the flat calm frame (5)
    }

    @Test("margin keeps the choice off the edges when interior frames exist")
    func marginRespected() {
        // All frames identical → all equally calm; margin must still exclude the edges.
        let f = Array(repeating: Self.solid(80), count: 5)
        let sig = FrameSignal.diffSignal(f)
        let rest = RestSelector.restFrame(in: 0..<5, diffSignal: sig, frameGrids: f, margin: 1)
        #expect(rest >= 1 && rest <= 3)
    }

    @Test("degenerate short hold returns a valid in-range frame, no crash")
    func degenerateShortHold() {
        let f = [Self.solid(0), Self.solid(0)]
        let sig = FrameSignal.diffSignal(f)
        let rest = RestSelector.restFrame(in: 0..<1, diffSignal: sig, frameGrids: f)
        #expect(rest == 0)
        // Empty grids → safe 0, no crash.
        #expect(RestSelector.restFrame(in: 0..<3, diffSignal: [], frameGrids: []) == 0)
    }
}
