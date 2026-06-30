import Testing
import Foundation
@testable import KeynoteDeployer

/// Section 07 — HoldDetector rewrite. The detector now orchestrates FrameSignal →
/// BoundaryDetector → RestSelector. Contract: ONE mark per anchor (never a silent
/// dedup-drop), explicit first/last boundaries, valid strictly-increasing spans.
/// Small synthetic decks; fps=10 so min-hold (=5 frames) fits the short fixtures.
@Suite("Section 07 — HoldDetector")
struct HoldDetectorTests {

    private static let fps = 10.0

    /// Spans the detector would see, for cross-checking Rest placement.
    private static func spans(_ frames: [[Double]]) -> [TransitionSpan] {
        let sig = FrameSignal.diffSignal(frames)
        let vars = frames.map { FrameSignal.frameVariance($0) }
        return BoundaryDetector.transitions(diffSignal: sig, variances: vars, fps: fps)
    }

    @Test("one mark per slide — colliding anchors are NOT collapsed (no dedup-drop)")
    func oneMarkPerSlideNoDrop() {
        let frames = SeedFixtures.cleanCut()                 // 24 frames, 3 slides
        // Two anchors in the SAME first hold (no boundary between them).
        let d = HoldDetector.detectDetailed(frameGrids: frames, anchors: [3, 5], frameCount: frames.count, fps: Self.fps)
        #expect(d.marks.count == 2)                          // both kept (old code collapsed to 1)
        #expect(d.collidedWithPrevious.contains(true))       // the shared-hold split is flagged
        #expect(SlideMarkLogic.isValid(d.marks, frameCount: frames.count))
    }

    @Test("tail-clustered / duplicate anchors preserve count when frames allow (no drop)")
    func clusteredAnchorsPreserveCount() {
        let frames = SeedFixtures.cleanCut()                 // 24 frames
        // Duplicate + adjacent anchors near the END — room-reserving normalization must still
        // yield 3 valid marks (the old code would silently drop the unfittable tail).
        let d = HoldDetector.detectDetailed(frameGrids: frames, anchors: [21, 21, 22], frameCount: frames.count, fps: Self.fps)
        #expect(d.marks.count == 3)
        #expect(SlideMarkLogic.isValid(d.marks, frameCount: frames.count))
    }

    @Test("marks are valid + strictly increasing on a clean 3-slide deck")
    func validStrictlyIncreasing() {
        let frames = SeedFixtures.cleanCut()
        let marks = HoldDetector.detect(frameGrids: frames, anchors: [4, 12, 20], frameCount: frames.count, fps: Self.fps)
        #expect(marks.count == 3)
        #expect(SlideMarkLogic.isValid(marks, frameCount: frames.count))
    }

    @Test("edge boundaries: first holdStart before the first cut, last holdEnd == frameCount-1")
    func edgeBoundaries() {
        let frames = SeedFixtures.cleanCut()                 // cuts at frames 7→8 and 15→16
        let marks = HoldDetector.detect(frameGrids: frames, anchors: [4, 12, 20], frameCount: frames.count, fps: Self.fps)
        #expect(marks.first!.holdStart >= 0 && marks.first!.holdStart <= 7)
        #expect(marks.last!.holdEnd == frames.count - 1)
    }

    @Test("Go (holdEnd) for an interior slide lands on the detected outgoing cut")
    func goLandsOnCut() {
        let frames = SeedFixtures.cleanCut()                 // first cut diff index 7 → span (7,8)
        let marks = HoldDetector.detect(frameGrids: frames, anchors: [4, 12, 20], frameCount: frames.count, fps: Self.fps)
        #expect(marks[0].holdEnd == 7)                       // outgoing transition start
    }

    @Test("Rest never lands inside a transition span (the original mid-fade bug)")
    func restNotInsideTransition() {
        let frames = SeedFixtures.crossFadeOnDark()          // a dark cross-fade
        let sp = Self.spans(frames)
        let marks = HoldDetector.detect(frameGrids: frames, anchors: [1, 16], frameCount: frames.count, fps: Self.fps)
        for m in marks {
            for s in sp {
                #expect(!(s.start < m.holdStart && m.holdStart < s.end))   // not strictly inside a transition
            }
        }
    }

    @Test("an anchor inside a transition span is flagged low-confidence")
    func lowConfidenceFlag() {
        let frames = SeedFixtures.crossFadeOnDark()          // fade roughly frames 4..14
        let d = HoldDetector.detectDetailed(frameGrids: frames, anchors: [1, 8, 16], frameCount: frames.count, fps: Self.fps)
        #expect(d.marks.count == 3)
        #expect(d.lowConfidenceMatch.contains(true))
    }

    @Test("degenerate / empty inputs are safe")
    func degenerate() {
        let frames = SeedFixtures.cleanCut()
        #expect(HoldDetector.detect(frameGrids: frames, anchors: [], frameCount: frames.count, fps: Self.fps).isEmpty)
        #expect(HoldDetector.detect(frameGrids: [], anchors: [0], frameCount: 0, fps: Self.fps).isEmpty)
        let tiny = [SeedFixtures.solid(0, 0, 0), SeedFixtures.solid(0, 0, 0)]
        let m = HoldDetector.detect(frameGrids: tiny, anchors: [0], frameCount: 2, fps: Self.fps)
        #expect(m.count == 1)
        #expect(SlideMarkLogic.isValid(m, frameCount: 2))
    }
}
