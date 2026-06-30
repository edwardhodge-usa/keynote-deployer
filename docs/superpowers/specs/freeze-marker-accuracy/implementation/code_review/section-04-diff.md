diff --git a/swift-app/Sources/Services/AdaptiveThreshold.swift b/swift-app/Sources/Services/AdaptiveThreshold.swift
new file mode 100644
index 0000000..ac35381
--- /dev/null
+++ b/swift-app/Sources/Services/AdaptiveThreshold.swift
@@ -0,0 +1,71 @@
+import Foundation
+
+/// Deck-adaptive thresholds over a per-frame diff signal — replaces the old fixed
+/// `motionThreshold = 6.0` that was tuned to one deck. All values are derived from
+/// each deck's OWN diff distribution (robust statistics) or expressed as unitless
+/// multiples / times, so nothing is a per-deck magic constant.
+///
+/// Pure; consumed by `BoundaryDetector` (section 06). The diff signal is the
+/// `FrameSignal.diffSignal` output (one value per adjacent frame pair, ~0–255 scale,
+/// dominated by near-zero static-hold values with sparse transition spikes).
+enum AdaptiveThreshold {
+
+    /// Absolute static-noise floor (on the 0–255 mean-abs scale). Keeps thresholds from
+    /// collapsing toward 0 on a perfectly clean deck, and floors the local-ratio
+    /// denominator so a dead-still dark hold can't manufacture a huge ratio from noise.
+    static let noiseFloor = 2.0
+    /// MAD multiplier for the hard threshold (≈3σ outlier line). Global, validated once.
+    static let kHard = 3.0
+    /// Gradual threshold as a fraction of the hard threshold (Ts ≈ 0.4·Tb).
+    static let gradualRatio = 0.4
+
+    /// Robust (hard=Tb, gradual=Ts) thresholds from the signal's own distribution.
+    /// hard = max(noiseFloor, median + kHard·1.4826·MAD, 0.5·max). The `0.5·max` term
+    /// rescues the common static-dominated case where >50% of values are ~0 → MAD
+    /// collapses to 0; the deck's largest diff is a real transition, so half of it is a
+    /// sound hard floor. gradual = gradualRatio·hard (strictly < hard). Never NaN/Inf;
+    /// guarantees gradual < hard, both ≥ noiseFloor's spirit.
+    static func dualThreshold(_ signal: [Double]) -> (hard: Double, gradual: Double) {
+        guard !signal.isEmpty else { return (noiseFloor, noiseFloor * gradualRatio) }
+        let med = median(signal)
+        let spread = 1.4826 * median(signal.map { abs($0 - med) })
+        let maxV = signal.max() ?? 0
+        let hard = Swift.max(noiseFloor, med + kHard * spread, 0.5 * maxV)
+        return (hard, gradualRatio * hard)
+    }
+
+    /// FPS-relative neighbor window: `max(2, Int(fps / 15))` — a constant TIME span
+    /// across framerates (30fps → 2, 60fps → 4) rather than a raw frame count.
+    static func window(forFps fps: Double) -> Int {
+        Swift.max(2, Int(fps / 15))
+    }
+
+    /// Local-window ratio (AdaptiveDetector): `ratio_i = score_i / mean(neighbors over
+    /// ±window, excluding i)`. A UNITLESS multiple (~3× at a real transition) needing no
+    /// per-deck constant — build/camera motion raises the neighbors too, so the ratio
+    /// stays low. The denominator is floored at `noiseFloor` so a dead-still region
+    /// yields ratios ~score/floor (small), not a huge tiny/tinier blowup. Returns one
+    /// ratio per input element (clamped windows at the ends).
+    static func localRatios(_ signal: [Double], window: Int) -> [Double] {
+        let n = signal.count
+        guard n > 0 else { return [] }
+        let w = Swift.max(1, window)
+        var out = [Double](repeating: 0, count: n)
+        for i in 0..<n {
+            let lo = Swift.max(0, i - w), hi = Swift.min(n - 1, i + w)
+            var sum = 0.0, count = 0
+            for j in lo...hi where j != i { sum += signal[j]; count += 1 }
+            let neighborMean = count > 0 ? sum / Double(count) : 0
+            out[i] = signal[i] / Swift.max(neighborMean, noiseFloor)
+        }
+        return out
+    }
+
+    /// Median of a value list (sorted-copy; empty → 0).
+    static func median(_ xs: [Double]) -> Double {
+        guard !xs.isEmpty else { return 0 }
+        let s = xs.sorted()
+        let mid = s.count / 2
+        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
+    }
+}
diff --git a/swift-app/Tests/AdaptiveThresholdTests.swift b/swift-app/Tests/AdaptiveThresholdTests.swift
new file mode 100644
index 0000000..9c394d6
--- /dev/null
+++ b/swift-app/Tests/AdaptiveThresholdTests.swift
@@ -0,0 +1,64 @@
+import Testing
+import Foundation
+@testable import KeynoteDeployer
+
+/// Section 04 — AdaptiveThreshold. Pure; hand-built `[Double]` signals inline.
+@Suite("Section 04 — AdaptiveThreshold")
+struct AdaptiveThresholdTests {
+
+    @Test("dualThreshold: gradual < hard, both above the noise floor, on a static-dominated signal")
+    func dualThresholdStaticDominated() {
+        // Long flat tail of ~0 with a few spikes — the typical deck distribution.
+        var sig = [Double](repeating: 0.1, count: 40)
+        sig += [50, 60, 55]   // sparse transition spikes
+        let (hard, gradual) = AdaptiveThreshold.dualThreshold(sig)
+        #expect(gradual < hard)
+        #expect(hard >= AdaptiveThreshold.noiseFloor)
+        #expect(gradual >= 0)
+        // Not dragged to ~0 by the flat tail (the 0.5·max rescue): a real spike (~55)
+        // should sit at/above hard, the static 0.1 well below gradual.
+        #expect(hard > 5)
+        #expect(0.1 < gradual)
+    }
+
+    @Test("dualThreshold: degenerate inputs never NaN/Inf and keep gradual < hard")
+    func dualThresholdDegenerate() {
+        for sig in [[Double](), [5.0], [Double](repeating: 7, count: 10)] {
+            let (hard, gradual) = AdaptiveThreshold.dualThreshold(sig)
+            #expect(hard.isFinite && gradual.isFinite)
+            #expect(gradual < hard)
+            #expect(hard >= AdaptiveThreshold.noiseFloor)
+        }
+    }
+
+    @Test("localRatios peak at an injected spike, stay ~1 on a uniform ramp")
+    func localRatiosSpikeVsRamp() {
+        var spike = [Double](repeating: 0.1, count: 21)
+        spike[10] = 40
+        let rs = AdaptiveThreshold.localRatios(spike, window: 2)
+        #expect(rs[10] >= 3)                       // sharp peak at the spike
+        #expect(rs[0] < 3 && rs[20] < 3)           // flat elsewhere
+
+        // A uniformly rising ramp: each frame's neighbors rose with it → ratio ~1.
+        let ramp = (0..<30).map { Double($0) * 3 + 10 }
+        let rr = AdaptiveThreshold.localRatios(ramp, window: 2)
+        // Interior ratios cluster near 1 (no false peak); none spikes to a cut level.
+        let interior = rr[5..<25]
+        #expect(interior.allSatisfy { $0 < 2.0 })
+    }
+
+    @Test("window is fps-relative")
+    func windowFpsRelative() {
+        #expect(AdaptiveThreshold.window(forFps: 30) == 2)
+        #expect(AdaptiveThreshold.window(forFps: 60) == 4)
+        #expect(AdaptiveThreshold.window(forFps: 24) < AdaptiveThreshold.window(forFps: 60))
+    }
+
+    @Test("noise floor prevents amplification on a dead-still region")
+    func noiseFloorGuard() {
+        // Tiny sensor-noise-magnitude wiggles — must NOT produce large ratios.
+        let noise = (0..<25).map { _ in Double.random(in: 0...0.4) }
+        let rs = AdaptiveThreshold.localRatios(noise, window: 2)
+        #expect(rs.allSatisfy { $0 < 1.0 })   // floored denominator keeps ratios small
+    }
+}
