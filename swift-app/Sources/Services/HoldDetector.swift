import Foundation

/// One slide's seed plus the diagnostic flags the harness (section 01) surfaces.
struct HoldDetection: Sendable, Equatable {
    /// One mark per slide. Count is PRESERVED whenever the frames allow (anchors.count ≤
    /// frameCount) — even for duplicate / tightly-clustered anchors; a slide is dropped only
    /// in the genuinely over-packed case (more distinct anchors than frames).
    let marks: [SlideMark]
    /// Parallel to `marks`: this slide shared a hold with no detected boundary to its
    /// neighbour (a deterministic midpoint split was used).
    let collidedWithPrevious: [Bool]
    /// Parallel to `marks`: the anchor fell INSIDE a detected transition (a wildly-wrong
    /// StillsMatch anchor) — a signal that StillsMatch, not the detector, is the suspect.
    let lowConfidenceMatch: [Bool]
}

/// Seeds per-slide Rest/Go marks by orchestrating the adaptive detection layers:
/// `FrameSignal` (multi-channel diff + variance) → `BoundaryDetector` (transition spans) →
/// `RestSelector` (settled+sharp Rest within each hold).
///
/// The stills/anchor count is the slide-count AUTHORITY: this emits exactly ONE mark per
/// anchor and never silently drops a slide (the old dedup + overlap-drop did). Anchors tell
/// WHICH slide; the detected spans tell WHERE the boundaries are. Pure over `[[Double]]`
/// grids; same `detect(...) → [SlideMark]` entry shape so `VideoTimestampDeriver` and the
/// timeline editor are unchanged.
enum HoldDetector {

    /// Primary entry (unchanged shape; `fps` added with a default for source compatibility).
    static func detect(frameGrids: [[Double]],
                       anchors: [Int],
                       frameCount: Int,
                       fps: Double = 30) -> [SlideMark] {
        detectDetailed(frameGrids: frameGrids, anchors: anchors, frameCount: frameCount, fps: fps).marks
    }

    /// Detailed entry — marks + the per-slide diagnostic flags the harness reads.
    static func detectDetailed(frameGrids: [[Double]],
                               anchors: [Int],
                               frameCount: Int,
                               fps: Double = 30) -> HoldDetection {
        guard !anchors.isEmpty, frameCount > 0 else {
            return HoldDetection(marks: [], collidedWithPrevious: [], lowConfidenceMatch: [])
        }
        let bound = Swift.min(frameCount, frameGrids.count)
        guard bound > 0 else {
            return HoldDetection(marks: [], collidedWithPrevious: [], lowConfidenceMatch: [])
        }

        // Sort but DO NOT dedup (dedup was the count-loss bug); clamp into the frame range.
        let sortedAnchors = anchors.sorted().map { Swift.max(0, Swift.min($0, bound - 1)) }
        let n = sortedAnchors.count

        // Signal + boundary layers — built over the SAME `bound` horizon as the clamps, so a
        // frameCount < frameGrids.count caller can't desync diff/variance lengths or let a span
        // reference a frame ≥ bound.
        let grids = Array(frameGrids[0..<bound])
        let diffSignal = FrameSignal.diffSignal(grids)
        let variances = grids.map { FrameSignal.frameVariance($0) }
        let spans = BoundaryDetector.transitions(diffSignal: diffSignal, variances: variances, fps: fps)
        // Distance (frames) beyond which an anchor is "far" from its assigned hold → a
        // wildly-wrong StillsMatch anchor (a StillsMatch suspect, not a detector fault).
        let farThreshold = Int(1.5 * fps)

        // Assign exactly one (Rest, Go) per anchor.
        var rawStart = [Int](), rawEnd = [Int]()
        var collided = [Bool](repeating: false, count: n)
        var lowConf = [Bool](repeating: false, count: n)
        var holdLo = 0   // the earliest frame this slide's hold may begin (after the prev transition)

        for i in 0..<n {
            let a = sortedAnchors[i]
            let nextAnchor = i < n - 1 ? sortedAnchors[i + 1] : bound

            // Outgoing transition = the LAST span starting in [a, nextAnchor) — the boundary
            // nearest the NEXT slide, so an earlier within-slide build doesn't cut Go short.
            let goSpan = spans.last { $0.start >= a && $0.start < nextAnchor }

            var holdEnd: Int
            var nextHoldStart: Int
            if i == n - 1 {
                holdEnd = bound - 1          // last slide extends to video end (no following transition)
                nextHoldStart = bound
            } else if let s = goSpan {
                holdEnd = s.start
                nextHoldStart = s.end
            } else {
                // No detected boundary between this anchor and the next: two anchors share a hold
                // (or an undetected boundary). Split deterministically at the midpoint; flag it.
                let mid = (a + nextAnchor) / 2
                holdEnd = Swift.max(a, Swift.min(mid, nextAnchor - 1))
                nextHoldStart = Swift.min(nextAnchor, holdEnd + 1)
                collided[i] = true
            }
            holdEnd = Swift.max(holdLo, Swift.min(holdEnd, bound - 1))

            // Rest = settled+sharp frame in [holdLo, holdEnd] (handles a slide-0 fade-in: the
            // calm frame after the opening fade, not frame 0). Clamp the range into the grids.
            let lo = Swift.max(0, Swift.min(holdLo, holdEnd))
            var rest = RestSelector.restFrame(in: lo..<(holdEnd + 1),
                                              diffSignal: diffSignal, frameGrids: grids, margin: 1)
            rest = Swift.max(lo, Swift.min(rest, holdEnd))
            rawStart.append(rest); rawEnd.append(holdEnd)

            // Low-confidence (StillsMatch suspect): the anchor sits INSIDE a transition span, OR
            // it is far from its assigned hold region [lo, holdEnd].
            let insideSpan = spans.contains { $0.start < a && a < $0.end }
            let distance = a < lo ? lo - a : (a > holdEnd ? a - holdEnd : 0)
            if insideSpan || distance > farThreshold { lowConf[i] = true }

            holdLo = Swift.max(holdLo, Swift.min(nextHoldStart, bound - 1))
        }

        // Validity normalization → strictly increasing, frame-distinct, in range
        // (`SlideMarkLogic.isValid`). ROOM-RESERVING: slide i's holdStart is capped at
        // `bound - (n - i)` so the remaining `n - i` slides always have distinct frames left —
        // this guarantees ONE mark per slide for every n ≤ bound (including duplicate / clustered
        // anchors; holdStart may legally sit below the anchor). Only n > bound (impossible from
        // strictly-increasing StillsMatch anchors) drops the unfittable tail.
        var marks: [SlideMark] = []
        var keptCollided: [Bool] = [], keptLowConf: [Bool] = []
        var prevEnd = -1
        for i in 0..<n {
            let maxStart = bound - (n - i)          // leave room for slides i..n-1
            var hs = Swift.max(rawStart[i], prevEnd + 1)
            if maxStart >= 0 { hs = Swift.min(hs, maxStart) }
            if hs > bound - 1 || hs <= prevEnd { continue }   // truly over-packed (n > bound)
            // Cap holdEnd so the remaining slides still fit (he ≤ bound - (n - i)).
            let heCap = Swift.max(hs, bound - (n - i))
            let he = Swift.max(hs, Swift.min(rawEnd[i], heCap))
            marks.append(SlideMark(holdStart: hs, holdEnd: he))
            keptCollided.append(collided[i]); keptLowConf.append(lowConf[i])
            prevEnd = he
        }
        return HoldDetection(marks: marks, collidedWithPrevious: keptCollided, lowConfidenceMatch: keptLowConf)
    }
}
