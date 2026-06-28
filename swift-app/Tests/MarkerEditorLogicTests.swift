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

    // MARK: - insertionTime

    @Test("insertionTime returns midpoint between selected and next neighbor")
    func insertionTimeMidpointBetweenNeighbors() {
        let m = [0.0, 2.0, 6.0]
        // After index 0: midpoint of 0.0 and 2.0 = 1.0
        #expect(MarkerEditorLogic.insertionTime(after: 0, markers: m, duration: 10) == 1.0)
        // After index 1: midpoint of 2.0 and 6.0 = 4.0
        #expect(MarkerEditorLogic.insertionTime(after: 1, markers: m, duration: 10) == 4.0)
    }

    @Test("insertionTime returns midpoint toward duration for the last marker")
    func insertionTimeLastMarkerTowardDuration() {
        let m = [0.0, 2.0, 6.0]
        // After index 2 (last): midpoint of 6.0 and 10.0 = 8.0
        #expect(MarkerEditorLogic.insertionTime(after: 2, markers: m, duration: 10) == 8.0)
    }

    @Test("insertionTime result is strictly between its neighbors for a 3-marker array")
    func insertionTimeIsStrictlyBetween() {
        let m = [1.0, 3.0, 7.0]
        for i in m.indices {
            let t = MarkerEditorLogic.insertionTime(after: i, markers: m, duration: 10)
            // Must be strictly greater than markers[i]
            #expect(t > m[i])
            // Must be strictly less than the next neighbor (or duration)
            let upper = i < m.count - 1 ? m[i + 1] : 10.0
            #expect(t < upper)
        }
    }

    // MARK: - quantizeToFrames

    @Test("quantizeToFrames snaps to nearest frame on a 30fps grid")
    func quantizeSnapsToFrameGrid() {
        // At 30fps: frame duration = 1/30 ≈ 0.03333; nearest frame for 2.3471 is
        // round(2.3471 * 30) / 30 = round(70.413) / 30 = 70 / 30 ≈ 2.3333...
        let result = MarkerEditorLogic.quantizeToFrames([2.3471], fps: 30)
        let expected = (2.3471 * 30).rounded() / 30
        #expect(result[0] == expected)
    }

    @Test("quantizeToFrames makes collapsing inputs frame-distinct and strictly increasing")
    func quantizeCollapsingInputsBecomesMonotonic() {
        // Two markers only 0.001s apart at 30fps both round to the same frame.
        // The second should be bumped to the next frame.
        let m = [1.0, 1.001]   // difference < 1/30; both round to frame 30
        let result = MarkerEditorLogic.quantizeToFrames(m, fps: 30)
        #expect(result.count == 2)
        #expect(result[0] < result[1])
        #expect(MarkerEditorLogic.isMonotonic(result))
        // The second frame should be exactly one frame ahead of the first
        let oneFrame = 1.0 / 30.0
        #expect(result[1] - result[0] >= oneFrame - 1e-9)
    }

    @Test("quantizeToFrames returns input unchanged when fps <= 0")
    func quantizeFpsZeroOrNegativeReturnsUnchanged() {
        let m = [0.5, 1.5, 3.0]
        #expect(MarkerEditorLogic.quantizeToFrames(m, fps: 0) == m)
        #expect(MarkerEditorLogic.quantizeToFrames(m, fps: -1) == m)
    }
}
