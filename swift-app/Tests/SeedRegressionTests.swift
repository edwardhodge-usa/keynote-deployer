import Testing
import Foundation
@testable import KeynoteDeployer

/// Section 08 — seed regression guard. Runs the FULL adaptive pipeline
/// (FrameSignal → BoundaryDetector → RestSelector via HoldDetector) on the three deck
/// archetypes and asserts the structural guarantees that must never regress, so a future
/// timeline-editor change can't silently break the seed again. The captured REAL-deck grids
/// + Edward's eyeball + the iPhone gate are the accuracy oracle (section-08 manual gate);
/// these offline tests lock the invariants.
@Suite("Section 08 — Seed regression")
struct SeedRegressionTests {

    private static let fps = 10.0

    private struct Deck { let name: String; let frames: [[Double]]; let anchors: [Int] }

    /// One anchor per slide, placed in each archetype's settled regions.
    private static func decks() -> [Deck] {
        [
            // clean-cut: 3 slides, holds [0-7],[8-15],[16-23].
            Deck(name: "clean-cut", frames: SeedFixtures.cleanCut(), anchors: [4, 12, 20]),
            // cross-fade-on-dark: 2 slides, dark-blue hold then dark-red hold.
            Deck(name: "cross-fade-on-dark", frames: SeedFixtures.crossFadeOnDark(), anchors: [1, 16]),
            // build-heavy: one slide with intra-slide motion → ONE anchor, must stay one slide.
            Deck(name: "build-heavy", frames: SeedFixtures.buildHeavy(), anchors: [2]),
        ]
    }

    @Test("every archetype: marks.count == anchors.count (slide-count authority preserved)")
    func countPreservedAllArchetypes() {
        for deck in Self.decks() {
            let marks = HoldDetector.detect(frameGrids: deck.frames, anchors: deck.anchors,
                                            frameCount: deck.frames.count, fps: Self.fps)
            #expect(marks.count == deck.anchors.count, "\(deck.name): count diverged")
        }
    }

    @Test("every archetype: marks satisfy SlideMarkLogic.isValid (editor invariant)")
    func validAllArchetypes() {
        for deck in Self.decks() {
            let marks = HoldDetector.detect(frameGrids: deck.frames, anchors: deck.anchors,
                                            frameCount: deck.frames.count, fps: Self.fps)
            #expect(SlideMarkLogic.isValid(marks, frameCount: deck.frames.count), "\(deck.name): invalid marks")
        }
    }

    @Test("every archetype: no Rest lands strictly inside a transition span (the core bug)")
    func restNeverInsideTransition() {
        for deck in Self.decks() {
            let sig = FrameSignal.diffSignal(deck.frames)
            let vars = deck.frames.map { FrameSignal.frameVariance($0) }
            let spans = BoundaryDetector.transitions(diffSignal: sig, variances: vars, fps: Self.fps)
            let marks = HoldDetector.detect(frameGrids: deck.frames, anchors: deck.anchors,
                                            frameCount: deck.frames.count, fps: Self.fps)
            for m in marks {
                for s in spans {
                    #expect(!(s.start < m.holdStart && m.holdStart < s.end),
                            "\(deck.name): Rest \(m.holdStart) inside transition (\(s.start),\(s.end))")
                }
            }
        }
    }
}
