diff --git a/swift-app/Sources/Services/HoldDetector.swift b/swift-app/Sources/Services/HoldDetector.swift
index 1731286..69070ea 100644
--- a/swift-app/Sources/Services/HoldDetector.swift
+++ b/swift-app/Sources/Services/HoldDetector.swift
@@ -1,86 +1,119 @@
 import Foundation
 
-/// Seeds per-slide hold spans from the stills DP-match anchors + forward motion.
-/// Pure over the same 32×18 RGB grids the encoder's `sampleGrids` produces, so it's
-/// unit-testable offline. Best-effort: the result is a SEED the user hand-tunes on
-/// the timeline.
+/// One slide's seed plus the diagnostic flags the harness (section 01) surfaces.
+struct HoldDetection: Sendable, Equatable {
+    /// One mark per slide (== anchors.count, except the impossible over-packed case).
+    let marks: [SlideMark]
+    /// Parallel to `marks`: this slide shared a hold with no detected boundary to its
+    /// neighbour (a deterministic midpoint split was used).
+    let collidedWithPrevious: [Bool]
+    /// Parallel to `marks`: the anchor fell INSIDE a detected transition (a wildly-wrong
+    /// StillsMatch anchor) — a signal that StillsMatch, not the detector, is the suspect.
+    let lowConfidenceMatch: [Bool]
+}
+
+/// Seeds per-slide Rest/Go marks by orchestrating the adaptive detection layers:
+/// `FrameSignal` (multi-channel diff + variance) → `BoundaryDetector` (transition spans) →
+/// `RestSelector` (settled+sharp Rest within each hold).
 ///
