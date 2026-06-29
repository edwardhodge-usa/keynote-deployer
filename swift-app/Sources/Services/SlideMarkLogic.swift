import Foundation

/// Pure, AVFoundation-free operations on the per-slide hold-span list. The list is
/// the authoritative slide set and must stay sorted, non-overlapping, and
/// frame-distinct: `holdStart_i <= holdEnd_i < holdStart_{i+1}`, all in
/// `[0, frameCount)`. Extracted from the view so it's unit-testable offline.
enum SlideMarkLogic {

    /// Clamp a moved boundary so it can't cross its neighbors.
    /// - holdStart_i ∈ [ (i>0 ? holdEnd_{i-1}+1 : 0), holdEnd_i ]
    /// - holdEnd_i   ∈ [ holdStart_i, (i<count-1 ? holdStart_{i+1}-1 : frameCount-1) ]
    static func clamp(_ frame: Int, ref: MarkerRef, marks: [SlideMark], frameCount: Int) -> Int {
        guard marks.indices.contains(ref.slide) else { return frame }
        let m = marks[ref.slide]
        switch ref.edge {
        case .start:
            let lower = ref.slide > 0 ? marks[ref.slide - 1].holdEnd + 1 : 0
            let upper = m.holdEnd
            return min(max(frame, lower), max(lower, upper))
        case .end:
            let lower = m.holdStart
            let upper = ref.slide < marks.count - 1 ? marks[ref.slide + 1].holdStart - 1 : frameCount - 1
            return min(max(frame, lower), max(lower, upper))
        }
    }

    /// Split the hold span containing `frame` into two slides at `frame`
    /// (left = holdStart…frame, right = frame+1…holdEnd). No-op if `frame` isn't
    /// strictly inside a hold (can't make a zero-length span).
    static func split(at frame: Int, marks: [SlideMark]) -> [SlideMark] {
        guard let i = marks.firstIndex(where: { frame >= $0.holdStart && frame < $0.holdEnd }) else { return marks }
        var out = marks
        let m = out[i]
        out[i] = SlideMark(holdStart: m.holdStart, holdEnd: frame)
        out.insert(SlideMark(holdStart: frame + 1, holdEnd: m.holdEnd), at: i + 1)
        return out
    }

    /// Merge slide `i` with `i+1` into one hold span (holdStart_i … holdEnd_{i+1}).
    /// Guarded: a single-slide deck is left unchanged.
    static func merge(slide i: Int, marks: [SlideMark]) -> [SlideMark] {
        guard marks.count > 1, marks.indices.contains(i), marks.indices.contains(i + 1) else { return marks }
        var out = marks
        out[i] = SlideMark(holdStart: out[i].holdStart, holdEnd: out[i + 1].holdEnd)
        out.remove(at: i + 1)
        return out
    }

    /// The full invariant: ordered, non-overlapping, frame-distinct, in range.
    static func isValid(_ marks: [SlideMark], frameCount: Int) -> Bool {
        guard !marks.isEmpty else { return false }
        for (idx, m) in marks.enumerated() {
            if m.holdStart < 0 || m.holdEnd >= frameCount || m.holdStart > m.holdEnd { return false }
            if idx > 0, marks[idx - 1].holdEnd >= m.holdStart { return false }
        }
        return true
    }
}
