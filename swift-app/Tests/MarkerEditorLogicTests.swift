import Testing
@testable import KeynoteDeployer

@Suite("MarkerEditorLogic")
struct MarkerEditorLogicTests {

    @Test("clamp keeps a marker strictly between its neighbors")
    func clampBetweenNeighbors() {
        let m = [0.0, 2.0, 4.0]
        // proposed above the upper neighbor → clamped just below it
        #expect(MarkerEditorLogic.clamp(5.0, index: 1, markers: m, duration: 10) == 4.0 - 0.001)
        // proposed below the lower neighbor → clamped just above it
        #expect(MarkerEditorLogic.clamp(-1.0, index: 1, markers: m, duration: 10) == 0.0 + 0.001)
        // proposed in range → unchanged
        #expect(MarkerEditorLogic.clamp(3.0, index: 1, markers: m, duration: 10) == 3.0)
    }

    @Test("clamp respects 0 and duration at the ends")
    func clampEnds() {
        let m = [1.0, 5.0]
        #expect(MarkerEditorLogic.clamp(-2.0, index: 0, markers: m, duration: 9) == 0.0)
        #expect(MarkerEditorLogic.clamp(99.0, index: 1, markers: m, duration: 9) == 9.0)
    }

    @Test("insert keeps the array sorted and returns the new index")
    func insertSorted() {
        let (m, idx) = MarkerEditorLogic.insert(3.0, into: [0.0, 2.0, 4.0])
        #expect(m == [0.0, 2.0, 3.0, 4.0])
        #expect(idx == 2)
        #expect(MarkerEditorLogic.isMonotonic(m))
    }

    @Test("remove deletes the marker and reselects in range")
    func removeReselects() {
        let (m, sel) = MarkerEditorLogic.remove(at: 2, from: [0.0, 2.0, 4.0])
        #expect(m == [0.0, 2.0])
        #expect(sel == 1)
    }

    @Test("remove is guarded at N==1 (a deck needs at least one slide)")
    func removeGuardedAtOne() {
        let (m, sel) = MarkerEditorLogic.remove(at: 0, from: [3.0])
        #expect(m == [3.0])
        #expect(sel == 0)
    }

    @Test("isMonotonic is false for equal or decreasing values")
    func monotonicDetectsViolations() {
        #expect(MarkerEditorLogic.isMonotonic([0.0, 1.0, 2.0]))
        #expect(!MarkerEditorLogic.isMonotonic([0.0, 1.0, 1.0]))
        #expect(!MarkerEditorLogic.isMonotonic([0.0, 3.0, 2.0]))
    }
}