-/// Design (learned from the real fade-heavy deck): the DP **anchor** is the frame a
-/// slide's still matched — a reliably *settled* frame, so it is taken verbatim as
-/// `holdStart` (the Rest point). The Rest must never be guessed by expanding a
-/// low-motion run backward — on a deck whose transitions are cross-fades on a dark
-/// background, per-frame motion stays below any threshold, so a backward expansion
-/// runs into the *previous* transition and Rest lands mid-fade (the exact bug this
-/// feature exists to kill). `holdEnd` (Go) is found by expanding FORWARD from the
-/// anchor to where motion begins; when no motion is detectable before the next slide
-/// (a fade), it falls back to a default transition window so the timeline still shows
-/// an editable green transition band instead of a 1-frame sliver.
+/// The stills/anchor count is the slide-count AUTHORITY: this emits exactly ONE mark per
+/// anchor and never silently drops a slide (the old dedup + overlap-drop did). Anchors tell
+/// WHICH slide; the detected spans tell WHERE the boundaries are. Pure over `[[Double]]`
+/// grids; same `detect(...) → [SlideMark]` entry shape so `VideoTimestampDeriver` and the
+/// timeline editor are unchanged.
 enum HoldDetector {
 
-    /// Mean absolute per-component diff between two grids of equal length.
-    static func diff(_ a: [Double], _ b: [Double]) -> Double {
-        guard a.count == b.count, !a.isEmpty else { return 0 }
-        var sum = 0.0
-        for i in 0..<a.count { sum += abs(a[i] - b[i]) }
-        return sum / Double(a.count)
-    }
-
-    /// - Parameters:
-    ///   - anchors: DP-matched settled frame per slide (strictly increasing).
-    ///   - motionThreshold: per-frame grid diff above which a frame counts as "moving".
-    ///   - defaultTransition: fallback transition length (frames) when a fade can't be
-    ///     detected — the green band before the next slide's Rest.
+    /// Primary entry (unchanged shape; `fps` added with a default for source compatibility).
     static func detect(frameGrids: [[Double]],
                        anchors: [Int],
                        frameCount: Int,
-                       motionThreshold: Double = 6.0,
-                       defaultTransition: Int = 15) -> [SlideMark] {
-        guard !anchors.isEmpty, frameCount > 0 else { return [] }
+                       fps: Double = 30) -> [SlideMark] {
+        detectDetailed(frameGrids: frameGrids, anchors: anchors, frameCount: frameCount, fps: fps).marks
+    }
 
-        // Deduplicate (and sort) so two stills matched to the same frame → one slide.
-        var deduped: [Int] = []
-        for v in anchors.sorted() { if deduped.last != v { deduped.append(v) } }
+    /// Detailed entry — marks + the per-slide diagnostic flags the harness reads.
+    static func detectDetailed(frameGrids: [[Double]],
+                               anchors: [Int],
+                               frameCount: Int,
+                               fps: Double = 30) -> HoldDetection {
+        guard !anchors.isEmpty, frameCount > 0 else {
+            return HoldDetection(marks: [], collidedWithPrevious: [], lowConfidenceMatch: [])
+        }
+        let bound = Swift.min(frameCount, frameGrids.count)
+        guard bound > 0 else {
+            return HoldDetection(marks: [], collidedWithPrevious: [], lowConfidenceMatch: [])
+        }
 
-        // Shared upper bound so frameCount != frameGrids.count can't desync clamps.
-        let bound = min(frameCount, frameGrids.count)
-        guard bound > 0 else { return [] }
+        // Sort but DO NOT dedup (dedup was the count-loss bug); clamp into the frame range.
+        let sortedAnchors = anchors.sorted().map { Swift.max(0, Swift.min($0, bound - 1)) }
+        let n = sortedAnchors.count
+
+        // Signal + boundary layers.
+        let diffSignal = FrameSignal.diffSignal(frameGrids)
+        let variances = (0..<bound).map { FrameSignal.frameVariance(frameGrids[$0]) }
+        let spans = BoundaryDetector.transitions(diffSignal: diffSignal, variances: variances, fps: fps)
+
+        // Assign exactly one (Rest, Go) per anchor.
+        var rawStart = [Int](), rawEnd = [Int]()
+        var collided = [Bool](repeating: false, count: n)
+        var lowConf = [Bool](repeating: false, count: n)
+        var holdLo = 0   // the earliest frame this slide's hold may begin (after the prev transition)
 
-        let n = deduped.count
-        var marks: [SlideMark] = []
-        marks.reserveCapacity(n)
         for i in 0..<n {
-            let hs = max(0, min(deduped[i], bound - 1))          // Rest = the anchor, verbatim
-            let nextA = (i < n - 1) ? deduped[i + 1] : bound      // exclusive upper limit
-            let lastBefore = min(bound - 1, nextA - 1)            // last frame we may use for Go
-            if lastBefore <= hs {
-                marks.append(SlideMark(holdStart: hs, holdEnd: hs)) // no room: zero-length hold
-                continue
-            }
-            // Forward-expand from the anchor through the static hold until motion starts.
-            var e = hs
-            while e < lastBefore, diff(frameGrids[e], frameGrids[e + 1]) < motionThreshold { e += 1 }
-            var he: Int
-            if e >= lastBefore {
-                // No motion found before the next slide (a fade) → default transition band.
-                he = max(hs, lastBefore - defaultTransition)
+            let a = sortedAnchors[i]
+            let nextAnchor = i < n - 1 ? sortedAnchors[i + 1] : bound
+
+            // Outgoing transition = the LAST span starting in [a, nextAnchor) — the boundary
+            // nearest the NEXT slide, so an earlier within-slide build doesn't cut Go short.
+            let goSpan = spans.last { $0.start >= a && $0.start < nextAnchor }
+
+            var holdEnd: Int
+            var nextHoldStart: Int
+            if i == n - 1 {
+                holdEnd = bound - 1          // last slide extends to video end (no following transition)
+                nextHoldStart = bound
+            } else if let s = goSpan {
+                holdEnd = s.start
+                nextHoldStart = s.end
             } else {
-                he = e                                            // motion onset = Go
+                // No detected boundary between this anchor and the next: two anchors share a hold
+                // (or an undetected boundary). Split deterministically at the midpoint; flag it.
+                let mid = (a + nextAnchor) / 2
+                holdEnd = Swift.max(a, Swift.min(mid, nextAnchor - 1))
+                nextHoldStart = Swift.min(nextAnchor, holdEnd + 1)
+                collided[i] = true
             }
-            he = max(hs, min(he, lastBefore))
-            marks.append(SlideMark(holdStart: hs, holdEnd: he))
+            holdEnd = Swift.max(holdLo, Swift.min(holdEnd, bound - 1))
+
+            // Rest = settled+sharp frame in [holdLo, holdEnd] (handles a slide-0 fade-in: the
+            // calm frame after the opening fade, not frame 0).
+            let lo = Swift.min(holdLo, holdEnd)
+            var rest = RestSelector.restFrame(in: lo..<(holdEnd + 1),
+                                              diffSignal: diffSignal, frameGrids: frameGrids, margin: 1)
+            rest = Swift.max(lo, Swift.min(rest, holdEnd))
+            rawStart.append(rest); rawEnd.append(holdEnd)
+
+            // Low-confidence: the anchor sits INSIDE a transition span (a wildly-wrong match).
+            if spans.contains(where: { $0.start < a && a < $0.end }) { lowConf[i] = true }
+
+            holdLo = Swift.max(holdLo, Swift.min(nextHoldStart, bound))
         }
 
-        // anchors are strictly increasing so holdStart is too, and each holdEnd < next
-        // holdStart by construction. The only exception is the impossible over-packed
-        // case (more distinct anchors than frames, so several clamp to bound-1): drop
-        // any mark that can't fit without overlapping its predecessor, guaranteeing a
-        // strictly-increasing, valid result for ALL inputs.
-        var result: [SlideMark] = []
-        for mark in marks {
-            if result.isEmpty || mark.holdStart > result.last!.holdEnd {
-                result.append(mark)
-            }
+        // Validity normalization → strictly increasing, frame-distinct, in range
+        // (`SlideMarkLogic.isValid`). For the realistic n ≤ bound case this never drops; the only
+        // exception is the impossible over-packed case (more distinct anchors than frames).
+        var marks: [SlideMark] = []
+        var keptCollided: [Bool] = [], keptLowConf: [Bool] = []
+        var prevEnd = -1
+        for i in 0..<n {
+            var hs = Swift.max(rawStart[i], prevEnd + 1)
+            if hs > bound - 1 { continue }          // over-packed (n > bound): drop the unfittable tail
+            let he = Swift.max(hs, Swift.min(rawEnd[i], bound - 1))
+            hs = Swift.min(hs, he)
+            marks.append(SlideMark(holdStart: hs, holdEnd: he))
+            keptCollided.append(collided[i]); keptLowConf.append(lowConf[i])
+            prevEnd = he
         }
-        return result
+        return HoldDetection(marks: marks, collidedWithPrevious: keptCollided, lowConfidenceMatch: keptLowConf)
     }
 }
diff --git a/swift-app/Sources/Services/VideoTimestampDeriver.swift b/swift-app/Sources/Services/VideoTimestampDeriver.swift
index 099f165..dc83e17 100644
--- a/swift-app/Sources/Services/VideoTimestampDeriver.swift
+++ b/swift-app/Sources/Services/VideoTimestampDeriver.swift
@@ -78,9 +78,10 @@ enum VideoTimestampDeriver {
             fps: fps,
             frameCount: frameGrids.count
         )
-        // Seed hold spans from frame motion around the DP anchors (frames). Best-effort
-        // seed for the timeline editor; the user hand-tunes.
-        let marks = HoldDetector.detect(frameGrids: frameGrids, anchors: frames, frameCount: frameGrids.count)
+        // Seed hold spans by adaptive detection around the DP anchors. Best-effort seed for
+        // the timeline editor; the user hand-tunes. fps drives the boundary detector's
+        // min-hold (seconds × fps), so pass the authoritative fps through.
+        let marks = HoldDetector.detect(frameGrids: frameGrids, anchors: frames, frameCount: frameGrids.count, fps: fps)
         return (analysis, marks)
     }
 }
