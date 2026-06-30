import Testing
@testable import KeynoteDeployer

@Suite("HoldDetector")
struct HoldDetectorTests {
    // Flat "color" grids; a transition is a value ramp. diff between consecutive = |Δ|.
    private func grid(_ v: Double) -> [Double] { [Double](repeating: v, count: 32 * 18 * 3) }

    @Test("Rest = the anchor; Go = forward motion onset")
    func restIsAnchorGoIsMotionOnset() {
        // flat 0..3 (10), motion at 4 (50), flat 7..9 (10). anchors at settled 0 and 8.
        let grids = [grid(10), grid(10), grid(10), grid(10), grid(50), grid(50), grid(50), grid(10), grid(10), grid(10)]
        let marks = HoldDetector.detect(frameGrids: grids, anchors: [0, 8], frameCount: grids.count, motionThreshold: 6.0)
        #expect(marks.count == 2)
        // slide 0: Rest=anchor 0; forward stops where motion begins (3→4 jump) → Go=3
        #expect(marks[0].holdStart == 0 && marks[0].holdEnd == 3)
        // slide 1: Rest=anchor 8 (NOT expanded backward into the prior motion)
        #expect(marks[1].holdStart == 8)
        #expect(marks[0].holdEnd < marks[1].holdStart)   // a real transition gap exists
        #expect(SlideMarkLogic.isValid(marks, frameCount: grids.count))
    }

    @Test("fade (no detectable motion) falls back to a default transition band")
    func fadeUsesDefaultTransition() {
        // entirely flat 40-frame clip (a fade reads as no motion), anchors 0 and 30.
        let grids = (0..<40).map { _ in grid(10) }
        let marks = HoldDetector.detect(frameGrids: grids, anchors: [0, 30], frameCount: 40,
                                        motionThreshold: 6.0, defaultTransition: 15)
        #expect(marks.count == 2)
        // Rest stays on the anchors; slide 0 gets a default green band before slide 1.
        #expect(marks[0].holdStart == 0)
        #expect(marks[0].holdEnd == 14)            // lastBefore(29) − default(15)
        #expect(marks[1].holdStart == 30)          // next Rest = its anchor, never mid-fade
        #expect(marks[1].holdEnd < 40)
        #expect(SlideMarkLogic.isValid(marks, frameCount: 40))
    }

    @Test("anchor with motion immediately after collapses to a zero-length hold")
    func degenerate() {
        let grids = [grid(0), grid(50), grid(0)]   // anchor 1 has motion on both sides
        let marks = HoldDetector.detect(frameGrids: grids, anchors: [1], frameCount: 3, motionThreshold: 6.0)
        #expect(marks == [SlideMark(holdStart: 1, holdEnd: 1)])
    }

    @Test("duplicate anchors collapse to a single slide and stay valid")
    func duplicateAnchors() {
        let grids = (0..<10).map { _ in grid(10) }
        let marks = HoldDetector.detect(frameGrids: grids, anchors: [5, 5], frameCount: 10, motionThreshold: 6.0)
        #expect(marks.count == 1)
        #expect(marks[0].holdStart == 5)
        #expect(SlideMarkLogic.isValid(marks, frameCount: 10))
    }

    @Test("over-packed anchors stay valid (drops unfittable spans)")
    func overPackedAnchorsStayValid() {
        let marks = HoldDetector.detect(frameGrids: [grid(10), grid(10)], anchors: [0, 1, 2],
                                        frameCount: 2, motionThreshold: 6.0)
        #expect(SlideMarkLogic.isValid(marks, frameCount: 2))
    }
}
