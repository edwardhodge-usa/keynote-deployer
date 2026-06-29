import Foundation

/// Seeds per-slide hold spans from frame motion. Pure over the same 32×18 RGB grids
/// the encoder's `sampleGrids` produces, so it's unit-testable offline. Best-effort:
/// the result is a SEED the user hand-tunes on the timeline, never authoritative
/// (the constant-bg detection caveat in CLAUDE.md doesn't bite — the human corrects
/// it). Slide COUNT comes from `anchors` (the stills DP-match), not from detection.
enum HoldDetector {

    /// Mean absolute per-component diff between two grids of equal length.
    static func diff(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var sum = 0.0
        for i in 0..<a.count { sum += abs(a[i] - b[i]) }
        return sum / Double(a.count)
    }

    static func detect(frameGrids: [[Double]],
                       anchors: [Int],
                       frameCount: Int,
                       motionThreshold: Double = 6.0) -> [SlideMark] {
        guard !anchors.isEmpty, frameCount > 0 else { return [] }
        let sorted = anchors.sorted()

        // Deduplicate adjacent duplicates so [5,5] → [5] (one slide, not two).
        var deduped: [Int] = []
        for v in sorted { if deduped.last != v { deduped.append(v) } }

        // Shared upper bound so frameCount != frameGrids.count can't desync the clamps.
        let bound = min(frameCount, frameGrids.count)
        guard bound > 0 else { return [] }

        // 1. Expand each anchor into its low-motion run.
        var marks: [SlideMark] = deduped.map { anchor in
            let a = max(0, min(anchor, bound - 1))
            var start = a, end = a
            while start > 0, diff(frameGrids[start - 1], frameGrids[start]) < motionThreshold { start -= 1 }
            while end < bound - 1, diff(frameGrids[end], frameGrids[end + 1]) < motionThreshold { end += 1 }
            return SlideMark(holdStart: start, holdEnd: end)
        }

        // 2. Resolve collisions: if slide i's hold reaches into slide i+1's, cut both
        //    at the midpoint of their anchors.
        for i in 0..<(marks.count - 1) where marks[i].holdEnd >= marks[i + 1].holdStart {
            let mid = (deduped[i] + deduped[i + 1]) / 2
            marks[i].holdEnd = min(marks[i].holdEnd, mid)
            marks[i + 1].holdStart = max(marks[i + 1].holdStart, mid + 1)
        }

        // 3. Final safety: enforce ordering + frame range so the seed is always valid.
        //    Order: push past previous holdEnd FIRST, then clamp into [0, bound-1].
        //    Clamping before the push allowed holdStart to escape the range when squeezed.
        for i in marks.indices {
            // a. Enforce ordering: start must come after the previous slide's end.
            marks[i].holdStart = max(marks[i].holdStart, i > 0 ? marks[i - 1].holdEnd + 1 : 0)
            // b. Keep end >= start before clamping.
            marks[i].holdEnd = max(marks[i].holdEnd, marks[i].holdStart)
            // c. Clamp both into [0, bound-1].
            marks[i].holdStart = max(0, min(marks[i].holdStart, bound - 1))
            marks[i].holdEnd   = max(0, min(marks[i].holdEnd,   bound - 1))
            // d. If clamping squeezed start past end, pin end to start.
            if marks[i].holdStart > marks[i].holdEnd { marks[i].holdEnd = marks[i].holdStart }
        }

        // 4. Drop any mark that can't fit without overlapping its predecessor.
        //    For the impossible over-packed case (deduped.count > bound), this ensures
        //    the result is always a valid, non-overlapping array.
        var result: [SlideMark] = []
        for mark in marks {
            if result.isEmpty || mark.holdStart > result.last!.holdEnd {
                result.append(mark)
            }
        }
        return result
    }
}
