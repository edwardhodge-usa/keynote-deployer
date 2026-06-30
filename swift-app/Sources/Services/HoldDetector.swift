import Foundation

/// Seeds per-slide hold spans from the stills DP-match anchors + forward motion.
/// Pure over the same 32×18 RGB grids the encoder's `sampleGrids` produces, so it's
/// unit-testable offline. Best-effort: the result is a SEED the user hand-tunes on
/// the timeline.
///
/// Design (learned from the real fade-heavy deck): the DP **anchor** is the frame a
/// slide's still matched — a reliably *settled* frame, so it is taken verbatim as
/// `holdStart` (the Rest point). The Rest must never be guessed by expanding a
/// low-motion run backward — on a deck whose transitions are cross-fades on a dark
/// background, per-frame motion stays below any threshold, so a backward expansion
/// runs into the *previous* transition and Rest lands mid-fade (the exact bug this
/// feature exists to kill). `holdEnd` (Go) is found by expanding FORWARD from the
/// anchor to where motion begins; when no motion is detectable before the next slide
/// (a fade), it falls back to a default transition window so the timeline still shows
/// an editable green transition band instead of a 1-frame sliver.
enum HoldDetector {

    /// Mean absolute per-component diff between two grids of equal length.
    static func diff(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var sum = 0.0
        for i in 0..<a.count { sum += abs(a[i] - b[i]) }
        return sum / Double(a.count)
    }

    /// - Parameters:
    ///   - anchors: DP-matched settled frame per slide (strictly increasing).
    ///   - motionThreshold: per-frame grid diff above which a frame counts as "moving".
    ///   - defaultTransition: fallback transition length (frames) when a fade can't be
    ///     detected — the green band before the next slide's Rest.
    static func detect(frameGrids: [[Double]],
                       anchors: [Int],
                       frameCount: Int,
                       motionThreshold: Double = 6.0,
                       defaultTransition: Int = 15) -> [SlideMark] {
        guard !anchors.isEmpty, frameCount > 0 else { return [] }

        // Deduplicate (and sort) so two stills matched to the same frame → one slide.
        var deduped: [Int] = []
        for v in anchors.sorted() { if deduped.last != v { deduped.append(v) } }

        // Shared upper bound so frameCount != frameGrids.count can't desync clamps.
        let bound = min(frameCount, frameGrids.count)
        guard bound > 0 else { return [] }

        let n = deduped.count
        var marks: [SlideMark] = []
        marks.reserveCapacity(n)
        for i in 0..<n {
            let hs = max(0, min(deduped[i], bound - 1))          // Rest = the anchor, verbatim
            let nextA = (i < n - 1) ? deduped[i + 1] : bound      // exclusive upper limit
            let lastBefore = min(bound - 1, nextA - 1)            // last frame we may use for Go
            if lastBefore <= hs {
                marks.append(SlideMark(holdStart: hs, holdEnd: hs)) // no room: zero-length hold
                continue
            }
            // Forward-expand from the anchor through the static hold until motion starts.
            var e = hs
            while e < lastBefore, diff(frameGrids[e], frameGrids[e + 1]) < motionThreshold { e += 1 }
            var he: Int
            if e >= lastBefore {
                // No motion found before the next slide (a fade) → default transition band.
                he = max(hs, lastBefore - defaultTransition)
            } else {
                he = e                                            // motion onset = Go
            }
            he = max(hs, min(he, lastBefore))
            marks.append(SlideMark(holdStart: hs, holdEnd: he))
        }

        // anchors are strictly increasing so holdStart is too, and each holdEnd < next
        // holdStart by construction. The only exception is the impossible over-packed
        // case (more distinct anchors than frames, so several clamp to bound-1): drop
        // any mark that can't fit without overlapping its predecessor, guaranteeing a
        // strictly-increasing, valid result for ALL inputs.
        var result: [SlideMark] = []
        for mark in marks {
            if result.isEmpty || mark.holdStart > result.last!.holdEnd {
                result.append(mark)
            }
        }
        return result
    }
}
