import Foundation

/// Deck-adaptive thresholds over a per-frame diff signal — replaces the old fixed
/// `motionThreshold = 6.0` that was tuned to one deck. Values derive from each deck's
/// OWN diff distribution (robust statistics) or are unitless multiples / times, so
/// nothing is a per-deck magic constant.
///
/// Pure; consumed by `BoundaryDetector` (section 06). The diff signal is
/// `FrameSignal.diffSignal` (one value per adjacent frame pair, ~0–255 scale, dominated
/// by near-zero static-hold values with sparse transition spikes / fade plateaus).
///
/// Division of labour (important): `localRatios` is a HARD-CUT detector — a sustained
/// cross-fade is a plateau in the diff signal, which is locally a ramp → ratio ≈ 1, so
/// localRatios CANNOT see a sustained fade and must not be relied on for it. Dark-fade
/// detection rests on the GRADUAL absolute threshold + twin-comparison accumulation in
/// section 06: the design goal here is `gradual < fadeStep < hard`, so each fade frame
/// enters the gradual band and the accumulated run crosses `hard`. The constants are
/// chosen so a ~1.5–2.0 dark-fade step lands strictly between gradual and hard.
enum AdaptiveThreshold {

    // MARK: Global constants (validated once across archetype decks; never per-deck)

    /// Absolute floor for the hard threshold (0–255 mean-abs scale). Static holds sit
    /// at ~0.1; this keeps `hard` from collapsing to 0 on a perfectly clean deck.
    static let hardFloor = 0.5
    /// Floor for the gradual threshold — explicitly placed ABOVE static-hold noise
    /// (~0.1) and BELOW a dark-fade step (~1.5–2.0) so a fade enters the gradual band
    /// while noise does not. Reconciled separately from `hardFloor` (it is intentionally
    /// below it; the old code's "gradual ≥ hardFloor" claim was the unfixable tension).
    static let gradualFloor = 0.3
    /// Local-ratio denominator floor — at the static-noise level (NOT the fade level),
    /// so a cut edge over a near-zero baseline still yields a large ratio. Decoupled
    /// from the threshold floors on purpose.
    static let ratioDenominatorFloor = 0.3
    /// MAD multiplier for the hard threshold (≈3σ outlier line).
    static let kHard = 3.0
    /// Gradual = `gradualRatio · hard` (Ts ≈ 0.4·Tb).
    static let gradualRatio = 0.4
    /// Rescue fraction applied to a high percentile when MAD collapses (see below).
    static let rescueFraction = 0.5
    /// MAD → σ consistency constant for normal data.
    static let madToSigma = 1.4826
    /// 90th-percentile gap → σ (z₀.₉ ≈ 1.2816), the MAD-collapse fallback spread.
    static let p90ToSigma = 1.2816

    /// Robust (hard=Tb, gradual=Ts) thresholds from the signal's own distribution.
    ///
    /// `spread` = the larger of the MAD-based σ and a 90th-percentile-gap σ. The second
    /// term rescues the common static-dominated case where >50% of values are ~0 → MAD
    /// collapses to 0 but the upper tail (fade plateau) still carries scale.
    /// `hard = max(hardFloor, median + kHard·spread, rescueFraction·P95)`. The P95 term
    /// (NOT raw max — a lone outlier can't set the bar for the whole deck) carries decks
    /// with sparse hard cuts where even P90 sits in the static region.
    /// `gradual = clamp(gradualRatio·hard, gradualFloor, hard−ε)`.
    static func dualThreshold(_ signal: [Double]) -> (hard: Double, gradual: Double) {
        guard !signal.isEmpty else { return (hardFloor, gradualFloor) }
        let med = median(signal)
        let madSigma = madToSigma * median(signal.map { abs($0 - med) })
        let p90 = percentile(signal, 0.90)
        let p95 = percentile(signal, 0.95)
        let pctSigma = Swift.max(0, (p90 - med) / p90ToSigma)
        let spread = Swift.max(madSigma, pctSigma)
        let hard = Swift.max(hardFloor, med + kHard * spread, rescueFraction * p95)
        let gradual = Swift.min(Swift.max(gradualRatio * hard, gradualFloor), hard - 1e-9)
        return (hard, gradual)
    }

    /// FPS-relative neighbor window: `max(2, round(fps / 15))` — a constant TIME span
    /// across framerates (30fps → 2, 60fps → 4, 59.94 → 4). Rounded (not truncated) so
    /// NTSC rates don't drift, matching this project's 29.97/23.976 precision history.
    static func window(forFps fps: Double) -> Int {
        Swift.max(2, Int((fps / 15).rounded()))
    }

    /// Local-window ratio (AdaptiveDetector): `ratio_i = score_i / mean(neighbors over
    /// ±window, excluding i)` — a unitless multiple (~3× at a hard cut) needing no
    /// per-deck constant. The denominator is floored at `ratioDenominatorFloor` (static
    /// noise level) so a cut edge over a near-zero baseline yields a large ratio while a
    /// dead-still region stays small. NOTE: a sustained fade is a plateau → ratio ≈ 1;
    /// this detects CUTS, not sustained fades (those are the gradual/twin path).
    /// Returns one ratio per input element (clamped windows at the ends).
    static func localRatios(_ signal: [Double], window: Int) -> [Double] {
        let n = signal.count
        guard n > 0 else { return [] }
        let w = Swift.max(1, window)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let lo = Swift.max(0, i - w), hi = Swift.min(n - 1, i + w)
            var sum = 0.0, count = 0
            for j in lo...hi where j != i { sum += signal[j]; count += 1 }
            let neighborMean = count > 0 ? sum / Double(count) : 0
            out[i] = signal[i] / Swift.max(neighborMean, ratioDenominatorFloor)
        }
        return out
    }

    /// Median of a value list (sorted-copy; empty → 0).
    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    /// Nearest-rank percentile, p in 0...1 (empty → 0).
    static func percentile(_ xs: [Double], _ p: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let idx = Swift.min(s.count - 1, Swift.max(0, Int(p * Double(s.count))))
        return s[idx]
    }
}
