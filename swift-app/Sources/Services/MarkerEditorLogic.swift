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
}
