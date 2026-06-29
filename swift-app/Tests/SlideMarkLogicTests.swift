import Testing
@testable import KeynoteDeployer

@Suite("SlideMarkLogic")
struct SlideMarkLogicTests {
    // marks: slide0 hold [0,5], slide1 hold [10,15], slide2 hold [20,28]; frameCount 30
    private let marks = [SlideMark(holdStart: 0, holdEnd: 5),
                         SlideMark(holdStart: 10, holdEnd: 15),
                         SlideMark(holdStart: 20, holdEnd: 28)]

    @Test("clamp holdStart stays in [prev.holdEnd+1, own.holdEnd]")
    func clampStart() {
        // slide1 holdStart can't go below prev.holdEnd+1 (6) or above own holdEnd (15)
        #expect(SlideMarkLogic.clamp(3, ref: MarkerRef(slide: 1, edge: .start), marks: marks, frameCount: 30) == 6)
        #expect(SlideMarkLogic.clamp(99, ref: MarkerRef(slide: 1, edge: .start), marks: marks, frameCount: 30) == 15)
        #expect(SlideMarkLogic.clamp(12, ref: MarkerRef(slide: 1, edge: .start), marks: marks, frameCount: 30) == 12)
    }

    @Test("clamp holdEnd stays in [own.holdStart, next.holdStart-1]")
    func clampEnd() {
        // slide1 holdEnd can't drop below own holdStart (10) or reach next holdStart (20) → max 19
        #expect(SlideMarkLogic.clamp(5, ref: MarkerRef(slide: 1, edge: .end), marks: marks, frameCount: 30) == 10)
        #expect(SlideMarkLogic.clamp(99, ref: MarkerRef(slide: 1, edge: .end), marks: marks, frameCount: 30) == 19)
    }

    @Test("clamp first holdStart floors at 0, last holdEnd ceils at frameCount-1")
    func clampEnds() {
        #expect(SlideMarkLogic.clamp(-4, ref: MarkerRef(slide: 0, edge: .start), marks: marks, frameCount: 30) == 0)
        #expect(SlideMarkLogic.clamp(99, ref: MarkerRef(slide: 2, edge: .end), marks: marks, frameCount: 30) == 29)
    }

    @Test("split divides the hold containing a frame into two slides")
    func split() {
        let out = SlideMarkLogic.split(at: 12, marks: marks)
        // slide1 [10,15] → [10,12] and [13,15]; count grows by 1
        #expect(out.count == 4)
        #expect(out[1] == SlideMark(holdStart: 10, holdEnd: 12))
        #expect(out[2] == SlideMark(holdStart: 13, holdEnd: 15))
        #expect(SlideMarkLogic.isValid(out, frameCount: 30))
    }

    @Test("merge joins slide i with i+1 into one hold span")
    func merge() {
        let out = SlideMarkLogic.merge(slide: 1, marks: marks)
        // slide1 [10,15] + slide2 [20,28] → [10,28]
        #expect(out.count == 2)
        #expect(out[1] == SlideMark(holdStart: 10, holdEnd: 28))
    }

    @Test("merge guarded at count 1")
    func mergeGuard() {
        let one = [SlideMark(holdStart: 0, holdEnd: 5)]
        #expect(SlideMarkLogic.merge(slide: 0, marks: one) == one)
    }

    @Test("isValid catches overlap and disorder")
    func validity() {
        #expect(SlideMarkLogic.isValid(marks, frameCount: 30))
        #expect(!SlideMarkLogic.isValid([SlideMark(holdStart: 0, holdEnd: 12), SlideMark(holdStart: 10, holdEnd: 15)], frameCount: 30)) // overlap
        #expect(!SlideMarkLogic.isValid([SlideMark(holdStart: 5, holdEnd: 3)], frameCount: 30)) // holdEnd<holdStart
        #expect(!SlideMarkLogic.isValid([SlideMark(holdStart: 0, holdEnd: 30)], frameCount: 30)) // holdEnd>=frameCount
    }
}