diff --git a/swift-app/Tests/HoldDetectorTests.swift b/swift-app/Tests/HoldDetectorTests.swift
index 37c7cad..04a8280 100644
--- a/swift-app/Tests/HoldDetectorTests.swift
+++ b/swift-app/Tests/HoldDetectorTests.swift
@@ -1,60 +1,84 @@
 import Testing
+import Foundation
 @testable import KeynoteDeployer
 
-@Suite("HoldDetector")
+/// Section 07 — HoldDetector rewrite. The detector now orchestrates FrameSignal →
+/// BoundaryDetector → RestSelector. Contract: ONE mark per anchor (never a silent
+/// dedup-drop), explicit first/last boundaries, valid strictly-increasing spans.
+/// Small synthetic decks; fps=10 so min-hold (=5 frames) fits the short fixtures.
+@Suite("Section 07 — HoldDetector")
 struct HoldDetectorTests {
-    // Flat "color" grids; a transition is a value ramp. diff between consecutive = |Δ|.
-    private func grid(_ v: Double) -> [Double] { [Double](repeating: v, count: 32 * 18 * 3) }
-
-    @Test("Rest = the anchor; Go = forward motion onset")
-    func restIsAnchorGoIsMotionOnset() {
-        // flat 0..3 (10), motion at 4 (50), flat 7..9 (10). anchors at settled 0 and 8.
-        let grids = [grid(10), grid(10), grid(10), grid(10), grid(50), grid(50), grid(50), grid(10), grid(10), grid(10)]
-        let marks = HoldDetector.detect(frameGrids: grids, anchors: [0, 8], frameCount: grids.count, motionThreshold: 6.0)
-        #expect(marks.count == 2)
-        // slide 0: Rest=anchor 0; forward stops where motion begins (3→4 jump) → Go=3
-        #expect(marks[0].holdStart == 0 && marks[0].holdEnd == 3)
-        // slide 1: Rest=anchor 8 (NOT expanded backward into the prior motion)
-        #expect(marks[1].holdStart == 8)
-        #expect(marks[0].holdEnd < marks[1].holdStart)   // a real transition gap exists
-        #expect(SlideMarkLogic.isValid(marks, frameCount: grids.count))
-    }
-
-    @Test("fade (no detectable motion) falls back to a default transition band")
-    func fadeUsesDefaultTransition() {
-        // entirely flat 40-frame clip (a fade reads as no motion), anchors 0 and 30.
-        let grids = (0..<40).map { _ in grid(10) }
-        let marks = HoldDetector.detect(frameGrids: grids, anchors: [0, 30], frameCount: 40,
-                                        motionThreshold: 6.0, defaultTransition: 15)
-        #expect(marks.count == 2)
-        // Rest stays on the anchors; slide 0 gets a default green band before slide 1.
-        #expect(marks[0].holdStart == 0)
-        #expect(marks[0].holdEnd == 14)            // lastBefore(29) − default(15)
-        #expect(marks[1].holdStart == 30)          // next Rest = its anchor, never mid-fade
-        #expect(marks[1].holdEnd < 40)
-        #expect(SlideMarkLogic.isValid(marks, frameCount: 40))
-    }
-
-    @Test("anchor with motion immediately after collapses to a zero-length hold")
-    func degenerate() {
-        let grids = [grid(0), grid(50), grid(0)]   // anchor 1 has motion on both sides
-        let marks = HoldDetector.detect(frameGrids: grids, anchors: [1], frameCount: 3, motionThreshold: 6.0)
-        #expect(marks == [SlideMark(holdStart: 1, holdEnd: 1)])
+
+    private static let fps = 10.0
+
+    /// Spans the detector would see, for cross-checking Rest placement.
+    private static func spans(_ frames: [[Double]]) -> [TransitionSpan] {
+        let sig = FrameSignal.diffSignal(frames)
+        let vars = frames.map { FrameSignal.frameVariance($0) }
+        return BoundaryDetector.transitions(diffSignal: sig, variances: vars, fps: fps)
+    }
+
+    @Test("one mark per slide — colliding anchors are NOT collapsed (no dedup-drop)")
+    func oneMarkPerSlideNoDrop() {
+        let frames = SeedFixtures.cleanCut()                 // 24 frames, 3 slides
+        // Two anchors in the SAME first hold (no boundary between them).
+        let d = HoldDetector.detectDetailed(frameGrids: frames, anchors: [3, 5], frameCount: frames.count, fps: Self.fps)
+        #expect(d.marks.count == 2)                          // both kept (old code collapsed to 1)
+        #expect(d.collidedWithPrevious.contains(true))       // the shared-hold split is flagged
+        #expect(SlideMarkLogic.isValid(d.marks, frameCount: frames.count))
+    }
+
+    @Test("marks are valid + strictly increasing on a clean 3-slide deck")
+    func validStrictlyIncreasing() {
+        let frames = SeedFixtures.cleanCut()
+        let marks = HoldDetector.detect(frameGrids: frames, anchors: [4, 12, 20], frameCount: frames.count, fps: Self.fps)
+        #expect(marks.count == 3)
+        #expect(SlideMarkLogic.isValid(marks, frameCount: frames.count))
     }
 
-    @Test("duplicate anchors collapse to a single slide and stay valid")
-    func duplicateAnchors() {
-        let grids = (0..<10).map { _ in grid(10) }
-        let marks = HoldDetector.detect(frameGrids: grids, anchors: [5, 5], frameCount: 10, motionThreshold: 6.0)
-        #expect(marks.count == 1)
-        #expect(marks[0].holdStart == 5)
-        #expect(SlideMarkLogic.isValid(marks, frameCount: 10))
+    @Test("edge boundaries: first holdStart before the first cut, last holdEnd == frameCount-1")
+    func edgeBoundaries() {
+        let frames = SeedFixtures.cleanCut()                 // cuts at frames 7→8 and 15→16
+        let marks = HoldDetector.detect(frameGrids: frames, anchors: [4, 12, 20], frameCount: frames.count, fps: Self.fps)
+        #expect(marks.first!.holdStart >= 0 && marks.first!.holdStart <= 7)
+        #expect(marks.last!.holdEnd == frames.count - 1)
     }
 
-    @Test("over-packed anchors stay valid (drops unfittable spans)")
-    func overPackedAnchorsStayValid() {
-        let marks = HoldDetector.detect(frameGrids: [grid(10), grid(10)], anchors: [0, 1, 2],
-                                        frameCount: 2, motionThreshold: 6.0)
-        #expect(SlideMarkLogic.isValid(marks, frameCount: 2))
+    @Test("Go (holdEnd) for an interior slide lands on the detected outgoing cut")
+    func goLandsOnCut() {
+        let frames = SeedFixtures.cleanCut()                 // first cut diff index 7 → span (7,8)
+        let marks = HoldDetector.detect(frameGrids: frames, anchors: [4, 12, 20], frameCount: frames.count, fps: Self.fps)
+        #expect(marks[0].holdEnd == 7)                       // outgoing transition start
+    }
+
+    @Test("Rest never lands inside a transition span (the original mid-fade bug)")
+    func restNotInsideTransition() {
+        let frames = SeedFixtures.crossFadeOnDark()          // a dark cross-fade
+        let sp = Self.spans(frames)
+        let marks = HoldDetector.detect(frameGrids: frames, anchors: [1, 16], frameCount: frames.count, fps: Self.fps)
+        for m in marks {
+            for s in sp {
+                #expect(!(s.start < m.holdStart && m.holdStart < s.end))   // not strictly inside a transition
+            }
+        }
+    }
+
+    @Test("an anchor inside a transition span is flagged low-confidence")
+    func lowConfidenceFlag() {
+        let frames = SeedFixtures.crossFadeOnDark()          // fade roughly frames 4..14
+        let d = HoldDetector.detectDetailed(frameGrids: frames, anchors: [1, 8, 16], frameCount: frames.count, fps: Self.fps)
+        #expect(d.marks.count == 3)
+        #expect(d.lowConfidenceMatch.contains(true))
+    }
+
+    @Test("degenerate / empty inputs are safe")
+    func degenerate() {
+        let frames = SeedFixtures.cleanCut()
+        #expect(HoldDetector.detect(frameGrids: frames, anchors: [], frameCount: frames.count, fps: Self.fps).isEmpty)
+        #expect(HoldDetector.detect(frameGrids: [], anchors: [0], frameCount: 0, fps: Self.fps).isEmpty)
+        let tiny = [SeedFixtures.solid(0, 0, 0), SeedFixtures.solid(0, 0, 0)]
+        let m = HoldDetector.detect(frameGrids: tiny, anchors: [0], frameCount: 2, fps: Self.fps)
+        #expect(m.count == 1)
+        #expect(SlideMarkLogic.isValid(m, frameCount: 2))
     }
 }
