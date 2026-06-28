import Foundation

/// Pure, AVFoundation-free operations on the per-slide marker list edited in the
/// Review Markers phase. The marker list is the authoritative slide set: it must
/// stay sorted + strictly increasing (the encoder's forced keyframes and the
/// viewer's {{TS}} both depend on it). Extracted from the view so it's unit-testable
/// offline.
enum MarkerEditorLogic {

    /// Clamp a proposed time for `markers[index]` so it stays strictly between its
    /// neighbors (an `epsilon` gap on each side) and within `[0, duration]`. Keeps
    /// markers from crossing while a scrubber drags one.
    static func clamp(_ proposed: Double,
                      index: Int,
                      markers: [Double],
                      duration: Double,
                      epsilon: Double = 0.001) -> Double {
        let lower = index > 0 ? markers[index - 1] + epsilon : 0
        let upper = index < markers.count - 1 ? markers[index + 1] - epsilon : duration
        if upper < lower { return lower }   // degenerate: neighbors closer than 2·epsilon
        return min(max(proposed, lower), upper)
    }

    /// Insert a new marker at `time`, keeping the array sorted. Returns the new
    /// array and the inserted element's index. Caller is responsible for choosing a
    /// `time` that doesn't duplicate a neighbor (use the current playhead, which sits
    /// between existing markers).
    static func insert(_ time: Double, into markers: [Double]) -> (markers: [Double], index: Int) {
        var m = markers
        let idx = m.firstIndex(where: { $0 > time }) ?? m.count
        m.insert(time, at: idx)
        return (m, idx)
    }

    /// Remove `markers[index]`. Guarded: never removes the last marker (a deck needs
    /// ≥1 slide). Returns the new array and the index to select next (clamped).
    static func remove(at index: Int, from markers: [Double]) -> (markers: [Double], selected: Int) {
        guard markers.count > 1, markers.indices.contains(index) else {
            return (markers, min(max(index, 0), max(markers.count - 1, 0)))
        }
        var m = markers
        m.remove(at: index)
        return (m, min(index, m.count - 1))
    }

    /// True iff strictly increasing — the encoder/viewer invariant.
    static func isMonotonic(_ markers: [Double]) -> Bool {
        zip(markers, markers.dropFirst()).allSatisfy { $0 < $1 }
    }

    /// Time at which "Add" should insert a new marker after `selected`: the midpoint
    /// between markers[selected] and its next neighbor, or — for the last marker —
    /// the midpoint toward `duration`. Caller inserts this (it's strictly between
    /// neighbors, so the array stays monotonic).
    static func insertionTime(after selected: Int, markers: [Double], duration: Double) -> Double {
        guard !markers.isEmpty, markers.indices.contains(selected) else {
            return duration / 2
        }
        if selected < markers.count - 1 {
            return (markers[selected] + markers[selected + 1]) / 2
        } else {
            return (markers[selected] + duration) / 2
        }
    }

    /// Snap each marker to its nearest frame (round(t*fps)/fps) and return a strictly
    /// increasing array: if a snapped value is <= the previous, bump it to previous +
    /// one frame. Guarantees frame-distinct, monotonic keyframes. fps must be > 0.
    static func quantizeToFrames(_ markers: [Double], fps: Double) -> [Double] {
        guard fps > 0 else { return markers }
        var result: [Double] = []
        for t in markers {
            let snapped = (t * fps).rounded() / fps
            if let prev = result.last, snapped <= prev {
                // Bump to prev + one frame, re-snapped to grid
                let bumped = ((prev + 1.0 / fps) * fps).rounded() / fps
                result.append(bumped)
            } else {
                result.append(snapped)
            }
        }
        return result
    }
}
