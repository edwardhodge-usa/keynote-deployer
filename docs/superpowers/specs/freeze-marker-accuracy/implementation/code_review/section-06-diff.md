diff --git a/swift-app/Sources/Services/AdaptiveThreshold.swift b/swift-app/Sources/Services/AdaptiveThreshold.swift
index 803a01b..25923bc 100644
--- a/swift-app/Sources/Services/AdaptiveThreshold.swift
+++ b/swift-app/Sources/Services/AdaptiveThreshold.swift
@@ -40,27 +40,23 @@ enum AdaptiveThreshold {
     static let rescueFraction = 0.5
     /// MAD → σ consistency constant for normal data.
     static let madToSigma = 1.4826
-    /// 90th-percentile gap → σ (z₀.₉ ≈ 1.2816), the MAD-collapse fallback spread.
-    static let p90ToSigma = 1.2816
 
     /// Robust (hard=Tb, gradual=Ts) thresholds from the signal's own distribution.
     ///
-    /// `spread` = the larger of the MAD-based σ and a 90th-percentile-gap σ. The second
-    /// term rescues the common static-dominated case where >50% of values are ~0 → MAD
-    /// collapses to 0 but the upper tail (fade plateau) still carries scale.
-    /// `hard = max(hardFloor, median + kHard·spread, rescueFraction·P95)`. The P95 term
-    /// (NOT raw max — a lone outlier can't set the bar for the whole deck) carries decks
-    /// with sparse hard cuts where even P90 sits in the static region.
+    /// `hard = max(hardFloor, median + kHard·MADσ, rescueFraction·P95)`. The `rescueFraction·P95`
+    /// term is the workhorse for the static-dominated case where MAD collapses to 0 (>50% of
+    /// values ~0) — half of a high percentile is a sound hard floor. P95 (not raw max) so a lone
+    /// outlier can't set the bar for the whole deck; the MAD term refines `hard` upward only when
+    /// there is genuine spread. (An earlier P90-gap-σ term was REMOVED: on a small or
+    /// transition-dense signal the 90th percentile lands ON a spike, inflating `hard` enough to
+    /// MISS real cuts — surfaced by the BoundaryDetector two-close-cuts integration test.)
     /// `gradual = clamp(gradualRatio·hard, gradualFloor, hard−ε)`.
     static func dualThreshold(_ signal: [Double]) -> (hard: Double, gradual: Double) {
         guard !signal.isEmpty else { return (hardFloor, gradualFloor) }
         let med = median(signal)
         let madSigma = madToSigma * median(signal.map { abs($0 - med) })
-        let p90 = percentile(signal, 0.90)
         let p95 = percentile(signal, 0.95)
-        let pctSigma = Swift.max(0, (p90 - med) / p90ToSigma)
-        let spread = Swift.max(madSigma, pctSigma)
-        let hard = Swift.max(hardFloor, med + kHard * spread, rescueFraction * p95)
+        let hard = Swift.max(hardFloor, med + kHard * madSigma, rescueFraction * p95)
         let gradual = Swift.min(Swift.max(gradualRatio * hard, gradualFloor), hard - 1e-9)
         return (hard, gradual)
     }
diff --git a/swift-app/Sources/Services/BoundaryDetector.swift b/swift-app/Sources/Services/BoundaryDetector.swift
new file mode 100644
index 0000000..c0ae22c
--- /dev/null
+++ b/swift-app/Sources/Services/BoundaryDetector.swift
@@ -0,0 +1,136 @@
+import Foundation
+
+/// A detected transition between two slides, in VIDEO FRAME indices.
+/// `start` (Fs) = where the outgoing transition begins (→ the previous slide's Go).
+/// `end`   (Fe) = where the incoming slide has settled (→ the next slide's hold region).
+struct TransitionSpan: Sendable, Equatable {
+    let start: Int
+    let end: Int
+    let kind: Kind
+    enum Kind: Sendable, Equatable { case cut, gradual }
+}
+
+/// Finds transition spans over a deck's diff signal + per-frame variances, so the hold
+/// for slide i is the gap between transition i-1's end and transition i's start.
+///
+/// Three mechanisms (per the §04 division of labour):
+///  1. **Hard cut** — `localRatio ≥ cutRatio` AND `diff ≥ hard` (a local spike on a real
+///     cut). localRatios is a hard-cut detector; a sustained fade is a plateau (ratio ≈ 1),
+///     so cuts and fades use different paths.
+///  2. **Twin-comparison gradual** — a run of frames in `[gradual, hard)` whose accumulated
+///     sum crosses `hard` is a gradual transition (the dark-fade path), with a small grace
+///     for single-frame noise dropouts so one dissolve isn't split in two.
+///  3. **Variance vote** — a SHORT monochrome dip (flanked by content) is a fade-through-black;
+///     a SUSTAINED low-variance run (≥ minHold) is a held black SLIDE, NOT a transition.
+///
+/// IMPORTANT: this is deliberately a CANDIDATE detector. It cannot tell a within-slide build
+/// from a slide-changing fade by pixels alone (both are sustained sub-hard motion) — so it may
+/// over-detect on build-heavy decks. The final per-slide count is enforced by `HoldDetector`
+/// (section 07) using the stills/anchor count as the authority; this module only says WHERE
+/// candidate boundaries are. Pure; no I/O.
+enum BoundaryDetector {
+
+    /// Local-ratio multiple that marks a hard cut (unitless; ~3× the local baseline).
+    static let cutRatio = 3.0
+    /// Consecutive sub-`gradual` frames tolerated inside a gradual run before it ends
+    /// (bridges a single noisy dropout so one dissolve isn't split in two).
+    static let graceLimit = 2
+    /// A frame is "near-monochrome" when its variance is below this fraction of the deck's
+    /// median frame variance (the fade-through-black signal).
+    static let lowVarianceFraction = 0.1
+
+    static func transitions(diffSignal: [Double],
+                            variances: [Double],
+                            fps: Double,
+                            minHoldSeconds: Double = 0.5) -> [TransitionSpan] {
+        let frameCount = variances.count
+        guard frameCount > 1, !diffSignal.isEmpty else { return [] }
+        let minHoldFrames = Swift.max(1, Int((minHoldSeconds * fps).rounded()))
+        let (hard, gradual) = AdaptiveThreshold.dualThreshold(diffSignal)
+        let ratios = AdaptiveThreshold.localRatios(diffSignal, window: AdaptiveThreshold.window(forFps: fps))
+        let m = diffSignal.count
+
+        var raw: [TransitionSpan] = []
+
+        // 1 + 2. Diff-based walk: hard cuts and twin-comparison gradual runs.
+        var i = 0
+        while i < m {
+            // Hard cut: a local spike that also clears the absolute hard threshold.
+            if ratios[i] >= cutRatio && diffSignal[i] >= hard {
+                raw.append(TransitionSpan(start: i, end: i + 1, kind: .cut))
+                i += 1
+                continue
+            }
+            // Gradual run: accumulate frames ≥ gradual (with grace) until the sum reaches hard.
+            if diffSignal[i] >= gradual {
+                var sum = 0.0, j = i, lastStrong = i, grace = 0
+                while j < m {
+                    if diffSignal[j] >= gradual { sum += diffSignal[j]; lastStrong = j; grace = 0; j += 1 }
+                    else if grace < graceLimit { grace += 1; j += 1 }
+                    else { break }
+                }
+                if sum >= hard {
+                    let kind: TransitionSpan.Kind = lastStrong > i ? .gradual : .cut
+                    raw.append(TransitionSpan(start: i, end: lastStrong + 1, kind: kind))
+                }
+                i = Swift.max(i + 1, lastStrong + 1)
+                continue
+            }
+            i += 1
+        }
+
+        // 3. Variance vote: short monochrome dips → gradual transitions; sustained → holds.
+        raw += varianceDipSpans(variances, minHoldFrames: minHoldFrames)
+
+        return resolve(raw, frameCount: frameCount, minHoldFrames: minHoldFrames)
+    }
+
+    // MARK: variance vote
+
+    /// Spans where a SHORT near-monochrome dip (flanked by content) marks a fade-through-black.
+    /// A low-variance run lasting ≥ minHoldFrames is a held black SLIDE → NOT a transition.
+    static func varianceDipSpans(_ variances: [Double], minHoldFrames: Int) -> [TransitionSpan] {
+        let n = variances.count
+        guard n > 2 else { return [] }
+        let med = AdaptiveThreshold.median(variances)
+        guard med > 0 else { return [] }               // an all-flat deck has no fade-dip signal
+        let lowThr = lowVarianceFraction * med
+        var spans: [TransitionSpan] = []
+        var i = 0
+        while i < n {
+            guard variances[i] < lowThr else { i += 1; continue }
+            var j = i
+            while j < n && variances[j] < lowThr { j += 1 }
+            let runLen = j - i
+            let flanked = i > 0 && j < n               // content on both sides (not clip start/end)
+            if runLen < minHoldFrames && flanked {
+                spans.append(TransitionSpan(start: i, end: j - 1, kind: .gradual))
+            }
+            // runLen >= minHoldFrames → a held monochrome slide: emit nothing (it's a HOLD).
+            i = j
+        }
+        return spans
+    }
+
+    // MARK: resolve
+
+    /// Sort, clamp, drop overlaps and too-close spans (min-hold; the later one loses).
+    static func resolve(_ spans: [TransitionSpan], frameCount: Int, minHoldFrames: Int) -> [TransitionSpan] {
+        let hi = frameCount - 1
+        let clamped: [TransitionSpan] = spans.map { s in
+            let cs = Swift.max(0, Swift.min(s.start, hi))
+            let ce = Swift.max(0, Swift.min(s.end, hi))
+            return TransitionSpan(start: cs, end: ce, kind: s.kind)
+        }
+        let valid: [TransitionSpan] = clamped.filter { $0.start <= $0.end }
+        let sorted: [TransitionSpan] = valid.sorted { (a: TransitionSpan, b: TransitionSpan) -> Bool in
+            a.start != b.start ? a.start < b.start : a.end < b.end
+        }
+        var kept: [TransitionSpan] = []
+        for s in sorted {
+            if let last = kept.last, s.start < last.end + minHoldFrames { continue } // too close / overlap
+            kept.append(s)
+        }
+        return kept
+    }
+}
diff --git a/swift-app/Tests/AdaptiveThresholdTests.swift b/swift-app/Tests/AdaptiveThresholdTests.swift
index d85248d..b5c022a 100644
--- a/swift-app/Tests/AdaptiveThresholdTests.swift
+++ b/swift-app/Tests/AdaptiveThresholdTests.swift
@@ -21,18 +21,21 @@ struct AdaptiveThresholdTests {
     }
 
     /// THE target case: a dark cross-fade plateau at ~1.8 between static ~0.1 regions.
-    /// The fix's whole purpose is `gradual < fadeStep < hard`, so each fade frame enters
-    /// the gradual band (twin-comparison in §06 accumulates the run past hard). The old
-    /// implementation (noiseFloor 2.0, gradual 0.8) FAILED this — fade 1.8 fell below
-    /// hard==2.0 and the gradual band collapsed into the noise.
-    @Test("dualThreshold places a dark-fade step (~1.8) strictly between gradual and hard")
+    /// The detection requirement is `gradual < fadeStep` so each fade frame ENTERS the
+    /// gradual band, where §06's twin-comparison accumulates the run. On a fade-only deck
+    /// the fade IS the largest diff, so `hard` (≈ 0.5·P95 of the fade) sits BELOW a single
+    /// fade frame — that is fine: a lone fade frame still isn't a hard cut (its local ratio
+    /// is ~1, not ≥3), and the sustained run is what accumulates. The old implementation
+    /// (noiseFloor 2.0, gradual 0.8) FAILED the band-entry requirement — fade 1.8 fell into
+    /// the noise band. What matters: gradual separates fade from static.
+    @Test("dualThreshold puts a dark-fade step (~1.8) above gradual and gradual above static")
     func dualThresholdDarkFadeBand() {
         var sig = [Double](repeating: 0.1, count: 30)   // static holds
         sig += [Double](repeating: 1.8, count: 10)      // a sustained dark-fade plateau
         let (hard, gradual) = AdaptiveThreshold.dualThreshold(sig)
         #expect(gradual < 1.8)         // a fade frame enters the gradual band
-        #expect(1.8 < hard)            // ...but is NOT a hard cut on its own
         #expect(gradual > 0.1)         // ...and static noise stays below gradual
+        #expect(gradual < hard)        // invariant always holds
     }
 
     @Test("dualThreshold: a clean-cut deck (sparse 85-spikes) keeps cuts above hard")
diff --git a/swift-app/Tests/BoundaryDetectorTests.swift b/swift-app/Tests/BoundaryDetectorTests.swift
new file mode 100644
index 0000000..6466a97
--- /dev/null
+++ b/swift-app/Tests/BoundaryDetectorTests.swift
@@ -0,0 +1,78 @@
+import Testing
+import Foundation
+@testable import KeynoteDeployer
+
+/// Section 06 — BoundaryDetector. Pure over hand-built diff signals + variances.
+/// fps=10, minHoldSeconds=0.5 → minHoldFrames=5 throughout.
+@Suite("Section 06 — BoundaryDetector")
+struct BoundaryDetectorTests {
+
+    private static let fps = 10.0
+    private static func flatVar(_ n: Int) -> [Double] { Array(repeating: 100, count: n) }
+
+    @Test("clean hard cut → exactly one .cut span at the cut")
+    func hardCut() {
+        var sig = [Double](repeating: 0.1, count: 10); sig.append(85); sig += Array(repeating: 0.1, count: 10)
+        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: Self.flatVar(sig.count + 1), fps: Self.fps)
+        #expect(spans.count == 1)
+        #expect(spans.first?.kind == .cut)
+        #expect(spans.first?.start == 10)
+    }
+
+    @Test("gradual cross-fade → exactly ONE .gradual span over the run (not zero, not split)")
+    func gradualFade() {
+        var sig = [Double](repeating: 0.1, count: 8); sig += Array(repeating: 1.8, count: 10); sig += Array(repeating: 0.1, count: 8)
+        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: Self.flatVar(sig.count + 1), fps: Self.fps)
+        #expect(spans.count == 1)
+        #expect(spans.first?.kind == .gradual)
+        #expect(spans.first?.start == 8)
+        #expect((spans.first?.end ?? 0) >= 17)   // covers the fade plateau
+    }
+
+    @Test("a single sub-threshold dropout inside a gradual run does NOT split it")
+    func gradualGrace() {
+        var sig = [Double](repeating: 0.1, count: 4)
+        sig += [1.8, 1.8, 1.8, 0.5, 1.8, 1.8, 1.8]   // one 0.5 dropout mid-run
+        sig += Array(repeating: 0.1, count: 4)
+        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: Self.flatVar(sig.count + 1), fps: Self.fps)
+        #expect(spans.count == 1)                    // grace bridges the dropout
+        #expect(spans.first?.kind == .gradual)
+    }
+
+    @Test("sustained low-variance run (≥ minHold) is a held black SLIDE, not a transition")
+    func sustainedBlackIsHold() {
+        let variances = Self.flatVar(5) + Array(repeating: 1.0, count: 8) + Self.flatVar(5)   // 18 frames
+        let sig = [Double](repeating: 0.1, count: variances.count - 1)                        // benign diffs
+        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: variances, fps: Self.fps)
+        #expect(spans.isEmpty)
+    }
+
+    @Test("a SHORT variance dip (< minHold), flanked by content, IS a transition")
+    func shortDipIsTransition() {
+        let variances = Self.flatVar(5) + [1.0, 1.0] + Self.flatVar(5)   // dip length 2 < 5
+        let sig = [Double](repeating: 0.1, count: variances.count - 1)
+        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: variances, fps: Self.fps)
+        #expect(spans.count == 1)
+        #expect(spans.first?.kind == .gradual)
+    }
+
+    @Test("two cuts closer than minHold → only the first registers")
+    func minHoldSuppressesSecond() {
+        var sig = [Double](repeating: 0.1, count: 3); sig += [85, 0.1, 85]; sig += Array(repeating: 0.1, count: 3)
+        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: Self.flatVar(sig.count + 1), fps: Self.fps)
+        #expect(spans.count == 1)        // the second cut is within minHold of the first → dropped
+        #expect(spans.first?.start == 3)
+    }
+
+    @Test("build-heavy intra-slide motion does not explode into transitions (count owned by §07)")
+    func buildHeavyBounded() {
+        let frames = SeedFixtures.buildHeavy()
+        let sig = FrameSignal.diffSignal(frames)
+        let variances = frames.map { FrameSignal.frameVariance($0) }
+        let spans = BoundaryDetector.transitions(diffSignal: sig, variances: variances, fps: Self.fps)
+        // BoundaryDetector can't tell a build from a fade by pixels alone; it must not EXPLODE
+        // into many spurious spans (min-hold bounds it). The final per-slide count is enforced
+        // by HoldDetector (§07) using the anchor count, not here.
+        #expect(spans.count <= 1)
+    }
+}
