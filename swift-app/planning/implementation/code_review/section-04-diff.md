diff --git a/swift-app/Sources/Services/SlideDetector.swift b/swift-app/Sources/Services/SlideDetector.swift
new file mode 100644
index 0000000..c2f8de5
--- /dev/null
+++ b/swift-app/Sources/Services/SlideDetector.swift
@@ -0,0 +1,146 @@
+import Foundation
+
+/// Auto "quiet-run" slide-boundary detection — a VERBATIM port of
+/// `src/utils/slideDetection.ts`. Pure array math over an adjacent-frame diff
+/// array (`GridSampler.frameDiffs`, section 03) producing `[DetectedSlide]`.
+///
+/// Boundaries are computed at deploy time and baked into the viewer HTML; the
+/// deployed viewer never detects slides itself. Auto is the SEED/fallback source —
+/// "seed quality", good enough to prove the pipeline. Over-counting a build step is
+/// acceptable (the human, or the deferred Stills matcher, corrects it); DROPPING a
+/// real slide is not — hence the conservative `transitionPeak` and the 0.33 adaptive
+/// factor below.
+///
+/// Constants are LOAD-BEARING — tuned against two real decks (39-slide, 22-slide).
+/// Do not round or simplify. Comparison operators are exact: quiet test `<=`,
+/// merge-gap test strict `<`, length filter `>=`.
+enum SlideDetector {
+    static let quietThreshold = 0.3
+    static let minQuietRun = 8
+    /// Conservative: merge ONLY unambiguous micro-builds (gap peak strictly < 0.5).
+    /// A real text-only slide change on a constant-bg deck can be as small as ~1.0;
+    /// ambiguous reveals sit at 0.5–0.9 — never risk dropping a real slide.
+    static let transitionPeak = 0.5
+    /// Adaptive-artifact-filter factor. 0.33, NOT 0.5 — the 0.5 value (stale scope doc)
+    /// wrongly dropped a real briefly-held ~12-frame slide; 0.33 keeps it.
+    static let adaptiveFactor = 0.33
+
+    /// Flag runs of >= minQuietRun consecutive frames with diff <= quietThreshold.
+    static func findQuietRuns(_ diffs: [Double]) -> [QuietRun] {
+        var runs: [QuietRun] = []
+        var runStart: Int? = nil
+
+        func push(_ start: Int, _ end: Int) {
+            runs.append(QuietRun(start: start, end: end,
+                                 length: end - start + 1,
+                                 lastStart: start, lastEnd: end))
+        }
+
+        for i in 0..<diffs.count {
+            if diffs[i] <= quietThreshold {
+                if runStart == nil { runStart = i }
+            } else {
+                if let s = runStart, i - s >= minQuietRun { push(s, i - 1) }
+                runStart = nil
+            }
+        }
+        if let s = runStart, diffs.count - s >= minQuietRun { push(s, diffs.count - 1) }
+        return runs
+    }
+
+    /// Peak frame-diff in the exclusive gap (a.end+1 ... b.start-1) between two runs;
+    /// 0 if the range is empty.
+    private static func gapPeak(_ diffs: [Double], _ a: QuietRun, _ b: QuietRun) -> Double {
+        var peak = 0.0
+        var k = a.end + 1
+        while k <= b.start - 1 {
+            if diffs[k] > peak { peak = diffs[k] }
+            k += 1
+        }
+        return peak
+    }
+
+    /// Merge adjacent quiet runs separated by a low-energy in-slide build
+    /// (gap peak strictly < transitionPeak). Merged run keeps the FIRST sub-run's
+    /// start and the LAST sub-run's end/lastStart/lastEnd.
+    static func mergeBuildRuns(_ runs: [QuietRun], _ diffs: [Double]) -> [QuietRun] {
+        guard !runs.isEmpty else { return runs }
+        var merged: [QuietRun] = [runs[0]]
+        for i in 1..<runs.count {
+            let cur = merged[merged.count - 1]
+            let next = runs[i]
+            if gapPeak(diffs, cur, next) < transitionPeak {
+                // QuietRun fields are `let` — rebuild the last element rather than mutate.
+                merged[merged.count - 1] = QuietRun(
+                    start: cur.start,
+                    end: next.end,
+                    length: next.end - cur.start + 1,
+                    lastStart: next.start,
+                    lastEnd: next.end)
+            } else {
+                merged.append(next)
+            }
+        }
+        return merged
+    }
+
+    /// Adaptive length filter: drop artifact "dark pauses".
+    /// adaptiveMin = max(minQuietRun, floor(median(lengths) * 0.33)); skipped for < 3 runs.
+    static func filterTransitionArtifacts(_ runs: [QuietRun]) -> [QuietRun] {
+        guard runs.count >= 3 else { return runs }
+        let lengths = runs.map { $0.length }.sorted()
+        let median = lengths[lengths.count / 2]   // integer division = floor
+        let adaptiveMin = max(minQuietRun, Int(floor(Double(median) * adaptiveFactor)))
+        return runs.filter { $0.length >= adaptiveMin }
+    }
+
+    /// One DetectedSlide per run; restFrame = floor((lastStart+lastEnd)/2).
+    /// First slide has nil transition; each later slide's transition spans the
+    /// inter-run gap (prevRun.end+1 ... run.start-1).
+    static func buildSlideMap(_ quietRuns: [QuietRun]) -> [DetectedSlide] {
+        var slides: [DetectedSlide] = []
+        for i in 0..<quietRuns.count {
+            let run = quietRuns[i]
+            let prevRun = i > 0 ? quietRuns[i - 1] : nil
+            let restFrame = (run.lastStart + run.lastEnd) / 2   // integer division = floor
+            let transition = prevRun.map { TransitionRange(start: $0.end + 1, end: run.start - 1) }
+            slides.append(DetectedSlide(restFrame: restFrame,
+                                        holdStart: run.start,
+                                        holdEnd: run.end,
+                                        transitionFrames: transition))
+        }
+        return slides
+    }
+
+    /// Orchestration: findQuietRuns → mergeBuildRuns → filterTransitionArtifacts → buildSlideMap.
+    /// Empty/degenerate diff arrays fall through to [] (no run of length >= 8 forms).
+    static func detectSlides(_ diffs: [Double]) -> [DetectedSlide] {
+        let allRuns = findQuietRuns(diffs)
+        let mergedRuns = mergeBuildRuns(allRuns, diffs)
+        let filteredRuns = filterTransitionArtifacts(mergedRuns)
+        return buildSlideMap(filteredRuns)
+    }
+
+    /// Boundary math (also reused by the later Manual phase). For each slide i>0:
+    /// transition.start = slides[i-1].holdEnd+1, transition.end = slides[i].holdStart-1;
+    /// inverted (start > end) ⇒ nil (hard cut). Slide 0 keeps nil.
+    static func recomputeTransitions(_ slides: [DetectedSlide]) -> [DetectedSlide] {
+        var out: [DetectedSlide] = []
+        for i in 0..<slides.count {
+            let s = slides[i]
+            let transition: TransitionRange?
+            if i == 0 {
+                transition = nil
+            } else {
+                let start = slides[i - 1].holdEnd + 1
+                let end = s.holdStart - 1
+                transition = start > end ? nil : TransitionRange(start: start, end: end)
+            }
+            out.append(DetectedSlide(restFrame: s.restFrame,
+                                     holdStart: s.holdStart,
+                                     holdEnd: s.holdEnd,
+                                     transitionFrames: transition))
+        }
+        return out
+    }
+}
diff --git a/swift-app/Tests/BoundaryMathTests.swift b/swift-app/Tests/BoundaryMathTests.swift
new file mode 100644
index 0000000..2ef9dc0
--- /dev/null
+++ b/swift-app/Tests/BoundaryMathTests.swift
@@ -0,0 +1,55 @@
+import Testing
+@testable import KeynoteDeployer
+
+@Suite("BoundaryMath")
+struct BoundaryMathTests {
+
+    private func slide(rest: Int, holdStart: Int, holdEnd: Int) -> DetectedSlide {
+        DetectedSlide(restFrame: rest, holdStart: holdStart, holdEnd: holdEnd,
+                      transitionFrames: nil)
+    }
+
+    @Test("recomputeTransitions builds contiguous transitions; slide 0 stays nil")
+    func recomputeContiguous() {
+        let slides = [
+            slide(rest: 5,  holdStart: 0,  holdEnd: 9),
+            slide(rest: 25, holdStart: 20, holdEnd: 31),
+            slide(rest: 45, holdStart: 40, holdEnd: 49),
+        ]
+        let out = SlideDetector.recomputeTransitions(slides)
+        #expect(out[0].transitionFrames == nil)
+        #expect(out[1].transitionFrames?.start == 10)   // slides[0].holdEnd + 1
+        #expect(out[1].transitionFrames?.end == 19)     // slides[1].holdStart - 1
+        #expect(out[2].transitionFrames?.start == 32)   // slides[1].holdEnd + 1
+        #expect(out[2].transitionFrames?.end == 39)     // slides[2].holdStart - 1
+        // Holds preserved.
+        #expect(out[1].holdStart == 20 && out[1].holdEnd == 31)
+        #expect(out[1].restFrame == 25)
+    }
+
+    @Test("recomputeTransitions: inverted/abutting holds ⇒ nil (hard cut)")
+    func recomputeInvertedIsNil() {
+        // slide 1 starts immediately after slide 0's hold end ⇒ start (10) > end (9) ⇒ nil.
+        let slides = [
+            slide(rest: 5,  holdStart: 0,  holdEnd: 9),
+            slide(rest: 12, holdStart: 10, holdEnd: 15),
+        ]
+        let out = SlideDetector.recomputeTransitions(slides)
+        #expect(out[1].transitionFrames == nil)
+    }
+
+    @Test("recomputeTransitions: overlapping holds ⇒ nil")
+    func recomputeOverlappingIsNil() {
+        let slides = [
+            slide(rest: 5,  holdStart: 0,  holdEnd: 12),
+            slide(rest: 14, holdStart: 8,  holdEnd: 18),   // starts before prev hold ends
+        ]
+        let out = SlideDetector.recomputeTransitions(slides)
+        #expect(out[1].transitionFrames == nil)            // start 13 > end 7
+    }
+
+    @Test("recomputeTransitions on empty ⇒ empty")
+    func recomputeEmpty() {
+        #expect(SlideDetector.recomputeTransitions([]).isEmpty)
+    }
+}
diff --git a/swift-app/Tests/SlideDetectorTests.swift b/swift-app/Tests/SlideDetectorTests.swift
new file mode 100644
index 0000000..35897e8
--- /dev/null
+++ b/swift-app/Tests/SlideDetectorTests.swift
@@ -0,0 +1,168 @@
+import Testing
+@testable import KeynoteDeployer
+
+@Suite("SlideDetector")
+struct SlideDetectorTests {
+
+    /// Mirrors the Electron Vitest `synth(holds, holdLen, gapPeaks)` helper exactly:
+    /// for each hold s (0-based) push `holdLen` zeros; then if s < holds-1 push
+    /// gapPeaks[s] followed by a 0.1 frame. The trailing 0.1 is part of the fixture.
+    private func synth(_ holds: Int, _ holdLen: Int, _ gapPeaks: [Double]) -> [Double] {
+        var out: [Double] = []
+        for s in 0..<holds {
+            out.append(contentsOf: Array(repeating: 0.0, count: holdLen))
+            if s < holds - 1 {
+                out.append(gapPeaks[s])
+                out.append(0.1)
+            }
+        }
+        return out
+    }
+
+    // MARK: - findQuietRuns
+
+    @Test("findQuietRuns flags runs >= minQuietRun, drops shorter ones")
+    func findQuietRunsThreshold() {
+        // 8 quiet frames then a spike then 7 quiet frames: first run qualifies (>=8),
+        // second (7) does not.
+        var diffs = Array(repeating: 0.0, count: 8)   // indices 0..7
+        diffs.append(1.0)                              // index 8 spike
+        diffs.append(contentsOf: Array(repeating: 0.0, count: 7))  // indices 9..15
+        let runs = SlideDetector.findQuietRuns(diffs)
+        #expect(runs.count == 1)
+        #expect(runs[0].start == 0)
+        #expect(runs[0].end == 7)
+        #expect(runs[0].length == 8)
+    }
+
+    @Test("findQuietRuns quiet test is inclusive (<= 0.3 qualifies)")
+    func findQuietRunsInclusiveThreshold() {
+        let diffs = Array(repeating: 0.3, count: 10)   // exactly at threshold ⇒ quiet
+        let runs = SlideDetector.findQuietRuns(diffs)
+        #expect(runs.count == 1)
+        #expect(runs[0].length == 10)
+    }
+
+    // MARK: - mergeBuildRuns
+
+    @Test("mergeBuildRuns merges a clearly-tiny micro-build gap (< 0.5), keeps boundaries")
+    func mergeBuildRunsMergesMicroBuild() {
+        // Two qualifying runs separated by a 0.45 gap peak (< 0.5) ⇒ merge into one.
+        let diffs = synth(2, 10, [0.45])
+        let runs = SlideDetector.findQuietRuns(diffs)
+        #expect(runs.count == 2)
+        let merged = SlideDetector.mergeBuildRuns(runs, diffs)
+        #expect(merged.count == 1)
+        #expect(merged[0].start == runs[0].start)        // first sub-run start
+        #expect(merged[0].end == runs[1].end)            // last sub-run end
+        #expect(merged[0].lastStart == runs[1].start)
+        #expect(merged[0].lastEnd == runs[1].end)
+    }
+
+    @Test("mergeBuildRuns does NOT merge a real change (gap >= 0.5 stays split)")
+    func mergeBuildRunsKeepsRealChange() {
+        let diffs = synth(2, 10, [1.0])
+        let runs = SlideDetector.findQuietRuns(diffs)
+        let merged = SlideDetector.mergeBuildRuns(runs, diffs)
+        #expect(merged.count == 2)
+    }
+
+    @Test("mergeBuildRuns gap peak of exactly 0.5 does NOT merge (strict <)")
+    func mergeBuildRunsBoundaryExclusive() {
+        let diffs = synth(2, 10, [0.5])
+        let runs = SlideDetector.findQuietRuns(diffs)
+        let merged = SlideDetector.mergeBuildRuns(runs, diffs)
+        #expect(merged.count == 2)
+    }
+
+    // MARK: - filterTransitionArtifacts
+
+    @Test("filterTransitionArtifacts skipped for < 3 runs (returns input)")
+    func filterSkippedUnderThree() {
+        let diffs = synth(2, 10, [1.0])
+        let runs = SlideDetector.findQuietRuns(diffs)
+        #expect(SlideDetector.filterTransitionArtifacts(runs).count == runs.count)
+    }
+
+    @Test("filterTransitionArtifacts 0.33 factor KEEPS a briefly-held real slide that 0.5 would drop")
+    func filterAdaptive033KeepsBriefSlide() {
+        // Three long holds (30) + one brief real hold (12). Sized so the 0.33 vs 0.5
+        // factor genuinely discriminates: median of [12,30,30,30] = 30.
+        //   0.33 → adaptiveMin = max(8, floor(30*0.33)=9)  ⇒ 12 >= 9  KEEPS  (4 runs)
+        //   0.5  → adaptiveMin = max(8, floor(30*0.5)=15)  ⇒ 12 < 15  DROPS  (3 runs)
+        let runs = [
+            QuietRun(start: 0,   end: 29,  length: 30, lastStart: 0,   lastEnd: 29),
+            QuietRun(start: 40,  end: 69,  length: 30, lastStart: 40,  lastEnd: 69),
+            QuietRun(start: 80,  end: 109, length: 30, lastStart: 80,  lastEnd: 109),
+            QuietRun(start: 120, end: 131, length: 12, lastStart: 120, lastEnd: 131),  // brief real slide
+        ]
+        let kept = SlideDetector.filterTransitionArtifacts(runs)
+        // 0.33 factor KEEPS the brief 12-frame slide ⇒ all 4 survive.
+        #expect(kept.count == 4)
+        // Sanity: a 0.5 factor (adaptiveMin 15) would DROP the 12 ⇒ only 3 survive.
+        let halfMin = max(SlideDetector.minQuietRun, Int((Double(30) * 0.5).rounded(.down)))
+        #expect(runs.filter { $0.length >= halfMin }.count == 3)
+    }
+
+    @Test("filterTransitionArtifacts drops a true short artifact run")
+    func filterDropsArtifact() {
+        let runs = [
+            QuietRun(start: 0,   end: 29,  length: 30, lastStart: 0,   lastEnd: 29),
+            QuietRun(start: 40,  end: 69,  length: 30, lastStart: 40,  lastEnd: 69),
+            QuietRun(start: 80,  end: 109, length: 30, lastStart: 80,  lastEnd: 109),
+            QuietRun(start: 120, end: 127, length: 8,  lastStart: 120, lastEnd: 127),  // artifact
+        ]
+        // median 30 ⇒ adaptiveMin = max(8, 9) = 9; length 8 < 9 ⇒ dropped.
+        let kept = SlideDetector.filterTransitionArtifacts(runs)
+        #expect(kept.count == 3)
+    }
+
+    // MARK: - buildSlideMap
+
+    @Test("buildSlideMap restFrame/holds/transition consistency")
+    func buildSlideMapConsistency() {
+        let runs = [
+            QuietRun(start: 0,  end: 9,  length: 10, lastStart: 0,  lastEnd: 9),
+            QuietRun(start: 20, end: 31, length: 12, lastStart: 20, lastEnd: 31),
+        ]
+        let slides = SlideDetector.buildSlideMap(runs)
+        #expect(slides.count == 2)
+        #expect(slides[0].restFrame == 4)            // floor((0+9)/2)
+        #expect(slides[0].holdStart == 0)
+        #expect(slides[0].holdEnd == 9)
+        #expect(slides[0].transitionFrames == nil)   // first slide: no transition
+        #expect(slides[1].restFrame == 25)           // floor((20+31)/2)
+        #expect(slides[1].holdStart == 20)
+        #expect(slides[1].holdEnd == 31)
+        #expect(slides[1].transitionFrames?.start == 10)   // prevRun.end + 1
+        #expect(slides[1].transitionFrames?.end == 19)     // run.start - 1
+    }
+
+    // MARK: - detectSlides (ported Vitest count assertions — load-bearing)
+
+    @Test("detectSlides synth(4,10,[0.7,1.2,0.45]) → 3 slides")
+    func detectSlidesPortedThree() {
+        // 0.45 micro-build merges; 0.7 ambiguous + 1.2 real change both stay.
+        let slides = SlideDetector.detectSlides(synth(4, 10, [0.7, 1.2, 0.45]))
+        #expect(slides.count == 3)
+    }
+
+    @Test("detectSlides synth(2,10,[1.0]) → 2 slides")
+    func detectSlidesPortedTwo() {
+        // 1.0 gap = a real text-only change on constant bg, never merged.
+        let slides = SlideDetector.detectSlides(synth(2, 10, [1.0]))
+        #expect(slides.count == 2)
+    }
+
+    // MARK: - degenerate input (guards the empty-slides[] deploy-crash class)
+
+    @Test("detectSlides([]) → []")
+    func detectSlidesEmpty() {
+        #expect(SlideDetector.detectSlides([]).isEmpty)
+    }
+
+    @Test("detectSlides([0.0]) (single element) → []")
+    func detectSlidesSingle() {
+        #expect(SlideDetector.detectSlides([0.0]).isEmpty)
+    }
+}
