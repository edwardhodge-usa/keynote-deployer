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
        // clip; they must be split at the midpoint of anchors 2 and 8 → mid=(2+8)/2=5.
        let grids = (0..<11).map { _ in grid(10) }
        let marks = HoldDetector.detect(frameGrids: grids, anchors: [2, 8], frameCount: 11, motionThreshold: 6.0)
        #expect(marks.count == 2)
        #expect(marks[0].holdEnd < marks[1].holdStart)
        // Pin the exact split: slide 0 ends at 5, slide 1 starts at 6.
        #expect(marks[0].holdEnd == 5 && marks[1].holdStart == 6)
        #expect(SlideMarkLogic.isValid(marks, frameCount: 11))
    }

    @Test("duplicate anchors collapse to a single slide and produce valid marks")
    func duplicateAnchors() {
        // [5, 5] deduplicates to [5]; the flat 10-frame clip expands to one span.
        let grids = (0..<10).map { _ in grid(10) }
        let marks = HoldDetector.detect(frameGrids: grids, anchors: [5, 5], frameCount: 10, motionThreshold: 6.0)
        // Dedup collapses [5,5] → [5] → exactly 1 SlideMark.
        #expect(marks.count == 1)
        #expect(SlideMarkLogic.isValid(marks, frameCount: 10))
    }

    @Test("over-packed anchors stay valid (drops unfittable spans)")
    func overPackedAnchorsStayValid() {
        // More anchors than available frames: 3 anchors [0, 1, 2], but only 2 frames.
        // The deduped anchors will compete for space; output must always be valid.
        let anchors = [0, 1, 2]
        let frameCount = 2
        let grids = [grid(10), grid(10)] // 2 flat grids
        let marks = HoldDetector.detect(frameGrids: grids, anchors: anchors, frameCount: frameCount, motionThreshold: 6.0)
        // The result may have fewer than 3 slides (impossible to fit all three without overlap),
        // but it MUST be valid.
        #expect(SlideMarkLogic.isValid(marks, frameCount: frameCount))
    }
}
