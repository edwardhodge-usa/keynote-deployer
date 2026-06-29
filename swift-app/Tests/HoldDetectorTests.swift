import Testing
@testable import KeynoteDeployer

@Suite("HoldDetector")
struct HoldDetectorTests {
    // Build a frame sequence: frames are flat "color" grids; a transition is a ramp.
    // grid value g repeated 1728× → diff between consecutive = |g1-g0| per component.
    private func grid(_ v: Double) -> [Double] { [Double](repeating: v, count: 32 * 18 * 3) }

    @Test("detects a low-motion hold around an anchor, bounded by motion ramps")
    func detectsHold() {
        // frames 0..2 = value 10 (hold A), 3..5 = ramp 40/70/100 (transition),
        // 6..9 = value 100 (hold B). anchors at the settled frames 1 and 8.
        let grids = [grid(10), grid(10), grid(10), grid(40), grid(70), grid(100), grid(100), grid(100), grid(100), grid(100)]
        let marks = HoldDetector.detect(frameGrids: grids, anchors: [1, 8], frameCount: grids.count, motionThreshold: 6.0)
        #expect(marks.count == 2)
        // hold A is the flat 0..2 run; hold B is the flat 5..9 run (100s)
        #expect(marks[0].holdStart == 0 && marks[0].holdEnd == 2)
        #expect(marks[1].holdStart == 5 && marks[1].holdEnd == 9)
        #expect(SlideMarkLogic.isValid(marks, frameCount: grids.count))
    }

    @Test("degenerate: an anchor with motion on both sides collapses to itself")
    func degenerate() {
        let grids = [grid(0), grid(50), grid(0)] // anchor 1 is a spike — no flat run
        let marks = HoldDetector.detect(frameGrids: grids, anchors: [1], frameCount: 3, motionThreshold: 6.0)
        #expect(marks == [SlideMark(holdStart: 1, holdEnd: 1)])
    }

    @Test("colliding runs are cut at the anchor midpoint")
    func collisionCut() {
        // entire clip is flat (no motion) with two anchors → both runs want the whole
        // clip; they must be split at the midpoint of anchors 2 and 8 → 5.
        let grids = (0..<11).map { _ in grid(10) }
        let marks = HoldDetector.detect(frameGrids: grids, anchors: [2, 8], frameCount: 11, motionThreshold: 6.0)
        #expect(marks.count == 2)
        #expect(marks[0].holdEnd < marks[1].holdStart)
        #expect(SlideMarkLogic.isValid(marks, frameCount: 11))
    }
}
