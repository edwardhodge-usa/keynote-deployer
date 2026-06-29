import Foundation

/// One slide's stable hold span, in VIDEO FRAME INDICES. The transition between
/// slide i and i+1 is the gap (holdEnd_i, holdStart_{i+1}). holdStart is the rest
/// point + forced keyframe; holdEnd is the start of the outgoing animation (also a
/// forced keyframe the viewer seeks to before playing the transition).
struct SlideMark: Sendable, Equatable {
    var holdStart: Int
    var holdEnd: Int
}

enum MarkerEdge: Sendable, Equatable { case start, end }

/// Identifies one editable boundary handle: a slide and which edge of its hold.
struct MarkerRef: Sendable, Equatable {
    var slide: Int
    var edge: MarkerEdge
}
